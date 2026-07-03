import 'package:flutter/material.dart';
import '../theme.dart';

const _sourceOpts = [('all', 'All'), ('github', 'GitHub'), ('producthunt', 'Product Hunt')];
const _stageOpts = [
  ('all', 'All'),
  ('emerging', 'Emerging'),
  ('rising', 'Rising'),
  ('steady', 'Steady'),
  ('fading', 'Fading'),
];
const _langOpts = [
  ('all', 'All tech'),
  ('Rust', 'Rust'),
  ('TypeScript', 'TS'),
  ('Go', 'Go'),
  ('Python', 'Python'),
  ('ai', 'AI'),
  ('database', 'Database'),
];
const _sortLabels = {
  'momentum': 'Momentum ↓',
  'velocity': 'Velocity ↓',
  'total': 'Total ↓',
  'newest': 'Newest',
};

class FiltersBar extends StatelessWidget {
  final String source;
  final String stage;
  final String lang;
  final String sortKey;
  final void Function(String) onSource;
  final void Function(String) onStage;
  final void Function(String) onLang;
  final VoidCallback onCycleSort;

  const FiltersBar({
    super.key,
    required this.source,
    required this.stage,
    required this.lang,
    required this.sortKey,
    required this.onSource,
    required this.onStage,
    required this.onLang,
    required this.onCycleSort,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: kHair),
              borderRadius: BorderRadius.circular(11),
              color: kSurf,
            ),
            child: Row(
              children: [
                for (final o in _sourceOpts) ...[
                  Expanded(
                    child: _SegButton(
                      label: o.$2,
                      active: source == o.$1,
                      onTap: () => onSource(o.$1),
                    ),
                  ),
                  if (o != _sourceOpts.last) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 11),
        SizedBox(
          height: 32,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            children: [
              _SortButton(label: _sortLabels[sortKey] ?? 'Momentum ↓', onTap: onCycleSort),
              const SizedBox(width: 7),
              const _Divider(),
              const SizedBox(width: 7),
              for (final o in _stageOpts) ...[
                _Chip(label: o.$2, active: stage == o.$1, onTap: () => onStage(o.$1)),
                const SizedBox(width: 7),
              ],
              const _Divider(),
              const SizedBox(width: 7),
              for (final o in _langOpts) ...[
                _Chip(label: o.$2, active: lang == o.$1, onTap: () => onLang(o.$1)),
                const SizedBox(width: 7),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 18, color: kHair);
}

class _SegButton extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _SegButton({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: active ? kAccent.withValues(alpha: .1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.01,
                color: active ? kAccent : kMut,
              ),
            ),
          ),
        ),
      );
}

class _SortButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SortButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: kSurf,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: kHair),
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.swap_vert, size: 13, color: kInk2),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.01,
                    color: kInk2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: active ? kAccent.withValues(alpha: .1) : kSurf,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: active ? kAccent.withValues(alpha: .35) : kHair),
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                letterSpacing: -0.01,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? kAccent : kMut,
              ),
            ),
          ),
        ),
      );
}
