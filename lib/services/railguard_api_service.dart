import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/app_alert.dart';
import 'auth_service.dart';
import 'local_storage_service.dart';

/// Represents an unattended luggage alert returned by the RailGuard Vision API.
class RailGuardAlertModel {
  final dynamic id;
  final String? eventUid;
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
  final DateTime? clearedTimestamp;
  final String disclaimer;

  RailGuardAlertModel({
    required this.id,
    this.eventUid,
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
    this.clearedTimestamp,
    this.disclaimer = "FOR HUMAN REVIEW ONLY — Does not detect explosives or narcotics.",
  });

  factory RailGuardAlertModel.fromJson(Map<String, dynamic> json) {
    return RailGuardAlertModel(
      id: json['id'] ?? json['event_uid'] ?? 0,
      eventUid: json['event_uid']?.toString(),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      cameraId: json['camera_id']?.toString() ?? 'CAM-01',
      trackId: json['track_id'] is int ? json['track_id'] : int.tryParse(json['track_id'].toString()) ?? 0,
      objectClass: json['object_class']?.toString() ?? 'luggage',
      eventDuration: (json['event_duration'] is num) ? (json['event_duration'] as num).toDouble() : 0.0,
      reason: json['reason']?.toString() ?? 'Unattended object condition',
      snapshotUrl: json['snapshot_url']?.toString() ?? '',
      clipUrl: json['clip_url']?.toString(),
      reviewStatus: json['review_status']?.toString() ?? 'unreviewed',
      reviewedBy: json['reviewed_by']?.toString(),
      clearedTimestamp: json['cleared_timestamp'] != null
          ? DateTime.tryParse(json['cleared_timestamp'].toString())
          : null,
      disclaimer: json['disclaimer']?.toString() ?? "FOR HUMAN REVIEW ONLY",
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
      message: "$reason on $cameraId. Duration: ${eventDuration.toStringAsFixed(1)}s. (FOR HUMAN REVIEW ONLY)",
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

  RailGuardApiService(this._storage, {AuthService? authService, http.Client? client})
      : _authService = authService,
        _client = client ?? http.Client();

  /// Default production Render URL or local fallback
  static const String defaultBaseUrl = "https://railguard-vision.onrender.com";

  String get baseUrl {
    final custom = _storage.getBackendUrl();
    if (custom.isNotEmpty && !custom.contains("10.0.2.2") && !custom.contains("localhost")) {
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
    effectiveToken ??= "dev-test-token";

    return {
      "Content-Type": "application/json",
      "Authorization": "Bearer $effectiveToken",
    };
  }

  /// Check backend liveness and storage status: GET /health
  Future<Map<String, dynamic>> checkHealth({String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/health");

    try {
      final res = await _client.get(uri).timeout(const Duration(seconds: 4));
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
      return {"success": false, "message": "Connection timed out to $target"};
    } on SocketException catch (e) {
      return {"success": false, "message": "Socket error: ${e.message}"};
    } catch (e) {
      return {"success": false, "message": "Unexpected error: $e"};
    }
  }

  /// Retrieve active or unreviewed unattended luggage alerts: GET /api/alerts
  Future<List<RailGuardAlertModel>> getAlerts({
    int limit = 50,
    bool unreviewedOnly = false,
    String? status,
    String? overrideUrl,
  }) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final queryParams = {
      "limit": limit.toString(),
      if (unreviewedOnly) "unreviewed_only": "true",
      if (status != null) "status": status,
    };
    final uri = Uri.parse("$target/api/alerts").replace(queryParameters: queryParams);
    final headers = await _buildHeaders();

    final res = await _client
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 5));

    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List<dynamic>;
      return list
          .map((item) => RailGuardAlertModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } else if (res.statusCode == 401) {
      throw Exception("Unauthorized: Invalid or expired Firebase ID token.");
    } else {
      throw Exception("Failed to load alerts: HTTP ${res.statusCode} - ${res.body}");
    }
  }

  /// Submit operator review: PATCH /api/alerts/{id}/review
  Future<RailGuardAlertModel> reviewAlert(
    dynamic alertId,
    String reviewStatus, {
    String? overrideUrl,
  }) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/$alertId/review");

    final payload = jsonEncode({"review_status": reviewStatus});
    final headers = await _buildHeaders();
    final res = await _client
        .patch(uri, headers: headers, body: payload)
        .timeout(const Duration(seconds: 5));

    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return RailGuardAlertModel.fromJson(decoded);
    } else {
      throw Exception("Failed to update review status: HTTP ${res.statusCode} - ${res.body}");
    }
  }

  /// Formats direct URL to fetch snapshot JPEG image with authorization query parameter
  Future<String> getSnapshotUrl(dynamic alertId, {String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final token = await _authService?.getIdToken() ?? "dev-test-token";
    return "$target/api/alerts/$alertId/snapshot?token=$token";
  }

  /// Formats direct URL to stream context MP4 video clip with authorization query parameter
  Future<String> getClipUrl(dynamic alertId, {String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final token = await _authService?.getIdToken() ?? "dev-test-token";
    return "$target/api/alerts/$alertId/clip?token=$token";
  }

  /// Retrieve running false alarm rate: GET /api/alerts/stats/false-alarm-rate
  Future<Map<String, dynamic>> getFalseAlarmRate({String? overrideUrl}) async {
    final target = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$target/api/alerts/stats/false-alarm-rate");
    final headers = await _buildHeaders();

    final res = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    return {"false_alarm_rate": null, "total_reviewed": 0, "false_alarms": 0};
  }

  void dispose() {
    _client.close();
  }
}
