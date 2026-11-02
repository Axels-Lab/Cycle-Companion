import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/daily_log.dart';

class DailyLogService {
  DailyLogService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> _logs(String coupleId) =>
      _db.collection('couples').doc(coupleId).collection('dailyLogs');

  Stream<List<DailyLog>> watchLogs(String coupleId) => _logs(coupleId)
      .orderBy('dateKey', descending: true)
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.docs.map(DailyLog.fromDocument).toList(growable: false),
      );

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
      await reference.delete();
      return;
    }

    final revisionReference = reference.collection('revisions').doc();
    await _db.runTransaction<void>((transaction) async {
      final currentSnapshot = await transaction.get(reference);
      final currentData = currentSnapshot.data();
      final newData = log.toFirestore();

      if (currentSnapshot.exists &&
          !_hasSameContent(currentData!, newData, log.dateKey)) {
        transaction.set(revisionReference, {
          ..._revisionSnapshot(log.dateKey, currentData),
          'updatedAt': currentData['updatedAt'] ?? FieldValue.serverTimestamp(),
          'editedAt': FieldValue.serverTimestamp(),
          'editedBy': user.uid,
        });
      }

      transaction.set(reference, {
        ...newData,
        'createdBy': currentData?['createdBy'] ?? user.uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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
