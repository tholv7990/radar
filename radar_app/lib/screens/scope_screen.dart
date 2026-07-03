import 'package:flutter/material.dart';
import '../models/signal_item.dart';
import '../logic/feed_logic.dart';
import '../theme.dart';
import '../widgets/radar_painter.dart';

class ScopeScreen extends StatelessWidget {
  final List<SignalItem> items;
  final void Function(SignalItem) onOpen;
  const ScopeScreen({super.key, required this.items, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final ranked = [...items]..sort((a, b) => b.rankScore.compareTo(a.rankScore));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('The Scope',
          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: kInk)),
      const SizedBox(height: 4),
      const Text('Quality × momentum. The sweet spot is top-right — genuinely good, still emerging.',
          style: TextStyle(fontSize: 13.5, height: 1.5, color: kMut)),
      const SizedBox(height: 16),
      AspectRatio(
        aspectRatio: 1,
        child: Container(
          decoration: BoxDecoration(color: kIndigo, borderRadius: BorderRadius.circular(16)),
          child: CustomPaint(painter: RadarPainter(items)),
        ),
      ),
      const SizedBox(height: 18),
      const Text('RANKED BY MOMENTUM',
          style: TextStyle(fontSize: 11.5, letterSpacing: 1, color: kFaint, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      ...ranked.asMap().entries.map((e) {
        final i = e.key;
        final it = e.value;
        final stage = stageMeta(it.momentumStage);
        final color = it.consistency == 'suspicious' ? kRed : stage.color;
        return InkWell(
          onTap: () => onOpen(it),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kHair))),
            child: Row(children: [
              SizedBox(width: 22, child: Text((i + 1).toString().padLeft(2, '0'),
                  style: const TextStyle(fontSize: 12, color: kMut))),
              Container(width: 9, height: 9, margin: const EdgeInsets.only(right: 11),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(it.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: kInk)),
                  Text('Quality ${it.provisionalQuality} · Momentum ${momentumPos(it).round()}',
                      style: const TextStyle(fontSize: 12, color: kMut)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: stage.color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(999)),
                child: Text(stage.label,
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: stage.color)),
              ),
            ]),
          ),
        );
      }),
    ]);
  }
}
