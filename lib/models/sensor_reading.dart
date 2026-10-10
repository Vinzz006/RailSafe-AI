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

  SensorReading({
    required this.deviceId,
    required this.timestamp,
    required this.sequence,
    required this.mode,
    required this.sensors,
    required this.status,
    required this.rawJson,
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

    // Ensure fallback if sensors object was missing or empty
    if (sensorsMap.isEmpty) {
      if (json.containsKey('sensor_1')) {
        sensorsMap['sensor_1'] = SensorChannelData.fromJson(json['sensor_1'], defaultLabel: "Sensor 1");
      }
      if (json.containsKey('sensor_2')) {
        sensorsMap['sensor_2'] = SensorChannelData.fromJson(json['sensor_2'], defaultLabel: "Sensor 2");
      }
    }

    return SensorReading(
      deviceId: devId,
      timestamp: ts,
      sequence: seq,
      mode: m,
      sensors: sensorsMap,
      status: st,
      rawJson: json,
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'sequence': sequence,
        'mode': mode,
        'sensors': sensors.map((k, v) => MapEntry(k, v.toJson())),
        'status': status,
      };

  double? get sensor1Value => sensors['sensor_1']?.value;
  double? get sensor2Value => sensors['sensor_2']?.value;

  /// Returns MQ-2 combustible / smoke raw reading (fallback to sensor_1 if not named)
  double get mq2Value =>
      sensors['mq2_raw']?.value ??
      sensors['mq2']?.value ??
      sensors['sensor_1']?.value ??
      0.0;

  /// Returns MQ-4 methane / CNG raw reading (fallback to sensor_2 if not named)
  double get mq4Value =>
      sensors['mq4_raw']?.value ??
      sensors['mq4']?.value ??
      sensors['sensor_2']?.value ??
      0.0;

  /// Returns MQ-7 carbon monoxide raw reading (fallback to sensor_3 or calibrated proportion)
  double get mq7Value =>
      sensors['mq7_raw']?.value ??
      sensors['mq7']?.value ??
      sensors['sensor_3']?.value ??
      ((sensors['sensor_1']?.value ?? 0.0) * 0.45);
}
