import 'package:flutter/material.dart';
import '../services/ble_service.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../services/simulation_service.dart';

class SettingsProvider extends ChangeNotifier {
  final LocalStorageService _storage;
  final BleService _bleService;
  final SimulationService _simulationService;
  final FirestoreService _firestoreService;

  late bool _isDemoModeEnabled;
  late String _demoScenario;
  late String _serviceUuid;
  late String _dataCharUuid;
  late String _cmdCharUuid;
  late int _staleTimeoutSeconds;

  SettingsProvider(
    this._storage,
    this._bleService,
    this._simulationService,
    this._firestoreService,
  ) {
    _isDemoModeEnabled = _storage.isDemoModeEnabled;
    _demoScenario = _storage.demoScenario;
    _serviceUuid = _storage.serviceUuid;
    _dataCharUuid = _storage.dataCharUuid;
    _cmdCharUuid = _storage.cmdCharUuid;
    _staleTimeoutSeconds = _storage.staleTimeoutSeconds;

    // Apply saved UUIDs to BleService
    _bleService.configureUuids(
      serviceUuid: _serviceUuid,
      dataCharUuid: _dataCharUuid,
      cmdCharUuid: _cmdCharUuid,
    );
    _simulationService.setScenario(_demoScenario);
  }

  bool get isDemoModeEnabled => _isDemoModeEnabled;
  String get demoScenario => _demoScenario;
  String get serviceUuid => _serviceUuid;
  String get dataCharUuid => _dataCharUuid;
  String get cmdCharUuid => _cmdCharUuid;
  int get staleTimeoutSeconds => _staleTimeoutSeconds;
  bool get isFirebaseConfigured => _firestoreService.isFirestoreAvailable;

  Future<void> setDemoMode(bool value) async {
    _isDemoModeEnabled = value;
    await _storage.setDemoMode(value);
    notifyListeners();
  }

  Future<void> setDemoScenario(String scenario) async {
    _demoScenario = scenario;
    _simulationService.setScenario(scenario);
    await _storage.setDemoScenario(scenario);
    notifyListeners();
  }

  Future<void> updateBleUuids({
    required String serviceUuid,
    required String dataCharUuid,
    required String cmdCharUuid,
  }) async {
    _serviceUuid = serviceUuid.trim();
    _dataCharUuid = dataCharUuid.trim();
    _cmdCharUuid = cmdCharUuid.trim();

    await _storage.setServiceUuid(_serviceUuid);
    await _storage.setDataCharUuid(_dataCharUuid);
    await _storage.setCmdCharUuid(_cmdCharUuid);

    _bleService.configureUuids(
      serviceUuid: _serviceUuid,
      dataCharUuid: _dataCharUuid,
      cmdCharUuid: _cmdCharUuid,
    );
    notifyListeners();
  }

  Future<void> setStaleTimeout(int seconds) async {
    _staleTimeoutSeconds = seconds;
    await _storage.setStaleTimeoutSeconds(seconds);
    notifyListeners();
  }
}
