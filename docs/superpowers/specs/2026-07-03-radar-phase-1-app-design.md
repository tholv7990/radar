# RADAR — Phase 1 App Design Spec

| | |
|---|---|
| **Date** | 2026-07-03 |
| **Scope** | Phase 1 — the RADAR mobile app: Login + Feed + Scope + Watchlist, reading the collector's data. **No** deep-dive / LLM (that's Phase 2). |
| **Builds on** | `2026-07-03-radar-phase-0-1-design.md` (architecture) · Phase 0 collector (live) · `RADAR.dc.html` (visual reference) |
| **Status** | Approved in brainstorming; pending written-spec review |

## 1. Context

Phase 0 is live: a daily collector writes `entities` + dated `snapshots` (with `provisional_quality`) into Supabase Postgres. Phase 1 is the **Flutter app** that turns that data into the skimmable, filterable, watchlist-able experience from the prototype. Everything expensive (the four-lens deep-dive) stays out — Phase 2.

## 2. Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Toolchain / target | **Android-first** on Windows (emulator or physical Android). iOS deferred to a Mac or cloud macOS build. Same Dart code either way. |
| 2 | Auth | **Supabase email/password, single account**, RLS enforced. Session persists (log in once per device). |
| 3 | Feed tap | Opens the GitHub/Product Hunt page externally. No rich detail screen in Phase 1 (that overlay *is* the Phase 2 deep-dive). |
| 4 | Ranking cold-start | Momentum score `coalesce`s to `provisional_quality` until ≥2 snapshots exist, then shifts to real velocity. |
| 5 | Build scope | All three tabs (Feed + Scope + Watchlist) in the first slice. |
| 6 | Refresh | The app's refresh = re-query Supabase for the latest snapshot data. It does **not** re-run the collector (that's the cron's job). |

## 3. Architecture

```
Flutter app (supabase_flutter)
  UI (screens/widgets)
     │  calls
  Repository (all Supabase access)
     │  reads signal_feed view · reads/writes watchlist_state · auth
     ▼
Supabase Postgres  ──  signal_feed (view) · watchlist_state · entities · snapshots
     ▲
  Collector (service-role, bypasses RLS) — unchanged
```

Three layers, clear boundaries: **UI → Repository → Supabase**. The app queries the `signal_feed` view **once per refresh** and does all filtering/sorting **in memory** (~100 rows — no per-filter round-trips). The repository is the only place that knows about Supabase.

## 4. The `signal_feed` view (build this first)

A read-time Postgres view — the Phase-1 data foundation. Per entity it joins the **latest** snapshot to a **~7-day-prior** snapshot and computes the derived fields. Condensed shape (final SQL finalized in the plan):

```sql
create or replace view signal_feed as
with latest as (
  select distinct on (entity_id) * from snapshots
  order by entity_id, captured_at desc
),
prior as (
  select distinct on (s.entity_id) s.* from snapshots s
  join latest l on l.entity_id = s.entity_id
  where s.captured_at <= l.captured_at - interval '7 days'
  order by s.entity_id, s.captured_at desc
)
select
  e.id, e.source, e.external_id, e.name, e.one_liner, e.url,
  e.language, e.topics, e.created_at,
  l.captured_at, l.stars, l.forks, l.watchers, l.votes, l.comments,
  l.rating, l.pushed_at, l.archived, l.provisional_quality,
  -- velocity: github → Δ stars; producthunt → Δ (votes+comments) over the window
  case when e.source='github' then l.stars - p.stars
       else (l.votes + l.comments) - (p.votes + p.comments) end as velocity,
  -- cross-consistency: does a secondary signal corroborate the primary spike?
  --   github: star-velocity vs fork/watcher-velocity direction
  --   producthunt: votes vs comments moving together
  -- → 'corroborated' | 'mixed' | 'suspicious'  (computed in SQL)
  ...as consistency,
  ...as momentum_stage,   -- emerging/rising/steady/fading (velocity+acceleration); 'new' when velocity is null
  coalesce(<momentum_score>, l.provisional_quality) as rank_score,
  w.state as watch_state
from entities e
join latest l on l.entity_id = e.id
left join prior p on p.entity_id = e.id
left join watchlist_state w on w.entity_id = e.id;
```

**Cold-start behavior:** with one snapshot, `prior` is empty → `velocity` is null → `momentum_stage='new'` and `rank_score` falls back to `provisional_quality`. After the 2nd daily run, velocity populates and ranking becomes real momentum — no app change needed.

## 5. Screens

- **Login** — email + password → Supabase Auth. Session persists; on cold start with a valid session, skip straight to the app. Invalid → error, stay on login.
- **Feed** — source segment (All / GitHub / Product Hunt) · sort cycle (momentum / velocity / total / newest) · stage chips · language chips · list of **signal rows**. Row: source icon, owner/name, one-liner, tags, primary metric (velocity or total), momentum-stage pill, consistency dot, last-active, **watch button** (cycles seen ↔ watching). **Row tap → open the item's URL externally.**
- **Scope** — quality × momentum radar drawn with `CustomPaint` (blips positioned by `provisional_quality` × momentum), plus the ranked list below. **Phase 1: every blip is hollow/provisional** — no deep-dives exist yet; blips go solid in Phase 2.
- **Watchlist** — same signal rows, filtered by state (active / watching / seen / dismissed).

Bottom nav switches Feed / Scope / Watchlist. A global "as of \<latest captured_at\>" stamp shows data freshness.

## 6. Auth & RLS

- Enable **RLS** on `entities`, `snapshots`, `watchlist_state`, `deep_dive_cache`.
- Policies: role `authenticated` may `select` all four; may `insert/update/delete` on `watchlist_state`.
- The **collector** connects as the DB owner / service-role → **bypasses RLS**, so it keeps writing unaffected.
- The app embeds only the **public anon key**, supplied at build via `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`. The DB DSN and service key never ship in the app.
- Create the single user account once (Supabase dashboard → Auth → Add user, or a one-time sign-up).

## 7. State & data flow

- A **repository singleton** wraps `supabase_flutter`: `signIn()`, `fetchFeed() → List<SignalItem>`, `setWatchState(entityId, state)`.
- UI uses `FutureBuilder` for the feed load and simple widget state for filters/sort. **Phase 2's Realtime drops into a `StreamBuilder`** on the deep-dive rows later — no rework.
- No heavyweight state library for an app this size. *Ponytail: add Riverpod only if it outgrows this.*

## 8. Error handling

- Network / query error → inline error with a retry button; never a blank crash.
- Empty filter result → "No signals match this filter" (prototype already designs this).
- Auth error / expired session → route back to Login.
- Freshness: show "as of \<latest captured_at\>"; distinguish *item* freshness (last push / launch age) from *data* freshness (last collector run).

## 9. Testing (light)

- Pure Dart functions for sort, filter, and momentum/stage labeling → unit tests (Flutter `test`).
- The `signal_feed` view → one integration check (query returns expected columns and orders by `rank_score`).
- Widget/golden tests skipped unless requested.

## 10. Definition of done

- ☐ `signal_feed` view created; returns computed momentum/consistency/rank with cold-start fallback.
- ☐ RLS + single-account auth; app requires login; collector unaffected.
- ☐ Feed: rows render from the view, filter/sort work, watch state persists to Supabase, tap opens URL.
- ☐ Scope: radar + ranked list render with provisional (hollow) blips.
- ☐ Watchlist: state-filtered rows.
- ☐ Runs on Android (emulator or device) with freshness stamp.
- ☐ **Out:** deep-dive overlay, any LLM/rubric/score, Realtime (all Phase 2).

## 11. Deferred / open

- **iOS build** — needs a Mac or cloud macOS; the code is ready, only the build target is deferred.
- **Phase 2** — deep-dive overlay, `deep_dive_cache.status` async + Realtime, solid Scope blips; its own spec once `trend-intelligence-spec.md` (the rubric) exists.
- **Final `signal_feed` SQL** (exact consistency/stage thresholds) — finalized in the plan; weights tuned by eye after data accrues.
