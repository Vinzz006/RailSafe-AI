import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:railsafe_ai/core/utils/screening_analyzer.dart';
import 'package:railsafe_ai/models/app_alert.dart';
import 'package:railsafe_ai/models/sensor_reading.dart';
import 'package:railsafe_ai/models/test_record.dart';
import 'package:railsafe_ai/services/ml_inference_service.dart';

void main() {
  group('SensorReading JSON Parsing Tests', () {
    test('Correctly parses complete protocol JSON packet', () {
      final json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "timestamp": "2026-01-01T10:30:00Z",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
          "sensor_1": {
            "value": 123.4,
            "unit": "raw"
          },
          "sensor_2": {
            "value": 45.6,
            "unit": "raw"
          }
        },
        "status": "ok"
      };

      final reading = SensorReading.fromJson(json);

      expect(reading.deviceId, equals("RAILSAFE-ESP32-01"));
      expect(reading.sequence, equals(1));
      expect(reading.mode, equals("hardware"));
      expect(reading.status, equals("ok"));
      expect(reading.sensor1Value, equals(123.4));
      expect(reading.sensor2Value, equals(45.6));
      expect(reading.sensors['sensor_1']?.unit, equals("raw"));
    });

    test('Safely handles missing fields and invalid types without crashing', () {
      final json = {
        "deviceId": null,
        "sequence": "invalid_num",
        "sensors": {
          "sensor_1": "corrupted",
          "sensor_2": 88.5
        }
      };

      final reading = SensorReading.fromJson(json);

      expect(reading.deviceId, equals("UNKNOWN-DEVICE"));
      expect(reading.sequence, equals(0));
      expect(reading.sensor1Value, equals(0.0));
      expect(reading.sensor2Value, equals(88.5));
    });

    test('Serializes to JSON correctly', () {
      final reading = SensorReading(
        deviceId: "DEV-100",
        timestamp: DateTime.parse("2026-05-10T12:00:00Z"),
        sequence: 42,
        mode: "demo",
        sensors: {
          "sensor_1": SensorChannelData(value: 75.2, unit: "ppm"),
          "sensor_2": SensorChannelData(value: 30.1, unit: "mV"),
        },
        status: "demo_ok",
        rawJson: {},
      );

      final json = reading.toJson();
      expect(json['deviceId'], equals("DEV-100"));
      expect(json['sequence'], equals(42));
      expect(json['mode'], equals("demo"));
      expect((json['sensors'] as Map)['sensor_1']['value'], equals(75.2));
    });
  });

  group('ScreeningAnalyzer Rule Logic Tests', () {
    test('Flags anomaly for secondary review when peak threshold is exceeded', () {
      final readings = [
        {
          "sensors": {
            "sensor_1": {"value": 70.0},
            "sensor_2": {"value": 35.0}
          }
        },
        {
          "sensors": {
            "sensor_1": {"value": 150.0},
            "sensor_2": {"value": 80.0}
          }
        },
        {
          "sensors": {
            "sensor_1": {"value": 320.0}, // Exceeds threshold (280.0)
            "sensor_2": {"value": 160.0}
          }
        },
        {
          "sensors": {
            "sensor_1": {"value": 85.0},
            "sensor_2": {"value": 40.0}
          }
        },
      ];

      final result = ScreeningAnalyzer.analyze(
        readings: readings,
        isDemo: false,
        wasInterrupted: false,
      );

      expect(result.status, equals(ScreeningStatus.anomalyFlagged));
      expect(result.requiresSecondaryReview, isTrue);
      expect(result.title, contains("Anomaly Flagged"));
      expect(result.metrics['sensor_1_max'], equals(320.0));
    });

    test('Identifies nominal baseline when all readings stay below threshold', () {
      final readings = [
        {
          "sensors": {
            "sensor_1": {"value": 60.0},
            "sensor_2": {"value": 30.0}
          }
        },
        {
          "sensors": {
            "sensor_1": {"value": 65.0},
            "sensor_2": {"value": 32.0}
          }
        },
        {
          "sensors": {
            "sensor_1": {"value": 58.0},
            "sensor_2": {"value": 29.0}
          }
        },
      ];

      final result = ScreeningAnalyzer.analyze(
        readings: readings,
        isDemo: false,
        wasInterrupted: false,
      );

      expect(result.status, equals(ScreeningStatus.normalBaseline));
      expect(result.requiresSecondaryReview, isFalse);
      expect(result.title, contains("Baseline Nominal"));
    });

    test('Marks test as interrupted when interrupted flag is true', () {
      final result = ScreeningAnalyzer.analyze(
        readings: [],
        isDemo: false,
        wasInterrupted: true,
      );

      expect(result.status, equals(ScreeningStatus.testInterrupted));
      expect(result.title, contains("Interrupted"));
    });

    test('Identifies inconclusive data when insufficient telemetry samples exist', () {
      final result = ScreeningAnalyzer.analyze(
        readings: [
          {
            "sensors": {
              "sensor_1": {"value": 50.0}
            }
          }
        ],
        isDemo: false,
        wasInterrupted: false,
      );

      expect(result.status, equals(ScreeningStatus.inconclusiveData));
      expect(result.title, contains("Incomplete Sampling"));
    });
  });

  group('TestRecord & AppAlert Serialization Tests', () {
    test('TestRecord serialization and copyWith operate reliably', () {
      final record = TestRecord(
        testId: "TEST-20261010-ABCD",
        userId: "user-42",
        deviceId: "RAILSAFE-ESP32-01",
        mode: "hardware",
        startedAt: DateTime.parse("2026-10-10T10:00:00Z"),
        completedAt: DateTime.parse("2026-10-10T10:00:15Z"),
        completionStatus: "completed",
        sensorReadings: [],
        screeningAssistanceStatus: "Baseline Nominal",
        screeningAssistanceDetails: "All nominal",
        metrics: {"sensor_1_max": 75.0},
        syncedToFirestore: false,
      );

      final json = record.toJson();
      expect(json['testId'], equals("TEST-20261010-ABCD"));
      expect(json['userId'], equals("user-42"));

      final restored = TestRecord.fromJson(json);
      expect(restored.testId, equals(record.testId));
      expect(restored.duration.inSeconds, equals(15));

      final updated = restored.copyWith(syncedToFirestore: true, notes: "Verified baggage");
      expect(updated.syncedToFirestore, isTrue);
      expect(updated.notes, equals("Verified baggage"));
    });

    test('AppAlert correctly parses severity and icon attributes', () {
      final alert = AppAlert(
        id: "ALERT-1",
        type: "device_connected",
        title: "ESP32 Connected",
        message: "Peripheral is ready",
        severity: AlertSeverity.success,
      );

      final json = alert.toJson();
      expect(json['severity'], equals("success"));

      final restored = AppAlert.fromJson(json);
      expect(restored.severity, equals(AlertSeverity.success));
    });
  });

  group('Embedded Random Forest ML Model & Multi-Channel Tests', () {
    test('SensorReading MQ2, MQ4, and MQ7 channel resolution', () {
      final json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "timestamp": "2026-01-01T10:30:00Z",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": {"value": 550.0},
          "mq4_raw": {"value": 850.0},
          "mq7_raw": {"value": 65.0},
        },
        "status": "ok"
      };

      final reading = SensorReading.fromJson(json);
      expect(reading.mq2Value, equals(550.0));
      expect(reading.mq4Value, equals(850.0));
      expect(reading.mq7Value, equals(65.0));
    });

    test('MlInferenceService executes 100-tree Random Forest predictions accurately', () {
      final modelFile = File('assets/models/railsafe_rf_model.json');
      expect(modelFile.existsSync(), isTrue, reason: 'Model asset file should exist');

      final mlService = MlInferenceService();
      mlService.loadFromString(modelFile.readAsStringSync());

      expect(mlService.isLoaded, isTrue);
      expect(mlService.estimatorCount, equals(100));
      expect(mlService.features, containsAll(['mq2_raw', 'mq4_raw', 'mq7_raw']));

      // Test calibrated normal baseline sample
      final normalPred = mlService.predict(mq2: 700.0, mq4: 1000.0, mq7: 80.0);
      expect(normalPred.label, equals('normal_synthetic'));
      expect(normalPred.isAnomaly, isFalse);
      expect(normalPred.normalProbability, greaterThan(0.90));

      // Test elevated anomaly sample
      final anomalyPred = mlService.predict(mq2: 100.0, mq4: 100.0, mq7: 100.0);
      expect(anomalyPred.label, equals('anomaly_synthetic'));
      expect(anomalyPred.isAnomaly, isTrue);
      expect(anomalyPred.anomalyProbability, greaterThan(0.90));
    });

    test('ScreeningAnalyzer integrates ML model predictions into test evaluation', () {
      final readings = [
        {
          "sensors": {
            "mq2_raw": {"value": 700.0},
            "mq4_raw": {"value": 1000.0},
            "mq7_raw": {"value": 80.0},
          }
        },
        {
          "sensors": {
            "mq2_raw": {"value": 710.0},
            "mq4_raw": {"value": 1020.0},
            "mq7_raw": {"value": 82.0},
          }
        },
        {
          "sensors": {
            "mq2_raw": {"value": 695.0},
            "mq4_raw": {"value": 990.0},
            "mq7_raw": {"value": 79.0},
          }
        },
      ];

      final result = ScreeningAnalyzer.analyze(
        readings: readings,
        isDemo: false,
        wasInterrupted: false,
      );

      expect(result.status, equals(ScreeningStatus.normalBaseline));
      expect(result.metrics.containsKey('ml_prediction'), isTrue);
      expect(result.metrics['ml_prediction'], equals('normal_synthetic'));
      expect(result.metrics.containsKey('ml_confidence'), isTrue);
    });
  });
}
