import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../screens/offers_screen.dart';
import '../utils/ch_routes.dart';
import 'api_client.dart';

/// Background isolate entrypoint. **Must be a top-level function** and marked
/// with `@pragma('vm:entry-point')` so the Dart VM keeps it when tree-shaking
/// in release builds.
///
/// Runs in a headless isolate — no widget tree, no Providers. Keep it thin.
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode) {
    debugPrint('[Push] background message id=${message.messageId} data=${message.data}');
  }
  // Nothing to do in the background isolate — FCM system-tray notification
  // already fired from the notification payload. Tap routing happens back in
  // the main isolate via `onMessageOpenedApp` / `getInitialMessage`.
}

/// Owns the whole client-side push pipeline:
///   1. Ask for notification permission (iOS + Android 13+).
///   2. Fetch the FCM token and register it with the backend (`POST /devices`).
///   3. Listen for token refreshes and re-register.
///   4. Handle foreground messages → render via flutter_local_notifications.
///   5. Handle tap-to-open (background + terminated) → route the app.
///
/// Wired from `main.dart` before `runApp` (init) and from AuthController after
/// a successful sign-in (`registerCurrentToken`), and from logout to drop the
/// token server-side (`unregisterCurrentToken`).
class PushNotificationsService {
  PushNotificationsService(this._api);

  final ApiClient _api;

  /// Root NavigatorState — set by `main.dart`. Used by the tap handler so we
  /// can push routes from outside the widget tree.
  static final GlobalKey<NavigatorState> rootNavigatorKey =
      GlobalKey<NavigatorState>(debugLabel: 'root-navigator');

  static const String _androidChannelId   = 'crunchy_hot_default';
  static const String _androidChannelName = 'إشعارات كرانشي هوت';
  static const String _androidChannelDesc = 'العروض الجديدة وتحديثات الطلب';

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local = FlutterLocalNotificationsPlugin();

  String? _lastRegisteredToken;

  /// One-shot setup. Call once from `main` after `Firebase.initializeApp`.
  Future<void> init() async {
    // ── Background handler must be registered before any await work ──
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

    // ── Local notifications channel (Android 8+) ──
    await _local.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS:     const DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (resp) => _routeFromPayload(resp.payload),
    );

    // Create the default Android channel so notifications posted via
    // flutter_local_notifications land with the right sound/importance and
    // FCM's own auto-created channel doesn't override our labels.
    if (!kIsWeb && Platform.isAndroid) {
      const channel = AndroidNotificationChannel(
        _androidChannelId,
        _androidChannelName,
        description: _androidChannelDesc,
        importance:  Importance.high,
      );
      await _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    }

    // ── Permission ──
    // iOS + Android 13+: pops the OS dialog. On older Android, this is a no-op
    // that returns "authorized".
    await _fcm.requestPermission(alert: true, badge: true, sound: true);

    // iOS: without setForegroundNotificationPresentationOptions, foreground
    // notifications render silently. Force alert/sound so the local-plugin
    // fallback stays consistent.
    if (!kIsWeb && Platform.isIOS) {
      await _fcm.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );
    }

    // ── Foreground stream: FCM doesn't render the notification while the app
    //    is up; we do it ourselves via flutter_local_notifications so the UX
    //    matches background delivery.
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // ── Tap-to-open when the app is backgrounded (not killed) ──
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _route(m.data));

    // ── Tap-to-open when the app was terminated ──
    final initial = await _fcm.getInitialMessage();
    if (initial != null) {
      // Delay until first frame so the NavigatorKey is attached.
      WidgetsBinding.instance.addPostFrameCallback((_) => _route(initial.data));
    }

    // ── Refresh handler: FCM can rotate tokens; re-POST when it happens ──
    _fcm.onTokenRefresh.listen(_upsertToken);
  }

  /// Fetch the current FCM token and POST it to `/devices`. Safe to call
  /// multiple times — the backend does `updateOrInsert` on (user_id, token).
  ///
  /// Called from AuthController after sign-in and after bootstrap so the
  /// server always has a fresh token for the currently signed-in user.
  Future<void> registerCurrentToken() async {
    try {
      // On web, FCM needs a VAPID key registered in Firebase Console → Cloud
      // Messaging → Web configuration. Wire the value here when web push is
      // wanted; without it, getToken() throws on web only.
      final token = kIsWeb
          ? await _fcm.getToken(
              vapidKey: const String.fromEnvironment('FCM_VAPID_KEY'),
            )
          : await _fcm.getToken();
      if (token == null || token.isEmpty) return;
      await _upsertToken(token);
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] registerCurrentToken failed: $e');
    }
  }

  /// Delete the currently-registered token from the backend (call on logout).
  /// Best-effort — swallows failures because logout should always complete.
  Future<void> unregisterCurrentToken() async {
    final token = _lastRegisteredToken;
    if (token == null || token.isEmpty) return;
    try {
      await _api.delete('/devices/$token');
    } catch (_) {/* best effort */}
    _lastRegisteredToken = null;
  }

  // ────────────────────────────────────────────────────────────────
  //  Internal helpers
  // ────────────────────────────────────────────────────────────────

  Future<void> _upsertToken(String token) async {
    if (token == _lastRegisteredToken) return;
    try {
      await _api.post('/devices', data: {
        'token':    token,
        'platform': _platform,
      });
      _lastRegisteredToken = token;
      if (kDebugMode) {
        debugPrint('[Push] token registered (${token.substring(0, 12)}…)');
      }
    } on ApiUnauthorizedException {
      // Not signed in yet — try again after the next sign-in via
      // registerCurrentToken().
    } catch (e) {
      if (kDebugMode) debugPrint('[Push] token register failed: $e');
    }
  }

  String get _platform {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  Future<void> _onForegroundMessage(RemoteMessage m) async {
    if (kDebugMode) {
      debugPrint('[Push] foreground id=${m.messageId} data=${m.data}');
    }
    final notif = m.notification;
    if (notif == null) return;

    // Encode the data map as a JSON payload string — the local plugin only
    // hands back a String on tap, and we need `screen`/`offer_id` back.
    final payload = m.data.isEmpty ? null : jsonEncode(m.data);

    await _local.show(
      m.hashCode,
      notif.title,
      notif.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannelId,
          _androidChannelName,
          channelDescription: _androidChannelDesc,
          importance: Importance.high,
          priority:   Priority.high,
          icon:      '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  void _routeFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _route(data.map((k, v) => MapEntry(k, v.toString())));
    } catch (_) {/* ignore malformed payload */}
  }

  void _route(Map<String, dynamic> data) {
    final screen = data['screen']?.toString();
    if (screen == null) return;

    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;

    switch (screen) {
      case 'offers':
        nav.push(ChRoutes.slideUpFade((_) => const OffersScreen()));
      // Add more targets here (product/{slug}, order/{number}) as marketing
      // teams introduce them. Unknown screens fall through and just open the
      // app to its last state — a good default.
    }
  }
}
