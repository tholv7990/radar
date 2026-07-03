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

  // comment bodies for sentiment (from stored raw_json if present, else skip)
  const comments = (raw["_comment_bodies"] as string[]) ?? [];
  if (comments.length) ctx.comment_sample = comments.slice(0, 40);
  grid.push({ label: "Reviews", value: `${raw["reviewsRating"] ?? "—"}★`, sub: String(raw["reviewsCount"] ?? "") });
  ctx.rating = raw["reviewsRating"]; ctx.votes = raw["votesCount"]; ctx.comments = raw["commentsCount"];
  return { source: "producthunt", grid, vetoHints, context: ctx };
}
