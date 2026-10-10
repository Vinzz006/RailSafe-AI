import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/app_alert.dart';
import '../models/test_record.dart';
import '../models/user_profile.dart';
import 'local_storage_service.dart';

class FirestoreSyncResult {
  final bool success;
  final String message;
  final int syncedCount;

  const FirestoreSyncResult({
    required this.success,
    required this.message,
    this.syncedCount = 0,
  });
}

class FirestoreService {
  final LocalStorageService _storage;
  bool _isFirebaseInitialized = false;
  FirebaseFirestore? _firestore;

  FirestoreService(this._storage);

  bool get isFirestoreAvailable => _isFirebaseInitialized && _firestore != null;

  void initialize() {
    try {
      if (Firebase.apps.isNotEmpty) {
        _isFirebaseInitialized = true;
        _firestore = FirebaseFirestore.instance;
        _firestore?.settings = const Settings(
          persistenceEnabled: true,
          cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
        );
      } else {
        _isFirebaseInitialized = false;
        _firestore = null;
      }
    } catch (_) {
      _isFirebaseInitialized = false;
      _firestore = null;
    }
  }

  /// Syncs or creates the user profile document in `users/{userId}`
  Future<void> syncUserProfile(UserProfile profile) async {
    if (!isFirestoreAvailable) return;
    try {
      final docRef = _firestore!.collection('users').doc(profile.uid);
      await docRef.set({
        'displayName': profile.displayName,
        'email': profile.email,
        'role': profile.role,
        'stationCode': profile.stationCode,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Offline fallback: handled locally
    }
  }

  /// Saves a test record to `users/{userId}/tests/{testId}`
  Future<bool> saveTestRecord(TestRecord record) async {
    // 1. Always persist locally first so test is NEVER lost
    await _storage.saveTest(record);

    if (!isFirestoreAvailable) {
      return false; // Stored locally, cloud sync unconfigured
    }

    try {
      final docRef = _firestore!
          .collection('users')
          .doc(record.userId)
          .collection('tests')
          .doc(record.testId);

      await docRef.set({
        'testId': record.testId,
        'deviceId': record.deviceId,
        'mode': record.mode,
        'startedAt': record.startedAt.toUtc().toIso8601String(),
        'completedAt': record.completedAt.toUtc().toIso8601String(),
        'completionStatus': record.completionStatus,
        'sensorReadings': record.sensorReadings,
        'screeningAssistanceStatus': record.screeningAssistanceStatus,
        'screeningAssistanceDetails': record.screeningAssistanceDetails,
        'metrics': record.metrics,
        'createdAt': FieldValue.serverTimestamp(),
        if (record.notes != null) 'notes': record.notes,
      }, SetOptions(merge: true));

      // Mark local copy as synced
      await _storage.updateTestSyncStatus(record.testId, true);
      return true;
    } catch (e) {
      // Firestore write failed or offline; local copy remains for future retry
      return false;
    }
  }

  /// Syncs all pending unsynced tests in the local queue
  Future<FirestoreSyncResult> syncPendingTests(String userId) async {
    if (!isFirestoreAvailable) {
      return const FirestoreSyncResult(
        success: false,
        message: "Cloud sync not configured. Records preserved in local storage.",
      );
    }

    final localTests = _storage.getSavedTests();
    final pending = localTests.where((t) => !t.syncedToFirestore && t.userId == userId).toList();

    if (pending.isEmpty) {
      return const FirestoreSyncResult(
        success: true,
        message: "All test records are up to date.",
        syncedCount: 0,
      );
    }

    int synced = 0;
    for (final test in pending) {
      try {
        final docRef = _firestore!
            .collection('users')
            .doc(userId)
            .collection('tests')
            .doc(test.testId);

        await docRef.set({
          'testId': test.testId,
          'deviceId': test.deviceId,
          'mode': test.mode,
          'startedAt': test.startedAt.toUtc().toIso8601String(),
          'completedAt': test.completedAt.toUtc().toIso8601String(),
          'completionStatus': test.completionStatus,
          'sensorReadings': test.sensorReadings,
          'screeningAssistanceStatus': test.screeningAssistanceStatus,
          'screeningAssistanceDetails': test.screeningAssistanceDetails,
          'metrics': test.metrics,
          'createdAt': FieldValue.serverTimestamp(),
          if (test.notes != null) 'notes': test.notes,
        }, SetOptions(merge: true));

        await _storage.updateTestSyncStatus(test.testId, true);
        synced++;
      } catch (_) {
        // Individual item failed; stop or continue
      }
    }

    return FirestoreSyncResult(
      success: synced > 0,
      message: synced == pending.length
          ? "Successfully synced $synced test(s) to Cloud Firestore."
          : "Synced $synced of ${pending.length} test(s). Retrying remaining later.",
      syncedCount: synced,
    );
  }

  /// Saves an alert event to `users/{userId}/alerts/{alertId}`
  Future<void> saveAlert(String userId, AppAlert alert) async {
    await _storage.saveAlert(alert);

    if (!isFirestoreAvailable) return;

    try {
      final docRef = _firestore!
          .collection('users')
          .doc(userId)
          .collection('alerts')
          .doc(alert.id);

      await docRef.set({
        'id': alert.id,
        'type': alert.type,
        'title': alert.title,
        'message': alert.message,
        'severity': alert.severity.name,
        'timestamp': alert.timestamp.toUtc().toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
        if (alert.relatedTestId != null) 'relatedTestId': alert.relatedTestId,
      }, SetOptions(merge: true));
    } catch (_) {
      // Persisted in local storage safely
    }
  }
}
