class SensorChannelData {
  final double value;
  final String unit;
  final String? label;

  SensorChannelData({
    required this.value,
    required this.unit,
    this.label,
  });

  factory SensorChannelData.fromJson(dynamic json, {String defaultLabel = "Sensor"}) {
    if (json is num) {
      return SensorChannelData(
        value: json.toDouble(),
        unit: "raw",
        label: defaultLabel,
      );
    }

    if (json is Map<String, dynamic>) {
      final rawVal = json['value'];
      final val = (rawVal is num)
          ? rawVal.toDouble()
          : double.tryParse(rawVal?.toString() ?? '0') ?? 0.0;
      final unit = json['unit']?.toString() ?? 'raw';
      final label = json['label']?.toString() ?? defaultLabel;

      return SensorChannelData(
        value: val,
        unit: unit,
        label: label,
      );
    }

    return SensorChannelData(
      value: 0.0,
      unit: "raw",
      label: defaultLabel,
    );
  }

  Map<String, dynamic> toJson() => {
        'value': value,
        'unit': unit,
        if (label != null) 'label': label,
      };
}

class SensorReading {
  final String deviceId;
  final DateTime timestamp;
  final int sequence;
  final String mode; // 'hardware' or 'demo'
  final Map<String, SensorChannelData> sensors;
  final String status;
  final Map<String, dynamic> rawJson;
  final List<String> missingChannels;

  SensorReading({
    required this.deviceId,
    required this.timestamp,
    required this.sequence,
    required this.mode,
    required this.sensors,
    required this.status,
    required this.rawJson,
    this.missingChannels = const [],
  });

  factory SensorReading.fromJson(Map<String, dynamic> json) {
    final devId = json['deviceId']?.toString() ?? 'UNKNOWN-DEVICE';
    DateTime ts;
    try {
      final rawTs = json['timestamp']?.toString();
      ts = rawTs != null ? DateTime.parse(rawTs) : DateTime.now();
    } catch (_) {
      ts = DateTime.now();
    }

    final seq = (json['sequence'] is num)
        ? (json['sequence'] as num).toInt()
        : int.tryParse(json['sequence']?.toString() ?? '0') ?? 0;

    final m = json['mode']?.toString() ?? 'hardware';
    final st = json['status']?.toString() ?? 'ok';

    final sensorsMap = <String, SensorChannelData>{};
    final rawSensors = json['sensors'];
    if (rawSensors is Map<String, dynamic>) {
      rawSensors.forEach((key, val) {
        sensorsMap[key] = SensorChannelData.fromJson(val, defaultLabel: key);
      });
    }

    // Ensure fallback if sensors object was missing or empty in legacy/demo payloads
    if (sensorsMap.isEmpty) {
      if (json.containsKey('sensor_1')) {
        sensorsMap['sensor_1'] = SensorChannelData.fromJson(json['sensor_1'], defaultLabel: "Sensor 1");
      }
      if (json.containsKey('sensor_2')) {
        sensorsMap['sensor_2'] = SensorChannelData.fromJson(json['sensor_2'], defaultLabel: "Sensor 2");
      }
    }

    final missing = <String>[];
    if (m == 'hardware') {
      final hasMq2 = sensorsMap.containsKey('mq2_raw') || sensorsMap.containsKey('mq2');
      final hasMq4 = sensorsMap.containsKey('mq4_raw') || sensorsMap.containsKey('mq4');
      final hasMq7 = sensorsMap.containsKey('mq7_raw') || sensorsMap.containsKey('mq7');
      if (!hasMq2) missing.add('mq2_raw');
      if (!hasMq4) missing.add('mq4_raw');
      if (!hasMq7) missing.add('mq7_raw');
    }

    return SensorReading(
      deviceId: devId,
      timestamp: ts,
      sequence: seq,
      mode: m,
      sensors: sensorsMap,
      status: st,
      rawJson: json,
      missingChannels: missing,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'sequence': sequence,
        'mode': mode,
        'sensors': sensors.map((k, v) => MapEntry(k, v.toJson())),
        'status': status,
        if (missingChannels.isNotEmpty) 'missingChannels': missingChannels,
      };

  bool get isHardwareMode => mode == 'hardware';
  bool get isDemoMode => mode == 'demo';

  /// Telemetry status reflecting any missing channels in physical hardware mode
  String get telemetryStatus => (isHardwareMode && hasMissingTelemetry) ? 'missing_telemetry' : status;

  /// Whether telemetry packet contains all required channels without missing fields
  bool get isTelemetryComplete => missingChannels.isEmpty;

  /// Whether any required physical telemetry channel is missing
  bool get hasMissingTelemetry => missingChannels.isNotEmpty;

  /// True if all 3 physical ADC channels (MQ-2, MQ-4, MQ-7) are present
  bool get hasAllPhysicalChannels =>
      (sensors.containsKey('mq2_raw') || sensors.containsKey('mq2')) &&
      (sensors.containsKey('mq4_raw') || sensors.containsKey('mq4')) &&
      (sensors.containsKey('mq7_raw') || sensors.containsKey('mq7'));

  // Backward-compatible channel accessors for legacy UI widgets
  double? get sensor1Value =>
      sensors['sensor_1']?.value ?? sensors['mq2_raw']?.value ?? sensors['mq2']?.value;
  double? get sensor2Value =>
      sensors['sensor_2']?.value ?? sensors['mq4_raw']?.value ?? sensors['mq4']?.value;
  double? get sensor3Value =>
      sensors['sensor_3']?.value ?? sensors['mq7_raw']?.value ?? sensors['mq7']?.value;

  /// Returns MQ-2 combustible / smoke raw reading.
  /// In hardware mode, returns actual measured value or null if missing (no fabrication).
  /// In demo mode, falls back to synthetic sensor_1 channel if present.
  double? get mq2Value {
    final direct = sensors['mq2_raw']?.value ?? sensors['mq2']?.value;
    if (direct != null) return direct;
    if (isDemoMode) {
      return sensors['sensor_1']?.value ?? 0.0;
    }
    return null;
  }

  /// Returns MQ-4 methane / CNG raw reading.
  /// In hardware mode, returns actual measured value or null if missing (no fabrication).
  /// In demo mode, falls back to synthetic sensor_2 channel if present.
  double? get mq4Value {
    final direct = sensors['mq4_raw']?.value ?? sensors['mq4']?.value;
    if (direct != null) return direct;
    if (isDemoMode) {
      return sensors['sensor_2']?.value ?? 0.0;
    }
    return null;
  }

  /// Returns MQ-7 carbon monoxide raw reading.
  /// In hardware mode, returns actual measured value or null if missing (no interpolation).
  /// In demo mode, falls back to synthetic sensor_3 channel or demo proportional model.
  double? get mq7Value {
    final direct = sensors['mq7_raw']?.value ?? sensors['mq7']?.value;
    if (direct != null) return direct;
    if (isDemoMode) {
      return sensors['sensor_3']?.value ?? ((sensors['sensor_1']?.value ?? 0.0) * 0.45);
    }
    return null;
  }
}

