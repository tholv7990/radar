import Anthropic from "npm:@anthropic-ai/sdk@^0.110.0";
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
  // Provider is a setting: key + optional reseller/proxy base URL + optional model override.
  // Lets the caller point at the user's shopaikey (or any Anthropic-compatible) proxy
  // without any code change — see the reseller-compatibility fallback note below.
  const baseURL = Deno.env.get("ANTHROPIC_BASE_URL"); // set to the reseller/gateway endpoint
  const client = new Anthropic({
    apiKey: Deno.env.get("ANTHROPIC_API_KEY")!,
    ...(baseURL ? { baseURL } : {}),
  });
  const model = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5";
  const msg = await client.messages.create({
    model,
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

// Reseller/proxy compatibility fallback: the forced tool_choice path above needs a
// genuinely Anthropic-compatible Messages API. If the configured ANTHROPIC_BASE_URL
// gateway rejects forced tool use (400/parse error) during the live smoke test,
// switch evaluate() to a no-tool variant: drop tools/tool_choice, append
// "Respond with ONLY a JSON object matching this shape: <SUBMIT_TOOL.input_schema>"
// to the prompt, read the text block, and JSON.parse it (validate against the
// schema; retry once on parse failure). Same output type, works on gateways that
// don't support forced tool use. Only make this switch if the tool path actually
// fails against the target endpoint — not applied preemptively here.
