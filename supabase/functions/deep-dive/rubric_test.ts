import { assert, assertEquals, assertThrows } from "jsr:@std/assert";
import { SUBMIT_TOOL, promptFor, validateResult } from "./rubric.ts";
import { EvalResult } from "./types.ts";

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

Deno.test("validateResult throws on malformed model output", () => {
  assertThrows(
    () =>
      validateResult({
        score: 150, // out of range
        verdict: "looks good",
        vetoes: [],
        reasons: [{ tone: "pos", title: "a", note: "b" }, { tone: "warn", title: "c", note: "d" }],
        rubric: [{ label: "x", score: 5, state: "pass", evidence: "y" }],
      }),
    Error,
    "model returned malformed evaluation",
  );
});

Deno.test("validateResult throws when rubric rows are missing fields", () => {
  assertThrows(
    () =>
      validateResult({
        score: 80,
        verdict: "solid",
        vetoes: [],
        reasons: [{ tone: "pos", title: "a", note: "b" }, { tone: "warn", title: "c", note: "d" }],
        rubric: [{ label: "x", state: "pass" }], // missing score/evidence
      }),
    Error,
    "model returned malformed evaluation",
  );
});

Deno.test("validateResult passes a well-formed evaluation through unchanged", () => {
  const valid: Omit<EvalResult, "evidence"> = {
    score: 82,
    verdict: "Strong candidate with active maintenance.",
    vetoes: [],
    reasons: [
      { tone: "pos", title: "Active maintenance", note: "Weekly commits." },
      { tone: "warn", title: "Small team", note: "Bus factor of 1." },
    ],
    rubric: [
      { label: "Adoption over attention", score: 8, state: "pass", evidence: "1.2k weekly downloads." },
      { label: "Maintenance pulse", score: 7, state: "watch", evidence: "Last release 3 months ago." },
    ],
  };
  const out = validateResult(valid);
  assertEquals(out, valid);
});
