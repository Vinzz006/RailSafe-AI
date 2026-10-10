import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/constants/ble_constants.dart';
import '../models/app_alert.dart';
import '../models/test_record.dart';
import '../models/user_profile.dart';

class LocalStorageService {
  static LocalStorageService? _instance;
  final SharedPreferences _prefs;

  LocalStorageService._(this._prefs);

  static Future<LocalStorageService> getInstance() async {
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = LocalStorageService._(prefs);
    }
    return _instance!;
  }

  // --- Demo Mode Setting ---
  bool get isDemoModeEnabled => _prefs.getBool(AppConstants.keyDemoMode) ?? false;
  Future<void> setDemoMode(bool value) async {
    await _prefs.setBool(AppConstants.keyDemoMode, value);
  }

  // --- Demo Scenario ('nominal' or 'anomaly') ---
  String get demoScenario => _prefs.getString(AppConstants.keyDemoScenario) ?? 'nominal';
  Future<void> setDemoScenario(String scenario) async {
    await _prefs.setString(AppConstants.keyDemoScenario, scenario);
  }

  // --- Custom BLE UUIDs ---
  String get serviceUuid =>
      _prefs.getString(AppConstants.keyServiceUuid) ?? BleConstants.defaultServiceUuid;
  Future<void> setServiceUuid(String uuid) async {
    await _prefs.setString(AppConstants.keyServiceUuid, uuid);
  }

  String get dataCharUuid =>
      _prefs.getString(AppConstants.keyDataCharUuid) ?? BleConstants.defaultDataCharacteristicUuid;
  Future<void> setDataCharUuid(String uuid) async {
    await _prefs.setString(AppConstants.keyDataCharUuid, uuid);
  }

  String get cmdCharUuid =>
      _prefs.getString(AppConstants.keyCmdCharUuid) ?? BleConstants.defaultCommandCharacteristicUuid;
  Future<void> setCmdCharUuid(String uuid) async {
    await _prefs.setString(AppConstants.keyCmdCharUuid, uuid);
  }

  int get staleTimeoutSeconds => _prefs.getInt(AppConstants.keyStaleTimeoutSec) ?? 4;
  Future<void> setStaleTimeoutSeconds(int seconds) async {
    await _prefs.setInt(AppConstants.keyStaleTimeoutSec, seconds);
  }

  // --- Python Backend Server URL ---
  String getBackendUrl() =>
      _prefs.getString(AppConstants.keyBackendUrl) ?? AppConstants.defaultBackendUrl;
  Future<void> setBackendUrl(String url) async {
    await _prefs.setString(AppConstants.keyBackendUrl, url.trim());
  }

  // --- Offline Tests Persistence ---
  List<TestRecord> getSavedTests() {
    final raw = _prefs.getString(AppConstants.keySavedTests);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => TestRecord.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveTest(TestRecord record) async {
    final current = getSavedTests();
    // Prevent duplicate entries by testId
    final index = current.indexWhere((t) => t.testId == record.testId);
    if (index >= 0) {
      current[index] = record;
    } else {
      current.insert(0, record);
    }
    final encoded = jsonEncode(current.map((t) => t.toJson()).toList());
    await _prefs.setString(AppConstants.keySavedTests, encoded);
  }

  Future<void> updateTestSyncStatus(String testId, bool synced) async {
    final current = getSavedTests();
    final index = current.indexWhere((t) => t.testId == testId);
    if (index >= 0) {
      current[index] = current[index].copyWith(syncedToFirestore: synced);
      final encoded = jsonEncode(current.map((t) => t.toJson()).toList());
      await _prefs.setString(AppConstants.keySavedTests, encoded);
    }
  }

  Future<void> deleteTest(String testId) async {
    final current = getSavedTests();
    current.removeWhere((t) => t.testId == testId);
    final encoded = jsonEncode(current.map((t) => t.toJson()).toList());
    await _prefs.setString(AppConstants.keySavedTests, encoded);
  }

  // --- Offline Alerts Persistence ---
  List<AppAlert> getSavedAlerts() {
    final raw = _prefs.getString(AppConstants.keySavedAlerts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((item) => AppAlert.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (_) {
      return [];
    }
  }

  Future<void> saveAlert(AppAlert alert) async {
    final current = getSavedAlerts();
    current.insert(0, alert);
    // Keep maximum 100 recent alerts
    if (current.length > 100) {
      current.removeRange(100, current.length);
    }
    final encoded = jsonEncode(current.map((a) => a.toJson()).toList());
    await _prefs.setString(AppConstants.keySavedAlerts, encoded);
  }

  Future<void> clearAlerts() async {
    await _prefs.remove(AppConstants.keySavedAlerts);
  }

  // --- User Profile Caching ---
  UserProfile? getCachedUser() {
    final raw = _prefs.getString(AppConstants.keyCachedUser);
    if (raw == null || raw.isEmpty) return null;
    try {
      return UserProfile.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> cacheUser(UserProfile? user) async {
    if (user == null) {
      await _prefs.remove(AppConstants.keyCachedUser);
    } else {
      await _prefs.setString(AppConstants.keyCachedUser, jsonEncode(user.toJson()));
    }
  }
}
