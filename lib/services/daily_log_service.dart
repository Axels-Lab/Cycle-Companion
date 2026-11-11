import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/daily_log.dart';
import 'daily_log_notification_summary.dart';

class DailyLogService {
  DailyLogService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const _pushApiUrl = String.fromEnvironment('PUSH_API_URL');

  CollectionReference<Map<String, dynamic>> _logs(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('dailyLogs');

  CollectionReference<Map<String, dynamic>> _partnerMoods(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('partnerMoods');

  Stream<List<DailyLog>> watchLogs(String coupleId) => _logs(coupleId)
      .orderBy('dateKey', descending: true)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(DailyLog.fromDocument).toList(growable: false),
      );

  Stream<PartnerMood?> watchPartnerMood(String coupleId, String dateKey) =>
      _partnerMoods(coupleId)
          .doc(dateKey)
          .snapshots()
          .map(
            (snapshot) => snapshot.exists
                ? PartnerMood.fromData(dateKey, snapshot.data()!)
                : null,
          );

  Future<void> savePartnerMood(
    String coupleId,
    String dateKey,
    List<String> moodTags,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before saving a mood check-in.');
    }

    final reference = _partnerMoods(coupleId).doc(dateKey);
    final selectedMoods = moodTags.toSet().toList()..sort();
    final changed = await _db.runTransaction<bool>((transaction) async {
      final snapshot = await transaction.get(reference);
      final currentMoods = List<String>.from(
        snapshot.data()?['moodTags'] as List<dynamic>? ?? const [],
      ).toSet();
      if (setEquals(currentMoods, selectedMoods.toSet())) return false;

      if (selectedMoods.isEmpty) {
        if (snapshot.exists) transaction.delete(reference);
        return snapshot.exists;
      }

      transaction.set(reference, {
        ...PartnerMood(
          dateKey: dateKey,
          moodTags: selectedMoods,
        ).toFirestore(user.uid),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    });
    if (changed) {
      await _sendPushNotification(
        user,
        coupleId,
        DailyLogNotificationSummary.forPartnerMoodChange(
          dateKey: dateKey,
          moods: selectedMoods,
        ),
        notificationType: 'partner_mood_updated',
      );
    }
  }

  Stream<List<DailyLogRevision>> watchRevisions(
    String coupleId,
    String dateKey,
  ) =>
      _logs(coupleId)
          .doc(dateKey)
          .collection('revisions')
          .orderBy('editedAt', descending: true)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map(DailyLogRevision.fromDocument)
                .toList(growable: false),
          );

  Stream<bool> watchHasRevisions(String coupleId, String dateKey) =>
      _logs(coupleId)
          .doc(dateKey)
          .collection('revisions')
          .limit(1)
          .snapshots()
          .map((snapshot) => snapshot.docs.isNotEmpty);

  Future<void> saveLog(String coupleId, DailyLog log) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before saving a cycle entry.');
    }

    final reference = _logs(coupleId).doc(log.dateKey);
    if (log.isEmpty) {
      final previousData = await _db.runTransaction<Map<String, dynamic>?>((
        transaction,
      ) async {
        final snapshot = await transaction.get(reference);
        if (!snapshot.exists) return null;
        final data = snapshot.data();
        transaction.delete(reference);
        return data;
      });
      if (previousData != null) {
        await _sendPushNotification(
          user,
          coupleId,
          DailyLogNotificationSummary.forChange(
            dateKey: log.dateKey,
            previousData: previousData,
            nextLog: null,
          ),
          notificationType: 'daily_log_updated',
        );
      }
      return;
    }

    final revisionReference = reference.collection('revisions').doc();
    final result = await _db
        .runTransaction<({bool changed, Map<String, dynamic>? previousData})>((
          transaction,
        ) async {
          final currentSnapshot = await transaction.get(reference);
          final currentData = currentSnapshot.data();
          final newData = log.toFirestore();
          final contentChanged =
              !currentSnapshot.exists ||
              !_hasSameContent(currentData!, newData, log.dateKey);

          if (currentSnapshot.exists && contentChanged) {
            final previousData = currentData!;
            transaction.set(revisionReference, {
              ..._revisionSnapshot(log.dateKey, previousData),
              'updatedAt':
                  previousData['updatedAt'] ?? FieldValue.serverTimestamp(),
              'editedAt': FieldValue.serverTimestamp(),
              'editedBy': user.uid,
            });
          }

          transaction.set(reference, {
            ...newData,
            'createdBy': currentData?['createdBy'] ?? user.uid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          return (changed: contentChanged, previousData: currentData);
        });
    if (result.changed) {
      await _sendPushNotification(
        user,
        coupleId,
        DailyLogNotificationSummary.forChange(
          dateKey: log.dateKey,
          previousData: result.previousData,
          nextLog: log,
        ),
        notificationType: 'daily_log_updated',
      );
    }
  }

  Future<void> _sendPushNotification(
    User user,
    String coupleId,
    DailyLogNotificationSummary summary, {
    required String notificationType,
  }) async {
    if (_pushApiUrl.isEmpty) {
      debugPrint(
        'Push notification not sent: configure PUSH_API_URL for this build.',
      );
      return;
    }

    try {
      final uri = Uri.parse(_pushApiUrl);
      if (uri.scheme != 'https' || uri.host.isEmpty) {
        throw const FormatException('PUSH_API_URL must be an HTTPS URL.');
      }
      final idToken = await user.getIdToken();
      if (idToken == null) {
        throw StateError(
          'Could not get a Firebase ID token for push delivery.',
        );
      }
      final response = await http
          .post(
            uri,
            headers: {
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'coupleId': coupleId,
              'title': summary.title,
              'message': summary.body,
              'type': notificationType,
            }),
          )
          .timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseBody = response.body.trim();
        final responseDetails = responseBody.isEmpty
            ? ''
            : ': ${responseBody.substring(0, responseBody.length > 300 ? 300 : responseBody.length)}';
        debugPrint(
          'Push notification request failed with HTTP '
          '${response.statusCode}$responseDetails.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Push notification request failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Map<String, Object?> _revisionSnapshot(
    String dateKey,
    Map<String, dynamic> data,
  ) {
    final log = DailyLog.fromData(dateKey, data);
    return log.toFirestore();
  }

  bool _hasSameContent(
    Map<String, dynamic> current,
    Map<String, Object?> next,
    String dateKey,
  ) {
    final currentLog = DailyLog.fromData(dateKey, current);
    final nextLog = DailyLog.fromData(dateKey, next);
    return currentLog.isPeriodDay == nextLog.isPeriodDay &&
        currentLog.selectedMoods.toSet().containsAll(nextLog.selectedMoods) &&
        nextLog.selectedMoods.toSet().containsAll(currentLog.selectedMoods) &&
        listEquals(
          currentLog.symptoms.toSet().toList()..sort(),
          nextLog.symptoms.toSet().toList()..sort(),
        ) &&
        currentLog.notes.trim() == nextLog.notes.trim() &&
        currentLog.flow == nextLog.flow &&
        currentLog.painLevel == nextLog.painLevel;
  }
}
