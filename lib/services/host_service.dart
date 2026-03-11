import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class HostService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static String? _currentCode;

  /// Generate a unique 6-digit pairing code
  static String generatePairingCode() {
    final random = Random();
    String code;
    do {
      code = (100000 + random.nextInt(900000)).toString();
    } while (_currentCode == code);
    _currentCode = code;
    return code;
  }

  /// Get current pairing code
  static String getCurrentCode() {
    return _currentCode ?? generatePairingCode();
  }

  /// Create a new session document in Firestore
  static Future<void> createSessionDocument() async {
    final code = generatePairingCode();

    try {
      await _db.collection('sessions').doc(code).set({
        'status': 'waiting',
        'connected_user_uid': '',
        'redeemed': false,
        'created_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      print('Session created for code: $code');
    } catch (e) {
      print('Failed to create session: $e');
      rethrow;
    }
  }

  /// Listen for session status changes
  static Stream<DocumentSnapshot> listenForSessionStatus() {
    final code = getCurrentCode();
    return _db.collection('sessions').doc(code).snapshots();
  }

  /// Get user info from connected_user field in session
  static Map<String, dynamic>? getUserInfoFromSession(
    DocumentSnapshot sessionDoc,
  ) {
    try {
      final data = sessionDoc.data() as Map<String, dynamic>;
      final connectedUser = data['connected_user'];

      if (connectedUser != null && connectedUser is Map<String, dynamic>) {
        return connectedUser;
      }
      return null;
    } catch (e) {
      print('Error getting user info from session: $e');
      return null;
    }
  }

  /// Extract UID from connected_user and update connected_user_uid field
  static Future<void> updateConnectedUserId(DocumentSnapshot sessionDoc) async {
    try {
      print('=== Starting updateConnectedUserId ===');
      final userInfo = getUserInfoFromSession(sessionDoc);
      print('User info from session: $userInfo');

      if (userInfo != null) {
        final uid = userInfo['uid'] ?? userInfo['id'];
        print('Extracted UID: $uid');

        if (uid != null && uid.toString().isNotEmpty) {
          print('Updating connected_user_uid field with: $uid');
          await sessionDoc.reference.update({'connected_user_uid': uid});
          print('Successfully updated connected_user_uid with: $uid');
        } else {
          print('UID is null or empty, cannot update connected_user_uid');
        }
      } else {
        print('User info is null, cannot extract UID');
      }
    } catch (e) {
      print('Error updating connected_user_uid: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  /// Get user info from connected_user_uid field
  static String? getConnectedUserId(DocumentSnapshot sessionDoc) {
    try {
      final data = sessionDoc.data() as Map<String, dynamic>;
      final connectedUserId = data['connected_user_uid'];

      if (connectedUserId != null && connectedUserId is String) {
        return connectedUserId;
      }
      return null;
    } catch (e) {
      print('Error getting connected user ID: $e');
      return null;
    }
  }

  /// Mark session as redeemed to prevent reuse
  static Future<void> markSessionAsRedeemed(DocumentSnapshot sessionDoc) async {
    try {
      print('=== Marking session as redeemed ===');
      await sessionDoc.reference.update({
        'redeemed': true,
        'redeemed_at': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      print('Session marked as redeemed successfully');
    } catch (e) {
      print('Failed to mark session as redeemed: $e');
    }
  }

  /// Check if session can be redeemed (anti-cheat)
  static Future<bool> canRedeemSession(String code) async {
    try {
      final sessionDoc = await _db.collection('sessions').doc(code).get();
      if (!sessionDoc.exists) {
        print('Session does not exist: $code');
        return false;
      }

      final data = sessionDoc.data() as Map<String, dynamic>;
      final redeemed = data['redeemed'] ?? false;
      final status = data['status'] ?? 'waiting';

      if (redeemed) {
        print('Session already redeemed: $code');
        return false;
      }

      if (status != 'waiting' &&
          status != 'connected' &&
          status != 'processing') {
        print('Session not in redeemable status: $code (status: $status)');
        return false;
      }

      return true;
    } catch (e) {
      print('Error checking session redeemability: $e');
      return false;
    }
  }

  /// Award points to user by their UID
  static Future<void> awardPointsToUserById(String userId) async {
    try {
      print('=== AWARDING POINTS TO USER: $userId ===');

      final userRef = _db.collection('users').doc(userId);

      await _db.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);

        if (userDoc.exists) {
          final currentPoints = userDoc.get('points') ?? 0;
          final newPoints = currentPoints + 1;
          transaction.update(userRef, {
            'points': newPoints,
            'last_connected': FieldValue.serverTimestamp(),
          });
          print(
              '✅ SUCCESS: Points awarded to user $userId: $newPoints (was $currentPoints)');
        } else {
          // Create user if doesn't exist
          transaction.set(userRef, {
            'points': 1,
            'uid': userId,
            'created_at': FieldValue.serverTimestamp(),
            'last_connected': FieldValue.serverTimestamp(),
          });
          print('✅ SUCCESS: Created new user $userId with 1 point');
        }
      });

      print('🎉 REWARD COMPLETE: User $userId received +1 points');
    } catch (e) {
      print('❌ FAILED: Could not award points to user $userId: $e');
      print('Stack trace: ${StackTrace.current}');
    }
  }

  /// Award points to user after processing completes
  static Future<void> awardPointsToUser(Map<String, dynamic> userInfo) async {
    try {
      final userId = userInfo['uid'] ?? userInfo['id'] ?? 'unknown';
      final userName = userInfo['name'] ?? userInfo['email'] ?? 'Unknown User';

      final userRef = _db.collection('users').doc(userId);

      await _db.runTransaction((transaction) async {
        final userDoc = await transaction.get(userRef);

        if (userDoc.exists) {
          final currentPoints = userDoc.get('points') ?? 0;
          transaction.update(userRef, {
            'points': currentPoints + 1,
            'last_connected': FieldValue.serverTimestamp(),
          });
          print('Points awarded to user $userName: ${currentPoints + 1}');
        } else {
          // Create user if doesn't exist
          transaction.set(userRef, {
            'points': 1,
            'name': userName,
            'email': userInfo['email'] ?? '',
            'created_at': FieldValue.serverTimestamp(),
            'last_connected': FieldValue.serverTimestamp(),
          });
          print('Created new user $userName with 1 point');
        }
      });
    } catch (e) {
      print('Failed to award points: $e');
    }
  }

  /// Generate new code after successful pairing
  static Future<void> generateNewCode() async {
    // Mark current session as completed
    final code = getCurrentCode();
    await _db.collection('sessions').doc(code).update({
      'status': 'completed',
      'updated_at': FieldValue.serverTimestamp(),
    });

    // Generate new code
    _currentCode = null;
    await createSessionDocument();
    print('New code generated: ${getCurrentCode()}');
  }

  /// Test Firebase connection
  static Future<void> testConnection() async {
    try {
      await _db.collection('connection_tests').add({
        'test': true,
        'timestamp': FieldValue.serverTimestamp(),
      });
      print('Firebase connection test successful');
    } catch (e) {
      print('Connection test failed: $e');
      rethrow;
    }
  }
}
