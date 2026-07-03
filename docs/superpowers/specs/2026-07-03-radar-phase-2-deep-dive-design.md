# RADAR — Phase 2 Deep-Dive Design Spec

| | |
|---|---|
| **Date** | 2026-07-03 |
| **Scope** | Phase 2 — the on-click deep-dive: evidence fetch + LLM rubric (Claude Sonnet) in a Supabase Edge Function, async via Realtime, rendered in the Flutter overlay; Scope blips go solid. |
| **Builds on** | Phase 0 collector (live) · Phase 1 app (`phase-1-app`) · `deep_dive_cache` table (already created) · `RADAR.dc.html` overlay design |
| **Status** | Approved in brainstorming; pending written-spec review |

## 1. Context

Phases 0–1 give a cheap, always-on ranked list with no LLM. Phase 2 adds the **expensive, on-click evaluation**: for a single item, fetch deep-dive-tier evidence, score it against a source-appropriate rubric with an LLM, and render the result. Everything expensive stays behind a tap; the background path never changes.

## 2. Locked decisions

| # | Decision | Choice |
|---|---|---|
| 1 | Rubric source | **Derive** from build-doc §B7 + the prototype's worked examples (no external spec needed). |
| 2 | Compute host | **Supabase Edge Function** (Deno/TS) — one platform, native Realtime, no new host. |
| 3 | Model | **Claude Sonnet** (nuanced judgment; Haiku too weak, Opus overkill). One cached call per deep-dive. |
| 4 | Execution | **Async + Supabase Realtime** — invoke → `status='running'` → work → `status='done'`; app subscribes. Cached indefinitely; manual re-run. |
| 5 | Storage | Existing `deep_dive_cache` table — **no schema change** to it. |

## 3. Architecture

```
Flutter app ── functions.invoke('deep-dive', {entity_id}) ──▶ Supabase Edge Function
     ▲                                                          │ 1. upsert deep_dive_cache status='running'
     │ Realtime subscription on deep_dive_cache row             │ 2. fetch deep-dive-tier evidence (GitHub/npm/PyPI or PH)
     │ (running → done/error)                                   │ 3. Claude Sonnet → forced-JSON rubric result
     └──────────────────────── writes ◀────────────────────────┘ 4. upsert status='done' + results
                                                                Anthropic API (key = function secret)
```

**Invariant preserved:** the LLM is called only here, only on a tap. Collector and list are untouched.

## 4. Evidence fetchers (Edge Function, Deno `fetch`)

Fetched only on click; tolerant of partial failure (a dead lookup flags missing evidence, never fails the whole dive).

**GitHub** (uses the existing GitHub token, server-side):
- `GET /repos/{full}/contributors` → contributor count (bus factor)
- `GET /repos/{full}/releases` → latest release + cadence
- `GET /repos/{full}/git/trees/{branch}?recursive=1` → presence of tests dirs + `.github/workflows` (code depth / CI)
- `GET /repos/{full}/readme` → README text (LLM problem-significance)
- npm / PyPI downloads + dependents (adoption-over-attention) — public APIs, best-effort

**Product Hunt** (existing PH token):
- comment bodies (`comments.edges[].node.body`) → sentiment / painkiller-vs-vitamin
- `product_url` fetch → pricing detected? (scan for pricing signals)
- HTTP HEAD/GET on `product_url` → URL-alive (veto signal)

## 5. Rubric (Claude Sonnet, forced JSON)

One structured prompt per source; the model is forced to call a `submit_evaluation` tool whose schema is the output (no free-text parsing).

**Repo → Quality Score (0–100), 7 dimensions (0–10 each):**
adoption over attention · maintenance pulse · bus factor · problem significance · code depth · maturity · license fit.

**App → Business Score (0–100), 6 dimensions:**
demand urgency · willingness to pay · moat / clone-risk · distribution & traction · feedback quality · team fit.

**Hard vetoes** (any → prominent, caps the verdict): archived/abandoned · security advisory · dead product URL · license kill · bought-metric evidence (`consistency='suspicious'` from the view).

**Output schema (→ `deep_dive_cache`):**
```json
{
  "score": 0,                        // → quality_score
  "verdict": "one-line summary",
  "vetoes":  [{"title": "", "note": ""}],            // → veto_flags
  "reasons": [{"tone": "pos|warn|neg", "title": "", "note": ""}],  // 2-3 → reasons
  "rubric":  [{"label": "", "score": 0, "state": "pass|watch|fail", "evidence": ""}],
  "evidence":[{"label": "", "value": "", "sub": ""}]
}
```
The whole object → `full_result`; `score` → `quality_score`; `vetoes` → `veto_flags`; `reasons` → `reasons`. `momentum_stage` continues to come from `signal_feed` (the view), not the LLM — the deep-dive judges **quality**; momentum stays background-computed.

## 6. Data — one small view addition

`deep_dive_cache` itself is unchanged. To let the app show **solid Scope blips** and a "scored" state without a second query, extend `signal_feed` (Phase 1's view) with a left join:
- add `dd.quality_score` and `dd.status as deep_dive_status` (null when never dived).
- `SignalItem` gains `qualityScore (int?)` + `deepDiveStatus (String?)`.
- **Scope**: blip uses `qualityScore` and renders **solid** when a `done` deep-dive exists; else `provisionalQuality`, **hollow** (Phase 1 behavior).

## 7. Flutter overlay (from the prototype)

A slide-up overlay driven by a `StreamBuilder` on the `deep_dive_cache` row (Realtime):
- `status='running'` → "Evaluating…" with a spinner (the multi-second job).
- `status='done'` → the full result: header, score ring, quality×momentum quadrant, **veto cards** (if any), the 2–3 "why" reasons, the rubric checklist (per-dimension score + evidence), the supporting-evidence grid, and `computed_at` + **Re-run**.
- `status='error'` → error + retry (re-invoke).

Tapping a Feed/Scope row opens the overlay and invokes the function if no fresh cache exists (else renders the cache immediately).

## 8. Error handling & cost

- Function failure → `status='error'` + `error_note`; overlay shows retry.
- Partial evidence failure → produce a result with missing signals flagged, never crash.
- **Cost:** one bounded Sonnet call per deep-dive, cached forever → total LLM spend tracks *clicks*, not catalog size (NFR-1 preserved). Re-run is the only way to re-spend.

## 9. Testing

- Evidence-fetch **parsers** → unit-tested against captured fixtures (GitHub/npm/PH JSON).
- Rubric **output** → JSON-schema validation test (shape + ranges); the tool-forced schema prevents malformed results.
- The LLM's **judgment** → eyeballed on real items (not asserted).
- Flutter overlay → the running/done/error **state machine** renders correctly (widget test with a faked cache stream).

## 10. Prerequisites (setup before build)

- **Anthropic API key** (yours) → stored as a Supabase Edge Function secret, never in the app.
- **Supabase CLI** → to deploy the Edge Function (`supabase functions deploy deep-dive`). Guided at build time.

## 11. Definition of done

- ☐ `deep-dive` Edge Function: fetches evidence, runs the Sonnet rubric, writes `deep_dive_cache` (running→done/error). Anthropic key server-side only.
- ☐ `signal_feed` extended with `quality_score` + `deep_dive_status`; `SignalItem` updated.
- ☐ App invokes + subscribes via Realtime; overlay renders running/done/error per the prototype.
- ☐ Scope blips go **solid** for deep-dived items.
- ☐ Cached indefinitely; manual re-run works.
- ☐ **Out:** the validation loop (backtest / precision@k / re-weighting) — still deferred.

## 12. Deferred / open

- **Validation loop** — retained snapshots keep it possible later; not in Phase 2.
- **Rubric weights / thresholds** — the LLM judges from criteria; exact per-dimension weighting tuned by eye after real deep-dives.
- **iOS build** of the app — unchanged from Phase 1 (needs macOS).
