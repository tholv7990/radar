import { assertEquals } from "jsr:@std/assert";
import { pkgNameFromPackageJson } from "./github.ts";
import { commentBodies } from "./producthunt.ts";

Deno.test("pkgNameFromPackageJson extracts a valid name", () => {
  assertEquals(pkgNameFromPackageJson('{"name":"fern-api"}'), "fern-api");
});
Deno.test("pkgNameFromPackageJson returns null on malformed JSON", () => {
  assertEquals(pkgNameFromPackageJson("{not json"), null);
});
Deno.test("pkgNameFromPackageJson returns null when name is missing", () => {
  assertEquals(pkgNameFromPackageJson('{"version":"1.0.0"}'), null);
});
Deno.test("pkgNameFromPackageJson returns null when name is not a string", () => {
  assertEquals(pkgNameFromPackageJson('{"name":123}'), null);
});
Deno.test("pkgNameFromPackageJson returns null when name is empty", () => {
  assertEquals(pkgNameFromPackageJson('{"name":""}'), null);
});

Deno.test("commentBodies extracts non-empty bodies and drops empty ones", () => {
  const gql = { data: { post: { comments: { edges: [{ node: { body: "great" } }, { node: { body: "" } }] } } } };
  assertEquals(commentBodies(gql), ["great"]);
});
Deno.test("commentBodies returns [] on garbage input", () => {
  assertEquals(commentBodies("not an object"), []);
  assertEquals(commentBodies(null), []);
  assertEquals(commentBodies(undefined), []);
});
Deno.test("commentBodies returns [] on missing shape", () => {
  assertEquals(commentBodies({}), []);
  assertEquals(commentBodies({ data: {} }), []);
  assertEquals(commentBodies({ data: { post: null } }), []);
  assertEquals(commentBodies({ data: { post: { comments: { edges: "nope" } } } }), []);
});
