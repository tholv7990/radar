# RADAR Phase 1 — App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch the loaded agency agents by role (Database Optimizer/Backend Architect for DB, Mobile App Builder/Frontend Developer for Flutter, Code Reviewer for task reviews).

**Goal:** The RADAR mobile app (Flutter, Android-first) — Login + Feed + Scope + Watchlist — reading the collector's Supabase data through a `signal_feed` view, with persistent watchlist state. No deep-dive / LLM (Phase 2).

**Architecture:** A Postgres **view** (`signal_feed`) computes momentum/consistency/rank from snapshots; RLS + a single account protect writes. A Flutter app in three layers — **UI → Repository → Supabase** — queries the view once per refresh and filters/sorts in memory (~100 rows).

**Tech Stack:** Postgres (Supabase) · Flutter/Dart · `supabase_flutter` · `url_launcher` · `intl` · Android SDK.

## Global Constraints

- **No LLM / no deep-dive** anywhere in Phase 1. (Spec invariant.)
- **Auth:** single-account **email/password**, RLS enforced; the collector (DB owner) bypasses RLS.
- **App reads the `signal_feed` view once per refresh; all filter/sort is in-memory.** No per-filter round-trips.
- **Anon key only in the app**, injected via `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_ANON_KEY=…`. The DB DSN / service key never ship in the app.
- **Android-first.** iOS build deferred to a Mac/cloud macOS. Same Dart either way.
- **Visual source of truth:** `RADAR.dc.html` (exact colors, spacing, copy). Palette: INK `#1a1a1a` · INK2 `#31302e` · MUT `#615d59` · FAINT `#a39e98` · CANVAS `#f6f5f4` · SURF `#ffffff` · HAIR `#e6e6e6` · GREEN `#1aae39` · TEAL `#2a9d99` · ORANGE `#dd5b00` · RED `#e03e3e` · INDIGO `#213183` · accent `#0075de`.
- **Verification environments:** DB tasks (Task 1) verify **here** via psycopg2 against Supabase. Flutter tasks (Tasks 2–8) require **Flutter + Android SDK installed on this machine**; their `flutter test` / `flutter run` verification happens once that toolchain is present.
- **Tap opens the item URL externally** (no rich detail screen — that's Phase 2).

## File structure

```
db/
  signal_feed.sql          # the view
  rls.sql                  # RLS enable + policies
scripts/
  apply_phase1_db.py       # apply view + RLS via psycopg2
  test_signal_feed.py      # integration check against Supabase
radar_app/                 # flutter create output (Task 2)
  pubspec.yaml
  lib/
    main.dart              # bootstrap: Supabase.initialize, auth gate, MaterialApp
    config.dart           # SUPABASE_URL / ANON_KEY from --dart-define
    theme.dart            # palette + text styles from the prototype
    models/signal_item.dart
    data/repository.dart   # signIn / fetchFeed / setWatchState
    logic/feed_logic.dart  # pure: filterAndSort, momentumStage label, consistency meta
    screens/login_screen.dart
    screens/home_scaffold.dart
    screens/feed_screen.dart
    screens/scope_screen.dart
    screens/watchlist_screen.dart
    widgets/signal_row.dart
    widgets/filters_bar.dart
    widgets/radar_painter.dart
  test/feed_logic_test.dart
```

---

### Task 1: DB — `signal_feed` view, RLS, single account *(verifiable here)*

**Files:**
- Create: `db/signal_feed.sql`, `db/rls.sql`, `scripts/apply_phase1_db.py`, `scripts/test_signal_feed.py`

**Interfaces:**
- Consumes: existing `entities`, `snapshots`, `watchlist_state` tables; `collector.config.load_config`, `collector.db.connect`.
- Produces: view `signal_feed` with columns `id, source, external_id, name, one_liner, url, language, topics, owner_type, created_at, captured_at, stars, forks, watchers, votes, comments, rating, provisional_quality, velocity, secondary_velocity, total_metric, consistency (text), momentum_stage (text), rank_score (numeric), watch_state (text|null)`. RLS policies on all four tables.

- [ ] **Step 1: Write `db/signal_feed.sql`**

```sql
create or replace view signal_feed as
with latest as (
  select distinct on (entity_id) * from snapshots
  order by entity_id, captured_at desc
),
prior as (
  select distinct on (s.entity_id) s.* from snapshots s
  join latest l on l.entity_id = s.entity_id
  where s.captured_at <= l.captured_at - interval '7 days'
  order by s.entity_id, s.captured_at desc
),
calc as (
  select
    e.id, e.source, e.external_id, e.name, e.one_liner, e.url,
    e.language, e.topics, e.owner_type, e.created_at,
    l.captured_at, l.stars, l.forks, l.watchers, l.votes, l.comments,
    l.rating, l.pushed_at, l.archived, l.provisional_quality,
    p.id as prior_id,
    case when e.source='github' then (l.stars - p.stars)
         else ((coalesce(l.votes,0)+coalesce(l.comments,0))
             - (coalesce(p.votes,0)+coalesce(p.comments,0))) end as velocity,
    case when e.source='github' then (l.forks - p.forks)
         else (l.comments - p.comments) end as secondary_velocity,
    case when e.source='github' then l.stars else l.votes end as total_metric,
    w.state as watch_state
  from entities e
  join latest l on l.entity_id = e.id
  left join prior p on p.entity_id = e.id
  left join watchlist_state w on w.entity_id = e.id
)
select
  c.*,
  -- consistency: does a secondary signal corroborate the primary move?
  case
    when c.prior_id is null then 'new'
    when c.velocity <= 0 then 'mixed'
    when c.secondary_velocity > 0 then 'corroborated'
    when c.velocity > 50 and c.secondary_velocity = 0 then 'suspicious'
    else 'mixed'
  end as consistency,
  -- momentum stage from growth rate (velocity relative to total); 'new' until a prior exists
  case
    when c.prior_id is null then 'new'
    when c.velocity <= 0 then 'fading'
    when c.velocity::numeric / nullif(c.total_metric,0) > 0.10 then 'emerging'
    when c.velocity::numeric / nullif(c.total_metric,0) > 0.03 then 'rising'
    else 'steady'
  end as momentum_stage,
  -- cold-start: rank by velocity when it exists, else provisional_quality
  coalesce(c.velocity::numeric, c.provisional_quality::numeric) as rank_score
from calc c;
```

- [ ] **Step 2: Write `db/rls.sql`**

```sql
alter table entities        enable row level security;
alter table snapshots       enable row level security;
alter table watchlist_state enable row level security;
alter table deep_dive_cache enable row level security;

-- read: any authenticated user
create policy read_entities  on entities        for select to authenticated using (true);
create policy read_snapshots on snapshots       for select to authenticated using (true);
create policy read_watch     on watchlist_state for select to authenticated using (true);
create policy read_cache     on deep_dive_cache for select to authenticated using (true);

-- write watchlist: any authenticated user (single-user app)
create policy write_watch_ins on watchlist_state for insert to authenticated with check (true);
create policy write_watch_upd on watchlist_state for update to authenticated using (true) with check (true);
create policy write_watch_del on watchlist_state for delete to authenticated using (true);
-- NOTE: the collector connects as the table owner and bypasses RLS entirely.
```

- [ ] **Step 3: Write `scripts/apply_phase1_db.py`**

```python
"""Apply the signal_feed view + RLS policies. Run from repo root: python -m scripts.apply_phase1_db"""
from pathlib import Path
from collector.config import load_config
from collector import db

cfg = load_config()
conn = db.connect(cfg)
with conn.cursor() as cur:
    cur.execute(Path("db/signal_feed.sql").read_text(encoding="utf-8"))
    # RLS: policies error if they already exist — drop-if-exists first for idempotency
    for stmt in Path("db/rls.sql").read_text(encoding="utf-8").split(";"):
        s = stmt.strip()
        if not s:
            continue
        try:
            cur.execute(s)
        except Exception as exc:
            if "already exists" in str(exc):
                conn.rollback()
                continue
            raise
conn.commit()
conn.close()
print("phase-1 db applied")
```

- [ ] **Step 4: Write `scripts/test_signal_feed.py` (integration check)**

```python
"""Verify signal_feed returns expected shape + ordering. Run: python -m scripts.test_signal_feed"""
from collector.config import load_config
from collector import db

conn = db.connect(load_config())
cur = conn.cursor()
cur.execute("select column_name from information_schema.columns where table_name='signal_feed'")
cols = {r[0] for r in cur.fetchall()}
for required in ("velocity", "consistency", "momentum_stage", "rank_score", "watch_state",
                 "provisional_quality", "source", "name"):
    assert required in cols, f"missing column {required}"

cur.execute("select count(*) from signal_feed")
n = cur.fetchone()[0]
assert n > 0, "signal_feed empty — did the collector run?"

# cold-start: with one snapshot, momentum_stage is 'new' and rank_score falls back to provisional_quality
cur.execute("select momentum_stage, rank_score, provisional_quality from signal_feed limit 5")
rows = cur.fetchall()
assert all(r[0] == 'new' for r in rows), "expected 'new' stage before 2nd snapshot"
assert all(float(r[1]) == float(r[2]) for r in rows), "rank_score should equal provisional_quality at cold-start"

cur.execute("select rank_score from signal_feed order by rank_score desc limit 3")
scores = [float(r[0]) for r in cur.fetchall()]
assert scores == sorted(scores, reverse=True), "not orderable by rank_score"
conn.close()
print(f"signal_feed OK — {n} rows, columns + cold-start + ordering verified")
```

- [ ] **Step 5: Apply and verify**

Run: `python -m scripts.apply_phase1_db` → expect `phase-1 db applied`
Run: `python -m scripts.test_signal_feed` → expect `signal_feed OK — <n> rows, …`

- [ ] **Step 6: Create the single app account**

In the Supabase dashboard → **Authentication → Users → Add user** → enter an email + password (this is your app login). Confirm the user appears. *(No code; this is the account the app signs in with.)*

- [ ] **Step 7: Commit**

```bash
git add db/signal_feed.sql db/rls.sql scripts/apply_phase1_db.py scripts/test_signal_feed.py
git commit -m "feat(app): signal_feed view + RLS + single-account auth"
```

---

### Task 2: Flutter scaffold + Supabase bootstrap + config *(needs Flutter toolchain)*

**Files:**
- Create: `radar_app/` (via `flutter create`), `radar_app/lib/config.dart`, `radar_app/lib/main.dart`, edit `radar_app/pubspec.yaml`

**Interfaces:**
- Produces: `Config.supabaseUrl`, `Config.supabaseAnonKey` (compile-time from `--dart-define`); a running app that initializes Supabase and shows a Login or Home based on session.

- [ ] **Step 1: Create the project**

Run (in repo root): `flutter create --org com.radar --project-name radar_app radar_app`
Expected: project scaffold under `radar_app/`.

- [ ] **Step 2: Add dependencies** — edit `radar_app/pubspec.yaml` `dependencies:`

```yaml
  supabase_flutter: ^2.5.0
  url_launcher: ^6.3.0
  intl: ^0.19.0
```

Run: `cd radar_app && flutter pub get` → expect resolution success.

- [ ] **Step 3: Write `radar_app/lib/config.dart`**

```dart
class Config {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
```

- [ ] **Step 4: Write `radar_app/lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_scaffold.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: Config.supabaseUrl, anonKey: Config.supabaseAnonKey);
  runApp(const RadarApp());
}

class RadarApp extends StatelessWidget {
  const RadarApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RADAR',
      debugShowCheckedModeBanner: false,
      theme: buildRadarTheme(),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          return session == null ? const LoginScreen() : const HomeScaffold();
        },
      ),
    );
  }
}
```

- [ ] **Step 5: Verify it launches**

Run: `flutter run --dart-define=SUPABASE_URL=<your-url> --dart-define=SUPABASE_ANON_KEY=<your-anon-key>` (Android emulator/device)
Expected: app launches to the Login screen (built in Task 4; until then a placeholder is fine). Fix any build errors before committing.

- [ ] **Step 6: Commit**

```bash
git add radar_app
git commit -m "feat(app): flutter scaffold + supabase bootstrap + config"
```

> **Note:** `radar_app/` includes generated Android/Gradle files. Add `radar_app/build/`, `radar_app/.dart_tool/` to `.gitignore` (Flutter's default `.gitignore` inside `radar_app/` already covers these — keep it).

---

### Task 3: Model + Repository

**Files:**
- Create: `radar_app/lib/models/signal_item.dart`, `radar_app/lib/data/repository.dart`, `radar_app/test/signal_item_test.dart`

**Interfaces:**
- Consumes: `signal_feed` columns (Task 1); `supabase_flutter`.
- Produces:
  - `SignalItem` with fields mirroring the view + `SignalItem.fromMap(Map<String,dynamic>)`.
  - `Repository` singleton: `Future<void> signIn(String email, String password)`, `Future<List<SignalItem>> fetchFeed()`, `Future<void> setWatchState(int entityId, String? state)`, `Future<void> signOut()`.

- [ ] **Step 1: Write the failing test** — `radar_app/test/signal_item_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/signal_item.dart';

void main() {
  test('fromMap maps view columns', () {
    final it = SignalItem.fromMap({
      'id': 7, 'source': 'github', 'name': 'driftdb', 'one_liner': 'db',
      'url': 'https://x', 'language': 'Rust', 'topics': ['database'],
      'stars': 8400, 'votes': null, 'comments': null,
      'provisional_quality': 89, 'velocity': 2140, 'total_metric': 8400,
      'consistency': 'corroborated', 'momentum_stage': 'emerging',
      'rank_score': 2140, 'watch_state': 'watching',
    });
    expect(it.id, 7);
    expect(it.source, 'github');
    expect(it.isGithub, true);
    expect(it.velocity, 2140);
    expect(it.consistency, 'corroborated');
    expect(it.watchState, 'watching');
    expect(it.topics, ['database']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd radar_app && flutter test test/signal_item_test.dart`
Expected: FAIL — `SignalItem` undefined.

- [ ] **Step 3: Write `radar_app/lib/models/signal_item.dart`**

```dart
class SignalItem {
  final int id;
  final String source;
  final String name;
  final String? oneLiner;
  final String? url;
  final String? language;
  final List<String> topics;
  final int? stars;
  final int? votes;
  final int? comments;
  final int provisionalQuality;
  final int? velocity;
  final int? totalMetric;
  final String consistency;   // corroborated | mixed | suspicious | new
  final String momentumStage; // emerging | rising | steady | fading | new
  final num rankScore;
  final String? watchState;   // seen | watching | dismissed | null

  SignalItem({
    required this.id, required this.source, required this.name, this.oneLiner,
    this.url, this.language, required this.topics, this.stars, this.votes,
    this.comments, required this.provisionalQuality, this.velocity,
    this.totalMetric, required this.consistency, required this.momentumStage,
    required this.rankScore, this.watchState,
  });

  bool get isGithub => source == 'github';

  static List<String> _topics(dynamic v) =>
      v == null ? <String>[] : (v as List).map((e) => e.toString()).toList();

  factory SignalItem.fromMap(Map<String, dynamic> m) => SignalItem(
        id: m['id'] as int,
        source: m['source'] as String,
        name: m['name'] as String,
        oneLiner: m['one_liner'] as String?,
        url: m['url'] as String?,
        language: m['language'] as String?,
        topics: _topics(m['topics']),
        stars: m['stars'] as int?,
        votes: m['votes'] as int?,
        comments: m['comments'] as int?,
        provisionalQuality: (m['provisional_quality'] ?? 0) as int,
        velocity: (m['velocity'] as num?)?.toInt(),
        totalMetric: (m['total_metric'] as num?)?.toInt(),
        consistency: (m['consistency'] ?? 'new') as String,
        momentumStage: (m['momentum_stage'] ?? 'new') as String,
        rankScore: (m['rank_score'] ?? 0) as num,
        watchState: m['watch_state'] as String?,
      );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd radar_app && flutter test test/signal_item_test.dart` → expect PASS.

- [ ] **Step 5: Write `radar_app/lib/data/repository.dart`**

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/signal_item.dart';

class Repository {
  Repository._();
  static final Repository instance = Repository._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<void> signIn(String email, String password) =>
      _db.auth.signInWithPassword(email: email, password: password);

  Future<void> signOut() => _db.auth.signOut();

  Future<List<SignalItem>> fetchFeed() async {
    final rows = await _db.from('signal_feed').select();
    return (rows as List)
        .map((r) => SignalItem.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> setWatchState(int entityId, String? state) async {
    if (state == null) {
      await _db.from('watchlist_state').delete().eq('entity_id', entityId);
    } else {
      await _db.from('watchlist_state').upsert(
        {'entity_id': entityId, 'state': state, 'updated_at': DateTime.now().toUtc().toIso8601String()},
        onConflict: 'entity_id',
      );
    }
  }
}
```

- [ ] **Step 6: Commit**

```bash
git add radar_app/lib/models radar_app/lib/data radar_app/test/signal_item_test.dart
git commit -m "feat(app): SignalItem model + repository"
```

---

### Task 4: Theme + Login screen + auth gate

**Files:**
- Create: `radar_app/lib/theme.dart`, `radar_app/lib/screens/login_screen.dart`

**Interfaces:**
- Consumes: `Repository.instance.signIn`, palette from Global Constraints.
- Produces: `buildRadarTheme()` (ThemeData); `LoginScreen` widget that signs in and (via the `main.dart` auth-state stream) routes to `HomeScaffold` on success.

- [ ] **Step 1: Write `radar_app/lib/theme.dart`** — palette constants + `ThemeData`

```dart
import 'package:flutter/material.dart';

const kInk = Color(0xFF1A1A1A);
const kInk2 = Color(0xFF31302E);
const kMut = Color(0xFF615D59);
const kFaint = Color(0xFFA39E98);
const kCanvas = Color(0xFFF6F5F4);
const kSurf = Color(0xFFFFFFFF);
const kHair = Color(0xFFE6E6E6);
const kGreen = Color(0xFF1AAE39);
const kTeal = Color(0xFF2A9D99);
const kOrange = Color(0xFFDD5B00);
const kRed = Color(0xFFE03E3E);
const kIndigo = Color(0xFF213183);
const kAccent = Color(0xFF0075DE);

ThemeData buildRadarTheme() => ThemeData(
      scaffoldBackgroundColor: kCanvas,
      fontFamily: 'Inter', // falls back to system if Inter not bundled
      colorScheme: ColorScheme.fromSeed(seedColor: kAccent, surface: kSurf),
      useMaterial3: true,
    );
```

- [ ] **Step 2: Write `radar_app/lib/screens/login_screen.dart`**

```dart
import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    setState(() { _busy = true; _error = null; });
    try {
      await Repository.instance.signIn(_email.text.trim(), _pass.text);
      // auth-state stream in main.dart routes to HomeScaffold
    } catch (e) {
      setState(() => _error = 'Sign-in failed. Check your email/password.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('RADAR', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 3, color: kInk)),
              const SizedBox(height: 24),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: _pass, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: kRed))),
              const SizedBox(height: 20),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Signing in…' : 'Sign in'))),
            ]),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Verify** — Run the app (`flutter run --dart-define=…`), enter the Task 1 Step 6 account → routes to Home (placeholder until Task 5). Wrong password → error text.

- [ ] **Step 4: Commit**

```bash
git add radar_app/lib/theme.dart radar_app/lib/screens/login_screen.dart
git commit -m "feat(app): theme + login screen + auth gate"
```

---

### Task 5: Feed logic (pure) + tests

**Files:**
- Create: `radar_app/lib/logic/feed_logic.dart`, `radar_app/test/feed_logic_test.dart`

**Interfaces:**
- Consumes: `SignalItem`.
- Produces:
  - `List<SignalItem> filterAndSort(List<SignalItem> items, {String source, String stage, String lang, String sortKey, String? watchFilter})`
  - `StageMeta stageMeta(String stage)` → `{label, arrow, color}`; `ConsMeta consMeta(String c)` → `{label, color}`.
  - Sort keys: `momentum` (rankScore desc), `velocity` (velocity desc), `total` (totalMetric desc), `newest` (createdAt desc).

- [ ] **Step 1: Write the failing test** — `radar_app/test/feed_logic_test.dart`

```dart
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
    expect(r.map((e) => e.name), ['b', 'a']); // c dismissed → hidden
  });

  test('source filter', () {
    final r = filterAndSort(items, source: 'producthunt', stage: 'all', lang: 'all', sortKey: 'momentum');
    expect(r.map((e) => e.name), ['b']);
  });

  test('sort by total', () {
    final r = filterAndSort(items, source: 'all', stage: 'all', lang: 'all', sortKey: 'total');
    expect(r.first.name, 'a'); // total 500 > b 200 (c hidden)
  });

  test('watch filter shows only that state', () {
    final r = filterAndSort(items, source: 'all', stage: 'all', lang: 'all', sortKey: 'momentum', watchFilter: 'dismissed');
    expect(r.map((e) => e.name), ['c']);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd radar_app && flutter test test/feed_logic_test.dart`
Expected: FAIL — `filterAndSort` undefined.

- [ ] **Step 3: Write `radar_app/lib/logic/feed_logic.dart`**

```dart
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
    return x.watchState != 'dismissed'; // feed hides dismissed
  }).toList();

  int cmp(SignalItem a, SignalItem b) => switch (sortKey) {
    'velocity' => (b.velocity ?? 0).compareTo(a.velocity ?? 0),
    'total'    => (b.totalMetric ?? 0).compareTo(a.totalMetric ?? 0),
    'newest'   => b.id.compareTo(a.id), // ponytail: proxy for recency until created_at wired
    _          => b.rankScore.compareTo(a.rankScore),
  };
  list.sort(cmp);
  return list;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd radar_app && flutter test test/feed_logic_test.dart` → expect PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add radar_app/lib/logic radar_app/test/feed_logic_test.dart
git commit -m "feat(app): pure feed filter/sort logic + tests"
```

---

### Task 6: Home scaffold + Feed screen + signal row + filters bar

**Files:**
- Create: `radar_app/lib/screens/home_scaffold.dart`, `radar_app/lib/screens/feed_screen.dart`, `radar_app/lib/widgets/signal_row.dart`, `radar_app/lib/widgets/filters_bar.dart`

**Interfaces:**
- Consumes: `Repository.instance.fetchFeed/setWatchState`, `filterAndSort`, `stageMeta/consMeta`, `SignalItem`.
- Produces: `HomeScaffold` (bottom nav Feed/Scope/Watchlist, holds fetched items + refresh); `FeedScreen(items, onOpen, onWatch, filter state)`; `SignalRow(item, onOpen, onWatch)`; `FiltersBar(...)`.

**Implementation guidance:** match `RADAR.dc.html` exactly for the row and filters (owner/name line, one-liner, tag chips, primary metric + unit, consistency dot + label, stage pill, last-active, watch bookmark button; source segment + sort cycle + stage chips + lang chips). Use the palette constants from `theme.dart`. `onOpen` calls `url_launcher`'s `launchUrl(Uri.parse(item.url))`. `onWatch` cycles `watching ↔ seen` via `Repository.setWatchState` then refreshes.

- [ ] **Step 1: Write `home_scaffold.dart`** — stateful; on init `fetchFeed()` into state; `BottomNavigationBar` with three tabs rendering `FeedScreen` / `ScopeScreen` (Task 7) / `WatchlistScreen` (built here as Feed with `watchFilter`); a refresh action re-calls `fetchFeed()`. Hold filter state (`source/stage/lang/sortKey`) here and pass down. Show an "as of" stamp from the max `captured_at`.

```dart
// Skeleton — full widget tree mirrors the prototype header/tabbar.
import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../models/signal_item.dart';
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
  String source = 'all', stage = 'all', lang = 'all', sortKey = 'momentum';

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await Repository.instance.fetchFeed();
    if (mounted) setState(() { _items = items; _loading = false; });
  }

  Future<void> _watch(SignalItem it) async {
    final next = it.watchState == 'watching' ? 'seen' : 'watching';
    await Repository.instance.setWatchState(it.id, next);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
      ? const Center(child: CircularProgressIndicator())
      : IndexedStack(index: _tab, children: [
          FeedScreen(items: _items, source: source, stage: stage, lang: lang, sortKey: sortKey,
            onSetFilter: (s, st, l, sk) => setState(() { source = s; stage = st; lang = l; sortKey = sk; }),
            onOpen: _open, onWatch: _watch, watchFilter: null),
          ScopeScreen(items: _items, onOpen: _open),
          FeedScreen(items: _items, source: 'all', stage: 'all', lang: 'all', sortKey: sortKey,
            onSetFilter: (s, st, l, sk) => setState(() => sortKey = sk),
            onOpen: _open, onWatch: _watch, watchFilter: 'all'),
        ]);
    return Scaffold(
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list), label: 'Feed'),
          NavigationDestination(icon: Icon(Icons.radar), label: 'Scope'),
          NavigationDestination(icon: Icon(Icons.bookmark_border), label: 'Watchlist'),
        ],
      ),
    );
  }

  void _open(SignalItem it) { /* url_launcher: launchUrl(Uri.parse(it.url!)) */ }
}
```

- [ ] **Step 2: Write `signal_row.dart`, `filters_bar.dart`, `feed_screen.dart`** matching the prototype's markup and the palette. `FeedScreen` applies `filterAndSort(items, …)` and renders `FiltersBar` + a `ListView` of `SignalRow`. Empty result → the "No signals match this filter." centered message.

- [ ] **Step 3: Verify** — `flutter run --dart-define=…`; log in; Feed lists real signals from Supabase; source/sort/stage/lang filters change the list; tapping a row opens the browser; watch button toggles and persists (re-open app → state kept). Watchlist tab shows only watched/seen.

- [ ] **Step 4: Commit**

```bash
git add radar_app/lib/screens radar_app/lib/widgets
git commit -m "feat(app): home scaffold + feed + watchlist + signal row + filters"
```

---

### Task 7: Scope screen + radar painter

**Files:**
- Create: `radar_app/lib/screens/scope_screen.dart`, `radar_app/lib/widgets/radar_painter.dart`

**Interfaces:**
- Consumes: `SignalItem`, `stageMeta`, palette.
- Produces: `ScopeScreen(items, onOpen)`; `RadarPainter extends CustomPainter` drawing rings, quadrant grid, the sweet-spot region, and one blip per item at `(x = provisionalQuality, y = momentum position)`.

**Implementation guidance:** mirror the prototype's Scope: indigo card, concentric rings, dashed axes, "SWEET SPOT" top-right, blips positioned by `provisional_quality` (x) and a momentum position (y). **Phase 1: all blips are hollow/provisional** (no deep-dive `quality_score` exists) — draw hollow/ringed dots, not solid. Below the radar, the "RANKED BY MOMENTUM" list (rank number, colored dot, name, `Quality <pq> · Momentum <pos>`, stage pill). Tapping a blip or list row calls `onOpen`. Momentum position for y: derive from `momentumStage`/`velocity` (e.g., emerging/rising high, steady mid, fading/new low) — a pure helper `double momentumPos(SignalItem)` you unit-test.

- [ ] **Step 1: Write the failing test** — `radar_app/test/momentum_pos_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/signal_item.dart';
import 'package:radar_app/widgets/radar_painter.dart';

SignalItem it(String stage) => SignalItem(id: 1, source: 'github', name: 'x',
  topics: const [], provisionalQuality: 50, consistency: 'new',
  momentumStage: stage, rankScore: 0);

void main() {
  test('momentumPos orders emerging > steady > fading', () {
    expect(momentumPos(it('emerging')) > momentumPos(it('steady')), true);
    expect(momentumPos(it('steady')) > momentumPos(it('fading')), true);
    expect(momentumPos(it('emerging')) <= 100 && momentumPos(it('fading')) >= 0, true);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd radar_app && flutter test test/momentum_pos_test.dart` → FAIL (`momentumPos` undefined).

- [ ] **Step 3: Implement `radar_painter.dart`** (with `momentumPos`) and `scope_screen.dart`

```dart
import 'package:flutter/material.dart';
import '../models/signal_item.dart';
import '../theme.dart';

double momentumPos(SignalItem it) => switch (it.momentumStage) {
  'emerging' => 90, 'rising' => 75, 'steady' => 45, 'fading' => 20, _ => 35,
};

class RadarPainter extends CustomPainter {
  final List<SignalItem> items;
  RadarPainter(this.items);
  @override
  void paint(Canvas canvas, Size size) {
    // rings + dashed axes on an indigo field; blip at
    //   x = provisionalQuality/100 * w, y = (1 - momentumPos/100) * h
    // Phase 1: hollow blips (stroke, no fill). Full styling per prototype.
  }
  @override
  bool shouldRepaint(covariant RadarPainter old) => old.items != items;
}
```

- [ ] **Step 4: Run to verify the helper passes**

Run: `cd radar_app && flutter test test/momentum_pos_test.dart` → PASS.

- [ ] **Step 5: Verify visually** — `flutter run`; Scope tab shows the radar with hollow blips and the ranked list; tapping opens the URL.

- [ ] **Step 6: Commit**

```bash
git add radar_app/lib/screens/scope_screen.dart radar_app/lib/widgets/radar_painter.dart radar_app/test/momentum_pos_test.dart
git commit -m "feat(app): scope radar + ranked list (provisional blips)"
```

---

### Task 8: Freshness stamp, sign-out, and full-suite check

**Files:**
- Modify: `radar_app/lib/screens/home_scaffold.dart` (add "as of" stamp + refresh + sign-out action)

- [ ] **Step 1:** Add a header showing `as of <max captured_at>` (format with `intl`), a refresh button calling `_load()`, and a sign-out action calling `Repository.instance.signOut()`.
- [ ] **Step 2: Run full Dart suite**

Run: `cd radar_app && flutter test` → expect all tests pass (`signal_item`, `feed_logic`, `momentum_pos`).

- [ ] **Step 3: End-to-end smoke on device** — install account signs in, all three tabs work, watch state persists across restarts, freshness stamp shows the collector's last run.

- [ ] **Step 4: Commit**

```bash
git add radar_app/lib/screens/home_scaffold.dart
git commit -m "feat(app): freshness stamp, refresh, sign-out"
```

---

## Definition of done (Phase 1)

- ☐ `signal_feed` view + RLS applied; integration test green; single account created. *(verified here)*
- ☐ App signs in (email/password), routes via auth state.
- ☐ Feed renders from the view; filter/sort work; watch state persists to Supabase; tap opens URL.
- ☐ Scope radar + ranked list render with provisional (hollow) blips.
- ☐ Watchlist filters by state; freshness stamp shows last run.
- ☐ `flutter test` green (model, feed logic, momentum-pos).
- ☐ Runs on Android.
- ☐ **Out:** deep-dive overlay, LLM/rubric/score, Realtime, solid Scope blips (all Phase 2).

## Self-review notes

- **Spec coverage:** §4 view → Task 1; §5 login/feed/scope/watchlist → Tasks 4/6/7/6; §6 auth+RLS → Tasks 1/4; §7 repository+state → Tasks 2/3/6; §8 error/empty/freshness → Tasks 4/6/8; §9 tests → Tasks 3/5/7. Cold-start fallback → Task 1 SQL + test.
- **Verification honesty:** Task 1 verifies here; Tasks 2–8 require Flutter+Android on this machine (per Global Constraints) — their verify steps run once the toolchain is installed. UI Tasks 6 & 7 reference `RADAR.dc.html` for exact styling rather than restating every pixel value; the non-obvious logic (model, filter/sort, momentum-pos) carries real unit tests.
