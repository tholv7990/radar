class Veto {
  final String title;
  final String note;
  const Veto(this.title, this.note);
}

class Reason {
  final String tone; // pos | warn | neg
  final String title;
  final String note;
  const Reason(this.tone, this.title, this.note);
}

class RubricRow {
  final String label;
  final int score; // 0-10
  final String state; // pass | watch | fail
  final String evidence;
  const RubricRow(this.label, this.score, this.state, this.evidence);
}

class EvidenceItem {
  final String label;
  final String value;
  final String? sub;
  const EvidenceItem(this.label, this.value, this.sub);
}

class DeepDiveResult {
  final int score;
  final String verdict;
  final List<Veto> vetoes;
  final List<Reason> reasons;
  final List<RubricRow> rubric;
  final List<EvidenceItem> evidence;

  const DeepDiveResult({
    required this.score,
    required this.verdict,
    required this.vetoes,
    required this.reasons,
    required this.rubric,
    required this.evidence,
  });

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      v == null ? <T>[] : (v as List).map((e) => f(e as Map<String, dynamic>)).toList();

  factory DeepDiveResult.fromMap(Map<String, dynamic> m) => DeepDiveResult(
        score: (m['score'] ?? 0) as int,
        verdict: (m['verdict'] ?? '') as String,
        vetoes: _list(m['vetoes'], (x) => Veto(x['title'] as String, x['note'] as String)),
        reasons: _list(m['reasons'], (x) => Reason(x['tone'] as String, x['title'] as String, x['note'] as String)),
        rubric: _list(m['rubric'], (x) => RubricRow(
            x['label'] as String, (x['score'] as num).toInt(), x['state'] as String, x['evidence'] as String)),
        evidence: _list(m['evidence'], (x) => EvidenceItem(
            x['label'] as String, x['value'].toString(), x['sub'] as String?)),
      );
}
