# RADAR — Phase 0 + 1 Design Spec

| | |
|---|---|
| **Date** | 2026-07-03 |
| **Scope** | Phase 0 (Collector) + Phase 1 (List / Scope / Watchlist app). Phase 2 (Deep-Dive) designed at architecture level only. |
| **Supersedes / builds on** | `trend-watchlist-build-document.md` (v2.0) + `RADAR.dc.html` prototype |
| **Roles** | Product Manager / Business Analyst (what & why) · Technical Architect (how) |
| **Status** | Approved in brainstorming; pending written-spec review |

## 1. Context & problem

A personal, single-user tool to watch what is *durably* rising across GitHub repos and Product Hunt launches, ranked by **momentum quality** rather than raw popularity. One user, four hats (CTO / CEO / investor / researcher). Two tiers: a cheap always-on **list**, and an expensive on-click **deep-dive**. See the build document for the full PRD; this spec captures the architecture after locking three open decisions.

## 2. Locked decisions

| # | Decision | Choice | Rationale |
|---|---|---|---|
| 1 | Platform & stack | **Flutter** (iOS+Android) · **Supabase** (Postgres + Edge Functions) · **Python collector** on GitHub Actions cron · **Anthropic API** for deep-dive | Native was chosen over Streamlit/PWA. Native ⇒ remote data + server-side deep-dive required ⇒ hosted Postgres. Supabase fits the relational snapshot model, needs no always-on server (NFR-2), and the daily cron doubles as free-tier keep-alive. |
| 2 | Scope quality axis | **Provisional proxy → confirmed** | Quality is an LLM/deep-dive value; plotting all items on it would break the no-LLM-background invariant. A cheap deterministic health proxy fills the x-axis (hollow blip) until a real deep-dive replaces it (solid blip). |
| 3 | Deep-dive execution | **Async + Supabase Realtime** | A real deep-dive is 15–40s (multi-fetch + LLM). Synchronous would risk Edge Function timeout and a frozen screen with nothing cached. Async writes the cache as it completes and survives app backgrounding. |

## 3. Architecture

```
GitHub Actions (daily cron)
        │  Python collector: fetch → pre-filter → upsert entity + insert snapshot
        ▼
┌─────────────────────────────────────────────┐
│  SUPABASE (Postgres)                          │
│  entities · snapshots · watchlist_state ·     │
│  deep_dive_cache        [+ SQL views]         │
│      ▲ writes cache          ▲ reads/writes   │
│      │                        │  (RLS)        │
│  Edge Function ◀── invoke ── Flutter app      │
│  (deep-dive: fetch+LLM)   ──▶ Realtime sub    │
└─────────────────────────────────────────────┘
        ▲
   Anthropic API (server-side key, on-click only)
```

**Invariant (load-bearing):** the LLM is only ever called by the Edge Function, only on a user tap. The collector and the list path never call Anthropic. This boundary is what keeps the tool cheap.

## 4. Components

### 4.1 Collector (Python · GitHub Actions cron, daily)
- Fetch GitHub Search + REST (authenticated, 5,000 req/hr; Search paged, ~30 req/min) and Product Hunt GraphQL (day's launches).
- Run the pre-filter gate (§8). Only survivors are stored.
- `upsert entities` on `(source, external_id)`; `insert snapshots` (one row per run). Idempotent — a re-run never duplicates identities.
- Compute and store `snapshots.provisional_quality` (deterministic, no extra API calls, no LLM).
- Store full `raw_json` on every snapshot (insurance).
- Fail loud, degrade safe (NFR-3/4): a failed run logs an error and leaves prior data intact.

### 4.2 Postgres + SQL views
- Velocity / acceleration / **cross-consistency flag** / light-momentum-score / momentum-stage are a **read-time SQL view** over `snapshots` using window functions ordered by `captured_at`. The app does no math; there is no extra service.
- Cross-consistency (first-class anti-gaming input, A9/FR-1.2) is computed from **background-tier metrics only**: GitHub — do star velocity, fork velocity, and watcher velocity corroborate each other; Product Hunt — do votes and comments move together. A star/vote spike with no matching secondary signal → `suspicious`. (Download corroboration is deep-dive tier and not used here.)

### 4.3 Edge Function `deep-dive` (Phase 2, architecture-level here)
- On `invoke({entity_id})`: upsert `deep_dive_cache` row `status='running'`, then background-process (Edge Function background task) so it doesn't depend on the client connection.
- Work: fetch deep-dive-tier signals (contributors, releases, file tree for tests/CI, README, downloads/dependents; for PH: comment bodies, pricing crawl, URL-alive check) → run the source-appropriate rubric via Anthropic → write `status='done'` + results.
- Anthropic + Supabase service keys stay in server-side env, never in the app.
- **Known ceiling (ponytail):** background task on the Edge Function. If a job ever exceeds the function wall-clock limit, upgrade to a job table + external worker. Not needed at single-user scale.

### 4.4 Flutter app (iOS+Android)
- Three tabs — **Feed**, **Scope**, **Watchlist** — plus a slide-up **Deep-Dive** overlay, matching the `RADAR.dc.html` prototype's shape (prototype is throwaway visual reference).
- Reads the list SQL view; reads/writes `watchlist_state` directly via `supabase_flutter` under Row-Level Security.
- Deep-dive: `invoke('deep-dive')` then subscribe to the `deep_dive_cache` row via Realtime; render "Evaluating…" → live result. "Re-run" re-invokes.

## 5. Data model

Keeps the build document's four tables. Two additions fall out of the locked decisions (marked **NEW**).

```sql
-- entities: durable identity of a repo/app
create table entities (
  id            bigint generated always as identity primary key,
  source        text not null check (source in ('github','producthunt')),
  external_id   text not null,          -- repo full_name | PH post id
  name          text not null,
  one_liner     text,
  url           text,
  language      text,                   -- github
  topics        text[],
  owner_type    text,                   -- github: User/Organization
  created_at    timestamptz,            -- item creation (age)
  default_branch text,                  -- github, for deep-dive file lookups
  first_seen_at timestamptz default now(),
  unique (source, external_id)
);

-- snapshots: one row per entity per collector run (the time-series)
create table snapshots (
  id            bigint generated always as identity primary key,
  entity_id     bigint not null references entities(id),
  captured_at   timestamptz not null default now(),
  -- github metrics
  stars int, forks int, watchers int, open_issues int,
  pushed_at timestamptz, license text, archived bool,
  -- producthunt metrics
  votes int, comments int, rating numeric, reviews_count int,
  provisional_quality int,              -- NEW: deterministic health proxy (§7)
  raw_json      jsonb not null
);
create index on snapshots (entity_id, captured_at desc);

-- watchlist_state: per-item user state
create table watchlist_state (
  entity_id  bigint primary key references entities(id),
  state      text not null check (state in ('seen','watching','dismissed')),
  note       text,
  updated_at timestamptz default now()
);

-- deep_dive_cache: Phase 2 results; the row IS the async job
create table deep_dive_cache (
  entity_id     bigint primary key references entities(id),
  status        text not null default 'running'
                  check (status in ('running','done','error')),  -- NEW
  error_note    text,                                            -- NEW
  computed_at   timestamptz default now(),
  quality_score int,
  momentum_stage text,
  veto_flags    jsonb,
  reasons       jsonb,
  full_result   jsonb
);
```

## 6. Data flow

**Background (per cron run):**
1. GitHub Search + PH GraphQL → candidate set.
2. Pre-filter gate (§8).
3. Per survivor: `upsert entities`, `insert snapshots` (incl. `provisional_quality`).
4. Read-time: list SQL view computes light-momentum-score and orders the list.

**On-click (async, Phase 2):**
1. Tap → `invoke('deep-dive', {entity_id})` → Edge Function sets `status='running'`, backgrounds the work.
2. App subscribes to that `deep_dive_cache` row via Realtime.
3. Function finishes → `status='done'` + results → app re-renders. Re-run re-invokes. Cached indefinitely (FR-2.3).

## 7. Provisional health proxy (Scope x-axis before deep-dive)

Deterministic, from **background-tier fields only** — no deep-dive fetches, no LLM. Produces a 0–100 score stored per snapshot.

- **GitHub:** license present · not archived (hard gate → low) · push recency (`days_since_push`) · fork:star ratio (usage vs bookmarking) · age sanity.
- **Product Hunt:** reviews rating · comment:vote ratio (engagement depth) · reviews count · product URL present.

Deliberately crude — that crudeness is why the Scope blip stays **hollow** until a real `quality_score` replaces it (**solid**). Weights start rough and are calibrated by eye after launch (build-doc design note: "thresholds/weights come later"). This is the tuning knob, not a precise model.

## 8. Pre-filter gate (cheap, deterministic, no LLM)

Only survivors are stored (and later deep-divable) — keeps the DB and inference bill from scaling with noise.
- **GitHub:** min stars · has license · not a fork · has README · commit within N days · not blocklisted.
- **Product Hunt:** min comment count · product URL resolves · not a duplicate re-launch · target language · not spam.

Thresholds start loose, tighten against real data.

## 9. Error handling & resilience

- **Collector:** fail loud / degrade safe (NFR-3/4); app always reads last good snapshot. Authenticated requests, paged Search API, polite pacing (NFR-5).
- **Deep-dive:** partial signal failure (e.g. npm down) → still produce a result with missing evidence flagged, never crash. Hard failure → `status='error'` + `error_note`, app shows retry.
- **Two freshness clocks, never conflated:** *item* freshness (last push / launch age) vs *data* freshness ("as of" last collector run). Both displayed.

## 10. Security

- **Anthropic key + Supabase service-role key:** server-side only (Edge Function env). Never in the app bundle.
- **App:** ships the Supabase anon key (public by design) under Row-Level Security. Single-user, so RLS can be minimal; watchlist writes and cache reads scoped appropriately.
- **Collector:** uses service-role / DB connection secret stored in GitHub Actions secrets.

## 11. Testing (light — one runnable check per non-trivial piece)

- Pre-filter gate: junk filtered out, good kept (sample payloads).
- Velocity: Δ over two snapshots yields expected delta.
- Provisional proxy: archived / no-license scores low; healthy scores high.
- Deep-dive evidence assembly: parse fixtures correctly (Phase 2).
- LLM rubric output judged by eye. No heavy framework, no fixtures beyond the above.

## 12. Phasing & definition of done

**Phase 0 — Collector (build first):**
- ☐ Cron runs, writes `entities` + dated `snapshots` (incl. `provisional_quality`).
- ☐ Pre-filter applied before storage. Idempotent upserts.

**Phase 1 — List / Scope / Watchlist app:**
- ☐ Flutter app reads the list SQL view, light-ranked by momentum, with freshness stamp.
- ☐ Feed + Scope (provisional proxy, hollow blips) + Watchlist tabs.
- ☐ `watchlist_state` (seen/watching/dismissed) persists via Supabase.
- ☐ **Out:** any LLM scoring, the four-lens rubric, deep-dive overlay results.

**Phase 2 — Deep-Dive (own spec later):**
- Architecture locked here (async + Realtime, Edge Function, `deep_dive_cache.status`). Full rubric logic depends on `trend-intelligence-spec.md`, which is **not in the project** — Phase 2 gets its own spec once that rubric is defined.

## 13. Deferred / open items

- **Validation loop** (backtest, precision@k, re-weighting): deferred by decision; retained daily snapshots keep the door open at no cost.
- **Rubric weights / pre-filter thresholds / momentum-window length:** tuned by eye after launch.
- **Phase 2 rubric detail:** blocked on `trend-intelligence-spec.md`.
- **Verify at implementation:** current `supabase_flutter` + Edge Functions API specifics and free-tier limits (standard, low-risk).
