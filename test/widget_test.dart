// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:silence/core/supabase_config.dart';
import 'package:silence/main.dart';

class InMemoryGotrueAsyncStorage extends GotrueAsyncStorage {
  final Map<String, String> _storage = const {};

  const InMemoryGotrueAsyncStorage();

  @override
  Future<String?> getItem({required String key}) async {
    return _storage[key];
  }

  @override
  Future<void> setItem({required String key, required String value}) async {
    // In-memory mock storage does not need to persist for smoke test
  }

  @override
  Future<void> removeItem({required String key}) async {
    // In-memory mock storage does not need to persist for smoke test
  }
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
        // Initialize Supabase for test context with EmptyLocalStorage to avoid hanging
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
          pkceAsyncStorage: InMemoryGotrueAsyncStorage(),
          autoRefreshToken: false,
          detectSessionInUri: false,
        ),
      );
    } catch (_) {
      // Catch already initialized error
    }

    // Build our app and trigger a frame.
    await tester.pumpWidget(const SilenceApp());

    // Verify that the MaterialApp is pumped successfully.
    expect(find.byType(MaterialApp), findsOneWidget);

    // Pump the timer in splash screen to avoid pending timers on dispose
    await tester.pump(const Duration(milliseconds: 1500));
  });
}


