import 'package:flutter/material.dart';
import '../models/signal_item.dart';
import '../logic/feed_logic.dart';
import '../theme.dart';

double momentumPos(SignalItem it) => switch (it.momentumStage) {
  'emerging' => 90,
  'rising'   => 75,
  'steady'   => 45,
  'fading'   => 20,
  _          => 35,
};

class RadarPainter extends CustomPainter {
  final List<SignalItem> items;
  RadarPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    const pad = 18.0;
    final cx = w / 2, cy = h / 2;

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white.withValues(alpha: 0.13)
      ..strokeWidth = 1;
    for (final r in [0.94, 0.70, 0.46, 0.20]) {
      canvas.drawCircle(Offset(cx, cy), (w / 2 - pad) * r, ring);
    }

    final axis = Paint()
      ..color = Colors.white.withValues(alpha: 0.17)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(cx, pad * 0.5), Offset(cx, h - pad * 0.5), axis);
    canvas.drawLine(Offset(pad * 0.5, cy), Offset(w - pad * 0.5, cy), axis);

    // sweet spot: top-right quadrant tint
    canvas.drawRect(
      Rect.fromLTWH(cx, pad * 0.5, w / 2 - pad * 0.5, h / 2 - pad * 0.5),
      Paint()..color = kGreen.withValues(alpha: 0.10),
    );

    for (final it in items) {
      // Deep-dive done: solid blip positioned by the confirmed quality_score.
      // Otherwise: hollow blip positioned by the provisional quality (Phase 1).
      final done = it.deepDiveStatus == 'done' && it.qualityScore != null;
      final qx = ((done ? it.qualityScore! : it.provisionalQuality).clamp(0, 100)) / 100.0;
      final my = momentumPos(it) / 100.0;
      final x = pad + (w - 2 * pad) * qx;
      final y = pad + (h - 2 * pad) * (1 - my); // higher momentum → higher up
      final color = it.consistency == 'suspicious' ? kRed : stageMeta(it.momentumStage).color;
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..style = done ? PaintingStyle.fill : PaintingStyle.stroke;
      canvas.drawCircle(Offset(x, y), 6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant RadarPainter old) => old.items != items;
}
