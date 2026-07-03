import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/signal_item.dart';
import 'package:radar_app/widgets/radar_painter.dart';

SignalItem it(String stage) => SignalItem(id: 1, source: 'github', name: 'x',
  topics: const [], provisionalQuality: 50, consistency: 'new',
  momentumStage: stage, rankScore: 0);

void main() {
  test('momentumPos orders emerging > rising > steady > fading', () {
    expect(momentumPos(it('emerging')) > momentumPos(it('rising')), true);
    expect(momentumPos(it('rising')) > momentumPos(it('steady')), true);
    expect(momentumPos(it('steady')) > momentumPos(it('fading')), true);
    expect(momentumPos(it('emerging')) <= 100 && momentumPos(it('fading')) >= 0, true);
  });
}
