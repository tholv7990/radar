# RADAR Phase 2A — Deep-Dive Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch agency agents by role (Database Optimizer for the view; Backend Architect / AI Engineer for the Edge Function; Code Reviewer for task reviews).

**Goal:** A Supabase Edge Function `deep-dive` that, on invoke, fetches deep-dive-tier evidence for one entity, scores it with Claude Sonnet against a source-appropriate rubric, and writes the result to `deep_dive_cache` (status running→done/error) — plus a `signal_feed` view extension exposing the cached score.

**Architecture:** App invokes the function with `{entity_id}`; the function sets `status='running'`, fetches evidence (GitHub/npm/PyPI or Product Hunt), calls Claude Sonnet with a forced-JSON tool schema, and upserts `status='done'` + results. Deno/TypeScript; Anthropic + Supabase service keys live as function secrets. The app (Plan 2B) subscribes via Realtime.

**Tech Stack:** Supabase Edge Functions (Deno) · `@anthropic-ai/sdk` · `@supabase/supabase-js` · Postgres · Python (existing, for the DB task + smoke).

## Global Constraints

- **No LLM anywhere but this function, only on invoke.** (Spec invariant — the background/list path is untouched.)
- **Model:** `claude-sonnet-5` (Claude Sonnet). One call per deep-dive; result cached in `deep_dive_cache`, re-run only on manual re-invoke.
- **Forced JSON:** the model MUST return via a tool (`submit_evaluation`) whose input schema IS the output — no free-text parsing.
- **Secrets server-side only:** `ANTHROPIC_API_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `GH_PAT`, `PH_TOKEN` are Edge Function secrets — never in the app or committed.
- **Partial-failure tolerant:** a failed evidence lookup (e.g. npm down) flags missing evidence; it does NOT fail the deep-dive.
- **Output → `deep_dive_cache`:** `score → quality_score`, `vetoes → veto_flags`, `reasons → reasons`, whole object → `full_result`. `momentum_stage` stays from `signal_feed` (not the LLM).
- **`deep_dive_cache` schema is unchanged** (created in Phase 1 Task 1). Only `signal_feed` gains two columns.
- **Verification environments:** Task 1 (DB view) verifies **here** via psycopg2. Tasks 2–6 (Edge Function) require the **Supabase CLI + Deno + an Anthropic API key** — their `supabase functions serve`/`deploy` + invoke steps run once that setup exists.

## File structure

```
db/
  signal_feed_v2.sql              # view + quality_score + deep_dive_status
scripts/
  apply_signal_feed_v2.py         # apply via psycopg2
  test_signal_feed_v2.py          # verify new columns
supabase/
  config.toml                     # supabase project config (functions block)
  functions/deep-dive/
    index.ts                      # HTTP entry: parse, orchestrate, status flow
    types.ts                      # Evidence + EvalResult shared types
    db.ts                         # service-role supabase client + cache upserts
    github.ts                     # GitHub/npm/PyPI evidence fetchers
    producthunt.ts                # PH evidence fetchers
    rubric.ts                     # Anthropic call + prompts + submit_evaluation schema
    fixtures/                      # captured JSON for deno tests
    rubric_test.ts                # schema/shape test
    parse_test.ts                 # fetcher-parser tests
```

## Prerequisites (before Tasks 2–6)

1. **Anthropic API key** — from console.anthropic.com. You'll add it as a function secret (Task 6).
2. **Supabase CLI** — `npm i -g supabase` (or scoop/brew). Used to serve/deploy the function.
3. `supabase login` + `supabase link --project-ref rdpvppcaskhoedvuhamp`.

---

### Task 1: `signal_feed` v2 — expose the cached score *(verifiable here)*

**Files:**
- Create: `db/signal_feed_v2.sql`, `scripts/apply_signal_feed_v2.py`, `scripts/test_signal_feed_v2.py`

**Interfaces:**
- Consumes: existing `signal_feed` (Phase 1), `deep_dive_cache`.
- Produces: `signal_feed` now also selects `quality_score (int|null)` and `deep_dive_status (text|null)` via a left join on `deep_dive_cache`.

- [ ] **Step 1: Write `db/signal_feed_v2.sql`** — re-create the view with the deep-dive left join

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
),
calc as (
  select
    e.id, e.source, e.external_id, e.name, e.one_liner, e.url,
    e.language, e.topics, e.owner_type, e.created_at,
    l.captured_at, l.stars, l.forks, l.watchers, l.votes, l.comments,
    l.rating, l.pushed_at, l.archived, l.provisional_quality,
    p.id as prior_id,
    case when p.id is null then null
         when e.source='github' then (l.stars - p.stars)
         else ((coalesce(l.votes,0)+coalesce(l.comments,0))
             - (coalesce(p.votes,0)+coalesce(p.comments,0))) end as velocity,
    case when e.source='github' then (l.forks - p.forks)
         else (l.comments - p.comments) end as secondary_velocity,
    case when e.source='github' then l.stars else l.votes end as total_metric,
    w.state as watch_state,
    dd.quality_score as quality_score,
    dd.status as deep_dive_status
  from entities e
  join latest l on l.entity_id = e.id
  left join prior p on p.entity_id = e.id
  left join watchlist_state w on w.entity_id = e.id
  left join deep_dive_cache dd on dd.entity_id = e.id
)
select
  c.*,
  case
    when c.prior_id is null then 'new'
    when c.velocity <= 0 then 'mixed'
    when c.secondary_velocity > 0 then 'corroborated'
    when c.velocity > 50 and c.secondary_velocity = 0 then 'suspicious'
    else 'mixed'
  end as consistency,
  case
    when c.prior_id is null then 'new'
    when c.velocity <= 0 then 'fading'
    when c.velocity::numeric / nullif(c.total_metric,0) > 0.10 then 'emerging'
    when c.velocity::numeric / nullif(c.total_metric,0) > 0.03 then 'rising'
    else 'steady'
  end as momentum_stage,
  coalesce(c.velocity::numeric, c.provisional_quality::numeric) as rank_score
from calc c;
grant select on signal_feed to authenticated;
```

- [ ] **Step 2: Write `scripts/apply_signal_feed_v2.py`**

```python
"""Apply the signal_feed v2 view. Run: python -m scripts.apply_signal_feed_v2"""
from pathlib import Path
from collector.config import load_config
from collector import db

cfg = load_config()
conn = db.connect(cfg)
with conn.cursor() as cur:
    cur.execute(Path("db/signal_feed_v2.sql").read_text(encoding="utf-8"))
conn.commit()
conn.close()
print("signal_feed v2 applied")
```

- [ ] **Step 3: Write `scripts/test_signal_feed_v2.py`**

```python
"""Verify signal_feed v2 exposes the deep-dive columns. Run: python -m scripts.test_signal_feed_v2"""
from collector.config import load_config
from collector import db

conn = db.connect(load_config())
cur = conn.cursor()
cur.execute("select column_name from information_schema.columns where table_name='signal_feed'")
cols = {r[0] for r in cur.fetchall()}
for required in ("quality_score", "deep_dive_status"):
    assert required in cols, f"missing column {required}"
# no deep-dives yet → both null everywhere
cur.execute("select count(*) from signal_feed where quality_score is not null")
assert cur.fetchone()[0] == 0, "expected no quality_score before any deep-dive"
# authenticated can still read
cur.execute("set role authenticated"); cur.execute("select count(*) from signal_feed"); assert cur.fetchone()[0] > 0
cur.execute("reset role")
conn.close()
print("signal_feed v2 OK — quality_score + deep_dive_status present, null pre-dive")
```

- [ ] **Step 4: Apply + verify**

Run: `python -m scripts.apply_signal_feed_v2` → `signal_feed v2 applied`
Run: `python -m scripts.test_signal_feed_v2` → `signal_feed v2 OK …`

- [ ] **Step 5: Commit**

```bash
git add db/signal_feed_v2.sql scripts/apply_signal_feed_v2.py scripts/test_signal_feed_v2.py
git commit -m "feat(deep-dive): signal_feed exposes cached quality_score + status"
```

---

### Task 2: Edge Function scaffold — config, shared types, DB client

**Files:**
- Create: `supabase/config.toml`, `supabase/functions/deep-dive/types.ts`, `supabase/functions/deep-dive/db.ts`, `supabase/functions/deep-dive/index.ts` (minimal)

**Interfaces:**
- Produces: `types.ts` (`Evidence`, `EvalResult`); `db.ts` (`serviceClient()`, `setRunning(id)`, `writeResult(id, r)`, `writeError(id, msg)`, `getEntity(id)`); a stub `index.ts` that returns 200.

- [ ] **Step 1: `supabase/config.toml`**

```toml
project_id = "rdpvppcaskhoedvuhamp"

[functions.deep-dive]
verify_jwt = true
```

- [ ] **Step 2: `types.ts`**

```typescript
export interface EvidenceItem { label: string; value: string; sub?: string }
export interface Evidence {
  source: "github" | "producthunt";
  grid: EvidenceItem[];          // the supporting-signals grid
  vetoHints: { title: string; note: string }[];  // hard-signal candidates (dead URL, archived…)
  context: Record<string, unknown>; // raw-ish signals handed to the LLM (readme, comments, counts)
}
export interface RubricRow { label: string; score: number; state: "pass" | "watch" | "fail"; evidence: string }
export interface EvalResult {
  score: number;
  verdict: string;
  vetoes: { title: string; note: string }[];
  reasons: { tone: "pos" | "warn" | "neg"; title: string; note: string }[];
  rubric: RubricRow[];
  evidence: EvidenceItem[];
}
export interface Entity {
  id: number; source: string; external_id: string; name: string;
  one_liner: string | null; url: string | null; default_branch: string | null;
  raw_json: Record<string, unknown>;
}
```

- [ ] **Step 3: `db.ts`**

```typescript
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { Entity, EvalResult } from "./types.ts";

export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
}

export async function getEntity(db: SupabaseClient, id: number): Promise<Entity> {
  const { data, error } = await db
    .from("entities")
    .select("id, source, external_id, name, one_liner, url, default_branch")
    .eq("id", id).single();
  if (error) throw new Error(`entity ${id}: ${error.message}`);
  // latest snapshot raw_json (for context)
  const { data: snap } = await db.from("snapshots")
    .select("raw_json").eq("entity_id", id)
    .order("captured_at", { ascending: false }).limit(1).single();
  return { ...data, raw_json: snap?.raw_json ?? {} } as Entity;
}

export async function setRunning(db: SupabaseClient, id: number) {
  await db.from("deep_dive_cache").upsert(
    { entity_id: id, status: "running", error_note: null, computed_at: new Date().toISOString() },
    { onConflict: "entity_id" });
}
export async function writeResult(db: SupabaseClient, id: number, r: EvalResult) {
  await db.from("deep_dive_cache").upsert({
    entity_id: id, status: "done", computed_at: new Date().toISOString(),
    quality_score: r.score, veto_flags: r.vetoes, reasons: r.reasons, full_result: r,
  }, { onConflict: "entity_id" });
}
export async function writeError(db: SupabaseClient, id: number, msg: string) {
  await db.from("deep_dive_cache").upsert(
    { entity_id: id, status: "error", error_note: msg, computed_at: new Date().toISOString() },
    { onConflict: "entity_id" });
}
```

- [ ] **Step 4: minimal `index.ts`**

```typescript
Deno.serve(async (req) => {
  try {
    const { entity_id } = await req.json();
    if (!entity_id) return new Response("entity_id required", { status: 400 });
    return Response.json({ ok: true, entity_id }); // real orchestration in Task 5
  } catch (e) {
    return new Response(String(e), { status: 500 });
  }
});
```

- [ ] **Step 5: Type-check**

Run: `cd supabase/functions/deep-dive && deno check index.ts db.ts types.ts`
Expected: no type errors. (Deno ships with the Supabase CLI; if standalone Deno isn't installed, this runs under `supabase functions serve` in Task 6.)

- [ ] **Step 6: Commit**

```bash
git add supabase/config.toml supabase/functions/deep-dive/{config.toml,types.ts,db.ts,index.ts} 2>/dev/null; git add supabase
git commit -m "feat(deep-dive): edge function scaffold + db client + types"
```

---

### Task 3: Evidence fetchers — GitHub + Product Hunt

**Files:**
- Create: `supabase/functions/deep-dive/github.ts`, `supabase/functions/deep-dive/producthunt.ts`, `fixtures/gh_contributors.json`, `fixtures/ph_post.json`, `parse_test.ts`

**Interfaces:**
- Consumes: `Entity`, `Evidence` (types.ts).
- Produces: `githubEvidence(entity): Promise<Evidence>`, `productHuntEvidence(entity): Promise<Evidence>`. Both catch per-signal errors and record them in `grid`/`vetoHints` rather than throwing.

- [ ] **Step 1: `github.ts`**

```typescript
import { Entity, Evidence, EvidenceItem } from "./types.ts";

const GH = "https://api.github.com";
function ghHeaders() {
  return { "Authorization": `Bearer ${Deno.env.get("GH_PAT")}`, "Accept": "application/vnd.github+json", "User-Agent": "radar" };
}
async function safe<T>(fn: () => Promise<T>, fallback: T): Promise<T> {
  try { return await fn(); } catch { return fallback; }
}

export async function githubEvidence(e: Entity): Promise<Evidence> {
  const full = e.external_id; // owner/repo
  const grid: EvidenceItem[] = [];
  const vetoHints: { title: string; note: string }[] = [];
  const ctx: Record<string, unknown> = {};

  const raw = e.raw_json as Record<string, unknown>;
  if (raw["archived"] === true) vetoHints.push({ title: "Archived repository", note: "Repo is archived/read-only." });

  const contributors = await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/contributors?per_page=100`, { headers: ghHeaders() });
    if (!r.ok) throw new Error();
    return (await r.json() as unknown[]).length;
  }, -1);
  if (contributors >= 0) { grid.push({ label: "Contributors", value: String(contributors) }); ctx.contributors = contributors; }

  const releases = await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/releases?per_page=10`, { headers: ghHeaders() });
    if (!r.ok) throw new Error();
    return await r.json() as { tag_name: string; published_at: string }[];
  }, []);
  if (releases.length) {
    grid.push({ label: "Latest release", value: releases[0].tag_name });
    ctx.release_count = releases.length; ctx.latest_release = releases[0].published_at;
  }

  const tree = await safe(async () => {
    const branch = e.default_branch ?? "main";
    const r = await fetch(`${GH}/repos/${full}/git/trees/${branch}?recursive=1`, { headers: ghHeaders() });
    if (!r.ok) throw new Error();
    return (await r.json() as { tree: { path: string }[] }).tree.map((t) => t.path);
  }, [] as string[]);
  const hasTests = tree.some((p) => /(^|\/)(test|tests|spec|__tests__)(\/|$)/i.test(p));
  const hasCI = tree.some((p) => p.startsWith(".github/workflows/"));
  if (tree.length) { grid.push({ label: "Tests / CI", value: `${hasTests ? "tests" : "no tests"} · ${hasCI ? "CI" : "no CI"}` }); ctx.hasTests = hasTests; ctx.hasCI = hasCI; }

  const readme = await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/readme`, { headers: { ...ghHeaders(), "Accept": "application/vnd.github.raw" } });
    if (!r.ok) throw new Error();
    return (await r.text()).slice(0, 6000);
  }, "");
  if (readme) ctx.readme = readme;

  grid.push({ label: "License", value: String(raw["license"] && (raw["license"] as Record<string, string>)["spdx_id"] || "—") });
  return { source: "github", grid, vetoHints, context: ctx };
}
```

- [ ] **Step 2: `producthunt.ts`**

```typescript
import { Entity, Evidence, EvidenceItem } from "./types.ts";

async function safe<T>(fn: () => Promise<T>, fallback: T): Promise<T> {
  try { return await fn(); } catch { return fallback; }
}

export async function productHuntEvidence(e: Entity): Promise<Evidence> {
  const raw = e.raw_json as Record<string, unknown>;
  const grid: EvidenceItem[] = [];
  const vetoHints: { title: string; note: string }[] = [];
  const ctx: Record<string, unknown> = {};

  const productUrl = (raw["website"] as string) ?? null;
  // URL-alive (veto signal)
  const alive = productUrl ? await safe(async () => {
    const r = await fetch(productUrl, { method: "GET", redirect: "follow" });
    return r.ok;
  }, false) : false;
  grid.push({ label: "URL alive", value: alive ? "Yes" : "No" });
  if (productUrl && !alive) vetoHints.push({ title: "Dead product URL", note: `${productUrl} did not respond OK.` });
  ctx.url_alive = alive; ctx.product_url = productUrl;

  // pricing detected (crawl product page)
  if (productUrl && alive) {
    const html = await safe(async () => (await fetch(productUrl)).text(), "");
    const pricing = /\$\d|\bpricing\b|\bper month\b|\/mo\b|per seat/i.test(html);
    grid.push({ label: "Pricing", value: pricing ? "detected" : "none" });
    ctx.pricing_detected = pricing;
  }

  // comment bodies for sentiment (from stored raw_json if present, else skip)
  const comments = (raw["_comment_bodies"] as string[]) ?? [];
  if (comments.length) ctx.comment_sample = comments.slice(0, 40);
  grid.push({ label: "Reviews", value: `${raw["reviewsRating"] ?? "—"}★`, sub: String(raw["reviewsCount"] ?? "") });
  ctx.rating = raw["reviewsRating"]; ctx.votes = raw["votesCount"]; ctx.comments = raw["commentsCount"];
  return { source: "producthunt", grid, vetoHints, context: ctx };
}
```

- [ ] **Step 3: `parse_test.ts`** (fixture-based; no network)

```typescript
import { assert, assertEquals } from "jsr:@std/assert";
// Pure helper extracted for testing: tests/CI detection from a file list.
export function detectTestsCI(paths: string[]) {
  return {
    hasTests: paths.some((p) => /(^|\/)(test|tests|spec|__tests__)(\/|$)/i.test(p)),
    hasCI: paths.some((p) => p.startsWith(".github/workflows/")),
  };
}
Deno.test("detects tests + CI from tree paths", () => {
  const r = detectTestsCI(["src/main.rs", "tests/it.rs", ".github/workflows/ci.yml"]);
  assert(r.hasTests); assert(r.hasCI);
});
Deno.test("no false positives", () => {
  const r = detectTestsCI(["src/main.rs", "README.md"]);
  assertEquals(r.hasTests, false); assertEquals(r.hasCI, false);
});
```

(Refactor `github.ts` to import `detectTestsCI` from a shared spot or duplicate the regex in the test — keep one source of truth: move `detectTestsCI` into `github.ts` and import it in the test.)

- [ ] **Step 4: Run the parser test**

Run: `cd supabase/functions/deep-dive && deno test parse_test.ts`
Expected: 2 passed. (Runs under the Supabase CLI's Deno; if standalone Deno absent, defer to Task 6's `functions serve` environment.)

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/deep-dive/{github.ts,producthunt.ts,parse_test.ts}
git commit -m "feat(deep-dive): github + product hunt evidence fetchers"
```

---

### Task 4: Rubric — Claude Sonnet with forced-JSON tool

**Files:**
- Create: `supabase/functions/deep-dive/rubric.ts`, `rubric_test.ts`

**Interfaces:**
- Consumes: `Evidence`, `EvalResult`.
- Produces: `evaluate(evidence, entity): Promise<EvalResult>`; `SUBMIT_TOOL` (the JSON schema); `promptFor(evidence, entity): string`.

- [ ] **Step 1: `rubric.ts`**

```typescript
import Anthropic from "npm:@anthropic-ai/sdk@0.32";
import { Entity, Evidence, EvalResult } from "./types.ts";

const REPO_DIMS = ["Adoption over attention","Maintenance pulse","Bus factor","Problem significance","Code depth","Maturity","License fit"];
const APP_DIMS  = ["Demand urgency","Willingness to pay","Moat / clone-risk","Distribution & traction","Feedback quality","Team fit"];

export const SUBMIT_TOOL = {
  name: "submit_evaluation",
  description: "Return the structured evaluation.",
  input_schema: {
    type: "object",
    properties: {
      score: { type: "integer", minimum: 0, maximum: 100 },
      verdict: { type: "string" },
      vetoes: { type: "array", items: { type: "object", properties: { title: {type:"string"}, note:{type:"string"} }, required:["title","note"] } },
      reasons: { type: "array", minItems: 2, maxItems: 3, items: { type: "object", properties: { tone:{enum:["pos","warn","neg"]}, title:{type:"string"}, note:{type:"string"} }, required:["tone","title","note"] } },
      rubric: { type: "array", items: { type: "object", properties: { label:{type:"string"}, score:{type:"integer",minimum:0,maximum:10}, state:{enum:["pass","watch","fail"]}, evidence:{type:"string"} }, required:["label","score","state","evidence"] } },
    },
    required: ["score","verdict","vetoes","reasons","rubric"],
  },
} as const;

export function promptFor(ev: Evidence, e: Entity): string {
  const dims = ev.source === "github" ? REPO_DIMS : APP_DIMS;
  const lens = ev.source === "github"
    ? "You are a skeptical CTO judging whether this open-source repo is trustworthy to adopt — reward adoption/usage over attention/stars."
    : "You are a skeptical CEO/investor judging whether this Product Hunt launch is a real business — reward painkillers over vitamins and evidence of willingness-to-pay.";
  return [
    lens,
    `Item: ${e.name} — ${e.one_liner ?? ""} (${e.url ?? ""})`,
    `Score EACH dimension 0-10 with one-line evidence, then an overall 0-100 score and a one-line verdict.`,
    `Dimensions: ${dims.join(", ")}.`,
    `Apply HARD VETOES where warranted (archived/abandoned, security advisory, dead URL, license kill, bought-metric evidence) — a veto caps the verdict.`,
    `Give 2-3 "why" reasons (tone pos/warn/neg).`,
    `Evidence collected:`,
    JSON.stringify(ev.context, null, 2),
    ev.vetoHints.length ? `Veto hints from deterministic checks: ${JSON.stringify(ev.vetoHints)}` : "",
    `Return ONLY via the submit_evaluation tool.`,
  ].join("\n\n");
}

export async function evaluate(ev: Evidence, e: Entity): Promise<EvalResult> {
  const client = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! });
  const msg = await client.messages.create({
    model: "claude-sonnet-5",
    max_tokens: 2000,
    tools: [SUBMIT_TOOL as unknown as Anthropic.Tool],
    tool_choice: { type: "tool", name: "submit_evaluation" },
    messages: [{ role: "user", content: promptFor(ev, e) }],
  });
  const block = msg.content.find((b) => b.type === "tool_use") as Anthropic.ToolUseBlock | undefined;
  if (!block) throw new Error("model did not return submit_evaluation");
  const out = block.input as Omit<EvalResult, "evidence">;
  return { ...out, evidence: ev.grid }; // attach the supporting-signals grid for the overlay
}
```

- [ ] **Step 2: `rubric_test.ts`** (schema/shape — no network)

```typescript
import { assert, assertEquals } from "jsr:@std/assert";
import { SUBMIT_TOOL, promptFor } from "./rubric.ts";

Deno.test("submit tool schema bounds score 0-100 and requires reasons 2-3", () => {
  const p = SUBMIT_TOOL.input_schema.properties;
  assertEquals(p.score.maximum, 100);
  assertEquals(p.reasons.minItems, 2);
  assertEquals(p.reasons.maxItems, 3);
});

Deno.test("prompt uses the repo lens + repo dimensions for github", () => {
  const prompt = promptFor(
    { source: "github", grid: [], vetoHints: [], context: { readme: "x" } },
    { id: 1, source: "github", external_id: "a/b", name: "b", one_liner: "db", url: "u", default_branch: "main", raw_json: {} },
  );
  assert(prompt.includes("CTO"));
  assert(prompt.includes("Adoption over attention"));
});
```

- [ ] **Step 3: Run the rubric test**

Run: `cd supabase/functions/deep-dive && deno test rubric_test.ts`
Expected: 2 passed. (Deferrable to Task 6 env if standalone Deno absent.)

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/deep-dive/{rubric.ts,rubric_test.ts}
git commit -m "feat(deep-dive): claude sonnet rubric with forced-json tool"
```

---

### Task 5: Orchestration — wire index.ts (running → done/error)

**Files:**
- Modify: `supabase/functions/deep-dive/index.ts`

**Interfaces:**
- Consumes: `serviceClient`, `getEntity`, `setRunning`, `writeResult`, `writeError` (db.ts); `githubEvidence`/`productHuntEvidence`; `evaluate`.

- [ ] **Step 1: Full `index.ts`**

```typescript
import { serviceClient, getEntity, setRunning, writeResult, writeError } from "./db.ts";
import { githubEvidence } from "./github.ts";
import { productHuntEvidence } from "./producthunt.ts";
import { evaluate } from "./rubric.ts";

Deno.serve(async (req) => {
  let entityId: number | undefined;
  const db = serviceClient();
  try {
    const body = await req.json();
    entityId = body.entity_id;
    if (!entityId) return new Response("entity_id required", { status: 400 });

    await setRunning(db, entityId);
    const entity = await getEntity(db, entityId);
    const evidence = entity.source === "github"
      ? await githubEvidence(entity)
      : await productHuntEvidence(entity);
    const result = await evaluate(evidence, entity);
    await writeResult(db, entityId, result);
    return Response.json({ status: "done", entity_id: entityId, score: result.score });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (entityId) { try { await writeError(db, entityId, msg); } catch { /* ignore */ } }
    return new Response(JSON.stringify({ status: "error", error: msg }), { status: 500 });
  }
});
```

- [ ] **Step 2: Type-check**

Run: `cd supabase/functions/deep-dive && deno check index.ts`
Expected: no type errors (deferrable to Task 6 env).

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/deep-dive/index.ts
git commit -m "feat(deep-dive): orchestrate fetch -> rubric -> cache (running/done/error)"
```

---

### Task 6: Deploy + live smoke *(needs Supabase CLI + Anthropic key)*

**Files:** none (deploy + verify).

- [ ] **Step 1: Set function secrets**

```bash
supabase secrets set ANTHROPIC_API_KEY=<your-key> GH_PAT=<your-github-pat> PH_TOKEN=<your-ph-token>
```
(`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are injected automatically for deployed functions.)

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy deep-dive
```
Expected: "Deployed Function deep-dive".

- [ ] **Step 3: Local test run of parsers/schema (if not done earlier)**

Run: `supabase functions serve deep-dive` in one shell; in another, the deno tests: `deno test supabase/functions/deep-dive/parse_test.ts supabase/functions/deep-dive/rubric_test.ts`
Expected: all pass.

- [ ] **Step 4: Live smoke** — invoke on a real GitHub entity and confirm the cache row

Pick an entity id (from `select id,name,source from entities where source='github' limit 1;`), then:
```bash
curl -s -X POST "https://rdpvppcaskhoedvuhamp.supabase.co/functions/v1/deep-dive" \
  -H "Authorization: Bearer <a-valid-user-access-token>" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": <ID>}'
```
Expected: `{"status":"done","entity_id":<ID>,"score":<0-100>}`. Then verify via psycopg2:
```bash
python -c "from collector.config import load_config; from collector import db; c=db.connect(load_config()).cursor(); c.execute(\"select status, quality_score, jsonb_array_length(reasons) from deep_dive_cache where entity_id=<ID>\"); print(c.fetchone())"
```
Expected: `('done', <int>, <2 or 3>)`.

- [ ] **Step 5: Commit any config touched, tag the milestone**

```bash
git add -A supabase
git commit -m "chore(deep-dive): deploy config" || echo "nothing to commit"
```

---

## Definition of done (Phase 2A)

- ☐ `signal_feed` exposes `quality_score` + `deep_dive_status` (verified here; null pre-dive).
- ☐ `deep-dive` Edge Function deployed; invoking it on a real entity writes `deep_dive_cache` status running→done with a 0–100 score, 2–3 reasons, rubric rows, and evidence grid.
- ☐ Evidence fetch is partial-failure tolerant; vetoes surface (archived / dead URL).
- ☐ Secrets server-side only; no keys committed or in the app.
- ☐ Deno parser/schema tests pass.
- ☐ **Out (Plan 2B):** the Flutter overlay, Realtime subscription, and solid Scope blips.

## Self-review notes

- **Spec coverage:** §3 architecture → Tasks 2/5; §4 fetchers → Task 3; §5 rubric+schema → Task 4; §6 view addition → Task 1; §8 error/partial-failure → Tasks 3/5; §9 testing → Tasks 3/4; §10 prereqs → Task 6. §7 overlay + Scope blips are **Plan 2B** (app), correctly deferred.
- **Verification honesty:** Task 1 verifies here; Tasks 2–5 type-check + deno-test where a Deno runtime exists, else verify under `supabase functions serve` (Task 6); Task 6 is the live end-to-end gate and needs your Anthropic key + Supabase CLI.
- **Model id `claude-sonnet-5` and `@anthropic-ai/sdk` tool-use API** — confirm exact version/shape at build time against current Anthropic docs.
