import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/app_alert.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';

class AlertsProvider extends ChangeNotifier {
  final LocalStorageService _storage;
  final FirestoreService _firestore;
  List<AppAlert> _alerts = [];
  final Uuid _uuid = const Uuid();

  AlertsProvider(this._storage, this._firestore) {
    _loadAlerts();
  }

  List<AppAlert> get alerts => _alerts;

  void _loadAlerts() {
    _alerts = _storage.getSavedAlerts();
    notifyListeners();
  }

  Future<void> addAlert({
    required String type,
    required String title,
    required String message,
    required AlertSeverity severity,
    String? userId,
    String? relatedTestId,
  }) async {
    final alert = AppAlert(
      id: "ALERT-${_uuid.v4().substring(0, 8).toUpperCase()}",
      type: type,
      title: title,
      message: message,
      severity: severity,
      timestamp: DateTime.now(),
      relatedTestId: relatedTestId,
    );

    _alerts.insert(0, alert);
    notifyListeners();

    await _storage.saveAlert(alert);
    if (userId != null) {
      await _firestore.saveAlert(userId, alert);
    }
  }

  Future<void> clearAlerts() async {
    _alerts.clear();
    await _storage.clearAlerts();
    notifyListeners();
  }
}
