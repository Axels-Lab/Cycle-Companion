import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  static const _channelId = 'tracker_updates';
  static const _channelName = 'Tracker updates';
  static const _channelDescription =
      'Notifications when your tracker updates a daily entry.';

  final _messaging = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  String? _registeredToken;
  bool _disposed = false;

  Future<void> initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    final settings = await _messaging.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized &&
        settings.authorizationStatus != AuthorizationStatus.provisional) {
      return;
    }

    final initialized = await _localNotifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    if (initialized != true) {
      throw StateError('Could not initialize push notification display.');
    }
    final android = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.high,
      ),
    );

    final token = await _getRegistrationToken();
    if (token != null) await _saveToken(token);
    _tokenSubscription = _registrationTokenRefreshes.listen(
      (token) => unawaited(
        _saveToken(token).catchError((Object error) {
          debugPrint(
            'Could not save the refreshed push notification token: $error',
          );
        }),
      ),
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Could not refresh the push notification token: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
    _messageSubscription = FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
    );
  }

  Future<void> _saveToken(String token) async {
    if (_disposed) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    await _deviceReference(
      uid,
      token,
    ).set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    _registeredToken = token;
  }

  // FCM HTTP v1 targets registration tokens; FIDs are not valid message targets.
  // ignore: deprecated_member_use
  Future<String?> _getRegistrationToken() => _messaging.getToken();

  // ignore: deprecated_member_use
  Stream<String> get _registrationTokenRefreshes => _messaging.onTokenRefresh;

  DocumentReference<Map<String, dynamic>> _deviceReference(
    String uid,
    String token,
  ) {
    final deviceId = sha256.convert(utf8.encode(token)).toString();
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(deviceId);
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: notification.title ?? 'Cycle Companion',
      body: notification.body ?? 'Your tracker updated a daily entry.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_notification',
        ),
      ),
    );
  }

  Future<void> unregister() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final token = _registeredToken ?? await _getRegistrationToken();
    if (token != null) {
      await _deviceReference(uid, token).delete();
    }
    _registeredToken = null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
  }
}
