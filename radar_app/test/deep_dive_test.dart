import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/deep_dive.dart';

void main() {
  test('DeepDiveResult.fromMap parses full_result', () {
    final r = DeepDiveResult.fromMap({
      'score': 89, 'verdict': 'Adopt-worthy.',
      'vetoes': [{'title': 'X', 'note': 'y'}],
      'reasons': [{'tone': 'pos', 'title': 'A', 'note': 'b'}],
      'rubric': [{'label': 'Adoption', 'score': 9, 'state': 'pass', 'evidence': 'e'}],
      'evidence': [{'label': 'Contributors', 'value': '24', 'sub': 'x'}],
    });
    expect(r.score, 89);
    expect(r.verdict, 'Adopt-worthy.');
    expect(r.vetoes.single.title, 'X');
    expect(r.reasons.single.tone, 'pos');
    expect(r.rubric.single.score, 9);
    expect(r.evidence.single.value, '24');
  });

  test('tolerates missing/empty lists', () {
    final r = DeepDiveResult.fromMap({'score': 40, 'verdict': 'meh'});
    expect(r.vetoes, isEmpty);
    expect(r.reasons, isEmpty);
    expect(r.rubric, isEmpty);
    expect(r.evidence, isEmpty);
  });
}
