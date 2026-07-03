import { Entity, Evidence, EvidenceItem } from "./types.ts";

const PH_GQL = "https://api.producthunt.com/v2/api/graphql";
const COMMENTS_QUERY =
  `query($id: ID!) { post(id: $id) { commentsCount comments(first: 30) { edges { node { body } } } } }`;

async function safe<T>(fn: () => Promise<T>, fallback: T): Promise<T> {
  try { return await fn(); } catch { return fallback; }
}

function isRecord(x: unknown): x is Record<string, unknown> {
  return typeof x === "object" && x !== null;
}

// Pure helper — walks a PH GraphQL response for comment bodies. Returns []
// on any shape mismatch (missing fields, wrong types, non-object input).
// Never throws.
export function commentBodies(gql: unknown): string[] {
  if (!isRecord(gql)) return [];
  const data = gql.data;
  if (!isRecord(data)) return [];
  const post = data.post;
  if (!isRecord(post)) return [];
  const comments = post.comments;
  if (!isRecord(comments)) return [];
  const edges = comments.edges;
  if (!Array.isArray(edges)) return [];

  const bodies: string[] = [];
  for (const edge of edges) {
    if (!isRecord(edge)) continue;
    const node = edge.node;
    if (!isRecord(node)) continue;
    const body = node.body;
    if (typeof body === "string" && body.length > 0) bodies.push(body);
  }
  return bodies;
}

export async function productHuntEvidence(e: Entity): Promise<Evidence> {
  const raw = e.raw_json as Record<string, unknown>;
  const grid: EvidenceItem[] = [];
  const vetoHints: { title: string; note: string }[] = [];
  const ctx: Record<string, unknown> = {};

  const productUrl = (raw["website"] as string) ?? null;
  // URL-alive (veto signal)
  const alive = productUrl ? await safe(async () => {
    const r = await fetch(productUrl, { method: "GET", redirect: "follow", signal: AbortSignal.timeout(8000) });
    return r.ok;
  }, false) : false;
  grid.push({ label: "URL alive", value: alive ? "Yes" : "No" });
  if (productUrl && !alive) vetoHints.push({ title: "Dead product URL", note: `${productUrl} did not respond OK.` });
  ctx.url_alive = alive; ctx.product_url = productUrl;

  // pricing detected (crawl product page)
  if (productUrl && alive) {
    const html = await safe(async () => (await fetch(productUrl, { signal: AbortSignal.timeout(8000) })).text(), "");
    const pricing = /\$\d|\bpricing\b|\bper month\b|\/mo\b|per seat/i.test(html);
    grid.push({ label: "Pricing", value: pricing ? "detected" : "none" });
    ctx.pricing_detected = pricing;
  }

  // comment bodies for sentiment — the collector doesn't store bodies, so
  // fetch them live from the PH GraphQL API. Best-effort: no PH_TOKEN or a
  // failed fetch just means no comment evidence, never fails the dive.
  const phToken = Deno.env.get("PH_TOKEN");
  const bodies = phToken ? await safe(async () => {
    const r = await fetch(PH_GQL, {
      method: "POST",
      headers: { "Authorization": `Bearer ${phToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ query: COMMENTS_QUERY, variables: { id: e.external_id } }),
      signal: AbortSignal.timeout(8000),
    });
    if (!r.ok) throw new Error();
    return commentBodies(await r.json());
  }, [] as string[]) : [];
  ctx.comment_sample = bodies.slice(0, 30);
  grid.push({ label: "Comment depth", value: bodies.length >= 15 ? "High" : bodies.length >= 5 ? "Medium" : "Low" });

  grid.push({ label: "Reviews", value: `${raw["reviewsRating"] ?? "—"}★`, sub: String(raw["reviewsCount"] ?? "") });
  ctx.rating = raw["reviewsRating"]; ctx.votes = raw["votesCount"]; ctx.comments = raw["commentsCount"];
  return { source: "producthunt", grid, vetoHints, context: ctx };
}
