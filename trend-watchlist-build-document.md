# Trend Watchlist — Build Document

**A personal tool to watch trending GitHub repos and Product Hunt apps, with on-demand deep evaluation.**

| | |
|---|---|
| **Document type** | Combined PRD + Solution Architecture + Data Dictionary |
| **Authors** | Business Analyst (Part A) · Technical Architect (Parts B & C) |
| **Version** | 2.0 — merged & build-ready |
| **Supersedes** | `build-document.md`, `field-specification.md` (now folded in as Parts A–B and C) |
| **Companion doc** | `trend-intelligence-spec.md` — full scoring rubrics & judgment logic (referenced in §B7) |
| **Key decisions locked** | Personal tool ✓ · Two-tier (list + deep-dive) ✓ · Scheduled collector ✓ · Daily cadence ✓ |

### Contents
- **Part A — Business Analysis** (A1–A10): what we're building, for whom, in what order, and how we know it's done.
- **Part B — Technical Architecture** (B1–B9): how it's realized — components, data sources, schema, flow, stack, ops, cost.
- **Part C — Data Dictionary** (C0–C8): every field captured and displayed, by source, tier, and view.

---

# PART A — BUSINESS ANALYSIS

*Owner: Business Analyst. Defines what we're building, for whom, in what order, and how we know it's done.*

## A1. Purpose & problem statement

There is no single place to watch what is *durably* rising across both the developer layer (GitHub) and the product layer (Product Hunt), judged by whether something is *actually good* rather than merely popular. Public leaderboards rank by attention — stars and votes — which in the AI era is cheap to produce and easy to fake. This tool exists so **one person** can (1) skim a lightly-curated list of candidates and (2) run a rigorous, multi-lens evaluation on any item worth a closer look.

## A2. Goals & non-goals

**Goals**
- Surface trending repos and apps ranked by *momentum quality*, not raw popularity.
- Let the user save, watch, and dismiss items (a working watchlist).
- On demand, produce a deep, explainable evaluation of a single item.
- Cost almost nothing to run (expensive work happens only on click).

**Non-goals (explicitly out of scope)**
- Not a commercial product; no other users, no accounts, no multi-tenant concerns.
- Not a forecasting product that must *prove* its accuracy — the longitudinal validation loop (backtest, precision@k, re-weighting) is **descoped to optional/future**. The user judges usefulness by eye.
- Not real-time. Data is as fresh as the last scheduled run.

## A3. User & context

A single user — the builder — who wears different **hats** depending on the moment: *CTO* (is this repo trustworthy to adopt?), *CEO* (is this app a real business?), *investor* (worth betting on?), *researcher* (is the signal real?). The tool serves all four because there is only one user; the deep-dive presents the lens appropriate to the source (CTO-heavy for repos, CEO-heavy for apps).

## A4. Scope & phasing

| Phase | Name | Contents | Status |
|---|---|---|---|
| **0** | Collector | Scheduled fetch → DB. Entities + dated snapshots. No UI. | Foundation — build first |
| **1** | The List | Filtered, lightly-ranked, skimmable list + watchlist state. **No LLM.** | Primary deliverable |
| **2** | The Deep-Dive | On-click four-lens evaluation, cached. **LLM here.** | Next |
| **Future** | Validation | Outcome labels, backtest, re-weighting. | Optional |

**Guiding rule:** cheap ordering in the background; expensive judgment only behind a click.

## A5. Functional requirements

*Phase 0 — Collector*
- **FR-0.1** Fetch candidate repos from GitHub and launches from Product Hunt on a schedule.
- **FR-0.2** Apply the pre-filter gate (§B6) before storing.
- **FR-0.3** Store each item as one **entity** plus a dated **snapshot** per run (never duplicate entities).

*Phase 1 — The List*
- **FR-1.1** Display a skimmable row per item (fields: §C6).
- **FR-1.2** Rank the list by a **light momentum score** (velocity + acceleration + a cross-consistency sanity check) — not the full rubric.
- **FR-1.3** Let the user set per-item state: **seen / watching / dismissed**, and persist it.
- **FR-1.4** Filter/sort the list (by source, language, stage, watchlist state).
- **FR-1.5** Show "as of \<timestamp\>" so stale data isn't misread as current.

*Phase 2 — The Deep-Dive*
- **FR-2.1** On click, fetch fresh detail for the item and run the source-appropriate rubric (repo → CTO-heavy; app → CEO-heavy).
- **FR-2.2** Output: the scored checklist, veto flags, quality × momentum placement, and the 2–3 reasons (fields: §C7).
- **FR-2.3** Cache the result so re-opening the same item is free; allow manual re-run.

## A6. Non-functional requirements

- **NFR-1 Cost** — background path does zero LLM work; total LLM spend scales only with clicks.
- **NFR-2 Simplicity/ops** — single-user, minimal infrastructure, ideally no always-on server to maintain.
- **NFR-3 Resilience** — a failed collector run must not corrupt data or block the app; the app always reads the last good snapshot.
- **NFR-4 Scraper fragility** — any HTML scraping must fail loudly (error, not silent empty) so breakage is noticed.
- **NFR-5 Rate-limit safety** — respect GitHub and Product Hunt limits with authenticated requests and polite pacing.
- **NFR-6 Data retention** — keep historical snapshots indefinitely (they're cheap and irreplaceable).

## A7. User flows

```
BROWSE:   open app → list (ranked, fresh-stamped) → skim rows → set seen/watching/dismissed
DECIDE:   spot something interesting → click it
EVALUATE: deep-dive runs rubric → checklist + reasons + veto + quality×momentum → judge → (watch or dismiss)
```

## A8. Assumptions, constraints & dependencies

- **Product Hunt API forbids commercial use by default** — acceptable here because the tool is personal. Some fields (e.g. maker names) are redacted; do not depend on them.
- **GitHub has no trending API** — candidates come from the Search API; velocity is computed from our own accumulated snapshots.
- **Velocity requires history** — the first useful velocity numbers appear only after ≥2 collector runs.
- Depends on: GitHub REST + Search APIs, Product Hunt GraphQL API, an LLM API (for Phase 2 only).

## A9. Risks & mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| List becomes a popularity leaderboard | Kills the whole value prop | Enforce light *quality* ranking (velocity/acceleration + cross-consistency), not raw counts |
| LLM work leaks into the background path | Cost + latency balloon | Hard architectural boundary: LLM only on the on-click path |
| Scraper breaks silently on HTML change | Stale/empty list unnoticed | Fail loudly (NFR-4); prefer official APIs over scraping wherever possible |
| Scope creep (pulling Phase 2/validation forward) | Phase 1 never ships | Definition-of-done gates (A10); validation stays out |
| Gamed metrics (bought stars/votes) | Junk ranks high | Cross-consistency check as a first-class ranking input |

## A10. Definition of done

**Phase 0/1 is done when:**
- ☐ Collector runs on schedule and writes entities + dated snapshots
- ☐ Pre-filter applied before storage
- ☐ List reads the DB, light-ranked by momentum, shows skim row + freshness
- ☐ Watchlist state (seen/watching/dismissed) persists
- ☐ **Out:** deep-dive, any LLM scoring, the four-lens rubric, the validation loop

**Phase 2 is done when:**
- ☐ Clicking an item runs the correct rubric and renders checklist + reasons + vetoes + quality×momentum
- ☐ Results are cached and manually re-runnable

---

# PART B — TECHNICAL ARCHITECTURE

*Owner: Technical Architect. Defines how the requirements above are realized.*

## B1. Architecture overview

Three decoupled components. The app never fetches the list live — it reads what the collector already wrote.

```
                    ┌──────────────────────────────────────────────┐
   SCHEDULE ───────▶│  COLLECTOR (Phase 0)                          │
   (daily)          │  GitHub Search+REST · PH GraphQL              │
                    │  → pre-filter → upsert entity + insert snapshot│
                    └───────────────────────┬──────────────────────┘
                                            │ writes
                                            ▼
                    ┌──────────────────────────────────────────────┐
                    │  DATABASE  (entities · snapshots · watchlist · │
                    │             deep_dive_cache)                   │
                    └───────────────────────┬──────────────────────┘
                          reads │                     ▲ writes (cache)
                                ▼                     │
                    ┌──────────────────────────────────────────────┐
                    │  APP                                          │
   BACKGROUND PATH  │  • LIST (Phase 1): read DB, light-rank, state │
   (cheap, no LLM)  │  • DEEP-DIVE (Phase 2): on click →            │
   ON-CLICK PATH    │      fetch fresh detail + run rubric (LLM) →  │
   (expensive)      │      cache result                            │
                    └──────────────────────────────────────────────┘
```

## B2. The two data paths (the core architectural boundary)

| | Background path (list) | On-click path (deep-dive) |
|---|---|---|
| Trigger | Schedule | User clicks an item |
| Work | Fetch counts, pre-filter, light-rank | Fetch full detail, run four-lens rubric |
| LLM? | **No** | **Yes** |
| Cost driver | Fixed (tiny) | Per click |
| Output | Ranked rows | Scored checklist + reasons |

*Do not let LLM work cross into the background path.* This boundary is what keeps the tool cheap and fast.

## B3. Data sources & integration

**GitHub**
- **Candidate discovery:** Search API — `GET /search/repositories?q=stars:>N pushed:>DATE language:X&sort=stars`. (Search API has a tighter limit, ~30 req/min authenticated — page deliberately.)
- **Per-repo detail:** REST/GraphQL — `stargazers_count`, forks, contributors, topics, license, releases, commit recency. **Authenticate** (5,000 req/hr vs. 60 unauth).
- **Adoption enrichment (deep-dive):** package downloads (npm/PyPI), dependent counts.
- **No trending endpoint** — velocity is derived from our snapshots, not fetched.

**Product Hunt**
- GraphQL — `https://api.producthunt.com/v2/api/graphql`, bearer token. Query the day's posts for `name`, `tagline`, `description`, `url`, `website`, `votesCount`, `commentsCount`, `reviewsRating`, and comment text.
- Volume is small (~25–50 launches/day) → no discovery filtering needed; take the day's set.
- Complexity-based rate limit; **commercial use prohibited** (fine here); some fields redacted.

## B4. Data model

Four tables. The key idea: **one entity, many dated snapshots.** (Full field-level detail in Part C.)

**`entities`** — the durable identity of a repo/app
```
id                (pk)
source            'github' | 'producthunt'
external_id       repo full-name  |  PH post id      (unique per source)
name
one_liner         short "what it is"
url
language / topic  (github)
first_seen_at
```

**`snapshots`** — one row per entity per collector run (this is your time-series)
```
id                (pk)
entity_id         (fk → entities)
captured_at
stars / forks     (github)
votes / comments / rating   (producthunt)
raw_json          (full payload for later use)
```
> Velocity = diff of snapshot metrics across a trailing window. Acceleration = change in velocity.

**`watchlist_state`** — per-item user state
```
entity_id         (fk, unique)
state             'seen' | 'watching' | 'dismissed'
note              (optional)
updated_at
```

**`deep_dive_cache`** — Phase 2 results
```
entity_id         (fk, unique)
computed_at
quality_score
momentum_stage
veto_flags        (json)
reasons           (json: the 2–3 explanations)
full_result       (json)
```

## B5. Data flow

**Background (per scheduled run):**
1. GitHub Search + PH GraphQL → candidate set.
2. Pre-filter gate (§B6).
3. For each survivor: **upsert** into `entities`, **insert** a new `snapshots` row.
4. (Read-time) list view computes light momentum score from recent snapshots and orders the list.

**On-click (Phase 2):**
1. Fetch fresh detail + adoption enrichment for the one entity.
2. Run the source-appropriate rubric (§B7).
3. Write `deep_dive_cache`; render checklist + reasons + veto + quality×momentum.

## B6. The pre-filter gate

Cheap, deterministic, no LLM. Only survivors get stored (and, later, deep-dived). This keeps both the DB and the inference bill from scaling with noise.

- **GitHub:** min stars · has a license · not a fork · has README · commit within N days · not on a blocklist.
- **Product Hunt:** min comment count · product URL resolves · not a duplicate re-launch · target language · not spam.

Thresholds start loose and tighten against real data.

## B7. Scoring integration (condensed — full detail in `trend-intelligence-spec.md`)

**Light momentum score (background, no LLM):** velocity + acceleration, adjusted by a **cross-consistency** check (a star/vote spike is trusted more when a matching fork/download/comment-depth signal corroborates it). Produces the list ordering and a coarse **momentum stage** (emerging / rising / peaking / fading).

**Deep-dive rubric (on-click, LLM-assisted):**
- **Repo → CTO-heavy Quality Score:** adoption-over-attention, maintenance pulse, bus factor, problem significance, code depth, maturity, license fit.
- **App → CEO-heavy Business Score:** demand urgency (painkiller vs. vitamin), willingness to pay, moat/clone-risk, distribution/traction, feedback quality, team fit.
- Plus **hard vetoes** (abandoned, security advisory, dead URL, license kill, bought-metric evidence) and the **quality × momentum** placement — the target quadrant being *high quality + still emerging*.

## B8. Scheduling, deployment & failure handling

- **Cadence: daily.** Daily snapshots + a trailing 7-day window for velocity (finer than weekly, still free since no LLM runs in the background).
- **Universe: start small** — 1–3 GitHub languages/topics with a min-stars floor; PH's daily launch set. Widen later.
- **Idempotent runs** — upsert on `entities.external_id`; a re-run inserts snapshots without duplicating identities.
- **Fail loud, degrade safe** — a failed run logs an error and leaves prior data intact; the app always reads the last good snapshot; scrapers (if any) error rather than return empty.

**Recommended stack** (zero-ops personal defaults, all swappable):

| Concern | Recommendation | Why |
|---|---|---|
| Language | **Python** | Best fit for API/data/LLM work |
| Scheduler | **GitHub Actions (cron)** | Free scheduled runs, no server to maintain |
| Database | **SQLite** (→ Postgres only if needed) | Single-user, zero-ops, file-based |
| App/UI | **Streamlit** (fast path) or FastAPI + light frontend | Streamlit builds data tools in hours |
| Deep-dive LLM | **Anthropic API (Claude)** | Runs the rubric on click |

## B9. Cost model & open items

- **Background:** GitHub + PH API calls only — effectively free within rate limits; GitHub Actions minutes free at this scale.
- **On-click:** one bounded LLM evaluation per deep-dive, cached. Total cost tracks *clicks*, not catalog size.
- **Deferred by decision:** the validation loop (spec §8) — buildable later; retained daily snapshots keep that door open at no cost.
- **Remaining tuning (not blocking):** pre-filter thresholds, momentum-window length, rubric weights — all calibrated by eye after launch.

---

# PART C — DATA DICTIONARY

*Owner: Technical Architect. Every field captured and displayed, by source, tier, and view. Realizes the schema in §B4 at field level.*

## C0. Governing principles

1. **Capture broad, display narrow.** Store the full raw payload (`raw_json`) plus the extracted columns below; surface only the handful that drive a decision.
2. **Two capture tiers.** *Background* = cheap, one API call per item, every cycle. *Deep-dive* = expensive, extra calls, only on click. Never pull deep-dive fields in the background.
3. **Store vs. derive.** Raw fields are captured; momentum/scores are *computed* from snapshots at read time (or on click), not stored as raw.

Legend — **Tier:** BG = background, DD = deep-dive. **Table:** `E`=entities, `S`=snapshots, `C`=deep_dive_cache, `W`=watchlist_state.

## C1. Capture — GitHub (Background tier)

From the Search API result object and/or `GET /repos/{owner}/{repo}` — all in a single call per repo.

| Field | Type | API source | Table | Notes |
|---|---|---|---|---|
| external_id | string | `full_name` (owner/repo) | E | unique key per source |
| name | string | `name` | E | |
| one_liner | string | `description` | E | the "what it is" |
| url | string | `html_url` | E | |
| language | string | `language` | E | primary language |
| topics | string[] | `topics` | E | tags |
| owner_type | enum | `owner.type` | E | User / Organization (company-backed → bus factor) |
| created_at | datetime | `created_at` | E | for age |
| archived | bool | `archived` | S | **veto signal** |
| is_fork | bool | `fork` | — | used by pre-filter, not stored |
| stars | int | `stargazers_count` | S | raw count (velocity source) |
| forks | int | `forks_count` | S | |
| watchers | int | `subscribers_count` | S | true watchers |
| open_issues | int | `open_issues_count` | S | |
| pushed_at | datetime | `pushed_at` | S | last push → maintenance pulse |
| license | string | `license.spdx_id` | S | MIT, GPL-3.0…; null = flag |
| default_branch | string | `default_branch` | E | needed for deep-dive file lookups |
| raw_json | json | full response | S | keep everything for later |

## C2. Capture — Product Hunt (Background tier)

From the GraphQL `Post` node — one query returns the day's launches.

| Field | Type | API source | Table | Notes |
|---|---|---|---|---|
| external_id | string | `id` | E | PH post id, unique key |
| name | string | `name` | E | |
| one_liner | string | `tagline` | E | |
| description | string | `description` | E | |
| ph_url | string | `url` | E | the Product Hunt page |
| product_url | string | `website` | E | actual product site → URL-survival check |
| topics | string[] | `topics.edges[].node.name` | E | |
| created_at | datetime | `createdAt` | E | launch date = T |
| votes | int | `votesCount` | S | interest (velocity source) |
| comments | int | `commentsCount` | S | discussion volume |
| rating | float | `reviewsRating` | S | feedback quality |
| reviews_count | int | `reviewsCount` | S | |
| raw_json | json | full node | S | |

> **Caveat:** maker/name fields are often redacted — do not design around them.

## C3. Capture — Deep-dive tier (on click only, both sources)

Extra API calls / external lookups. Fetched only when an item is opened; results land in `C`.

**GitHub**
| Field | Type | Source | Notes |
|---|---|---|---|
| contributor_count | int | `GET /repos/../contributors` | bus factor |
| latest_release / release_count | date, int | `GET /repos/../releases` | release cadence |
| has_tests / has_ci | bool | file tree (`git/trees?recursive=1`): test dirs, `.github/workflows` | code depth |
| readme_text | text | `GET /repos/../readme` | LLM problem-significance |
| dependents_count | int | dependents page / API | real adoption |
| package_downloads | int/series | npm / PyPI (external) | hardest-to-fake adoption |

**Product Hunt**
| Field | Type | Source | Notes |
|---|---|---|---|
| comment_bodies | text[] | GraphQL `comments.edges[].node.body` | LLM sentiment / painkiller-vs-vitamin |
| pricing_detected | bool | crawl `product_url` | willingness to pay |
| url_alive | bool | HTTP check on `product_url` | **veto signal** (dead = negative) |

## C4. Derived / computed fields

Not captured — computed from snapshots (background) or during the deep-dive. Nothing here is "raw."

| Field | Computed from | When | Used by |
|---|---|---|---|
| age_days | now − created_at | read | context |
| days_since_push (gh) | now − pushed_at | read | maintenance pulse |
| days_since_launch (ph) | now − created_at | read | context |
| stars_per_week (gh) | Δ stars over trailing 7d snapshots | read | **list ranking** |
| votes/comments velocity (ph) | Δ over trailing window | read | **list ranking** |
| acceleration | change in velocity between windows | read | momentum stage |
| fork_to_star_ratio (gh) | forks ÷ stars | read | usage vs. bookmarking |
| comment_to_vote_ratio (ph) | comments ÷ votes | read | engagement depth |
| cross_consistency_flag | do independent signals corroborate the spike? | read | **anti-gaming / ranking** |
| momentum_stage | velocity + acceleration | read | list badge |
| light_momentum_score | velocity + acceleration × consistency | read | **list order** |
| quality_score / business_score | four-lens rubric | on click | deep-dive |
| veto_flags | hard disqualifiers | on click | deep-dive |
| quality×momentum quadrant | quality_score × momentum_stage | on click | deep-dive |
| reasons | LLM, from rubric evidence | on click | deep-dive |

## C5. User-state fields (`W`)

| Field | Type | Values | Notes |
|---|---|---|---|
| state | enum | seen / watching / dismissed | the watchlist |
| note | text | free | optional |
| updated_at | datetime | | |

## C6. Display — List view (Phase 1, the skim row)

Minimal by design — just enough to decide "worth a click?" Everything here is cheap (captured or read-time derived); **no deep-dive fields**.

| Shown | From | Purpose |
|---|---|---|
| name + owner / source badge | E | identity |
| one_liner | E | what it is |
| language / topics | E | relevance filter |
| **primary momentum**: stars/week (gh) · votes + comments (ph) | derived | the ranking signal |
| momentum stage (↑ emerging/rising · → steady · ↓ fading) | derived | timing at a glance |
| total stars / total votes | S | secondary context |
| consistency indicator | derived | trust / anti-gaming tell |
| age / last-active | derived | freshness of the *item* |
| watchlist control (seen/watching/dismiss) | W | the action |
| "as of \<timestamp\>" (global) | last run | freshness of the *data* |

Default sort: `light_momentum_score` desc; filterable by source / language / stage / state.

## C7. Display — Deep-dive view (Phase 2, on click)

Rich. Renders the rubric result plus its supporting evidence. Reads `C` (cached) or computes fresh.

| Shown | From | |
|---|---|---|
| header: name, one_liner, source, link | E | |
| **score**: quality (repo) / business (app), 0–100 | C | headline number |
| **quality × momentum quadrant** | C | is it the target (good + still emerging)? |
| **veto flags** (prominent if any) | C | kill signals first |
| **the 2–3 reasons** | C | why it scored this way |
| rubric checklist (each feature: pass/score + evidence) | C | the actual checklist |
| supporting evidence — repo: contributors, release cadence, tests/CI, license, downloads/dependents | DD capture | |
| supporting evidence — app: pricing detected, comment sentiment summary, url-alive, comment-depth | DD capture | |
| computed_at + "re-run" control | C | cache freshness |

## C8. Design notes

- **Background stays single-call.** Contributors, releases, file tree, downloads, comment bodies, pricing — all deep-dive tier. Pulling them per cycle would blow rate limits and the "cheap/no-LLM" boundary.
- **`raw_json` is your insurance.** Store the whole payload every snapshot; a field not extracted today is still there tomorrow — no re-fetch, no lost history.
- **Two freshness clocks, don't conflate them.** *Item* freshness (last push / launch age) vs. *data* freshness ("as of" last collector run). Both shown, different meanings.
- **Thresholds/weights come later.** Which fields *rank* and how heavily is tuned by eye after launch; this spec fixes *what exists*, not the weights.

---

*Build order restated: **Phase 0 collector first** (it starts the irreplaceable time-series), then **Phase 1 list**, then **Phase 2 deep-dive**. Everything sophisticated lives behind a click and is built last. Full scoring logic lives in the companion `trend-intelligence-spec.md`.*
