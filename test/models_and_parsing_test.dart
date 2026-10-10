import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:railsafe_ai/core/constants/ble_constants.dart';
import 'package:railsafe_ai/core/utils/screening_analyzer.dart';
import 'package:railsafe_ai/models/app_alert.dart';
import 'package:railsafe_ai/models/prediction_response.dart';
import 'package:railsafe_ai/models/sensor_reading.dart';
import 'package:railsafe_ai/models/test_record.dart';
import 'package:railsafe_ai/services/ble_service.dart';
import 'package:railsafe_ai/services/local_storage_service.dart';
import 'package:railsafe_ai/services/prediction_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  group('Real Three-Sensor ESP32 Telemetry & Protocol Compatibility Tests', () {
    // 1. Parsing a valid three-sensor JSON packet
    test('1. Parses valid three-sensor JSON packet with independent physical values', () {
      final json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": 1234,
          "mq4_raw": 1456,
          "mq7_raw": 1678
        },
        "status": "ok"
      };

      final reading = SensorReading.fromJson(json);

      expect(reading.deviceId, equals("RAILSAFE-ESP32-01"));
      expect(reading.sequence, equals(1));
      expect(reading.mode, equals("hardware"));
      expect(reading.status, equals("ok"));
      expect(reading.isTelemetryComplete, isTrue);
      expect(reading.hasMissingTelemetry, isFalse);
      expect(reading.hasAllPhysicalChannels, isTrue);
      expect(reading.mq2Value, equals(1234.0));
      expect(reading.mq4Value, equals(1456.0));
      expect(reading.mq7Value, equals(1678.0));
    });

    // 2. Correct mapping of each value to its corresponding sensor
    test('2. Correctly maps physical ADC pins to corresponding sensor channels', () {
      // PIN_MQ2 (GPIO 32) -> mq2_raw
      // PIN_MQ4 (GPIO 34) -> mq4_raw
      // PIN_MQ7 (GPIO 35) -> mq7_raw
      final json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 10,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": 320.5,
          "mq4_raw": 340.5,
          "mq7_raw": 350.5
        },
        "status": "ok"
      };

      final reading = SensorReading.fromJson(json);

      // Verify each sensor receives strictly its assigned channel without cross-talk
      expect(reading.mq2Value, equals(320.5));
      expect(reading.mq4Value, equals(340.5));
      expect(reading.mq7Value, equals(350.5));
      expect(reading.mq2Value, isNot(equals(reading.mq4Value)));
      expect(reading.mq4Value, isNot(equals(reading.mq7Value)));
    });

    // 3. A sensor reading changing independently of the other two
    test('3. Sensor reading changes independently without cross-channel derivation', () {
      final t1Json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {"mq2_raw": 500.0, "mq4_raw": 450.0, "mq7_raw": 100.0},
        "status": "ok"
      };
      final t2Json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 2,
        "mode": "hardware",
        "sensors": {"mq2_raw": 500.0, "mq4_raw": 450.0, "mq7_raw": 950.0},
        "status": "ok"
      };

      final r1 = SensorReading.fromJson(t1Json);
      final r2 = SensorReading.fromJson(t2Json);

      // MQ-7 changed by +850.0
      expect(r2.mq7Value, equals(950.0));
      expect(r1.mq7Value, equals(100.0));

      // MQ-2 and MQ-4 remained completely static and unaffected
      expect(r1.mq2Value, equals(500.0));
      expect(r2.mq2Value, equals(500.0));
      expect(r1.mq4Value, equals(450.0));
      expect(r2.mq4Value, equals(450.0));

      // Confirms MQ-7 is NOT derived from MQ-2 (not 500 * 0.45 = 225.0)
      expect(r2.mq7Value, isNot(equals(r2.mq2Value! * 0.45)));
    });

    // 4. Missing mq7_raw and other missing required fields
    test('4. Missing required physical fields returns null, no fabrication, flags missing telemetry', () {
      // 4a: Missing mq7_raw
      final missingMq7Json = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 5,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": 1200,
          "mq4_raw": 1400
        },
        "status": "ok"
      };
      final rMissingMq7 = SensorReading.fromJson(missingMq7Json);
      expect(rMissingMq7.mq2Value, equals(1200.0));
      expect(rMissingMq7.mq4Value, equals(1400.0));
      expect(rMissingMq7.mq7Value, isNull); // Must not interpolate mq2 * 0.45 or return 0
      expect(rMissingMq7.isTelemetryComplete, isFalse);
      expect(rMissingMq7.hasMissingTelemetry, isTrue);
      expect(rMissingMq7.missingChannels, contains("mq7_raw"));
      expect(rMissingMq7.telemetryStatus, equals("missing_telemetry"));

      // 4b: Missing mq2_raw and mq4_raw
      final missingMultipleJson = {
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 6,
        "mode": "hardware",
        "sensors": {
          "mq7_raw": 800
        },
        "status": "ok"
      };
      final rMissingMultiple = SensorReading.fromJson(missingMultipleJson);
      expect(rMissingMultiple.mq2Value, isNull);
      expect(rMissingMultiple.mq4Value, isNull);
      expect(rMissingMultiple.mq7Value, equals(800.0));
      expect(rMissingMultiple.missingChannels, contains("mq2_raw"));
      expect(rMissingMultiple.missingChannels, contains("mq4_raw"));
      expect(rMissingMultiple.telemetryStatus, equals("missing_telemetry"));
    });

    // 5. Malformed JSON and incomplete BLE notification chunks
    test('5. Safely buffers incomplete BLE chunks and recovers without crashing on malformed JSON', () async {
      final ble = BleService();
      final emitted = <SensorReading>[];
      final sub = ble.readingStream.listen(emitted.add);

      // Incomplete Chunk 1
      final chunk1 = utf8.encode('{"deviceId":"RAILSAFE-ESP32-01","sequence":1,"mode":"hardware","sensors":{"mq2_raw":1');
      ble.handleIncomingBytesForTesting(chunk1);
      await pumpEventQueue();
      expect(emitted, isEmpty); // No reading emitted yet

      // Incomplete Chunk 2 completing the packet with trailing newline
      final chunk2 = utf8.encode('234,"mq4_raw":1456,"mq7_raw":1678},"status":"ok"}\n');
      ble.handleIncomingBytesForTesting(chunk2);
      await pumpEventQueue();
      expect(emitted.length, equals(1));
      expect(emitted.first.sequence, equals(1));
      expect(emitted.first.mq2Value, equals(1234.0));
      expect(emitted.first.mq4Value, equals(1456.0));
      expect(emitted.first.mq7Value, equals(1678.0));

      // Malformed JSON chunk (should be logged safely without crashing)
      final malformedChunk = utf8.encode('CORRUPTED_GARBAGE_DATA_1234\n');
      expect(() => ble.handleIncomingBytesForTesting(malformedChunk), returnsNormally);
      await pumpEventQueue();
      expect(emitted.length, equals(1)); // No corrupted packet emitted

      // Subsequent valid packet arrives and succeeds
      final chunk3 = utf8.encode('{"deviceId":"RAILSAFE-ESP32-01","sequence":2,"mode":"hardware","sensors":{"mq2_raw":2000,"mq4_raw":2100,"mq7_raw":2200},"status":"ok"}\n');
      ble.handleIncomingBytesForTesting(chunk3);
      await pumpEventQueue();
      expect(emitted.length, equals(2));
      expect(emitted[1].sequence, equals(2));

      await sub.cancel();
      ble.dispose();
    });

    // 6. Newline-framed packets and multiple packets received in one BLE stream
    test('6. Handles newline-delimited stream with multiple packets in one BLE chunk', () async {
      final ble = BleService();
      final emitted = <SensorReading>[];
      final sub = ble.readingStream.listen(emitted.add);

      final multiPacketStream = utf8.encode(
        '{"deviceId":"RAILSAFE-ESP32-01","sequence":10,"mode":"hardware","sensors":{"mq2_raw":100,"mq4_raw":200,"mq7_raw":300},"status":"ok"}\n'
        '{"deviceId":"RAILSAFE-ESP32-01","sequence":11,"mode":"hardware","sensors":{"mq2_raw":105,"mq4_raw":205,"mq7_raw":305},"status":"ok"}\n'
        '{"deviceId":"RAILSAFE-ESP32-01","sequence":12,"mode":"hardware","sensors":{"mq2_raw":110,"mq4_raw":210,"mq7_raw":310},"status":"ok"}\n'
      );

      ble.handleIncomingBytesForTesting(multiPacketStream);
      await pumpEventQueue();

      expect(emitted.length, equals(3));
      expect(emitted[0].sequence, equals(10));
      expect(emitted[0].mq2Value, equals(100.0));
      expect(emitted[1].sequence, equals(11));
      expect(emitted[1].mq4Value, equals(205.0));
      expect(emitted[2].sequence, equals(12));
      expect(emitted[2].mq7Value, equals(310.0));

      await sub.cancel();
      ble.dispose();
    });

    // 7. Correct three-feature /predict payload construction
    test('7. Constructs exact 3-feature payload (mq2_raw, mq4_raw, mq7_raw) for /predict', () async {
      SharedPreferences.setMockInitialValues({
        "backend_url": "http://127.0.0.1:8000",
      });
      final storage = await LocalStorageService.getInstance();

      Map<String, dynamic>? interceptedBody;
      final mockClient = MockClient((request) async {
        if (request.url.path == '/predict') {
          interceptedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              "deviceId": "RAILSAFE-ESP32-01",
              "sequence": 42,
              "prediction": "nominal",
              "label": "normal_synthetic",
              "anomalyScore": 0.05,
              "normalScore": 0.95,
              "confidence": 95.0,
              "reviewRequired": false,
              "modelVersion": "1.0.0",
              "inferenceTimestamp": "2026-10-10T12:00:00Z",
              "inputFeatures": {
                "mq2_raw": 1234.0,
                "mq4_raw": 1456.0,
                "mq7_raw": 1678.0
              }
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('Not Found', 404);
      });

      final apiService = PredictionApiService(storage, client: mockClient);
      final response = await apiService.predict(
        deviceId: "RAILSAFE-ESP32-01",
        sequence: 42,
        timestamp: DateTime.parse("2026-10-10T12:00:00Z"),
        mq2: 1234.0,
        mq4: 1456.0,
        mq7: 1678.0,
        idToken: "test_token_123",
      );

      expect(response.prediction, equals("nominal"));
      expect(interceptedBody, isNotNull);
      expect(interceptedBody!['deviceId'], equals("RAILSAFE-ESP32-01"));
      expect(interceptedBody!['sequence'], equals(42));
      final sensorsPayload = interceptedBody!['sensors'] as Map<String, dynamic>;
      expect(sensorsPayload.containsKey('mq2_raw'), isTrue);
      expect(sensorsPayload.containsKey('mq4_raw'), isTrue);
      expect(sensorsPayload.containsKey('mq7_raw'), isTrue);
      expect(sensorsPayload['mq2_raw'], equals(1234.0));
      expect(sensorsPayload['mq4_raw'], equals(1456.0));
      expect(sensorsPayload['mq7_raw'], equals(1678.0));
      // Ensure exact 3 features expected by Python backend Pydantic schema
      expect(sensorsPayload.keys.toList(), containsAll(['mq2_raw', 'mq4_raw', 'mq7_raw']));

      apiService.dispose();
    });

    // 8. Existing BLE UUIDs and legacy/demo behavior remaining compatible where required
    test('8. Preserves exact BLE UUIDs and maintains isolated legacy/demo mode behavior', () {
      // Check UUID constants
      expect(BleConstants.defaultServiceUuid.toLowerCase(), equals("12345678-1234-5678-1234-56789abcdef0"));
      expect(BleConstants.defaultDataCharacteristicUuid.toLowerCase(), equals("12345678-1234-5678-1234-56789abcdef1"));
      expect(BleConstants.defaultCommandCharacteristicUuid.toLowerCase(), equals("12345678-1234-5678-1234-56789abcdef2"));

      // Check legacy demo payload compatibility
      final demoLegacyJson = {
        "deviceId": "RAILSAFE-DEMO-SIM",
        "sequence": 1,
        "mode": "demo",
        "sensors": {
          "sensor_1": {"value": 200.0, "unit": "ppm"},
          "sensor_2": {"value": 100.0, "unit": "mV"}
        },
        "status": "demo_ok"
      };

      final demoReading = SensorReading.fromJson(demoLegacyJson);
      expect(demoReading.isDemoMode, isTrue);
      expect(demoReading.isHardwareMode, isFalse);
      expect(demoReading.status, equals("demo_ok"));
      expect(demoReading.mq2Value, equals(200.0));
      expect(demoReading.mq4Value, equals(100.0));
      // Demo mode retains synthetic 45% proportional estimation for simulation sessions
      expect(demoReading.mq7Value, equals(90.0)); // 200 * 0.45
      expect(demoReading.hasMissingTelemetry, isFalse); // Not flagged as missing because mode == 'demo'
    });
  });
}
