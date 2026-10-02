import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'social_service.dart';

const _firebaseApiKey = String.fromEnvironment('FIREBASE_API_KEY');
const _firebaseAppId = String.fromEnvironment('FIREBASE_APP_ID');
const _firebaseMessagingSenderId = String.fromEnvironment(
  'FIREBASE_MESSAGING_SENDER_ID',
);
const _firebaseProjectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
const _firebaseAuthDomain = String.fromEnvironment('FIREBASE_AUTH_DOMAIN');
const _firebaseStorageBucket = String.fromEnvironment(
  'FIREBASE_STORAGE_BUCKET',
);
const _firebaseWebVapidKey = String.fromEnvironment('FIREBASE_WEB_VAPID_KEY');

FirebaseOptions get _firebaseOptions => FirebaseOptions(
  apiKey: _firebaseApiKey,
  appId: _firebaseAppId,
  messagingSenderId: _firebaseMessagingSenderId,
  projectId: _firebaseProjectId,
  authDomain: _firebaseAuthDomain.isEmpty ? null : _firebaseAuthDomain,
  storageBucket: _firebaseStorageBucket.isEmpty ? null : _firebaseStorageBucket,
);

bool get _firebaseConfigured {
  if (!kIsWeb) {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
  return _firebaseApiKey.isNotEmpty &&
      _firebaseAppId.isNotEmpty &&
      _firebaseMessagingSenderId.isNotEmpty &&
      _firebaseProjectId.isNotEmpty;
}

Future<void> _initializeFirebaseApp() => kIsWeb
    ? Firebase.initializeApp(options: _firebaseOptions)
    : Firebase.initializeApp();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (!_firebaseConfigured) return;
  if (Firebase.apps.isEmpty) {
    await _initializeFirebaseApp();
  }
}

class PushNotificationService {
  PushNotificationService._();
  static final instance = PushNotificationService._();

  final _events = StreamController<void>.broadcast();
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  String? _authToken;
  String? _registrationToken;
  bool _initialized = false;

  Stream<void> get events => _events.stream;
  bool get isConfigured => _firebaseConfigured;

  static Future<void> initializeFirebase() async {
    if (!_firebaseConfigured || Firebase.apps.isNotEmpty) return;
    try {
      await _initializeFirebaseApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (_) {
      // The app remains usable when a platform-specific Firebase setup is absent.
    }
  }

  Future<void> start(String authToken) async {
    if (!_firebaseConfigured || _authToken == authToken && _initialized) return;
    _authToken = authToken;
    try {
      await initializeFirebase();
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      final token = await messaging.getToken(
        vapidKey: kIsWeb && _firebaseWebVapidKey.isNotEmpty
            ? _firebaseWebVapidKey
            : null,
      );
      if (token != null) await _register(authToken, token);
      await _tokenRefreshSubscription?.cancel();
      _tokenRefreshSubscription = messaging.onTokenRefresh.listen(
        (token) => _register(authToken, token),
      );
      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (_) => _events.add(null),
      );
      _initialized = true;
    } catch (_) {
      // Stored notifications and WebSocket realtime continue to work when
      // Firebase has not been configured for this build or permission is denied.
    }
  }

  Future<void> stop(String? authToken) async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundSubscription = null;
    final registrationToken = _registrationToken;
    if (authToken != null && registrationToken != null) {
      try {
        await SocialService.unregisterPushDevice(
          authToken,
          registrationToken,
          _platform,
        );
      } catch (_) {
        // Token reassignment on the next login prevents cross-account delivery.
      }
    }
    _authToken = null;
    _registrationToken = null;
    _initialized = false;
  }

  Future<void> _register(String authToken, String registrationToken) async {
    await SocialService.registerPushDevice(
      authToken,
      registrationToken,
      _platform,
    );
    _registrationToken = registrationToken;
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      _ => 'web',
    };
  }
}
