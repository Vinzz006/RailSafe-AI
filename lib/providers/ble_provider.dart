import 'dart:async';
import 'package:flutter/material.dart';
import '../models/device_info.dart';
import '../models/sensor_reading.dart';
import '../services/ble_service.dart';

class BleProvider extends ChangeNotifier {
  final BleService _bleService;
  List<DeviceInfo> _discoveredDevices = [];
  String? _errorMessage;
  bool _isPermissionDenied = false;

  StreamSubscription? _statusSub;
  StreamSubscription? _devicesSub;

  BleProvider(this._bleService) {
    _statusSub = _bleService.statusStream.listen((_) => notifyListeners());
    _devicesSub = _bleService.devicesStream.listen((devices) {
      _discoveredDevices = devices;
      notifyListeners();
    });
  }

  BleStatus get status => _bleService.status;
  bool get isConnected => _bleService.isConnected;
  bool get isScanning => _bleService.status == BleStatus.scanning;
  bool get isConnecting => _bleService.status == BleStatus.connecting;
  bool get hasStaleData => _bleService.hasStaleData;
  DateTime? get lastDataReceivedAt => _bleService.lastDataReceivedAt;
  String? get connectedDeviceName => _bleService.connectedDeviceName;
  List<DeviceInfo> get discoveredDevices => _discoveredDevices;
  String? get errorMessage => _errorMessage;
  bool get isPermissionDenied => _isPermissionDenied;

  Stream<SensorReading> get readingStream => _bleService.readingStream;

  void clearError() {
    _errorMessage = null;
    _isPermissionDenied = false;
    notifyListeners();
  }

  Future<void> startScan() async {
    _errorMessage = null;
    _isPermissionDenied = false;
    notifyListeners();

    try {
      await _bleService.startScan();
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      if (e.toString().contains("permission") || e.toString().contains("Permission")) {
        _isPermissionDenied = true;
      }
      notifyListeners();
    }
  }

  Future<void> stopScan() async {
    await _bleService.stopScan();
    notifyListeners();
  }

  Future<bool> connect(String deviceId) async {
    _errorMessage = null;
    notifyListeners();

    try {
      await _bleService.connect(deviceId);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceFirst("Exception: ", "");
      notifyListeners();
      return false;
    }
  }

  Future<void> disconnect() async {
    await _bleService.disconnect();
    notifyListeners();
  }

  Future<bool> sendCommand(String cmd) async {
    return await _bleService.sendCommand(cmd);
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _devicesSub?.cancel();
    super.dispose();
  }
}
