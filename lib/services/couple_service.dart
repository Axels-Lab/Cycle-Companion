import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CoupleMembership {
  const CoupleMembership({required this.coupleId, required this.role});

  final String coupleId;
  final String role;

  bool get isTracker => role == 'tracker';
}

class CoupleInvite {
  const CoupleInvite({required this.coupleId, required this.code});

  final String coupleId;
  final String code;
}

class CoupleDetails {
  const CoupleDetails({
    required this.members,
    required this.roles,
    required this.displayNames,
    required this.inviteCode,
    required this.createdAt,
    required this.pairedAt,
  });

  final List<String> members;
  final Map<String, String> roles;
  final Map<String, String> displayNames;
  final String? inviteCode;
  final DateTime? createdAt;
  final DateTime? pairedAt;

  bool get isPaired => members.length == 2;

  String? partnerOf(String uid) {
    for (final member in members) {
      if (member != uid) return member;
    }
    return null;
  }

  factory CoupleDetails.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) throw StateError('The pairing could not be found.');

    final rolesData = Map<String, dynamic>.from(
      data['roles'] as Map? ?? const {},
    );
    final profilesData = Map<String, dynamic>.from(
      data['memberProfiles'] as Map? ?? const {},
    );

    return CoupleDetails(
      members: List<String>.from(data['members'] as List<dynamic>),
      roles: rolesData.map((uid, role) => MapEntry(uid, role as String)),
      displayNames: profilesData.map((uid, profile) {
        final profileData = Map<String, dynamic>.from(profile as Map);
        final name = profileData['displayName'];
        return MapEntry(uid, name is String ? name : '');
      }),
      inviteCode: data['inviteCode'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      pairedAt: (data['pairedAt'] as Timestamp?)?.toDate(),
    );
  }
}

class CoupleService {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<CoupleMembership?> getMembership(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final data = doc.data();
    final coupleId = data?['coupleId'] as String?;
    if (coupleId == null) return null;

    final role = data?['role'] as String?;
    if (role != 'tracker' && role != 'partner') {
      throw StateError('Your account has an invalid pairing role.');
    }
    return CoupleMembership(coupleId: coupleId, role: role!);
  }

  Stream<CoupleDetails> watchCoupleDetails(String coupleId) => _db
      .collection('couples')
      .doc(coupleId)
      .snapshots()
      .map(CoupleDetails.fromDocument);

  Future<void> updateDisplayName({
    required String coupleId,
    required String displayName,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before updating your profile.');

    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty || normalizedName.length > 40) {
      throw ArgumentError('Your name must be between 1 and 40 characters.');
    }

    final coupleRef = _db.collection('couples').doc(coupleId);
    await _db.runTransaction<void>((transaction) async {
      final coupleSnapshot = await transaction.get(coupleRef);
      if (!coupleSnapshot.exists) {
        throw StateError('The pairing could not be found.');
      }

      final coupleData = coupleSnapshot.data()!;
      final members = List<String>.from(coupleData['members'] as List<dynamic>);
      if (!members.contains(uid)) {
        throw StateError('You are no longer part of this pairing.');
      }

      final profiles = Map<String, dynamic>.from(
        coupleData['memberProfiles'] as Map? ?? const {},
      );
      final oldProfile = Map<String, dynamic>.from(
        profiles[uid] as Map? ?? const {},
      );
      profiles[uid] = {...oldProfile, 'displayName': normalizedName};
      transaction.update(coupleRef, {'memberProfiles': profiles});
    });
  }

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no confusing 0/O/1/I
    final rnd = Random.secure();
    return List.generate(8, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<CoupleInvite> createCouple({
    required String role,
    required String displayName,
  }) async {
    if (role != 'tracker' && role != 'partner') {
      throw ArgumentError.value(role, 'role', 'Must be tracker or partner.');
    }
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before creating a couple.');
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty || normalizedName.length > 40) {
      throw ArgumentError('Your name must be between 1 and 40 characters.');
    }

    final coupleRef = _db.collection('couples').doc();
    final userRef = _db.collection('users').doc(uid);
    final codeCollection = _db.collection('inviteCodes');

    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _generateCode();
      final inviteRef = codeCollection.doc(code);
      final created = await _db.runTransaction<bool>((transaction) async {
        final inviteSnapshot = await transaction.get(inviteRef);
        final userSnapshot = await transaction.get(userRef);
        if (inviteSnapshot.exists) return false;
        if (userSnapshot.data()?['coupleId'] != null) {
          throw StateError('This account is already paired.');
        }

        transaction.set(coupleRef, {
          'members': [uid],
          'roles': {uid: role},
          'memberProfiles': {
            uid: {'displayName': normalizedName},
          },
          'inviteCode': code,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(userRef, {'coupleId': coupleRef.id, 'role': role});
        transaction.set(inviteRef, {
          'coupleId': coupleRef.id,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (created) return CoupleInvite(coupleId: coupleRef.id, code: code);
    }
    throw StateError('Could not create an invite code. Please try again.');
  }

  Future<void> joinCouple({
    required String code,
    required String displayName,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Sign in before joining a couple.');
    final normalizedName = displayName.trim();
    if (normalizedName.isEmpty || normalizedName.length > 40) {
      throw ArgumentError('Your name must be between 1 and 40 characters.');
    }

    final normalizedCode = code.toUpperCase().trim();
    if (!RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(normalizedCode)) {
      throw ArgumentError('Enter a valid eight-character invite code.');
    }

    final inviteRef = _db.collection('inviteCodes').doc(normalizedCode);
    final userRef = _db.collection('users').doc(uid);
    await _db.runTransaction<void>((transaction) async {
      final inviteSnapshot = await transaction.get(inviteRef);
      if (!inviteSnapshot.exists) throw StateError('Invalid or expired code.');

      final coupleId = inviteSnapshot.data()?['coupleId'] as String?;
      if (coupleId == null) throw StateError('This invite code is invalid.');
      final coupleRef = _db.collection('couples').doc(coupleId);
      final coupleSnapshot = await transaction.get(coupleRef);
      final userSnapshot = await transaction.get(userRef);
      if (!coupleSnapshot.exists) {
        throw StateError('This invite code is no longer available.');
      }
      if (userSnapshot.data()?['coupleId'] != null) {
        throw StateError('This account is already paired.');
      }

      final couple = coupleSnapshot.data()!;
      final members = List<String>.from(couple['members'] as List<dynamic>);
      final roles = Map<String, dynamic>.from(couple['roles'] as Map);
      if (members.length != 1 || roles.length != 1) {
        throw StateError('This couple is already full.');
      }

      final creatorRole = roles[members.single];
      if (creatorRole != 'tracker' && creatorRole != 'partner') {
        throw StateError('The invite has an invalid pairing role.');
      }
      final role = creatorRole == 'tracker' ? 'partner' : 'tracker';
      final updatedMembers = [...members, uid];
      final updatedRoles = {...roles, uid: role};
      final updatedProfiles = Map<String, dynamic>.from(
        couple['memberProfiles'] as Map? ?? const {},
      );
      updatedProfiles[uid] = {'displayName': normalizedName};

      transaction.update(coupleRef, {
        'members': updatedMembers,
        'roles': updatedRoles,
        'memberProfiles': updatedProfiles,
        'inviteCode': null,
        'pairedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(userRef, {'coupleId': coupleId, 'role': role});
      transaction.delete(inviteRef);
    });
  }
}
