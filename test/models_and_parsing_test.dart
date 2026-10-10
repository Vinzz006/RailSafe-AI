import 'package:flutter_test/flutter_test.dart';
import 'package:railsafe_ai/core/utils/screening_analyzer.dart';
import 'package:railsafe_ai/models/app_alert.dart';
import 'package:railsafe_ai/models/prediction_response.dart';
import 'package:railsafe_ai/models/sensor_reading.dart';
import 'package:railsafe_ai/models/test_record.dart';

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
    test('Flags anomaly for secondary review when peak threshold is exceeded (offline guard)', () {
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
      expect(result.title, contains("Threshold Exceeded"));
      expect(result.metrics['sensor_1_max'], equals(320.0));
      expect(result.metrics['ml_prediction'], equals("prediction_service_unavailable"));
    });

    test('Identifies nominal baseline when all readings stay below threshold without backend', () {
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
      expect(result.title, contains("Prediction Service Offline"));
      expect(result.metrics['ml_prediction'], equals("prediction_service_unavailable"));
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

  group('Python Backend ML Prediction Models & Integration Tests', () {
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

    test('PredictionResponse parses backend JSON payload accurately', () {
      final json = {
        "deviceId": "railsafe-esp32-01",
        "sequence": 42,
        "prediction": "anomaly",
        "label": "anomaly_synthetic",
        "anomalyScore": 0.98,
        "normalScore": 0.02,
        "confidence": 98.0,
        "reviewRequired": true,
        "modelVersion": "1.0.0",
        "inferenceTimestamp": "2026-10-10T12:00:00Z",
        "inputFeatures": {
          "mq2_raw": 100.0,
          "mq4_raw": 100.0,
          "mq7_raw": 100.0
        },
        "userId": "test-officer-id"
      };

      final pred = PredictionResponse.fromJson(json);

      expect(pred.deviceId, equals("railsafe-esp32-01"));
      expect(pred.sequence, equals(42));
      expect(pred.prediction, equals("anomaly"));
      expect(pred.label, equals("anomaly_synthetic"));
      expect(pred.anomalyScore, equals(0.98));
      expect(pred.normalScore, equals(0.02));
      expect(pred.confidence, equals(98.0));
      expect(pred.reviewRequired, isTrue);
      expect(pred.isAnomaly, isTrue);
      expect(pred.modelVersion, equals("1.0.0"));
      expect(pred.inputFeatures['mq2_raw'], equals(100.0));
      expect(pred.inputFeatures['mq4_raw'], equals(100.0));
      expect(pred.inputFeatures['mq7_raw'], equals(100.0));
      expect(pred.userId, equals("test-officer-id"));
    });

    test('ScreeningAnalyzer integrates authoritative backend ML response for nominal baseline', () {
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

      final backendPrediction = PredictionResponse(
        deviceId: "RAILSAFE-ESP32-01",
        sequence: 3,
        prediction: "nominal",
        label: "normal_synthetic",
        anomalyScore: 0.02,
        normalScore: 0.98,
        confidence: 98.0,
        reviewRequired: false,
        modelVersion: "1.0.0",
        inferenceTimestamp: DateTime.parse("2026-10-10T12:00:00Z"),
        inputFeatures: {"mq2_raw": 710.0, "mq4_raw": 1020.0, "mq7_raw": 82.0},
      );

      final result = ScreeningAnalyzer.analyze(
        readings: readings,
        isDemo: false,
        wasInterrupted: false,
        backendPrediction: backendPrediction,
      );

      expect(result.status, equals(ScreeningStatus.normalBaseline));
      expect(result.requiresSecondaryReview, isFalse);
      expect(result.metrics['ml_prediction'], equals('normal_synthetic'));
      expect(result.metrics['ml_model'], contains('RandomForest v1.0.0'));
      expect(result.metrics['ml_anomaly_prob'], equals(2.0));
      expect(result.metrics['ml_confidence'], equals(98.0));
    });

    test('ScreeningAnalyzer integrates authoritative backend ML response for flagged anomaly', () {
      final readings = [
        {
          "sensors": {
            "mq2_raw": {"value": 100.0},
            "mq4_raw": {"value": 100.0},
            "mq7_raw": {"value": 100.0},
          }
        },
        {
          "sensors": {
            "mq2_raw": {"value": 95.0},
            "mq4_raw": {"value": 98.0},
            "mq7_raw": {"value": 99.0},
          }
        },
        {
          "sensors": {
            "mq2_raw": {"value": 102.0},
            "mq4_raw": {"value": 101.0},
            "mq7_raw": {"value": 100.0},
          }
        },
      ];

      final backendPrediction = PredictionResponse(
        deviceId: "RAILSAFE-ESP32-01",
        sequence: 3,
        prediction: "anomaly",
        label: "anomaly_synthetic",
        anomalyScore: 0.96,
        normalScore: 0.04,
        confidence: 96.0,
        reviewRequired: true,
        modelVersion: "1.0.0",
        inferenceTimestamp: DateTime.parse("2026-10-10T12:00:00Z"),
        inputFeatures: {"mq2_raw": 102.0, "mq4_raw": 101.0, "mq7_raw": 100.0},
      );

      final result = ScreeningAnalyzer.analyze(
        readings: readings,
        isDemo: false,
        wasInterrupted: false,
        backendPrediction: backendPrediction,
      );

      expect(result.status, equals(ScreeningStatus.anomalyFlagged));
      expect(result.requiresSecondaryReview, isTrue);
      expect(result.metrics['ml_prediction'], equals('anomaly_synthetic'));
      expect(result.title, contains('Anomaly Flagged'));
      expect(result.metrics['ml_anomaly_prob'], equals(96.0));
      expect(result.metrics['ml_model'], contains('RandomForest v1.0.0'));
    });
  });
}
