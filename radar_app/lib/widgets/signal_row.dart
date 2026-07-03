import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../logic/feed_logic.dart';
import '../models/signal_item.dart';
import '../theme.dart';
import 'source_mark.dart';

final _numFmt = NumberFormat('#,##0');

class _StateTagMeta {
  final String label;
  final Color color;
  const _StateTagMeta(this.label, this.color);
}

_StateTagMeta? _stateTagFor(String? watchState) => switch (watchState) {
      'watching' => const _StateTagMeta('Watching', kAccent),
      'seen' => const _StateTagMeta('Seen', kFaint),
      'dismissed' => const _StateTagMeta('Dismissed', kRed),
      _ => null,
    };

class SignalRow extends StatelessWidget {
  final SignalItem item;
  final VoidCallback onOpen;
  final VoidCallback onWatch;

  const SignalRow({
    super.key,
    required this.item,
    required this.onOpen,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final sm = stageMeta(item.momentumStage);
    final cm = consMeta(item.consistency);
    final stateTag = _stateTagFor(item.watchState);
    final isWatching = item.watchState == 'watching';
    final dim = item.watchState == 'dismissed' ? 0.55 : 1.0;

    final tags = item.isGithub
        ? [if (item.language != null && item.language!.isNotEmpty) item.language!, ...item.topics]
        : item.topics;

    // Cold-start (no prior snapshot) has null velocity → show the plain total
    // with a total-style unit, not a misleading "+N / wk". Real velocity + the
    // "/ wk" form appear once ≥2 snapshots exist.
    final hasVel = item.velocity != null;
    final metric = item.velocity ?? item.totalMetric ?? 0;
    final sign = (item.isGithub && hasVel && metric >= 0) ? '+' : '';
    final primaryText = '$sign${_numFmt.format(metric)}';
    final primaryUnit = hasVel
        ? (item.isGithub ? 'stars / wk' : 'votes + comments')
        : (item.isGithub ? 'stars' : 'votes');
    final secondaryText = '${_numFmt.format(item.totalMetric ?? 0)} total';

    return Opacity(
      opacity: dim,
      child: Material(
        color: kSurf,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: kHair),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SourceMark(isGithub: item.isGithub),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  item.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: kInk,
                                    letterSpacing: -0.02,
                                  ),
                                ),
                              ),
                              if (stateTag != null) ...[
                                const SizedBox(width: 7),
                                _StateTagChip(meta: stateTag),
                              ],
                            ],
                          ),
                          if (item.oneLiner != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.oneLiner!,
                              style: const TextStyle(fontSize: 14, height: 1.45, color: kInk2),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: onWatch,
                        icon: Icon(
                          isWatching ? Icons.bookmark : Icons.bookmark_border,
                          size: 17,
                          color: isWatching ? kAccent : kFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: tags
                        .map((t) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF2F1EF),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                t,
                                style: const TextStyle(fontSize: 11.5, color: kMut),
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                primaryText,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.02,
                                  color: kInk,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                primaryUnit,
                                style: const TextStyle(fontSize: 12, color: kMut),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(color: cm.color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                cm.label,
                                style: TextStyle(fontSize: 11, color: cm.color, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 8),
                              const Text('·', style: TextStyle(color: Color(0xFFD4D2CE))),
                              const SizedBox(width: 8),
                              Text(
                                secondaryText,
                                style: const TextStyle(fontSize: 12, color: kMut),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                      decoration: BoxDecoration(
                        color: sm.color.withValues(alpha: .11),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(sm.arrow, style: TextStyle(fontSize: 11, color: sm.color)),
                          const SizedBox(width: 4),
                          Text(
                            sm.label,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: sm.color),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StateTagChip extends StatelessWidget {
  final _StateTagMeta meta;
  const _StateTagChip({required this.meta});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: meta.color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          meta.label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: meta.color),
        ),
      );
}
