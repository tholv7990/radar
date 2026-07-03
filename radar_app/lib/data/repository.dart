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
