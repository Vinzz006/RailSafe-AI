import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/constants/ble_constants.dart';
import '../core/errors/app_error.dart';
import '../models/device_info.dart';
import '../models/sensor_reading.dart';

enum BleStatus {
  disconnected,
  scanning,
  connecting,
  connected,
  disconnecting,
}

class BleService {
  String _serviceUuid = BleConstants.defaultServiceUuid;
  String _dataCharUuid = BleConstants.defaultDataCharacteristicUuid;
  String _cmdCharUuid = BleConstants.defaultCommandCharacteristicUuid;

  BleStatus _status = BleStatus.disconnected;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _dataCharacteristic;
  BluetoothCharacteristic? _cmdCharacteristic;

  DateTime? _lastDataReceivedAt;
  final StringBuffer _packetBuffer = StringBuffer();

  // Streams
  final StreamController<BleStatus> _statusController = StreamController<BleStatus>.broadcast();
  final StreamController<List<DeviceInfo>> _devicesController = StreamController<List<DeviceInfo>>.broadcast();
  final StreamController<SensorReading> _readingController = StreamController<SensorReading>.broadcast();
  final StreamController<String> _rawLogsController = StreamController<String>.broadcast();

  StreamSubscription? _scanResultsSub;
  StreamSubscription? _deviceStateSub;
  StreamSubscription? _charValueSub;
  StreamSubscription? _adapterStateSub;

  final Map<String, DeviceInfo> _discoveredDevices = {};

  BleService();

  // Getters
  BleStatus get status => _status;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  String? get connectedDeviceName => _connectedDevice?.platformName.isNotEmpty == true
      ? _connectedDevice?.platformName
      : _connectedDevice?.remoteId.str;
  DateTime? get lastDataReceivedAt => _lastDataReceivedAt;
  bool get isConnected => _status == BleStatus.connected && _connectedDevice != null;
  bool get hasStaleData {
    if (!isConnected || _lastDataReceivedAt == null) return false;
    return DateTime.now().difference(_lastDataReceivedAt!) > BleConstants.staleDataThreshold;
  }

  Stream<BleStatus> get statusStream => _statusController.stream;
  Stream<List<DeviceInfo>> get devicesStream => _devicesController.stream;
  Stream<SensorReading> get readingStream => _readingController.stream;
  Stream<String> get rawLogsStream => _rawLogsController.stream;

  void configureUuids({String? serviceUuid, String? dataCharUuid, String? cmdCharUuid}) {
    if (serviceUuid != null) _serviceUuid = serviceUuid.toLowerCase();
    if (dataCharUuid != null) _dataCharUuid = dataCharUuid.toLowerCase();
    if (cmdCharUuid != null) _cmdCharUuid = cmdCharUuid.toLowerCase();
  }

  void _setStatus(BleStatus newStatus) {
    _status = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(_status);
    }
  }

  void _log(String message) {
    if (kDebugMode) print("[BLE_SERVICE] $message");
    if (!_rawLogsController.isClosed) {
      _rawLogsController.add(message);
    }
  }

  /// Verifies and requests required Bluetooth & Location permissions
  Future<bool> checkAndRequestPermissions() async {
    if (!Platform.isAndroid) return true;

    // Check Bluetooth state first
    final isSupported = await FlutterBluePlus.isSupported;
    if (!isSupported) {
      throw BlePermissionException("Bluetooth Low Energy is not supported on this device.");
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      // Prompt user or turn on Bluetooth if allowed
      try {
        await FlutterBluePlus.turnOn();
      } catch (_) {
        throw BlePermissionException("Bluetooth is disabled. Please enable Bluetooth in system settings.");
      }
    }

    // Android 12+ (API 31+) permissions
    final scanStatus = await Permission.bluetoothScan.request();
    final connectStatus = await Permission.bluetoothConnect.request();
    final locationStatus = await Permission.locationWhenInUse.request();

    if (scanStatus.isPermanentlyDenied || connectStatus.isPermanentlyDenied) {
      throw BlePermissionException("Bluetooth permissions permanently denied. Please grant in App Settings.");
    }

    if (!scanStatus.isGranted && !locationStatus.isGranted) {
      throw BlePermissionException("Bluetooth scan permission is required to discover ESP32.");
    }

    return true;
  }

  /// Scans for nearby BLE devices with timeout
  Future<void> startScan() async {
    if (_status == BleStatus.scanning) return;

    await checkAndRequestPermissions();

    _discoveredDevices.clear();
    _devicesController.add([]);
    _setStatus(BleStatus.scanning);
    _log("Starting BLE scan for ESP32 devices...");

    _scanResultsSub?.cancel();
    _scanResultsSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName;
        final devInfo = DeviceInfo(
          id: r.device.remoteId.str,
          name: name,
          rssi: r.rssi,
          isConnectable: r.advertisementData.connectable,
          serviceUuids: r.advertisementData.serviceUuids.map((u) => u.str128.toLowerCase()).toList(),
        );

        _discoveredDevices[devInfo.id] = devInfo;
      }
      _devicesController.add(_discoveredDevices.values.toList()
        ..sort((a, b) => b.rssi.compareTo(a.rssi)));
    }, onError: (e) {
      _log("Scan error: $e");
      _setStatus(BleStatus.disconnected);
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: BleConstants.scanTimeout,
        androidUsesFineLocation: false,
      );
    } catch (e) {
      _setStatus(BleStatus.disconnected);
      throw BleConnectionException("Failed to initiate BLE scan: $e");
    }
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (_status == BleStatus.scanning) {
      _setStatus(BleStatus.disconnected);
    }
    _log("BLE scan stopped.");
  }

  /// Connects to a selected BLE peripheral
  Future<void> connect(String deviceId) async {
    await stopScan();
    _setStatus(BleStatus.connecting);
    _log("Connecting to BLE device: $deviceId");

    final device = BluetoothDevice.fromId(deviceId);
    _connectedDevice = device;

    _deviceStateSub?.cancel();
    _deviceStateSub = device.connectionState.listen((state) {
      _log("Connection state changed: $state");
      if (state == BluetoothConnectionState.connected) {
        _setStatus(BleStatus.connected);
      } else if (state == BluetoothConnectionState.disconnected) {
        _setStatus(BleStatus.disconnected);
        _connectedDevice = null;
        _dataCharacteristic = null;
        _cmdCharacteristic = null;
        _charValueSub?.cancel();
      }
    });

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: BleConstants.connectionTimeout,
        autoConnect: false,
      );

      // Request MTU up to 512 bytes on Android to allow whole JSON packet notifications
      if (Platform.isAndroid) {
        try {
          await device.requestMtu(512);
          _log("Requested BLE MTU of 512 bytes.");
        } catch (e) {
          _log("MTU request warning: $e");
        }
      }

      // Discover GATT Services
      _log("Discovering GATT services for target service $_serviceUuid...");
      final services = await device.discoverServices();
      _log("Discovered ${services.length} services.");

      BluetoothCharacteristic? foundDataChar;
      BluetoothCharacteristic? foundCmdChar;

      for (final s in services) {
        for (final c in s.characteristics) {
          final charUuid = c.uuid.str128.toLowerCase();
          if (charUuid == _dataCharUuid.toLowerCase() ||
              c.uuid.str.toLowerCase() == _dataCharUuid.toLowerCase()) {
            foundDataChar = c;
          }
          if (charUuid == _cmdCharUuid.toLowerCase() ||
              c.uuid.str.toLowerCase() == _cmdCharUuid.toLowerCase()) {
            foundCmdChar = c;
          }
        }
      }

      // If specific UUID not found, fallback to first notify characteristic
      if (foundDataChar == null) {
        for (final s in services) {
          for (final c in s.characteristics) {
            if (c.properties.notify || c.properties.indicate) {
              foundDataChar = c;
              _log("Fallback to notification characteristic: ${c.uuid.str128}");
              break;
            }
          }
          if (foundDataChar != null) break;
        }
      }

      if (foundDataChar == null) {
        throw BleConnectionException(
          "Compatible sensor telemetry characteristic not found on this device.",
        );
      }

      _dataCharacteristic = foundDataChar;
      _cmdCharacteristic = foundCmdChar;

      // Subscribe to notifications
      await foundDataChar.setNotifyValue(true);
      _log("Subscribed to data notifications on ${foundDataChar.uuid.str128}");

      _charValueSub?.cancel();
      _charValueSub = foundDataChar.onValueReceived.listen((bytes) {
        _handleIncomingBytes(bytes);
      }, onError: (e) {
        _log("Error in characteristic notification stream: $e");
      });

      _setStatus(BleStatus.connected);
    } catch (e) {
      _setStatus(BleStatus.disconnected);
      _connectedDevice = null;
      try {
        await device.disconnect();
      } catch (_) {}
      throw BleConnectionException("Connection failed: $e");
    }
  }

  /// Visible for testing byte framing, buffering, and packet processing
  @visibleForTesting
  void handleIncomingBytesForTesting(List<int> bytes) => _handleIncomingBytes(bytes);

  /// Processes raw incoming bytes with framing/chunking support & JSON parsing
  void _handleIncomingBytes(List<int> bytes) {
    if (bytes.isEmpty) return;

    try {
      final chunk = utf8.decode(bytes, allowMalformed: true);
      _packetBuffer.write(chunk);
      final currentBuffer = _packetBuffer.toString();

      // Check if we have complete JSON message:
      // Protocols either end with '\n' OR have balanced '{' ... '}'
      if (currentBuffer.contains('\n') ||
          (currentBuffer.startsWith('{') && currentBuffer.trim().endsWith('}'))) {
        final messages = currentBuffer.split('\n');

        // All items except possibly the last one (if no trailing newline)
        for (int i = 0; i < messages.length - 1; i++) {
          final line = messages[i].trim();
          if (line.isNotEmpty) {
            _parseAndEmitJson(line);
          }
        }

        final lastSegment = messages.last.trim();
        if (lastSegment.startsWith('{') && lastSegment.endsWith('}')) {
          _parseAndEmitJson(lastSegment);
          _packetBuffer.clear();
        } else {
          _packetBuffer.clear();
          if (lastSegment.isNotEmpty) {
            _packetBuffer.write(lastSegment);
          }
        }
      }
    } catch (e) {
      _log("Error handling BLE bytes: $e");
    }
  }

  void _parseAndEmitJson(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map<String, dynamic>) {
        final reading = SensorReading.fromJson(decoded);
        _lastDataReceivedAt = DateTime.now();
        if (!_readingController.isClosed) {
          _readingController.add(reading);
        }
      }
    } catch (e) {
      _log("Warning: Malformed telemetry packet ignored: '$jsonString'. Parse error: $e");
    }
  }

  /// Sends a hardware command (e.g., CMD:START_TEST or CMD:STOP_TEST)
  Future<bool> sendCommand(String command) async {
    if (!isConnected || _cmdCharacteristic == null) {
      _log("Cannot send command '$command': Device not connected or command characteristic missing.");
      return false;
    }

    try {
      final bytes = utf8.encode("$command\n");
      await _cmdCharacteristic!.write(bytes, withoutResponse: false);
      _log("Sent command successfully: $command");
      return true;
    } catch (e) {
      _log("Failed to send command: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    _setStatus(BleStatus.disconnecting);
    _log("Disconnecting from device...");

    try {
      _charValueSub?.cancel();
      _charValueSub = null;
      if (_dataCharacteristic != null) {
        try {
          await _dataCharacteristic!.setNotifyValue(false);
        } catch (_) {}
      }
      if (_connectedDevice != null) {
        await _connectedDevice!.disconnect();
      }
    } catch (e) {
      _log("Disconnect error: $e");
    } finally {
      _connectedDevice = null;
      _dataCharacteristic = null;
      _cmdCharacteristic = null;
      _deviceStateSub?.cancel();
      _packetBuffer.clear();
      _setStatus(BleStatus.disconnected);
    }
  }

  void dispose() {
    _scanResultsSub?.cancel();
    _deviceStateSub?.cancel();
    _charValueSub?.cancel();
    _adapterStateSub?.cancel();
    _statusController.close();
    _devicesController.close();
    _readingController.close();
    _rawLogsController.close();
  }
}
