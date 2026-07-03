import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repository.dart';
import '../models/signal_item.dart';
import '../theme.dart';
import 'feed_screen.dart';
import 'scope_screen.dart';

class HomeScaffold extends StatefulWidget {
  const HomeScaffold({super.key});
  @override
  State<HomeScaffold> createState() => _HomeScaffoldState();
}

class _HomeScaffoldState extends State<HomeScaffold> {
  int _tab = 0;
  List<SignalItem> _items = [];
  bool _loading = true;
  String? _error;
  String source = 'all', stage = 'all', lang = 'all', sortKey = 'momentum';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await Repository.instance.fetchFeed();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load signals.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _open(SignalItem it) async {
    if (it.url == null) return;
    await launchUrl(Uri.parse(it.url!), mode: LaunchMode.externalApplication);
  }

  Future<void> _watch(SignalItem it) async {
    final next = it.watchState == 'watching' ? 'seen' : 'watching';
    await Repository.instance.setWatchState(it.id, next);
    await _load();
  }

  void _setFilter(String s, String st, String l, String sk) => setState(() {
        source = s;
        stage = st;
        lang = l;
        sortKey = sk;
      });

  String _asOf() {
    final ts = _items.map((e) => e.capturedAt).whereType<DateTime>().toList();
    if (ts.isEmpty) return '—';
    ts.sort();
    return DateFormat('MMM d · HH:mm').format(ts.last.toLocal());
  }

  Future<void> _signOut() async {
    await Repository.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (_error != null) {
      body = Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, style: const TextStyle(color: kMut)),
          TextButton(onPressed: _load, child: const Text('Retry')),
        ]),
      );
    } else {
      body = IndexedStack(index: _tab, children: [
        FeedScreen(
          items: _items,
          source: source,
          stage: stage,
          lang: lang,
          sortKey: sortKey,
          watchFilter: null,
          onSetFilter: _setFilter,
          onOpen: _open,
          onWatch: _watch,
        ),
        ScopeScreen(items: _items, onOpen: _open),
        FeedScreen(
          items: _items,
          source: 'all',
          stage: 'all',
          lang: 'all',
          sortKey: sortKey,
          watchFilter: 'all',
          onSetFilter: (s, st, l, sk) => setState(() => sortKey = sk),
          onOpen: _open,
          onWatch: _watch,
        ),
      ]);
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _Header(
              count: _items.length,
              loading: _loading,
              asOf: _asOf(),
              onRefresh: _load,
              onSignOut: _signOut,
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: kSurf,
          indicatorColor: kAccent.withValues(alpha: 0.12),
          iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? kAccent : kFaint)),
          labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: s.contains(WidgetState.selected) ? kAccent : kFaint)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.list), label: 'Feed'),
            NavigationDestination(icon: Icon(Icons.radar), label: 'Scope'),
            NavigationDestination(icon: Icon(Icons.bookmark_border), selectedIcon: Icon(Icons.bookmark), label: 'Watchlist'),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final int count;
  final bool loading;
  final String asOf;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;
  const _Header({
    required this.count,
    required this.loading,
    required this.asOf,
    required this.onRefresh,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
        decoration: const BoxDecoration(
          color: kSurf,
          border: Border(bottom: BorderSide(color: kHair)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    _RadarGlyph(),
                    SizedBox(width: 9),
                    Text(
                      'RADAR',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        letterSpacing: 2.5,
                        color: kInk,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Material(
                        color: kSurf,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onRefresh,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: kHair),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: loading
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 1.6, color: kMut),
                                  )
                                : const Icon(Icons.refresh, size: 16, color: kMut),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: Material(
                        color: kSurf,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: onSignOut,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: kHair),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: const Icon(Icons.logout, size: 16, color: kMut),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: kGreen,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kGreen.withValues(alpha: .55), blurRadius: 7)],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'AS OF',
                  style: TextStyle(
                    fontSize: 10.5,
                    letterSpacing: 1.3,
                    color: kFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  asOf,
                  style: const TextStyle(fontSize: 11.5, letterSpacing: -0.1, color: kMut),
                ),
                const Spacer(),
                Text(
                  '$count signals tracked',
                  style: const TextStyle(fontSize: 10.5, letterSpacing: 0.4, color: kFaint, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ),
      );
}

class _RadarGlyph extends StatelessWidget {
  const _RadarGlyph();
  @override
  Widget build(BuildContext context) => const SizedBox(
        width: 24,
        height: 24,
        child: CustomPaint(painter: _RadarGlyphPainter()),
      );
}

class _RadarGlyphPainter extends CustomPainter {
  const _RadarGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const center = Offset(12, 12);

    canvas.drawCircle(
      center,
      10.5,
      Paint()
        ..color = kAccent.withValues(alpha: .22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(
      center,
      6.5,
      Paint()
        ..color = kAccent.withValues(alpha: .38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final wedge = Path()
      ..moveTo(12, 12)
      ..lineTo(12, 1.5)
      ..arcToPoint(const Offset(21, 7), radius: const Radius.circular(10.5))
      ..close();
    canvas.drawPath(wedge, Paint()..color = kAccent.withValues(alpha: .16));

    canvas.drawLine(
      center,
      const Offset(12, 1.5),
      Paint()
        ..color = kAccent
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(center, 2, Paint()..color = kAccent);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

