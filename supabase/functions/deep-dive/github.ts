import { Entity, Evidence, EvidenceItem } from "./types.ts";

const GH = "https://api.github.com";
function ghHeaders() {
  return { "Authorization": `Bearer ${Deno.env.get("GH_PAT")}`, "Accept": "application/vnd.github+json", "User-Agent": "radar" };
}
async function safe<T>(fn: () => Promise<T>, fallback: T): Promise<T> {
  try { return await fn(); } catch { return fallback; }
}

// Pure helper (also imported by parse_test.ts — single source of truth for the
// tests/CI detection regexes, don't duplicate them).
export function detectTestsCI(paths: string[]) {
  return {
    hasTests: paths.some((p) => /(^|\/)(test|tests|spec|__tests__)(\/|$)/i.test(p)),
    hasCI: paths.some((p) => p.startsWith(".github/workflows/")),
  };
}

// Pure helper — parses a package.json body and returns its `name` field, or
// null on a missing/empty/non-string name or invalid JSON. Never throws.
export function pkgNameFromPackageJson(text: string): string | null {
  try {
    const parsed = JSON.parse(text) as { name?: unknown };
    return typeof parsed?.name === "string" && parsed.name.length > 0 ? parsed.name : null;
  } catch {
    return null;
  }
}

export async function githubEvidence(e: Entity): Promise<Evidence> {
  const full = e.external_id; // owner/repo
  const grid: EvidenceItem[] = [];
  const vetoHints: { title: string; note: string }[] = [];
  const ctx: Record<string, unknown> = {};

  const raw = e.raw_json as Record<string, unknown>;
  if (raw["archived"] === true) vetoHints.push({ title: "Archived repository", note: "Repo is archived/read-only." });

  const contributors = await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/contributors?per_page=100`, { headers: ghHeaders(), signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error();
    return (await r.json() as unknown[]).length;
  }, -1);
  if (contributors >= 0) { grid.push({ label: "Contributors", value: String(contributors) }); ctx.contributors = contributors; }

  const releases = await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/releases?per_page=10`, { headers: ghHeaders(), signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error();
    return await r.json() as { tag_name: string; published_at: string }[];
  }, []);
  if (releases.length) {
    grid.push({ label: "Latest release", value: releases[0].tag_name });
    ctx.release_count = releases.length; ctx.latest_release = releases[0].published_at;
  }

  const tree = await safe(async () => {
    const branch = e.default_branch ?? "main";
    const r = await fetch(`${GH}/repos/${full}/git/trees/${branch}?recursive=1`, { headers: ghHeaders(), signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error();
    return (await r.json() as { tree: { path: string }[] }).tree.map((t) => t.path);
  }, [] as string[]);
  const { hasTests, hasCI } = detectTestsCI(tree);
  if (tree.length) { grid.push({ label: "Tests / CI", value: `${hasTests ? "tests" : "no tests"} · ${hasCI ? "CI" : "no CI"}` }); ctx.hasTests = hasTests; ctx.hasCI = hasCI; }

  // npm download adoption — only if the repo ships a top-level package.json.
  const pkgJsonText = tree.includes("package.json") ? await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/contents/package.json`, {
      headers: { ...ghHeaders(), "Accept": "application/vnd.github.raw" },
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new Error();
    return await r.text();
  }, "") : "";
  const npmName = pkgJsonText ? pkgNameFromPackageJson(pkgJsonText) : null;

  if (npmName) {
    const downloads = await safe(async () => {
      const r = await fetch(`https://api.npmjs.org/downloads/point/last-month/${encodeURIComponent(npmName)}`, {
        signal: AbortSignal.timeout(8000),
      });
      if (!r.ok) throw new Error();
      return (await r.json() as { downloads: number }).downloads;
    }, 0);
    if (downloads > 0) {
      grid.push({ label: "npm downloads", value: `${downloads}/mo` });
      ctx.npm_downloads = downloads;
    }
  } else if (tree.includes("pyproject.toml") || tree.includes("setup.py")) {
    // PyPI fallback — only attempted when there's no npm package name. Guess
    // the package name from the repo name (best-effort; no manifest parsing).
    const repoName = full.split("/")[1] ?? "";
    const pkg = repoName.toLowerCase().replaceAll("_", "-");
    if (pkg) {
      const lastMonth = await safe(async () => {
        const r = await fetch(`https://pypistats.org/api/packages/${pkg}/recent`, {
          signal: AbortSignal.timeout(8000),
        });
        if (!r.ok) throw new Error();
        return (await r.json() as { data: { last_month: number } }).data.last_month;
      }, 0);
      if (lastMonth > 0) {
        grid.push({ label: "PyPI downloads", value: `${lastMonth}/mo` });
        ctx.pypi_downloads = lastMonth;
      }
    }
  }

  const readme = await safe(async () => {
    const r = await fetch(`${GH}/repos/${full}/readme`, { headers: { ...ghHeaders(), "Accept": "application/vnd.github.raw" }, signal: AbortSignal.timeout(8000) });
    if (!r.ok) throw new Error();
    return (await r.text()).slice(0, 6000);
  }, "");
  if (readme) ctx.readme = readme;

  grid.push({ label: "License", value: String(raw["license"] && (raw["license"] as Record<string, string>)["spdx_id"] || "—") });
  return { source: "github", grid, vetoHints, context: ctx };
}
