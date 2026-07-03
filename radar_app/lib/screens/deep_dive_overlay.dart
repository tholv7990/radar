import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/repository.dart';
import '../models/deep_dive.dart';
import '../models/signal_item.dart';
import '../theme.dart';
import '../widgets/radar_painter.dart' show momentumPos;
import '../widgets/source_mark.dart';

/// Full-screen deep-dive result view. Kicks off a server-side evaluation
/// (if one isn't already cached) and renders the live `deep_dive_cache` row
/// via Realtime: running -> done/error.
class DeepDiveOverlay extends StatefulWidget {
  final SignalItem item;
  const DeepDiveOverlay({super.key, required this.item});

  @override
  State<DeepDiveOverlay> createState() => _DeepDiveOverlayState();
}

class _DeepDiveOverlayState extends State<DeepDiveOverlay> {
  late String? _watchState = widget.item.watchState;
  bool _rerunning = false;

  @override
  void initState() {
    super.initState();
    _maybeKickoff();
  }

  Future<void> _maybeKickoff() async {
    final cached = await Repository.instance.fetchDeepDive(widget.item.id);
    if (cached == null || cached['status'] != 'done') {
      await Repository.instance.invokeDeepDive(widget.item.id);
    }
  }

  Future<void> _rerun() async {
    setState(() => _rerunning = true);
    try {
      await Repository.instance.invokeDeepDive(widget.item.id);
    } finally {
      if (mounted) setState(() => _rerunning = false);
    }
  }

  Future<void> _toggleWatch() async {
    final next = _watchState == 'watching' ? 'seen' : 'watching';
    setState(() => _watchState = next);
    await Repository.instance.setWatchState(widget.item.id, next);
  }

  Future<void> _openLink() async {
    final url = widget.item.url;
    if (url == null) return;
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Color _ringColor(int s) => s >= 68 ? kGreen : (s >= 42 ? kOrange : kRed);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              item: widget.item,
              isWatching: _watchState == 'watching',
              onBack: () => Navigator.of(context).pop(),
              onWatch: _toggleWatch,
              onOpenLink: widget.item.url == null ? null : _openLink,
            ),
            Expanded(
              child: StreamBuilder<Map<String, dynamic>?>(
                stream: Repository.instance.deepDiveStream(widget.item.id),
                builder: (context, snap) {
                  final row = snap.data;
                  final status = row?['status'] as String?;
                  if (row == null || status == null || status == 'running') {
                    return _loading();
                  }
                  if (status == 'error') {
                    return _error(row['error_note'] as String?);
                  }
                  final raw = row['full_result'];
                  if (status != 'done' || raw is! Map) {
                    // Unexpected shape — treat as still-evaluating rather than crash.
                    return _loading();
                  }
                  final result = DeepDiveResult.fromMap(raw.cast<String, dynamic>());
                  return _done(result, row);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 32, 18, 32),
        children: [
          _TitleBlock(item: widget.item),
          const SizedBox(height: 40),
          const Center(
            child: Column(
              children: [
                SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(strokeWidth: 2.4, color: kAccent),
                ),
                SizedBox(height: 18),
                Text(
                  'Evaluating…',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kInk),
                ),
                SizedBox(height: 6),
                Text(
                  'This runs a fresh evaluation — a few seconds.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: kMut),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _error(String? note) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 32, 18, 32),
        children: [
          _TitleBlock(item: widget.item),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kRed.withValues(alpha: .055),
              border: Border.all(color: kRed.withValues(alpha: .28)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.error_outline, size: 18, color: kRed),
                    SizedBox(width: 8),
                    Text(
                      'Evaluation failed',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kRed),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  note ?? 'Something went wrong running this evaluation.',
                  style: const TextStyle(fontSize: 13, height: 1.45, color: kInk2),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: _PillButton(
              icon: Icons.refresh,
              label: _rerunning ? 'Running…' : 'Retry',
              onPressed: _rerunning ? null : _rerun,
            ),
          ),
        ],
      );

  Widget _done(DeepDiveResult r, Map<String, dynamic> row) {
    final ringColor = _ringColor(r.score);
    final momentum = momentumPos(widget.item);
    final inTarget = r.score >= 64 &&
        momentum >= 58 &&
        (widget.item.momentumStage == 'emerging' || widget.item.momentumStage == 'rising') &&
        widget.item.consistency != 'suspicious' &&
        r.vetoes.isEmpty;
    final targetLabel = inTarget
        ? '● In the sweet spot'
        : (r.vetoes.isNotEmpty ? '● Vetoed — out' : '○ Outside target');
    final targetColor = inTarget ? kGreen : (r.vetoes.isNotEmpty ? kRed : kFaint);

    final rubricTitle = widget.item.isGithub ? 'CTO RUBRIC' : 'CEO RUBRIC';
    final rubricLens = widget.item.isGithub ? 'is it trustworthy?' : 'is it a business?';

    final computedAt = row['computed_at'] as String?;
    final computedAtLabel = computedAt == null
        ? 'just now'
        : DateFormat('MMM d · HH:mm').format(DateTime.parse(computedAt).toLocal());

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 40),
      children: [
        _TitleBlock(item: widget.item),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _ScoreCard(score: r.score, verdict: r.verdict, ringColor: ringColor)),
            const SizedBox(width: 12),
            Expanded(
              child: _QuadrantCard(
                qualityFraction: (r.score.clamp(0, 100)) / 100.0,
                momentumFraction: (momentum.clamp(0, 100)) / 100.0,
                dotColor: ringColor,
                targetLabel: targetLabel,
                targetColor: targetColor,
              ),
            ),
          ],
        ),
        if (r.vetoes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Column(
            children: r.vetoes.map((v) => _VetoCard(veto: v)).toList(),
          ),
        ],
        const SizedBox(height: 22),
        const _SectionLabel('WHY THIS SCORE'),
        const SizedBox(height: 11),
        Column(
          children: r.reasons.map((reason) => _ReasonRow(reason: reason)).toList(),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionLabel(rubricTitle),
            Text(rubricLens, style: const TextStyle(fontSize: 11, color: kFaint, fontStyle: FontStyle.italic)),
          ],
        ),
        const SizedBox(height: 11),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: kHair),
            borderRadius: BorderRadius.circular(12),
            color: kSurf,
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < r.rubric.length; i++)
                _RubricRowTile(row: r.rubric[i], showDivider: i < r.rubric.length - 1),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionLabel('SUPPORTING SIGNALS'),
        const SizedBox(height: 11),
        _EvidenceGrid(items: r.evidence),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.only(top: 16),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: kHair))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  'Evaluated $computedAtLabel\nCached · re-runnable',
                  style: const TextStyle(fontSize: 11, height: 1.5, color: kFaint),
                ),
              ),
              const SizedBox(width: 12),
              _PillButton(
                icon: Icons.refresh,
                label: _rerunning ? 'Running…' : 'Re-run',
                onPressed: _rerunning ? null : _rerun,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final SignalItem item;
  final bool isWatching;
  final VoidCallback onBack;
  final VoidCallback onWatch;
  final VoidCallback? onOpenLink;

  const _Header({
    required this.item,
    required this.isWatching,
    required this.onBack,
    required this.onWatch,
    required this.onOpenLink,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        decoration: const BoxDecoration(
          color: kSurf,
          border: Border(bottom: BorderSide(color: kHair)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _PillButton(icon: Icons.chevron_left, label: 'Back', onPressed: onBack),
            Row(
              children: [
                SourceMark(isGithub: item.isGithub, size: 24),
                const SizedBox(width: 9),
                _IconSquareButton(
                  icon: isWatching ? Icons.bookmark : Icons.bookmark_border,
                  color: isWatching ? kAccent : kMut,
                  onPressed: onWatch,
                ),
                const SizedBox(width: 8),
                _IconSquareButton(
                  icon: Icons.open_in_new,
                  color: kMut,
                  onPressed: onOpenLink,
                ),
              ],
            ),
          ],
        ),
      );
}

class _IconSquareButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;
  const _IconSquareButton({required this.icon, required this.color, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 34,
        height: 34,
        child: Material(
          color: kSurf,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: kHair),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 16, color: onPressed == null ? kFaint.withValues(alpha: .6) : color),
            ),
          ),
        ),
      );
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  const _PillButton({required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 34,
        child: Material(
          color: kSurf,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                border: Border.all(color: kHair),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 15, color: kInk2),
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kInk2),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _TitleBlock extends StatelessWidget {
  final SignalItem item;
  const _TitleBlock({required this.item});

  @override
  Widget build(BuildContext context) {
    final tags = item.isGithub
        ? [if (item.language != null && item.language!.isNotEmpty) item.language!, ...item.topics]
        : item.topics;
    final captured = item.capturedAt == null
        ? null
        : DateFormat('MMM d · HH:mm').format(item.capturedAt!.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -0.03, color: kInk),
        ),
        if (item.oneLiner != null) ...[
          const SizedBox(height: 7),
          Text(
            item.oneLiner!,
            style: const TextStyle(fontSize: 15, height: 1.5, color: kInk2),
          ),
        ],
        if (tags.isNotEmpty || captured != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...tags.map((t) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEEDEB),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(t, style: const TextStyle(fontSize: 11, color: kMut)),
                  )),
              if (captured != null)
                Text('Captured $captured', style: const TextStyle(fontSize: 11, color: kFaint)),
            ],
          ),
        ],
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final int score;
  final String verdict;
  final Color ringColor;
  const _ScoreCard({required this.score, required this.verdict, required this.ringColor});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: kSurf,
          border: Border.all(color: kHair),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            const Text(
              'QUALITY SCORE',
              style: TextStyle(fontSize: 9.5, letterSpacing: 1.1, color: kFaint, fontWeight: FontWeight.w600),
            ),
            SizedBox(
              width: 118,
              height: 118,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: CustomPaint(
                  painter: _ScoreRingPainter(score: score, color: ringColor),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$score',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.03,
                            color: kInk,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text('/ 100', style: TextStyle(fontSize: 10.5, color: kFaint)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Text(
              verdict,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, height: 1.4, color: kInk2),
            ),
          ],
        ),
      );
}

class _ScoreRingPainter extends CustomPainter {
  final int score;
  final Color color;
  const _ScoreRingPainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 6;

    canvas.drawCircle(center, radius, Paint()..color = const Color(0xFFECECEA)..style = PaintingStyle.stroke..strokeWidth = 8);

    final sweep = 2 * math.pi * (score.clamp(0, 100) / 100.0);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final progress = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, -math.pi / 2, sweep, false, progress);
  }

  @override
  bool shouldRepaint(covariant _ScoreRingPainter old) => old.score != score || old.color != color;
}

class _QuadrantCard extends StatelessWidget {
  final double qualityFraction;
  final double momentumFraction;
  final Color dotColor;
  final String targetLabel;
  final Color targetColor;

  const _QuadrantCard({
    required this.qualityFraction,
    required this.momentumFraction,
    required this.dotColor,
    required this.targetLabel,
    required this.targetColor,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: kSurf,
          border: Border.all(color: kHair),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'QUALITY × MOMENTUM',
              style: TextStyle(fontSize: 9.5, letterSpacing: 0.9, color: kFaint, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFAF9F8),
                    border: Border.all(color: const Color(0xFFECECEA)),
                  ),
                  child: CustomPaint(
                    painter: _QuadrantPainter(
                      qualityFraction: qualityFraction,
                      momentumFraction: momentumFraction,
                      dotColor: dotColor,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              targetLabel,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: targetColor),
            ),
          ],
        ),
      );
}

class _QuadrantPainter extends CustomPainter {
  final double qualityFraction;
  final double momentumFraction;
  final Color dotColor;
  const _QuadrantPainter({
    required this.qualityFraction,
    required this.momentumFraction,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Sweet-spot tint: top-right quadrant.
    canvas.drawRect(
      Rect.fromLTWH(w / 2, 0, w / 2, h / 2),
      Paint()..color = kGreen.withValues(alpha: 0.09),
    );

    _dashedLine(canvas, Offset(w / 2, 0), Offset(w / 2, h), const Color(0xFFE6E6E6));
    _dashedLine(canvas, Offset(0, h / 2), Offset(w, h / 2), const Color(0xFFE6E6E6));

    final x = w * qualityFraction;
    final y = h * (1 - momentumFraction);
    canvas.drawCircle(Offset(x, y), 8, Paint()..color = dotColor.withValues(alpha: .3));
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = dotColor);
    canvas.drawCircle(Offset(x, y), 6, Paint()..color = Colors.white.withValues(alpha: .85)..style = PaintingStyle.stroke..strokeWidth = 1.5);
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Color color) {
    const dashWidth = 2.0, gapWidth = 3.0;
    final paint = Paint()..color = color..strokeWidth = 1;
    final total = (to - from).distance;
    final direction = (to - from) / total;
    var covered = 0.0;
    while (covered < total) {
      final start = from + direction * covered;
      final end = from + direction * math.min(covered + dashWidth, total);
      canvas.drawLine(start, end, paint);
      covered += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _QuadrantPainter old) =>
      old.qualityFraction != qualityFraction || old.momentumFraction != momentumFraction || old.dotColor != dotColor;
}

class _VetoCard extends StatelessWidget {
  final Veto veto;
  const _VetoCard({required this.veto});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: kRed.withValues(alpha: .055),
          border: Border.all(color: kRed.withValues(alpha: .28)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.warning_amber_rounded, size: 18, color: kRed),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VETO — ${veto.title}',
                    style: const TextStyle(fontSize: 10, letterSpacing: 0.6, color: kRed, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    veto.note,
                    style: const TextStyle(fontSize: 13, height: 1.45, color: kInk2),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ReasonRow extends StatelessWidget {
  final Reason reason;
  const _ReasonRow({required this.reason});

  Color get _toneColor => switch (reason.tone) {
        'pos' => kGreen,
        'warn' => kOrange,
        _ => kRed,
      };

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: _toneColor, shape: BoxShape.circle),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reason.title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kInk, letterSpacing: -0.01),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    reason.note,
                    style: const TextStyle(fontSize: 13, height: 1.45, color: kMut),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _RubricRowTile extends StatelessWidget {
  final RubricRow row;
  final bool showDivider;
  const _RubricRowTile({required this.row, required this.showDivider});

  Color get _stateColor => switch (row.state) {
        'pass' => kGreen,
        'watch' => kOrange,
        _ => kRed,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: showDivider
            ? const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0EFED))))
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    row.label,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: kInk, letterSpacing: -0.01),
                  ),
                ),
                SizedBox(
                  width: 52,
                  height: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Stack(
                      children: [
                        Container(color: const Color(0xFFEDEDEC)),
                        FractionallySizedBox(
                          widthFactor: (row.score.clamp(0, 10)) / 10.0,
                          child: Container(color: _stateColor),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 30,
                  child: Text(
                    '${row.score}/10',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _stateColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              row.evidence,
              style: const TextStyle(fontSize: 11.5, height: 1.4, color: kMut),
            ),
          ],
        ),
      );
}

class _EvidenceGrid extends StatelessWidget {
  final List<EvidenceItem> items;
  const _EvidenceGrid({required this.items});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const gap = 9.0;
          final colWidth = (constraints.maxWidth - gap) / 2;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items
                .map((e) => SizedBox(
                      width: colWidth,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                        decoration: BoxDecoration(
                          color: kSurf,
                          border: Border.all(color: kHair),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.label.toUpperCase(),
                              style: const TextStyle(fontSize: 9, letterSpacing: 0.5, color: kFaint, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 5),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  e.value,
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.01, color: kInk),
                                ),
                                if (e.sub != null) ...[
                                  const SizedBox(width: 6),
                                  Text(e.sub!, style: const TextStyle(fontSize: 10.5, color: kFaint)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          );
        },
      );
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontSize: 10.5, letterSpacing: 1, color: kFaint, fontWeight: FontWeight.w600),
      );
}
