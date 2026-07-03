export interface EvidenceItem { label: string; value: string; sub?: string }
export interface Evidence {
  source: "github" | "producthunt";
  grid: EvidenceItem[];          // the supporting-signals grid
  vetoHints: { title: string; note: string }[];  // hard-signal candidates (dead URL, archived…)
  context: Record<string, unknown>; // raw-ish signals handed to the LLM (readme, comments, counts)
}
export interface RubricRow { label: string; score: number; state: "pass" | "watch" | "fail"; evidence: string }
export interface EvalResult {
  score: number;
  verdict: string;
  vetoes: { title: string; note: string }[];
  reasons: { tone: "pos" | "warn" | "neg"; title: string; note: string }[];
  rubric: RubricRow[];
  evidence: EvidenceItem[];
}
export interface Entity {
  id: number; source: string; external_id: string; name: string;
  one_liner: string | null; url: string | null; default_branch: string | null;
  raw_json: Record<string, unknown>;
}
