import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';
import '../models/app_alert.dart';
import 'auth_service.dart';
import 'local_storage_service.dart';

/// Specific exception types for RailGuard Vision API interactions
class RailGuardApiException implements Exception {
  final String message;
  final int? statusCode;
  RailGuardApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class RailGuardTimeoutException extends RailGuardApiException {
  RailGuardTimeoutException(super.message);
}

class RailGuardAuthException extends RailGuardApiException {
  RailGuardAuthException(super.message, [super.statusCode = 401]);
}

class RailGuardForbiddenException extends RailGuardApiException {
  RailGuardForbiddenException(super.message, [super.statusCode = 403]);
}

class RailGuardServerException extends RailGuardApiException {
  RailGuardServerException(super.message, [super.statusCode = 500]);
}

class RailGuardNetworkException extends RailGuardApiException {
  RailGuardNetworkException(super.message);
}

class RailGuardFormatException extends RailGuardApiException {
  RailGuardFormatException(super.message);
}

/// Represents an unattended luggage alert returned by the RailGuard Vision API.
class RailGuardAlertModel {
  final dynamic id;
  final String eventUid;
  final DateTime timestamp;
  final String cameraId;
  final int trackId;
  final String objectClass;
  final double eventDuration;
  final String reason;
  final String snapshotUrl;
  final String? clipUrl;
  final String reviewStatus; // 'unreviewed', 'verified', 'false_alarm'
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final DateTime? clearedTimestamp;
  final DateTime? createdAt;
  final String disclaimer;

  RailGuardAlertModel({
    required this.id,
    required this.eventUid,
    required this.timestamp,
    required this.cameraId,
    required this.trackId,
    required this.objectClass,
    required this.eventDuration,
    required this.reason,
    required this.snapshotUrl,
    this.clipUrl,
    required this.reviewStatus,
    this.reviewedBy,
    this.reviewedAt,
    this.clearedTimestamp,
    this.createdAt,
    this.disclaimer =
        "FOR HUMAN REVIEW ONLY — Does not detect explosives or narcotics. Verify physical context.",
  });

  bool get isReviewed => reviewStatus == 'verified' || reviewStatus == 'false_alarm';
  bool get isVerified => reviewStatus == 'verified';
  bool get isFalseAlarm => reviewStatus == 'false_alarm';
  bool get isUnreviewed => reviewStatus == 'unreviewed';
  bool get isCleared => clearedTimestamp != null;

  factory RailGuardAlertModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['event_uid'] ?? 0;
    final uid = json['event_uid']?.toString() ?? rawId.toString();

    DateTime parsedTimestamp;
    if (json['timestamp'] != null) {
      parsedTimestamp = DateTime.tryParse(json['timestamp'].toString()) ?? DateTime.now();
    } else {
      parsedTimestamp = DateTime.now();
    }

    int parsedTrackId = 0;
    if (json['track_id'] is int) {
      parsedTrackId = json['track_id'] as int;
    } else if (json['track_id'] != null) {
      parsedTrackId = int.tryParse(json['track_id'].toString()) ?? 0;
    }

    double parsedDuration = 0.0;
    if (json['event_duration'] is num) {
      parsedDuration = (json['event_duration'] as num).toDouble();
    } else if (json['event_duration'] != null) {
      parsedDuration = double.tryParse(json['event_duration'].toString()) ?? 0.0;
    }

    DateTime? parsedReviewedAt;
    if (json['reviewed_at'] != null) {
      parsedReviewedAt = DateTime.tryParse(json['reviewed_at'].toString());
    }

    DateTime? parsedCleared;
    if (json['cleared_timestamp'] != null) {
      parsedCleared = DateTime.tryParse(json['cleared_timestamp'].toString());
    }

    DateTime? parsedCreated;
    if (json['created_at'] != null) {
      parsedCreated = DateTime.tryParse(json['created_at'].toString());
    }

    return RailGuardAlertModel(
      id: rawId,
      eventUid: uid,
      timestamp: parsedTimestamp,
      cameraId: json['camera_id']?.toString() ?? 'CAM-01',
      trackId: parsedTrackId,
      objectClass: json['object_class']?.toString() ?? 'luggage',
      eventDuration: parsedDuration,
      reason: json['reason']?.toString() ?? 'Unattended object condition',
      snapshotUrl: json['snapshot_url']?.toString() ?? '/api/alerts/$uid/snapshot',
      clipUrl: json['clip_url']?.toString(),
      reviewStatus: json['review_status']?.toString() ?? 'unreviewed',
      reviewedBy: json['reviewed_by']?.toString(),
      reviewedAt: parsedReviewedAt,
      clearedTimestamp: parsedCleared,
      createdAt: parsedCreated,
      disclaimer: json['disclaimer']?.toString() ??
          "FOR HUMAN REVIEW ONLY — Does not detect explosives or narcotics. Verify physical context.",
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_uid': eventUid,
      'timestamp': timestamp.toIso8601String(),
      'camera_id': cameraId,
      'track_id': trackId,
      'object_class': objectClass,
      'event_duration': eventDuration,
      'reason': reason,
      'snapshot_url': snapshotUrl,
      'clip_url': clipUrl,
      'review_status': reviewStatus,
      'reviewed_by': reviewedBy,
      'reviewed_at': reviewedAt?.toIso8601String(),
      'cleared_timestamp': clearedTimestamp?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'disclaimer': disclaimer,
    };
  }

  RailGuardAlertModel copyWith({
    dynamic id,
    String? eventUid,
    DateTime? timestamp,
    String? cameraId,
    int? trackId,
    String? objectClass,
    double? eventDuration,
    String? reason,
    String? snapshotUrl,
    String? clipUrl,
    String? reviewStatus,
    String? reviewedBy,
    DateTime? reviewedAt,
    DateTime? clearedTimestamp,
    DateTime? createdAt,
    String? disclaimer,
  }) {
    return RailGuardAlertModel(
      id: id ?? this.id,
      eventUid: eventUid ?? this.eventUid,
      timestamp: timestamp ?? this.timestamp,
      cameraId: cameraId ?? this.cameraId,
      trackId: trackId ?? this.trackId,
      objectClass: objectClass ?? this.objectClass,
      eventDuration: eventDuration ?? this.eventDuration,
      reason: reason ?? this.reason,
      snapshotUrl: snapshotUrl ?? this.snapshotUrl,
      clipUrl: clipUrl ?? this.clipUrl,
      reviewStatus: reviewStatus ?? this.reviewStatus,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      clearedTimestamp: clearedTimestamp ?? this.clearedTimestamp,
      createdAt: createdAt ?? this.createdAt,
      disclaimer: disclaimer ?? this.disclaimer,
    );
  }

  /// Converts this vision alert into an AppAlert for display in alerts UI.
  AppAlert toAppAlert() {
    AlertSeverity sev = AlertSeverity.warning;
    if (reviewStatus == 'false_alarm') {
      sev = AlertSeverity.info;
    } else if (reviewStatus == 'verified') {
      sev = AlertSeverity.danger;
    }

    return AppAlert(
      id: "RG-$id",
      type: "vision_unattended_bag",
      title: "Luggage Alert: $objectClass (#$trackId)",
      message:
          "$reason on $cameraId. Duration: ${eventDuration.toStringAsFixed(1)}s. (FOR HUMAN REVIEW ONLY)",
      severity: sev,
      timestamp: timestamp,
      relatedTestId: cameraId,
    );
  }
}

/// Service client for connecting Flutter to Render-hosted RailGuard Vision API.
class RailGuardApiService {
  final LocalStorageService _storage;
  final AuthService? _authService;
  final http.Client _client;

  /// Configurable request timeout accommodating Render Free tier wake-up latency (~30-40s)
  final Duration requestTimeout;

  RailGuardApiService(
    this._storage, {
    this._authService,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 35),
  })  : _client = client ?? http.Client();

  /// Default production Render URL as single source of truth
  static const String defaultBaseUrl = AppConstants.defaultRailGuardBackendUrl;

  /// Dynamic base URL with centralized fallback to Render
  String get baseUrl {
    final custom = _storage.getRailGuardBackendUrl().trim();
    if (custom.isNotEmpty) {
      return custom.replaceAll(RegExp(r'/+$'), '');
    }
    return defaultBaseUrl;
  }

  /// Builds authenticated headers attaching the real Firebase ID Token
  Future<Map<String, String>> _buildHeaders([String? token]) async {
    String? effectiveToken = token;
    if (effectiveToken == null && _authService != null) {
      effectiveToken = await _authService.getIdToken();
    }

    if (effectiveToken == null || effectiveToken.trim().isEmpty) {
      throw RailGuardAuthException(
        "User is not signed in. Please sign in with Firebase to access operator endpoints.",
        401,
      );
    }

    return {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Authorization": "Bearer ${effectiveToken.trim()}",
    };
  }

  /// Check backend liveness and storage status: GET /health
  Future<Map<String, dynamic>> checkHealth({String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/health");

    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return {
          "success": true,
          "status": decoded["status"],
          "version": decoded["version"],
          "persistence": decoded["persistence"] ?? "Cloud Firestore",
          "disclaimer": decoded["disclaimer"],
        };
      }
      return {
        "success": false,
        "message": "HTTP ${res.statusCode}: ${res.body}",
      };
    } on TimeoutException {
      return {"success": false, "message": "Connection timed out to $target (server waking up?)"};
    } on SocketException catch (e) {
      return {"success": false, "message": "Socket error: ${e.message}"};
    } catch (e) {
      return {"success": false, "message": "Unexpected error: $e"};
    }
  }

  /// Check database and dependency readiness: GET /ready
  Future<Map<String, dynamic>> checkReadiness({String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/ready");

    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return {
          "ready": true,
          "firestore_connected": decoded["firestore_connected"] == true,
          "project_id": decoded["project_id"],
          "collection": decoded["collection"],
        };
      }
      return {
        "ready": false,
        "status_code": res.statusCode,
        "message": res.body,
      };
    } catch (e) {
      return {"ready": false, "error": e.toString()};
    }
  }

  /// Retrieve active or unreviewed unattended luggage alerts: GET /api/alerts
  Future<List<RailGuardAlertModel>> getAlerts({
    int limit = 50,
    bool unreviewedOnly = false,
    String? status,
    String? overrideUrl,
    Duration? customTimeout,
  }) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final queryParams = <String, String>{
      "limit": limit.toString(),
      if (unreviewedOnly) "unreviewed_only": "true",
    };
    if (status != null && status.isNotEmpty && status.toLowerCase() != 'all') {
      queryParams["status"] = status;
    }

    final uri = Uri.parse("$target/api/alerts").replace(queryParameters: queryParams);
    final headers = await _buildHeaders();
    final effectiveTimeout = customTimeout ?? requestTimeout;

    try {
      final res = await _client.get(uri, headers: headers).timeout(effectiveTimeout);

      if (res.statusCode == 200) {
        try {
          final list = jsonDecode(res.body) as List<dynamic>;
          return list
              .map((item) => RailGuardAlertModel.fromJson(item as Map<String, dynamic>))
              .toList();
        } catch (e) {
          throw RailGuardFormatException("Malformed response parsing alerts: $e");
        }
      } else if (res.statusCode == 401) {
        throw RailGuardAuthException(
          "Session expired or unauthorized (HTTP 401). Please sign in again.",
          401,
        );
      } else if (res.statusCode == 403) {
        throw RailGuardForbiddenException(
          "Forbidden (HTTP 403). You do not have permission to view alerts.",
          403,
        );
      } else if (res.statusCode >= 500) {
        throw RailGuardServerException(
          "Backend server error (HTTP ${res.statusCode}). Service may be waking up or experiencing issues.",
          res.statusCode,
        );
      } else {
        throw RailGuardApiException("Failed to load alerts: HTTP ${res.statusCode}", res.statusCode);
      }
    } on TimeoutException {
      throw RailGuardTimeoutException(
        "Connection timed out (${effectiveTimeout.inSeconds}s). Render server may be waking up from idle. Please tap Retry.",
      );
    } on SocketException catch (e) {
      throw RailGuardNetworkException("Network error connecting to backend: ${e.message}");
    } on http.ClientException catch (e) {
      throw RailGuardNetworkException("Connection failed: ${e.message}");
    }
  }

  /// Retrieve single alert details: GET /api/alerts/{id}
  Future<RailGuardAlertModel> getAlertDetail(
    dynamic alertId, {
    String? overrideUrl,
  }) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/$alertId");
    final headers = await _buildHeaders();

    try {
      final res = await _client.get(uri, headers: headers).timeout(requestTimeout);

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return RailGuardAlertModel.fromJson(decoded);
      } else if (res.statusCode == 401) {
        throw RailGuardAuthException("Session expired or unauthorized (HTTP 401). Please sign in again.");
      } else if (res.statusCode == 403) {
        throw RailGuardForbiddenException("Forbidden (HTTP 403). You do not have permission to view this alert.");
      } else if (res.statusCode == 404) {
        throw RailGuardApiException("Alert not found (HTTP 404).", 404);
      } else if (res.statusCode >= 500) {
        throw RailGuardServerException("Backend server error (HTTP ${res.statusCode}).");
      } else {
        throw RailGuardApiException("Failed to load alert details: HTTP ${res.statusCode}", res.statusCode);
      }
    } on TimeoutException {
      throw RailGuardTimeoutException("Connection timed out loading alert details.");
    } on SocketException catch (e) {
      throw RailGuardNetworkException("Network error: ${e.message}");
    }
  }

  /// Submit operator review: PATCH /api/alerts/{id}/review
  Future<RailGuardAlertModel> reviewAlert(
    dynamic alertId,
    String reviewStatus, {
    String? overrideUrl,
  }) async {
    if (reviewStatus != 'verified' && reviewStatus != 'false_alarm') {
      throw ArgumentError(
        "Invalid reviewStatus '$reviewStatus'. Must be either 'verified' or 'false_alarm'.",
      );
    }

    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/$alertId/review");

    final payload = jsonEncode({"review_status": reviewStatus});
    final headers = await _buildHeaders();

    try {
      final res = await _client.patch(uri, headers: headers, body: payload).timeout(requestTimeout);

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return RailGuardAlertModel.fromJson(decoded);
      } else if (res.statusCode == 401) {
        throw RailGuardAuthException("Session expired or unauthorized (HTTP 401). Please sign in again.");
      } else if (res.statusCode == 403) {
        throw RailGuardForbiddenException("Forbidden (HTTP 403). You do not have permission to submit reviews.");
      } else if (res.statusCode == 404) {
        throw RailGuardApiException("Alert not found (HTTP 404).", 404);
      } else if (res.statusCode >= 500) {
        throw RailGuardServerException("Backend server error (HTTP ${res.statusCode}).");
      } else {
        throw RailGuardApiException("Failed to update review status: HTTP ${res.statusCode}", res.statusCode);
      }
    } on TimeoutException {
      throw RailGuardTimeoutException("Connection timed out submitting review. Please retry.");
    } on SocketException catch (e) {
      throw RailGuardNetworkException("Network error submitting review: ${e.message}");
    }
  }

  /// Formats direct URL to fetch snapshot JPEG image with authorization query parameter
  Future<String> getSnapshotUrl(dynamic alertId, {String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final token = await _authService?.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw RailGuardAuthException("User is not signed in. Cannot generate evidence URL.");
    }
    return "$target/api/alerts/$alertId/snapshot?token=${Uri.encodeComponent(token.trim())}";
  }

  /// Formats direct URL to stream context MP4 video clip with authorization query parameter
  Future<String> getClipUrl(dynamic alertId, {String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final token = await _authService?.getIdToken();
    if (token == null || token.trim().isEmpty) {
      throw RailGuardAuthException("User is not signed in. Cannot generate video clip URL.");
    }
    return "$target/api/alerts/$alertId/clip?token=${Uri.encodeComponent(token.trim())}";
  }

  /// Fetches raw snapshot JPEG bytes with Bearer ID Token in authorization header
  Future<Uint8List> fetchSnapshotBytes(dynamic alertId, {String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/$alertId/snapshot");
    final headers = await _buildHeaders();

    try {
      final res = await _client.get(uri, headers: headers).timeout(requestTimeout);
      if (res.statusCode == 200) {
        return res.bodyBytes;
      } else if (res.statusCode == 401) {
        throw RailGuardAuthException("Unauthorized (HTTP 401): Session expired.");
      } else if (res.statusCode == 403) {
        throw RailGuardForbiddenException("Forbidden (HTTP 403): Insufficient permissions.");
      } else if (res.statusCode == 404) {
        throw RailGuardApiException("Snapshot not found (HTTP 404).", 404);
      } else if (res.statusCode >= 500) {
        throw RailGuardServerException("Backend server error loading snapshot: HTTP ${res.statusCode}");
      } else {
        throw RailGuardApiException("Failed to load snapshot: HTTP ${res.statusCode}", res.statusCode);
      }
    } on TimeoutException {
      throw RailGuardTimeoutException("Connection timed out loading snapshot image.");
    } on SocketException catch (e) {
      throw RailGuardNetworkException("Network error loading snapshot: ${e.message}");
    }
  }

  /// Fetches raw video clip bytes with Bearer ID Token in authorization header
  Future<Uint8List?> fetchClipBytes(dynamic alertId, {String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/$alertId/clip");
    final headers = await _buildHeaders();

    try {
      final res = await _client.get(uri, headers: headers).timeout(requestTimeout);
      if (res.statusCode == 200) {
        return res.bodyBytes;
      } else if (res.statusCode == 404) {
        return null;
      } else if (res.statusCode == 401) {
        throw RailGuardAuthException("Unauthorized (HTTP 401): Session expired.");
      } else {
        throw RailGuardApiException("Failed to stream video clip: HTTP ${res.statusCode}", res.statusCode);
      }
    } on TimeoutException {
      throw RailGuardTimeoutException("Connection timed out loading video clip.");
    } on SocketException catch (e) {
      throw RailGuardNetworkException("Network error loading clip: ${e.message}");
    }
  }

  /// Retrieve running false alarm rate: GET /api/alerts/stats/false-alarm-rate
  Future<Map<String, dynamic>> getFalseAlarmRate({String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/stats/false-alarm-rate");
    final headers = await _buildHeaders();

    try {
      final res = await _client.get(uri, headers: headers).timeout(requestTimeout);
      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      } else if (res.statusCode == 401) {
        throw RailGuardAuthException("Session expired or unauthorized (HTTP 401). Please sign in again.");
      }
      return {"false_alarm_rate": null, "total_reviewed": 0, "false_alarms": 0};
    } catch (_) {
      return {"false_alarm_rate": null, "total_reviewed": 0, "false_alarms": 0};
    }
  }

  void dispose() {
    _client.close();
  }
}
