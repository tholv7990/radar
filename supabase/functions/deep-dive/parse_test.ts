import { assert, assertEquals } from "jsr:@std/assert";
import { detectTestsCI } from "./github.ts";

Deno.test("detects tests + CI from tree paths", () => {
  const r = detectTestsCI(["src/main.rs", "tests/it.rs", ".github/workflows/ci.yml"]);
  assert(r.hasTests); assert(r.hasCI);
});
Deno.test("no false positives", () => {
  const r = detectTestsCI(["src/main.rs", "README.md"]);
  assertEquals(r.hasTests, false); assertEquals(r.hasCI, false);
});
