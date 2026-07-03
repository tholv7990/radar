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
