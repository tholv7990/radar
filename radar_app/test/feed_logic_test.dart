import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/signal_item.dart';
import 'package:radar_app/logic/feed_logic.dart';

SignalItem item(String name, {String source = 'github', int? vel, num rank = 0,
    int total = 0, String stage = 'rising', String? watch}) =>
  SignalItem(id: name.hashCode, source: source, name: name, topics: const [],
      provisionalQuality: 50, velocity: vel, totalMetric: total,
      consistency: 'corroborated', momentumStage: stage, rankScore: rank, watchState: watch);

void main() {
  final items = [
    item('a', vel: 100, rank: 100, total: 500),
    item('b', vel: 300, rank: 300, total: 200, source: 'producthunt'),
    item('c', vel: 50, rank: 50, total: 900, watch: 'dismissed'),
  ];

  test('default feed drops dismissed and sorts by momentum desc', () {
    final r = filterAndSort(items, source: 'all', stage: 'all', lang: 'all', sortKey: 'momentum');
    expect(r.map((e) => e.name), ['b', 'a']);
  });

  test('source filter', () {
    final r = filterAndSort(items, source: 'producthunt', stage: 'all', lang: 'all', sortKey: 'momentum');
    expect(r.map((e) => e.name), ['b']);
  });

  test('sort by total', () {
    final r = filterAndSort(items, source: 'all', stage: 'all', lang: 'all', sortKey: 'total');
    expect(r.first.name, 'a');
  });

  test('watch filter shows only that state', () {
    final r = filterAndSort(items, source: 'all', stage: 'all', lang: 'all', sortKey: 'momentum', watchFilter: 'dismissed');
    expect(r.map((e) => e.name), ['c']);
  });
}
