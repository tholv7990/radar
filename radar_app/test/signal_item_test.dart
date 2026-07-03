import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/signal_item.dart';

void main() {
  test('fromMap maps view columns', () {
    final it = SignalItem.fromMap({
      'id': 7, 'source': 'github', 'name': 'driftdb', 'one_liner': 'db',
      'url': 'https://x', 'language': 'Rust', 'topics': ['database'],
      'stars': 8400, 'votes': null, 'comments': null,
      'provisional_quality': 89, 'velocity': 2140, 'total_metric': 8400,
      'consistency': 'corroborated', 'momentum_stage': 'emerging',
      'rank_score': 2140, 'watch_state': 'watching',
      'quality_score': 91, 'deep_dive_status': 'done',
    });
    expect(it.id, 7);
    expect(it.source, 'github');
    expect(it.isGithub, true);
    expect(it.velocity, 2140);
    expect(it.consistency, 'corroborated');
    expect(it.watchState, 'watching');
    expect(it.topics, ['database']);
    expect(it.qualityScore, 91);
    expect(it.deepDiveStatus, 'done');
  });
}
