import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/signal_item.dart';

class Repository {
  Repository._();
  static final Repository instance = Repository._();
  SupabaseClient get _db => Supabase.instance.client;

  Future<void> signIn(String email, String password) =>
      _db.auth.signInWithPassword(email: email, password: password);

  /// Returns true if a session was created (signed in immediately),
  /// false if email confirmation is required before sign-in. Throws on failure.
  Future<bool> signUp(String email, String password) async {
    final res = await _db.auth.signUp(email: email, password: password);
    return res.session != null;
  }

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
}
