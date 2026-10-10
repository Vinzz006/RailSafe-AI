import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:railsafe_ai/core/constants/app_constants.dart';
import 'package:railsafe_ai/models/app_alert.dart';
import 'package:railsafe_ai/services/auth_service.dart';
import 'package:railsafe_ai/services/local_storage_service.dart';
import 'package:railsafe_ai/services/railguard_api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestMockAuthService extends AuthService {
  String? mockToken;

  TestMockAuthService(super.storage, {this.mockToken = "test-firebase-id-token"});

  @override
  Future<String?> getIdToken({bool forceRefresh = false}) async {
    return mockToken;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.getInstance();
  });

  group('RailGuard Production Base URL Configuration', () {
    test('Default base URL matches exact Render production address', () {
      expect(
        RailGuardApiService.defaultBaseUrl,
        equals("https://railsafe-ai-backend.onrender.com"),
      );
      expect(
        AppConstants.defaultRailGuardBackendUrl,
        equals("https://railsafe-ai-backend.onrender.com"),
      );

      final service = RailGuardApiService(storage);
      expect(service.baseUrl, equals("https://railsafe-ai-backend.onrender.com"));
      // Ensure no trailing slash or /health appended to baseUrl
      expect(service.baseUrl.endsWith('/'), isFalse);
      expect(service.baseUrl.endsWith('/health'), isFalse);
    });

    test('Custom URL normalizes trailing slashes properly', () async {
      await storage.setRailGuardBackendUrl("https://railsafe-ai-backend.onrender.com///");
      final service = RailGuardApiService(storage);
      expect(service.baseUrl, equals("https://railsafe-ai-backend.onrender.com"));
    });
  });

  group('Firebase ID Token Authentication & Request Headers', () {
    test('Attaches Authorization Bearer token from signed-in user and JSON headers', () async {
      String? capturedAuthHeader;
      String? capturedAccept;
      String? capturedContentType;

      final mockClient = MockClient((request) async {
        capturedAuthHeader = request.headers['Authorization'];
        capturedAccept = request.headers['Accept'];
        capturedContentType = request.headers['Content-Type'];

        return http.Response(jsonEncode([]), 200);
      });

      final authService = TestMockAuthService(
        storage,
        mockToken: "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.dummy_token_payload",
      );

      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final alerts = await service.getAlerts();
      expect(alerts, isEmpty);
      expect(
        capturedAuthHeader,
        equals("Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.dummy_token_payload"),
      );
      expect(capturedAccept, equals("application/json"));
      expect(capturedContentType, equals("application/json"));
    });

    test('Rejects request with clear exception when user is signed out (null token)', () async {
      final mockClient = MockClient((request) async => http.Response("[]", 200));
      final authService = TestMockAuthService(storage, mockToken: null);

      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.getAlerts(),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains("User is not signed in"),
          ),
        ),
      );
    });

    test('Rejects request when user token is empty whitespace', () async {
      final mockClient = MockClient((request) async => http.Response("[]", 200));
      final authService = TestMockAuthService(storage, mockToken: "   ");

      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.getAlerts(),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains("User is not signed in"),
          ),
        ),
      );
    });
  });

  group('HTTP Error & Status Handling', () {
    test('Handles HTTP 401 Unauthorized with session expired message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({"detail": "Token expired or invalid"}),
          401,
        );
      });

      final authService = TestMockAuthService(storage, mockToken: "expired-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.getAlerts(),
        throwsA(
          predicate(
            (e) =>
                e is Exception &&
                e.toString().contains("Session expired or unauthorized (HTTP 401)"),
          ),
        ),
      );
    });

    test('Handles HTTP 403 Forbidden with permissions message', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({"detail": "Forbidden: Non-operator role"}),
          403,
        );
      });

      final authService = TestMockAuthService(storage, mockToken: "limited-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.getAlerts(),
        throwsA(
          predicate(
            (e) =>
                e is RailGuardForbiddenException &&
                e.message.contains("Forbidden (HTTP 403)"),
          ),
        ),
      );
    });

    test('Handles HTTP 500 Server Error throwing RailGuardServerException without masking as empty', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({"detail": "Failed to retrieve alerts from persistence layer."}),
          500,
        );
      });

      final authService = TestMockAuthService(storage, mockToken: "valid-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.getAlerts(),
        throwsA(
          predicate(
            (e) =>
                e is RailGuardServerException &&
                e.statusCode == 500 &&
                e.message.contains("Backend server error (HTTP 500)"),
          ),
        ),
      );
    });

    test('Handles TimeoutException throwing RailGuardTimeoutException with retry guidance', () async {
      final mockClient = MockClient((request) async {
        throw TimeoutException("Future not completed within timeout");
      });

      final authService = TestMockAuthService(storage, mockToken: "valid-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.getAlerts(),
        throwsA(
          predicate(
            (e) =>
                e is RailGuardTimeoutException &&
                e.message.contains("Connection timed out"),
          ),
        ),
      );
    });

    test('Successful empty response returns empty list without error', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode([]), 200);
      });

      final authService = TestMockAuthService(storage, mockToken: "valid-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final alerts = await service.getAlerts();
      expect(alerts, isEmpty);
    });
  });

  group('Alert Listing & Filtering Endpoints', () {
    test('Successfully parses alert listing and formats query parameters', () async {
      late Uri capturedUri;

      final mockClient = MockClient((request) async {
        capturedUri = request.url;
        final sampleAlerts = [
          {
            "id": "alert-evt-101",
            "event_uid": "evt-101",
            "timestamp": "2026-10-11T04:00:00Z",
            "camera_id": "CAM-PLATFORM-02",
            "track_id": 14,
            "object_class": "suitcase",
            "event_duration": 18.5,
            "reason": "Unattended bag detected for 18.5s",
            "snapshot_url": "/api/alerts/evt-101/snapshot",
            "clip_url": "/api/alerts/evt-101/clip",
            "review_status": "unreviewed",
            "reviewed_by": null,
            "reviewed_at": null,
            "cleared_timestamp": null,
            "disclaimer": "FOR HUMAN REVIEW ONLY",
          }
        ];
        return http.Response(jsonEncode(sampleAlerts), 200);
      });

      final authService = TestMockAuthService(storage);
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final alerts = await service.getAlerts(
        limit: 25,
        unreviewedOnly: true,
        status: "unreviewed",
      );

      expect(alerts.length, equals(1));
      expect(alerts.first.id, equals("alert-evt-101"));
      expect(alerts.first.eventUid, equals("evt-101"));
      expect(alerts.first.cameraId, equals("CAM-PLATFORM-02"));
      expect(alerts.first.trackId, equals(14));
      expect(alerts.first.objectClass, equals("suitcase"));
      expect(alerts.first.eventDuration, equals(18.5));
      expect(alerts.first.isUnreviewed, isTrue);
      expect(alerts.first.isVerified, isFalse);

      expect(capturedUri.queryParameters['limit'], equals("25"));
      expect(capturedUri.queryParameters['unreviewed_only'], equals("true"));
      expect(capturedUri.queryParameters['status'], equals("unreviewed"));
    });

    test('Retrieves single alert detail via GET /api/alerts/{id}', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals("/api/alerts/evt-200"));
        final sample = {
          "id": "evt-200",
          "event_uid": "evt-200",
          "timestamp": "2026-10-11T04:10:00Z",
          "camera_id": "CAM-01",
          "track_id": 5,
          "object_class": "backpack",
          "event_duration": 12.0,
          "reason": "Unattended backpack condition",
          "snapshot_url": "/api/alerts/evt-200/snapshot",
          "review_status": "verified",
          "reviewed_by": "operator-007",
        };
        return http.Response(jsonEncode(sample), 200);
      });

      final authService = TestMockAuthService(storage);
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final detail = await service.getAlertDetail("evt-200");
      expect(detail.eventUid, equals("evt-200"));
      expect(detail.isVerified, isTrue);
      expect(detail.reviewedBy, equals("operator-007"));
    });
  });

  group('Operator Review Submissions', () {
    test('Submits PATCH /api/alerts/{id}/review with valid review_status', () async {
      late String capturedBody;
      late String capturedMethod;

      final mockClient = MockClient((request) async {
        capturedMethod = request.method;
        capturedBody = request.body;
        final responseData = {
          "id": "evt-300",
          "event_uid": "evt-300",
          "timestamp": "2026-10-11T04:15:00Z",
          "camera_id": "CAM-03",
          "track_id": 8,
          "object_class": "trolley",
          "event_duration": 22.4,
          "reason": "Unattended trolley on platform",
          "snapshot_url": "/api/alerts/evt-300/snapshot",
          "review_status": "verified",
          "reviewed_by": "operator-uid-123",
          "reviewed_at": "2026-10-11T04:16:00Z",
        };
        return http.Response(jsonEncode(responseData), 200);
      });

      final authService = TestMockAuthService(storage);
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final result = await service.reviewAlert("evt-300", "verified");
      expect(capturedMethod, equals("PATCH"));
      final bodyMap = jsonDecode(capturedBody) as Map<String, dynamic>;
      expect(bodyMap["review_status"], equals("verified"));
      expect(result.reviewStatus, equals("verified"));
      expect(result.isVerified, isTrue);
    });

    test('Rejects invalid review_status locally before sending HTTP request', () async {
      final mockClient = MockClient((request) async => http.Response("{}", 200));
      final authService = TestMockAuthService(storage);
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      expect(
        () async => await service.reviewAlert("evt-300", "invalid_status"),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('Evidence Fetching & URLs', () {
    test('Generates authorized snapshot URL with URL-encoded token query parameter', () async {
      final authService = TestMockAuthService(storage, mockToken: "secret/token+sample");
      final service = RailGuardApiService(storage, authService: authService);

      final url = await service.getSnapshotUrl("evt-555");
      expect(
        url,
        contains("https://railsafe-ai-backend.onrender.com/api/alerts/evt-555/snapshot?token="),
      );
      expect(url, contains(Uri.encodeComponent("secret/token+sample")));
    });

    test('Generates authorized video clip URL with token', () async {
      final authService = TestMockAuthService(storage, mockToken: "clip-token");
      final service = RailGuardApiService(storage, authService: authService);

      final url = await service.getClipUrl("evt-555");
      expect(
        url,
        equals("https://railsafe-ai-backend.onrender.com/api/alerts/evt-555/clip?token=clip-token"),
      );
    });

    test('fetchSnapshotBytes fetches bytes with Bearer ID token in header', () async {
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
      String? sentAuth;

      final mockClient = MockClient((request) async {
        sentAuth = request.headers['Authorization'];
        return http.Response.bytes(fakeBytes, 200, headers: {'content-type': 'image/jpeg'});
      });

      final authService = TestMockAuthService(storage, mockToken: "secure-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final bytes = await service.fetchSnapshotBytes("evt-666");
      expect(bytes, equals(fakeBytes));
      expect(sentAuth, equals("Bearer secure-token"));
    });
  });

  group('Diagnostics & False Alarm Statistics', () {
    test('checkHealth performs unauthenticated GET /health', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals("/health"));
        expect(request.headers.containsKey("Authorization"), isFalse);
        return http.Response(
          jsonEncode({
            "status": "healthy",
            "service": "RailGuard Vision Cloud Backend",
            "version": "1.0.0",
            "persistence": "Cloud Firestore",
            "disclaimer": "FOR HUMAN REVIEW ONLY",
          }),
          200,
        );
      });

      final service = RailGuardApiService(storage, client: mockClient);
      final health = await service.checkHealth();

      expect(health["success"], isTrue);
      expect(health["status"], equals("healthy"));
      expect(health["persistence"], equals("Cloud Firestore"));
    });

    test('checkReadiness performs GET /ready', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals("/ready"));
        return http.Response(
          jsonEncode({
            "status": "ready",
            "firestore_connected": true,
            "project_id": "railsafe-ai-92d9f",
            "collection": "railguard_alerts",
          }),
          200,
        );
      });

      final service = RailGuardApiService(storage, client: mockClient);
      final ready = await service.checkReadiness();

      expect(ready["ready"], isTrue);
      expect(ready["firestore_connected"], isTrue);
      expect(ready["project_id"], equals("railsafe-ai-92d9f"));
    });

    test('getFalseAlarmRate queries /api/alerts/stats/false-alarm-rate with auth', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, equals("/api/alerts/stats/false-alarm-rate"));
        expect(request.headers["Authorization"], equals("Bearer stats-token"));
        return http.Response(
          jsonEncode({
            "false_alarm_rate": 0.25,
            "total_reviewed": 20,
            "false_alarms": 5,
          }),
          200,
        );
      });

      final authService = TestMockAuthService(storage, mockToken: "stats-token");
      final service = RailGuardApiService(
        storage,
        authService: authService,
        client: mockClient,
      );

      final stats = await service.getFalseAlarmRate();
      expect(stats["false_alarm_rate"], equals(0.25));
      expect(stats["total_reviewed"], equals(20));
      expect(stats["false_alarms"], equals(5));
    });
  });

  group('Safe Model Parsing Resilience', () {
    test('Handles nulls, stringified numbers, and missing fields safely without crashing', () {
      final raw = {
        "id": null,
        "event_uid": "safe-uid-99",
        "timestamp": "invalid-date",
        "camera_id": null,
        "track_id": "123",
        "object_class": null,
        "event_duration": "45.6",
        "reason": null,
        "snapshot_url": null,
        "clip_url": null,
        "review_status": null,
        "reviewed_by": null,
        "cleared_timestamp": null,
      };

      final model = RailGuardAlertModel.fromJson(raw);

      expect(model.eventUid, equals("safe-uid-99"));
      expect(model.cameraId, equals("CAM-01"));
      expect(model.trackId, equals(123));
      expect(model.objectClass, equals("luggage"));
      expect(model.eventDuration, equals(45.6));
      expect(model.reviewStatus, equals("unreviewed"));
      expect(model.isUnreviewed, isTrue);
      expect(model.isCleared, isFalse);
    });

    test('toAppAlert converts model to AppAlert with proper severity', () {
      final verifiedAlert = RailGuardAlertModel(
        id: "v-1",
        eventUid: "v-1",
        timestamp: DateTime.now(),
        cameraId: "CAM-01",
        trackId: 1,
        objectClass: "bag",
        eventDuration: 10.0,
        reason: "Unattended bag",
        snapshotUrl: "/snap",
        reviewStatus: "verified",
      );

      final appAlert = verifiedAlert.toAppAlert();
      expect(appAlert.severity, equals(AlertSeverity.danger));
      expect(appAlert.title, contains("Luggage Alert"));

      final falseAlarm = verifiedAlert.copyWith(reviewStatus: "false_alarm");
      expect(falseAlarm.toAppAlert().severity, equals(AlertSeverity.info));
    });
  });
}
