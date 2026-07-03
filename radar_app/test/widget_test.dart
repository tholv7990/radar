// Placeholder smoke test. RadarApp initializes Supabase in main() and reads
// Supabase.instance.client.auth in build(), so pumping it directly here would
// require a live Supabase instance. Real widget tests land with Tasks 4/6
// once LoginScreen/HomeScaffold replace the inline placeholders.
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('placeholder', () {
    expect(1 + 1, 2);
  });
}
