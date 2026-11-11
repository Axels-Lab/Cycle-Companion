import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class PushNotificationService {
  static const _channelId = 'tracker_updates';
  static const _channelName = 'Shared updates';
  static const _channelDescription =
      'Notifications for shared cycle and mood updates.';
  static const _channel = AndroidNotificationChannel(
    _channelId,
    _channelName,
    description: _channelDescription,
    importance: Importance.high,
  );

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
    await _createNotificationChannel(_localNotifications);

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
    final title = notification?.title ?? message.data['title'];
    final body = notification?.body ?? message.data['body'];
    if (title is! String || body is! String) return;

    await _showNotification(_localNotifications, message, title, body);
  }

  static Future<void> _createNotificationChannel(
    FlutterLocalNotificationsPlugin notifications,
  ) async {
    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_channel);
  }

  static Future<void> _showNotification(
    FlutterLocalNotificationsPlugin notifications,
    RemoteMessage message,
    String title,
    String body,
  ) {
    return notifications.show(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          icon: 'ic_stat_notification',
          color: const Color(0xFFFFC8D8),
          largeIcon: const DrawableResourceAndroidBitmap(
            'ic_stat_notification_large',
          ),
          styleInformation: BigTextStyleInformation(body),
          category: AndroidNotificationCategory.message,
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
