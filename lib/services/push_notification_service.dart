import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers this device for FCM push, shows a heads-up banner when a push
/// arrives while the app is in the FOREGROUND (Android), routes taps to the
/// in-app notifications screen, and keeps the `device_tokens` table in sync.
///
/// SENDING pushes is done server-side (Supabase Edge Function `send-push`); the
/// client only registers + receives + displays.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  /// Used to navigate on notification tap (the service is outside the widget
  /// tree). Wired into `MaterialApp(navigatorKey: ...)` in main.dart.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// High-importance channel so foreground/background notifications pop as a
  /// heads-up banner. Its id must match the manifest's default-channel meta-data.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    'Notifications',
    description: 'SILENCE alerts (requests, approvals, payments, replies)',
    importance: Importance.high,
  );

  /// Web Push (VAPID) public key — only used on web.
  static const String _webVapidKey =
      'BDcs-ftvK7NUTeOWeRt-6VxzlW57PsjoseJTEUr-kIsKM2sC7LpRWUUB4t5jp-bMkQAqHIaFWjA2UxRtcUxqzmw';

  bool _initialized = false;
  String? _lastSavedToken;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // 1. Ask for permission (OS prompt on iOS / Android 13+).
    try {
      await _messaging.requestPermission(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('FCM permission request failed: $e');
    }

    // 2. Local notifications (for the foreground heads-up banner) + Android channel.
    await _initLocalNotifications();

    // 3. iOS: also present a banner while in the foreground.
    try {
      await _messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}

    // 4. Token: save now (if signed in), on refresh, and on sign-in.
    await _syncToken();
    _messaging.onTokenRefresh.listen((token) {
      _lastSavedToken = null;
      _saveToken(token);
    });
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

    // 5. App opened by tapping a push (terminated / background).
    try {
      final initial = await _messaging.getInitialMessage();
      if (initial != null) _routeFromData(initial.data);
    } catch (e) {
      debugPrint('FCM getInitialMessage failed: $e');
    }
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _routeFromData(m.data));

    // 6. Foreground message → show a heads-up banner (Android; iOS handled above).
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings =
        InitializationSettings(android: androidInit, iOS: iosInit);
    try {
      await _localNotifications.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (resp) {
          final payload = resp.payload;
          if (payload == null || payload.isEmpty) {
            _routeFromData(const {});
            return;
          }
          try {
            _routeFromData(
                Map<String, dynamic>.from(jsonDecode(payload) as Map));
          } catch (_) {
            _routeFromData(const {});
          }
        },
      );
      // Create the Android channel + request Android 13 notif permission.
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_channel);
      await android?.requestNotificationsPermission();
    } catch (e) {
      debugPrint('Local notifications init failed: $e');
    }
  }

  void _showForegroundNotification(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return; // data-only messages: nothing to show
    // iOS already shows the banner via setForegroundNotificationPresentationOptions.
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.android) return;
    if (kIsWeb) return; // web foreground shows in-tab via the browser/SW

    _localNotifications.show(
      id: message.hashCode,
      title: n.title ?? 'SILENCE',
      body: n.body ?? '',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  /// All taps (FCM tap, cold-start, local-notification tap) funnel here.
  /// v1: open the in-app notifications screen (where the alert lives).
  void _routeFromData(Map<String, dynamic> data) {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    try {
      nav.pushNamed('/member/notifications');
    } catch (e) {
      debugPrint('FCM tap navigation failed: $e');
    }
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
    if (user == null) return;
    if (token == _lastSavedToken) return;
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
}
