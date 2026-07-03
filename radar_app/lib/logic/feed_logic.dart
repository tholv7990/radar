import 'package:flutter/material.dart';
import '../models/signal_item.dart';
import '../theme.dart';

class StageMeta { final String label; final String arrow; final Color color;
  const StageMeta(this.label, this.arrow, this.color); }
class ConsMeta { final String label; final Color color;
  const ConsMeta(this.label, this.color); }

StageMeta stageMeta(String s) => switch (s) {
  'emerging' => const StageMeta('Emerging', '↑', kGreen),
  'rising'   => const StageMeta('Rising', '↑', kTeal),
  'steady'   => const StageMeta('Steady', '→', kOrange),
  'fading'   => const StageMeta('Fading', '↓', kMut),
  _          => const StageMeta('New', '·', kFaint),
};

ConsMeta consMeta(String c) => switch (c) {
  'corroborated' => const ConsMeta('Corroborated', kGreen),
  'mixed'        => const ConsMeta('Mixed signal', kOrange),
  'suspicious'   => const ConsMeta('Suspicious', kRed),
  _              => const ConsMeta('New', kFaint),
};

List<SignalItem> filterAndSort(
  List<SignalItem> items, {
  required String source,
  required String stage,
  required String lang,
  required String sortKey,
  String? watchFilter,
}) {
  var list = items.where((x) {
    if (source != 'all' && x.source != source) return false;
    if (stage != 'all' && x.momentumStage != stage) return false;
    if (lang != 'all') {
      final q = lang.toLowerCase();
      final hit = (x.language?.toLowerCase() == q) ||
          x.topics.any((t) => t.toLowerCase() == q);
      if (!hit) return false;
    }
    if (watchFilter != null) {
      if (watchFilter == 'all') return x.watchState != null && x.watchState != 'dismissed';
      return x.watchState == watchFilter;
    }
    return x.watchState != 'dismissed';
  }).toList();

  int cmp(SignalItem a, SignalItem b) => switch (sortKey) {
    'velocity' => (b.velocity ?? 0).compareTo(a.velocity ?? 0),
    'total'    => (b.totalMetric ?? 0).compareTo(a.totalMetric ?? 0),
    'newest'   => b.id.compareTo(a.id),
    _          => b.rankScore.compareTo(a.rankScore),
  };
  list.sort(cmp);
  return list;
}
