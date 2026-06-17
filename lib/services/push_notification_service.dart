import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers this device for FCM push and keeps `users.fcm_token` in sync.
///
/// v1 scope (this file):
///   • ask notification permission (iOS + Android 13+),
///   • fetch the FCM token and save it to the signed-in user's row,
///   • re-save on token refresh and on sign-in,
///   • log foreground messages + taps (in-app navigation on tap is a next step).
///
/// SENDING pushes is NOT done here — that requires a server (Supabase Edge
/// Function with a service account); the client only registers + receives.
///
/// NOTE (single-device for now): one token per user row. Multi-device (a
/// dedicated `device_tokens` table) is a planned upgrade.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Web Push (VAPID) public key. Get it from Firebase Console → Project
  /// Settings → Cloud Messaging → "Web Push certificates" → Generate key pair,
  /// then paste it here. Only used for web push (ignored on Android/iOS).
  static const String _webVapidKey = 'BDcs-ftvK7NUTeOWeRt-6VxzlW57PsjoseJTEUr-kIsKM2sC7LpRWUUB4t5jp-bMkQAqHIaFWjA2UxRtcUxqzmw';

  bool _initialized = false;
  String? _lastSavedToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Ask for permission (shows the OS prompt on iOS / Android 13+).
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('FCM permission request failed: $e');
    }

    // 2. iOS: show heads-up while the app is in the foreground too.
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      // not supported on every platform — safe to ignore
    }

    // 3. Save the current token (if a user is already signed in).
    await _syncToken();

    // 4. Re-save when FCM rotates the token.
    _messaging.onTokenRefresh.listen((token) {
      _lastSavedToken = null; // force a re-save
      _saveToken(token);
    });

    // 5. Save on sign-in (a fresh login won't have had a user at startup).
    _supabase.auth.onAuthStateChange.listen((data) {
      switch (data.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.userUpdated:
          _syncToken();
          break;
        case AuthChangeEvent.signedOut:
          _lastSavedToken = null;
          break;
        default:
          break;
      }
    });

    // 6. App opened by tapping a push (from terminated or background state).
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);
    } catch (e) {
      debugPrint('FCM getInitialMessage failed: $e');
    }
    FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);

    // 7. Foreground messages (logged for now; a local-notification banner +
    //    in-app routing is the next increment).
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM foreground: ${message.notification?.title} — '
          '${message.notification?.body} | data=${message.data}');
    });
  }

  Future<void> _syncToken() async {
    try {
      final token = kIsWeb
          ? await _messaging.getToken(vapidKey: _webVapidKey)
          : await _messaging.getToken();
      if (token != null) await _saveToken(token);
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
    }
  }

  Future<void> _saveToken(String token) async {
    final user = _supabase.auth.currentUser;
    if (user == null) return; // only persist for a signed-in user
    if (token == _lastSavedToken) return; // skip redundant writes
    try {
      await _supabase.from('device_tokens').upsert({
        'token': token,
        'user_id': user.id,
        'platform': _platform(),
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'token');
      _lastSavedToken = token;
      debugPrint('FCM token saved (device_tokens) for user ${user.id}');
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }

  String _platform() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      default:
        return 'other';
    }
  }

  /// Where a tapped notification should take the user. Wired to real in-app
  /// destinations (via message.data) in a follow-up step.
  void _handleTap(RemoteMessage message) {
    debugPrint('FCM notification tapped: data=${message.data}');
  }
}
