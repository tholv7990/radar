import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import '../logic/feed_logic.dart';
import '../models/signal_item.dart';
import '../theme.dart';

const _githubMarkSvg = '''
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="#1a1a1a" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.724-4.042-1.61-4.042-1.61C4.422 18.07 3.633 17.7 3.633 17.7c-1.087-.744.084-.729.084-.729 1.205.084 1.838 1.236 1.838 1.236 1.07 1.835 2.809 1.305 3.495.998.108-.776.417-1.305.76-1.605-2.665-.3-5.466-1.332-5.466-5.93 0-1.31.465-2.38 1.235-3.22-.135-.303-.54-1.523.105-3.176 0 0 1.005-.322 3.3 1.23.96-.267 1.98-.399 3-.405 1.02.006 2.04.138 3 .405 2.28-1.552 3.285-1.23 3.285-1.23.645 1.653.24 2.873.12 3.176.765.84 1.23 1.91 1.23 3.22 0 4.61-2.805 5.625-5.475 5.92.42.36.81 1.096.81 2.22 0 1.606-.015 2.896-.015 3.286 0 .315.21.69.825.57C20.565 22.092 24 17.592 24 12.297c0-6.627-5.373-12-12-12"/></svg>
''';

const _productHuntMarkSvg = '''
<svg width="24" height="24" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><path fill="#DA552F" d="M13.604 8.4h-3.405V12h3.405c.995 0 1.801-.806 1.801-1.801 0-.993-.805-1.799-1.801-1.799zM12 0C5.372 0 0 5.372 0 12s5.372 12 12 12 12-5.372 12-12S18.628 0 12 0zm1.604 14.4h-3.405V18H7.801V6h5.803c2.319 0 4.199 1.88 4.199 4.199 0 2.321-1.88 4.201-4.199 4.201z"/></svg>
''';

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

    final velocity = item.velocity ?? item.totalMetric ?? 0;
    final primaryText = item.isGithub
        ? '${velocity >= 0 ? '+' : ''}${_numFmt.format(velocity)}'
        : _numFmt.format(velocity);
    final primaryUnit = item.isGithub ? 'stars / wk' : 'votes + comments';
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
                    _SourceMark(isGithub: item.isGithub),
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

class _SourceMark extends StatelessWidget {
  final bool isGithub;
  const _SourceMark({required this.isGithub});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 22,
        height: 22,
        child: Padding(
          padding: const EdgeInsets.only(top: 1),
          child: SvgPicture.string(isGithub ? _githubMarkSvg : _productHuntMarkSvg),
        ),
      );
}
