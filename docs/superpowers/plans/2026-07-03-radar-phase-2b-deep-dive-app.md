# RADAR Phase 2B — Deep-Dive App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Dispatch agency agents by role (Mobile App Builder / Frontend Developer for UI, Code Reviewer for task reviews).

**Goal:** The Flutter deep-dive experience — tap an item → invoke the `deep-dive` Edge Function → stream the result into an overlay (score, quadrant, vetoes, reasons, rubric, evidence) via Supabase Realtime — plus solid Scope blips for deep-dived items.

**Architecture:** `SignalItem` gains the cached `qualityScore`/`deepDiveStatus` (from `signal_feed` v2). A `DeepDiveResult` model parses `deep_dive_cache.full_result`. The repository invokes the function and exposes a Realtime stream of the cache row; the overlay is a `StreamBuilder` state machine (running → done/error). The Scope radar draws solid blips when a `done` deep-dive exists.

**Tech Stack:** Flutter/Dart · `supabase_flutter` (`functions.invoke` + `.stream()` Realtime) · `url_launcher` · `intl`. No new dependencies.

## Global Constraints

- **No new LLM/network logic in the app** — the app only *invokes* the Edge Function and *reads* `deep_dive_cache`; all evidence/scoring is server-side (Phase 2A).
- **Realtime, not polling:** the overlay subscribes to the `deep_dive_cache` row via `supabase_flutter`'s `.stream()`.
- **Cached indefinitely; manual re-run** re-invokes the function (spec FR-2.3).
- **Visual source of truth:** the deep-dive overlay in `RADAR.dc.html` (lines ~232–372: header/score-ring/quadrant/veto/reasons/rubric-checklist/evidence-grid/re-run). Palette is in `radar_app/lib/theme.dart`.
- **Tap opens the deep-dive overlay** (Phase 1's row-tap = open URL moves *into* the overlay's external-link button).
- **Scope blips:** solid (filled) using `qualityScore` when `deepDiveStatus == 'done'`; else hollow using `provisionalQuality` (Phase 1 behavior).
- **Verification environments:** `flutter test`/`analyze`/`build web` verify here (Flutter at `/c/src/flutter/bin/flutter`, NOT on PATH — prepend `export PATH="/c/src/flutter/bin:$PATH"`). The **live** invoke + Realtime flow requires the deployed Edge Function (Phase 2A Task 6) + login — exercised on-device after deploy, not in this plan's automated checks.

## File structure

```
radar_app/lib/
  models/signal_item.dart      # MODIFY: + qualityScore, + deepDiveStatus
  models/deep_dive.dart        # NEW: DeepDiveResult + Veto/Reason/RubricRow/EvidenceItem + fromMap
  data/repository.dart         # MODIFY: + invokeDeepDive, + deepDiveStream, + fetchDeepDive
  screens/deep_dive_overlay.dart  # NEW: the overlay (StreamBuilder state machine)
  screens/home_scaffold.dart   # MODIFY: row tap -> open overlay (not URL)
  widgets/radar_painter.dart   # MODIFY: solid blip when done
  screens/scope_screen.dart    # MODIFY: blip x + ranked "Quality" use qualityScore when done
  test/deep_dive_test.dart     # NEW: DeepDiveResult.fromMap
  test/signal_item_test.dart   # MODIFY: assert new fields
```

---

### Task 1: Models — SignalItem fields + DeepDiveResult

**Files:**
- Modify: `radar_app/lib/models/signal_item.dart`
- Create: `radar_app/lib/models/deep_dive.dart`, `radar_app/test/deep_dive_test.dart`
- Modify: `radar_app/test/signal_item_test.dart`

**Interfaces:**
- Produces: `SignalItem` gains `qualityScore (int?)`, `deepDiveStatus (String?)`. `DeepDiveResult` with `score (int)`, `verdict (String)`, `vetoes (List<Veto>)`, `reasons (List<Reason>)`, `rubric (List<RubricRow>)`, `evidence (List<EvidenceItem>)` + `factory DeepDiveResult.fromMap(Map<String,dynamic>)`. `Veto{title,note}`, `Reason{tone,title,note}`, `RubricRow{label,score,state,evidence}`, `EvidenceItem{label,value,sub?}`.

- [ ] **Step 1: Write the failing test** — `radar_app/test/deep_dive_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:radar_app/models/deep_dive.dart';

void main() {
  test('DeepDiveResult.fromMap parses full_result', () {
    final r = DeepDiveResult.fromMap({
      'score': 89, 'verdict': 'Adopt-worthy.',
      'vetoes': [{'title': 'X', 'note': 'y'}],
      'reasons': [{'tone': 'pos', 'title': 'A', 'note': 'b'}],
      'rubric': [{'label': 'Adoption', 'score': 9, 'state': 'pass', 'evidence': 'e'}],
      'evidence': [{'label': 'Contributors', 'value': '24', 'sub': 'x'}],
    });
    expect(r.score, 89);
    expect(r.verdict, 'Adopt-worthy.');
    expect(r.vetoes.single.title, 'X');
    expect(r.reasons.single.tone, 'pos');
    expect(r.rubric.single.score, 9);
    expect(r.evidence.single.value, '24');
  });

  test('tolerates missing/empty lists', () {
    final r = DeepDiveResult.fromMap({'score': 40, 'verdict': 'meh'});
    expect(r.vetoes, isEmpty);
    expect(r.reasons, isEmpty);
    expect(r.rubric, isEmpty);
    expect(r.evidence, isEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd radar_app && export PATH="/c/src/flutter/bin:$PATH" && flutter test test/deep_dive_test.dart`
Expected: FAIL — `DeepDiveResult` undefined.

- [ ] **Step 3: Create `radar_app/lib/models/deep_dive.dart`**

```dart
class Veto {
  final String title;
  final String note;
  const Veto(this.title, this.note);
}

class Reason {
  final String tone; // pos | warn | neg
  final String title;
  final String note;
  const Reason(this.tone, this.title, this.note);
}

class RubricRow {
  final String label;
  final int score; // 0-10
  final String state; // pass | watch | fail
  final String evidence;
  const RubricRow(this.label, this.score, this.state, this.evidence);
}

class EvidenceItem {
  final String label;
  final String value;
  final String? sub;
  const EvidenceItem(this.label, this.value, this.sub);
}

class DeepDiveResult {
  final int score;
  final String verdict;
  final List<Veto> vetoes;
  final List<Reason> reasons;
  final List<RubricRow> rubric;
  final List<EvidenceItem> evidence;

  const DeepDiveResult({
    required this.score,
    required this.verdict,
    required this.vetoes,
    required this.reasons,
    required this.rubric,
    required this.evidence,
  });

  static List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
      v == null ? <T>[] : (v as List).map((e) => f(e as Map<String, dynamic>)).toList();

  factory DeepDiveResult.fromMap(Map<String, dynamic> m) => DeepDiveResult(
        score: (m['score'] ?? 0) as int,
        verdict: (m['verdict'] ?? '') as String,
        vetoes: _list(m['vetoes'], (x) => Veto(x['title'] as String, x['note'] as String)),
        reasons: _list(m['reasons'], (x) => Reason(x['tone'] as String, x['title'] as String, x['note'] as String)),
        rubric: _list(m['rubric'], (x) => RubricRow(
            x['label'] as String, (x['score'] as num).toInt(), x['state'] as String, x['evidence'] as String)),
        evidence: _list(m['evidence'], (x) => EvidenceItem(
            x['label'] as String, x['value'].toString(), x['sub'] as String?)),
      );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd radar_app && export PATH="/c/src/flutter/bin:$PATH" && flutter test test/deep_dive_test.dart` → 2 pass.

- [ ] **Step 5: Add the two fields to `SignalItem`** — `radar_app/lib/models/signal_item.dart`

Add to the fields + constructor:
```dart
  final int? qualityScore;
  final String? deepDiveStatus;
```
(constructor: `this.qualityScore, this.deepDiveStatus,`)

And in `fromMap`, add:
```dart
        qualityScore: (m['quality_score'] as num?)?.toInt(),
        deepDiveStatus: m['deep_dive_status'] as String?,
```

- [ ] **Step 6: Extend `radar_app/test/signal_item_test.dart`** — add to the existing map + asserts:

Add `'quality_score': 91, 'deep_dive_status': 'done',` to the test map, and:
```dart
    expect(it.qualityScore, 91);
    expect(it.deepDiveStatus, 'done');
```

- [ ] **Step 7: Run + commit**

Run: `cd radar_app && export PATH="/c/src/flutter/bin:$PATH" && flutter test test/deep_dive_test.dart test/signal_item_test.dart` → all pass.
```bash
cd "c:/Users/Admin/Desktop/Radar"
git add radar_app/lib/models radar_app/test/deep_dive_test.dart radar_app/test/signal_item_test.dart
git commit -m "feat(app): DeepDiveResult model + SignalItem quality fields"
```

---

### Task 2: Repository — invoke + Realtime stream + fetch

**Files:**
- Modify: `radar_app/lib/data/repository.dart`

**Interfaces:**
- Consumes: `Supabase.instance.client` (already wrapped as `_db`).
- Produces: `Future<void> invokeDeepDive(int entityId)`, `Stream<Map<String,dynamic>?> deepDiveStream(int entityId)`, `Future<Map<String,dynamic>?> fetchDeepDive(int entityId)`.

- [ ] **Step 1: Add the three methods** to `Repository` (after `setWatchState`)

```dart
  /// Trigger a deep-dive on the server (Edge Function). Fire-and-forget;
  /// the result arrives via [deepDiveStream].
  Future<void> invokeDeepDive(int entityId) async {
    await _db.functions.invoke('deep-dive', body: {'entity_id': entityId});
  }

  /// Live stream of the deep_dive_cache row for one entity (null until it exists).
  Stream<Map<String, dynamic>?> deepDiveStream(int entityId) {
    return _db
        .from('deep_dive_cache')
        .stream(primaryKey: ['entity_id'])
        .eq('entity_id', entityId)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  /// One-shot read of the cached deep-dive row (null if never run).
  Future<Map<String, dynamic>?> fetchDeepDive(int entityId) async {
    final rows = await _db.from('deep_dive_cache').select().eq('entity_id', entityId).limit(1);
    final list = rows as List;
    return list.isEmpty ? null : list.first as Map<String, dynamic>;
  }
```

- [ ] **Step 2: Verify + commit**

Run: `cd radar_app && export PATH="/c/src/flutter/bin:$PATH" && flutter analyze lib/data/repository.dart` → no errors.
```bash
cd "c:/Users/Admin/Desktop/Radar"
git add radar_app/lib/data/repository.dart
git commit -m "feat(app): repository deep-dive invoke + realtime stream"
```

---

### Task 3: The deep-dive overlay

**Files:**
- Create: `radar_app/lib/screens/deep_dive_overlay.dart`

**Interfaces:**
- Consumes: `SignalItem`, `Repository.instance` (`invokeDeepDive`/`deepDiveStream`/`fetchDeepDive`/`setWatchState`), `DeepDiveResult` + submodels, `stageMeta`/`consMeta` (feed_logic.dart), palette (theme.dart), `url_launcher`.
- Produces: `DeepDiveOverlay(item: SignalItem)` — a full-screen widget opened as a route/sheet from a row tap.

**Behavior (the StreamBuilder state machine):**
- `initState`: `fetchDeepDive(item.id)`; if it's null or its `status != 'done'`, call `invokeDeepDive(item.id)` (kick off a run). Always subscribe to `deepDiveStream(item.id)`.
- `StreamBuilder<Map?>`:
  - row null OR `status == 'running'` → **Evaluating…** (centered spinner + the item header + "This runs a fresh evaluation — a few seconds").
  - `status == 'error'` → error card with `error_note` + a **Retry** button (`invokeDeepDive` again).
  - `status == 'done'` → parse `full_result` via `DeepDiveResult.fromMap` and render the full result.

**Rendering (match `RADAR.dc.html` lines ~232–372, palette from theme.dart):**
- Sticky header: **Back** button, source mark (reuse the SVG marks from `signal_row.dart` — extract `_SourceMark` to a shared widget or duplicate the two SVG strings), a watch bookmark (`setWatchState`), and an external-link button (`launchUrl(Uri.parse(item.url!))`).
- Title block: owner/name, one-liner, tags, age/last-active.
- **Score card:** a circular ring (CustomPaint or a `Stack` with a `CircularProgressIndicator` styled) showing `result.score` / 100; ring color = green ≥68, orange ≥42, else red; a one-line `result.verdict` under it.
- **Quality × momentum quadrant:** small box, blip at `(x = result.score, y = momentumPos(item))` (import `momentumPos` from radar_painter.dart); a "In the sweet spot / Outside target / Vetoed — out" tag (sweet spot when score≥64 & momentumPos≥58 & stage∈{emerging,rising} & consistency≠suspicious & vetoes empty).
- **Veto cards** (if `result.vetoes` non-empty): red-bordered cards, "VETO — <title>" + note.
- **Why this score:** the 2–3 `result.reasons` (tone dot green/orange/red + title + note).
- **Rubric checklist:** `result.rubric` rows — label, a small bar (width = score*10%), score/10, evidence line; bar/score color by `state` (pass=green, watch=orange, fail=red).
- **Supporting signals:** `result.evidence` as a 2-col grid of label/value(/sub) cards.
- Footer: "Evaluated <computed_at>" (from the cache row's `computed_at`, format with `intl`) + a **Re-run** button (`invokeDeepDive`).

- [ ] **Step 1: Implement `deep_dive_overlay.dart`** per the behavior + rendering above, using the prototype for exact styling. Start from this skeleton (fill the `done` body per the rendering spec):

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/repository.dart';
import '../models/signal_item.dart';
import '../models/deep_dive.dart';
import '../theme.dart';
import '../widgets/radar_painter.dart'; // momentumPos

class DeepDiveOverlay extends StatefulWidget {
  final SignalItem item;
  const DeepDiveOverlay({super.key, required this.item});
  @override
  State<DeepDiveOverlay> createState() => _DeepDiveOverlayState();
}

class _DeepDiveOverlayState extends State<DeepDiveOverlay> {
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

  Color _ringColor(int s) => s >= 68 ? kGreen : (s >= 42 ? kOrange : kRed);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCanvas,
      body: SafeArea(
        child: StreamBuilder<Map<String, dynamic>?>(
          stream: Repository.instance.deepDiveStream(widget.item.id),
          builder: (context, snap) {
            final row = snap.data;
            final status = row?['status'] as String?;
            if (row == null || status == 'running') return _loading();
            if (status == 'error') return _error(row?['error_note'] as String?);
            final result = DeepDiveResult.fromMap(
                (row!['full_result'] as Map).cast<String, dynamic>());
            return _done(result, row);
          },
        ),
      ),
    );
  }

  Widget _header() { /* Back + source mark + watch + external link (launchUrl item.url) */ throw UnimplementedError(); }
  Widget _loading() { /* header + centered CircularProgressIndicator + "Evaluating…" */ throw UnimplementedError(); }
  Widget _error(String? note) { /* header + error text + Retry -> invokeDeepDive */ throw UnimplementedError(); }
  Widget _done(DeepDiveResult r, Map<String, dynamic> row) { /* full render per the rendering spec */ throw UnimplementedError(); }
}
```
(Replace each `throw UnimplementedError()` with the real widget tree per the rendering spec + prototype. Do NOT leave `UnimplementedError` in the committed file — `flutter analyze` + `flutter build web` must pass, which requires real widgets.)

- [ ] **Step 2: Verify + commit**

Run: `cd radar_app && export PATH="/c/src/flutter/bin:$PATH" && flutter analyze` → no errors. Then `flutter build web --dart-define=SUPABASE_URL=https://rdpvppcaskhoedvuhamp.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_m8aOsaAf0PoLCRKkEVK2Ww_IsORAa-p` → compiles.
```bash
cd "c:/Users/Admin/Desktop/Radar"
git add radar_app/lib/screens/deep_dive_overlay.dart
git commit -m "feat(app): deep-dive overlay (running/done/error via realtime)"
```

---

### Task 4: Wire the tap + solid Scope blips

**Files:**
- Modify: `radar_app/lib/screens/home_scaffold.dart`, `radar_app/lib/widgets/radar_painter.dart`, `radar_app/lib/screens/scope_screen.dart`

**Interfaces:**
- Consumes: `DeepDiveOverlay`, `SignalItem.qualityScore`/`deepDiveStatus`.

- [ ] **Step 1: Row tap opens the overlay** — in `home_scaffold.dart`, change `_open(SignalItem it)` from `launchUrl` to opening the overlay:

```dart
  void _open(SignalItem it) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeepDiveOverlay(item: it),
      fullscreenDialog: true,
    ));
  }
```
Add `import 'deep_dive_overlay.dart';`. (The external URL is now reachable from the overlay's link button — Task 3.)

- [ ] **Step 2: Solid blips in `radar_painter.dart`** — in `RadarPainter.paint`, per item choose fill vs hollow:

```dart
    for (final it in items) {
      final done = it.deepDiveStatus == 'done' && it.qualityScore != null;
      final qx = ((done ? it.qualityScore! : it.provisionalQuality).clamp(0, 100)) / 100.0;
      final my = momentumPos(it) / 100.0;
      final x = pad + (w - 2 * pad) * qx;
      final y = pad + (h - 2 * pad) * (1 - my);
      final color = it.consistency == 'suspicious' ? kRed : stageMeta(it.momentumStage).color;
      final paint = Paint()..color = color..strokeWidth = 1.6;
      paint.style = done ? PaintingStyle.fill : PaintingStyle.stroke; // solid once evaluated
      canvas.drawCircle(Offset(x, y), 6, paint);
    }
```

- [ ] **Step 3: Ranked list uses real quality** — in `scope_screen.dart`, the ranked-row "Quality {pq}" text uses `it.qualityScore ?? it.provisionalQuality`:

Change `'Quality ${it.provisionalQuality} · Momentum ${momentumPos(it).round()}'` to
`'Quality ${it.qualityScore ?? it.provisionalQuality} · Momentum ${momentumPos(it).round()}'`.

- [ ] **Step 4: Verify + commit**

Run: `cd radar_app && export PATH="/c/src/flutter/bin:$PATH" && flutter test && flutter analyze` → tests pass, no errors. Then `flutter build web --dart-define=SUPABASE_URL=https://rdpvppcaskhoedvuhamp.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_m8aOsaAf0PoLCRKkEVK2Ww_IsORAa-p` → compiles.
```bash
cd "c:/Users/Admin/Desktop/Radar"
git add radar_app/lib/screens/home_scaffold.dart radar_app/lib/widgets/radar_painter.dart radar_app/lib/screens/scope_screen.dart
git commit -m "feat(app): tap opens deep-dive overlay + solid scope blips when evaluated"
```

---

## Definition of done (Phase 2B)

- ☐ `SignalItem` exposes `qualityScore`/`deepDiveStatus`; `DeepDiveResult.fromMap` parses `full_result` (tested).
- ☐ Repository: `invokeDeepDive` (functions.invoke), `deepDiveStream` (Realtime), `fetchDeepDive`.
- ☐ Overlay renders running → done/error from the Realtime stream, matching the prototype (score ring, quadrant, vetoes, reasons, rubric, evidence, re-run, external link).
- ☐ Row tap opens the overlay; Scope blips go **solid** for `done` items using `qualityScore`.
- ☐ `flutter test` green; `flutter analyze` clean; `flutter build web` compiles.
- ☐ **Deferred to on-device (post-deploy):** the live invoke→Realtime→render loop (needs Phase 2A Task 6 deployed + login).

## Self-review notes

- **Spec coverage:** spec §6 view addition consumed by SignalItem (Task 1); §7 overlay state machine (Task 3) + Scope solid blips (Task 4) + Realtime (Task 2); FR-2.3 cache/re-run (Task 3 re-run + fetch-then-invoke).
- **Verification honesty:** Tasks 1–4 verify via flutter test/analyze/build web here. The live invoke + Realtime path is on-device after Phase 2A Task 6 deploy — noted in Global Constraints, not asserted here.
- **Type consistency:** `qualityScore (int?)`, `deepDiveStatus (String?)`, `DeepDiveResult`/`Veto`/`Reason`/`RubricRow`/`EvidenceItem`, and the three repository method signatures are used identically across Tasks 1–4.
