import 'package:flutter/material.dart';
import '../logic/feed_logic.dart';
import '../models/signal_item.dart';
import '../theme.dart';
import '../widgets/filters_bar.dart';
import '../widgets/signal_row.dart';

const _sortOrder = ['momentum', 'velocity', 'total', 'newest'];

String nextSortKey(String key) {
  final i = _sortOrder.indexOf(key);
  return _sortOrder[(i + 1) % _sortOrder.length];
}

class FeedScreen extends StatelessWidget {
  final List<SignalItem> items;
  final String source;
  final String stage;
  final String lang;
  final String sortKey;
  final String? watchFilter;
  final void Function(String source, String stage, String lang, String sortKey) onSetFilter;
  final void Function(SignalItem) onOpen;
  final void Function(SignalItem) onWatch;

  const FeedScreen({
    super.key,
    required this.items,
    required this.source,
    required this.stage,
    required this.lang,
    required this.sortKey,
    this.watchFilter,
    required this.onSetFilter,
    required this.onOpen,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final filtered = filterAndSort(
      items,
      source: source,
      stage: stage,
      lang: lang,
      sortKey: sortKey,
      watchFilter: watchFilter,
    );

    return Column(
      children: [
        FiltersBar(
          source: source,
          stage: stage,
          lang: lang,
          sortKey: sortKey,
          onSource: (v) => onSetFilter(v, stage, lang, sortKey),
          onStage: (v) => onSetFilter(source, v, lang, sortKey),
          onLang: (v) => onSetFilter(source, stage, v, sortKey),
          onCycleSort: () => onSetFilter(source, stage, lang, nextSortKey(sortKey)),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'No signals match this filter.',
                    style: TextStyle(fontSize: 13, letterSpacing: 0.2, color: kMut),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final it = filtered[i];
                    return SignalRow(
                      item: it,
                      onOpen: () => onOpen(it),
                      onWatch: () => onWatch(it),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
