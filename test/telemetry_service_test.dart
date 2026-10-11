import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:railsafe_ai/models/sensor_reading.dart';
import 'package:railsafe_ai/services/auth_service.dart';
import 'package:railsafe_ai/services/local_storage_service.dart';
import 'package:railsafe_ai/services/telemetry_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthService extends AuthService {
  final String? _token;
  MockAuthService(super.storage, [this._token = "test-firebase-id-token"]);

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async => _token;
}

void main() {
  late LocalStorageService storage;
  late MockAuthService authService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.getInstance();
    authService = MockAuthService(storage);
  });

  group('TelemetryService API Unit Tests', () {
    test('postTelemetry sends single reading with Bearer token', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, equals('/api/telemetry'));
        expect(request.headers['Authorization'], equals('Bearer test-firebase-id-token'));
        expect(request.headers['Content-Type'], contains('application/json'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['deviceId'], equals('RAILSAFE-ESP32-01'));
        expect(body['sequence'], equals(1));

        return http.Response(
          jsonEncode({
            "status": "ok",
            "count": 1,
            "reading": body,
            "message": "Telemetry frame recorded",
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final reading = SensorReading.fromJson({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": 1500,
          "mq4_raw": 900,
          "mq7_raw": 450,
        },
      });

      final result = await service.postTelemetry(reading);
      expect(result['status'], equals('ok'));
      expect(result['count'], equals(1));
    });

    test('postTelemetryBatch sends multiple readings in single request', () async {
      final mockClient = MockClient((request) async {
        expect(request.method, equals('POST'));
        expect(request.url.path, equals('/api/telemetry'));

        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['readings'], isA<List>());
        expect((body['readings'] as List).length, equals(2));

        return http.Response(
          jsonEncode({
            "status": "ok",
            "count": 2,
            "message": "Batch ingested",
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final r1 = SensorReading.fromJson({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "sensors": {"mq2_raw": 1200},
      });
      final r2 = SensorReading.fromJson({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 2,
        "sensors": {"mq2_raw": 1300},
      });

      final result = await service.postTelemetryBatch([r1, r2]);
      expect(result['status'], equals('ok'));
      expect(result['count'], equals(2));
    });

    test('getLatestTelemetry parses latest reading and returns null on 404', () async {
      final mockClient = MockClient((request) async {
        if (request.url.queryParameters['device_id'] == 'RAILSAFE-ESP32-01') {
          return http.Response(
            jsonEncode({
              "status": "ok",
              "device_id": "RAILSAFE-ESP32-01",
              "reading": {
                "deviceId": "RAILSAFE-ESP32-01",
                "sequence": 99,
                "mode": "hardware",
                "sensors": {
                  "mq2_raw": 2100,
                  "mq4_raw": 1100,
                  "mq7_raw": 650,
                },
                "status": "ok",
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{"detail": "Not found"}', 404);
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final latest = await service.getLatestTelemetry('RAILSAFE-ESP32-01');
      expect(latest, isNotNull);
      expect(latest!.sequence, equals(99));
      expect(latest.mq2Value, equals(2100.0));

      final missing = await service.getLatestTelemetry('UNKNOWN-DEV');
      expect(missing, isNull);
    });

    test('getTelemetryHistory parses list of historical readings', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals('/api/telemetry'));
        expect(request.url.queryParameters['limit'], equals('10'));

        return http.Response(
          jsonEncode({
            "status": "ok",
            "device_id": "DEV-01",
            "count": 2,
            "readings": [
              {
                "deviceId": "DEV-01",
                "sequence": 2,
                "sensors": {"mq2_raw": 1500},
              },
              {
                "deviceId": "DEV-01",
                "sequence": 1,
                "sensors": {"mq2_raw": 1400},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final history = await service.getTelemetryHistory('DEV-01', limit: 10);
      expect(history.length, equals(2));
      expect(history.first.sequence, equals(2));
    });

    test('Handles 401 Unauthorized throwing TelemetryAuthException', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          '{"detail": "Missing authentication token."}',
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final reading = SensorReading.fromJson({
        "deviceId": "DEV",
        "sequence": 1,
        "sensors": {"mq2_raw": 100},
      });

      expect(
        () => service.postTelemetry(reading),
        throwsA(isA<TelemetryAuthException>()),
      );
    });

    test('Handles 500 Server Error throwing TelemetryApiException', () async {
      final mockClient = MockClient((request) async {
        return http.Response('{"detail": "Database unavailable"}', 500);
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final reading = SensorReading.fromJson({
        "deviceId": "DEV",
        "sequence": 1,
        "sensors": {"mq2_raw": 100},
      });

      expect(
        () => service.postTelemetry(reading),
        throwsA(isA<TelemetryApiException>()),
      );
    });
  });

  group('TelemetrySyncQueue Unit Tests', () {
    test('Enqueues readings and flushes batch when batchSize reached', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        return http.Response(
          jsonEncode({"status": "ok", "count": 2}),
          201,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = TelemetryService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final queue = TelemetrySyncQueue(
        telemetryService: service,
        batchSize: 2,
        flushInterval: const Duration(seconds: 10),
      );

      expect(queue.currentState.status, equals(TelemetrySyncStatus.idle));
      expect(queue.currentState.queuedCount, equals(0));

      final r1 = SensorReading.fromJson({"deviceId": "DEV-01", "sequence": 1, "sensors": {}});
      final r2 = SensorReading.fromJson({"deviceId": "DEV-01", "sequence": 2, "sensors": {}});

      queue.enqueue(r1);
      expect(queue.currentState.queuedCount, equals(1));

      // Adding 2nd reading hits batchSize (2) -> triggers flush
      queue.enqueue(r2);
      await Future.delayed(const Duration(milliseconds: 50));

      expect(requestCount, equals(1));
      expect(queue.currentState.queuedCount, equals(0));
      expect(queue.currentState.totalSyncedCount, equals(2));
      expect(queue.currentState.status, equals(TelemetrySyncStatus.synced));

      queue.dispose();
    });

    test('Deduplicates duplicate sequence readings from being enqueued twice', () async {
      final mockClient = MockClient((request) async => http.Response('{"status":"ok"}', 201));
      final service = TelemetryService(storage, authService: authService, client: mockClient);
      final queue = TelemetrySyncQueue(
        telemetryService: service,
        batchSize: 10,
        flushInterval: const Duration(seconds: 60),
      );

      final r1 = SensorReading.fromJson({"deviceId": "DEV-01", "sequence": 5, "sensors": {}});
      queue.enqueue(r1);
      queue.enqueue(r1); // Duplicate

      expect(queue.currentState.queuedCount, equals(1));
      queue.dispose();
    });

    test('Bridges offline state: retains queue and marks offlineQueued on network error', () async {
      bool shouldFail = true;
      final mockClient = MockClient((request) async {
        if (shouldFail) {
          throw http.ClientException("Connection refused");
        }
        return http.Response(jsonEncode({"status": "ok", "count": 1}), 201);
      });

      final service = TelemetryService(storage, authService: authService, client: mockClient);
      final queue = TelemetrySyncQueue(
        telemetryService: service,
        batchSize: 1,
        flushInterval: const Duration(seconds: 60),
      );

      final reading = SensorReading.fromJson({"deviceId": "DEV-01", "sequence": 1, "sensors": {}});
      queue.enqueue(reading);
      await Future.delayed(const Duration(milliseconds: 50));

      // Failed -> items retained, status is offlineQueued
      expect(queue.currentState.status, equals(TelemetrySyncStatus.offlineQueued));
      expect(queue.currentState.queuedCount, equals(1));

      // Recover network and retryNow()
      shouldFail = false;
      await queue.retryNow();

      expect(queue.currentState.status, equals(TelemetrySyncStatus.synced));
      expect(queue.currentState.queuedCount, equals(0));
      expect(queue.currentState.totalSyncedCount, equals(1));

      queue.dispose();
    });

    test('Bounded queue drops oldest when maxQueueSize is exceeded', () async {
      final mockClient = MockClient((request) async => http.Response('{"status":"ok"}', 201));
      final service = TelemetryService(storage, authService: authService, client: mockClient);
      final queue = TelemetrySyncQueue(
        telemetryService: service,
        maxQueueSize: 3,
        batchSize: 10,
        flushInterval: const Duration(seconds: 60),
      );

      for (int i = 1; i <= 5; i++) {
        queue.enqueue(SensorReading.fromJson({
          "deviceId": "DEV-01",
          "sequence": i,
          "sensors": {},
        }));
      }

      // Max queue size is 3 -> queue length stays 3
      expect(queue.currentState.queuedCount, equals(3));
      queue.dispose();
    });
  });

  group('Physical vs Demo Sensor Semantics Tests', () {
    test('Hardware mode: missing MQ-7 is marked as missing and null (never fabricated)', () {
      final reading = SensorReading.fromJson({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 1,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": 1200,
          "mq4_raw": 800,
        },
      });

      expect(reading.isHardwareMode, isTrue);
      expect(reading.hasMissingTelemetry, isTrue);
      expect(reading.missingChannels, contains('mq7_raw'));
      expect(reading.mq7Value, isNull); // Never fabricated as 0
    });

    test('Hardware mode: measured zero ADC count is preserved as 0.0, not null', () {
      final reading = SensorReading.fromJson({
        "deviceId": "RAILSAFE-ESP32-01",
        "sequence": 2,
        "mode": "hardware",
        "sensors": {
          "mq2_raw": 0,
          "mq4_raw": 0.0,
          "mq7_raw": 0,
        },
      });

      expect(reading.isHardwareMode, isTrue);
      expect(reading.hasMissingTelemetry, isFalse);
      expect(reading.mq2Value, equals(0.0));
      expect(reading.mq4Value, equals(0.0));
      expect(reading.mq7Value, equals(0.0));
    });
  });
}
