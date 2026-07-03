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
