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
