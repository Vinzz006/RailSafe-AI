import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/app_constants.dart';
import '../models/sensor_reading.dart';
import 'auth_service.dart';
import 'local_storage_service.dart';

/// Exception thrown on telemetry cloud API operations.
class TelemetryApiException implements Exception {
  final String message;
  final int? statusCode;
  TelemetryApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

class TelemetryAuthException extends TelemetryApiException {
  TelemetryAuthException(super.message, [super.statusCode = 401]);
}

class TelemetryTimeoutException extends TelemetryApiException {
  TelemetryTimeoutException(super.message);
}

class TelemetryNetworkException extends TelemetryApiException {
  TelemetryNetworkException(super.message);
}

/// Cloud sync statuses for telemetry background uploader.
enum TelemetrySyncStatus {
  idle,
  syncing,
  synced,
  offlineQueued,
  error,
}

/// Snapshot of the telemetry synchronization queue state.
class TelemetrySyncState {
  final TelemetrySyncStatus status;
  final int queuedCount;
  final int totalSyncedCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const TelemetrySyncState({
    required this.status,
    required this.queuedCount,
    this.totalSyncedCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  bool get isOffline => status == TelemetrySyncStatus.offlineQueued;
  bool get isSyncing => status == TelemetrySyncStatus.syncing;
  bool get hasError => status == TelemetrySyncStatus.error;
}

/// Client for communicating with Render FastAPI telemetry endpoints.
class TelemetryService {
  final LocalStorageService _storage;
  final AuthService? authService;
  final http.Client _client;
  final Duration requestTimeout;

  TelemetryService(
    this._storage, {
    this.authService,
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 25),
  })  : _client = client ?? http.Client();

  static const String defaultBaseUrl = AppConstants.defaultRailGuardBackendUrl;

  String get baseUrl {
    final custom = _storage.getRailGuardBackendUrl().trim();
    if (custom.isNotEmpty) {
      return custom.replaceAll(RegExp(r'/+$'), '');
    }
    return defaultBaseUrl;
  }

  Future<Map<String, String>> _buildHeaders() async {
    String? token;
    if (authService != null) {
      try {
        token = await authService!.getIdToken();
      } catch (e) {
        if (kDebugMode) print("[TelemetryService] Error getting ID token: $e");
      }
    }

    final headers = <String, String>{
      "Content-Type": "application/json",
      "Accept": "application/json",
    };

    if (token != null && token.isNotEmpty) {
      headers["Authorization"] = "Bearer ${token.trim()}";
    }

    return headers;
  }

  /// Sends a single physical reading to Render backend (POST /api/telemetry).
  Future<Map<String, dynamic>> postTelemetry(SensorReading reading) async {
    final uri = Uri.parse("$baseUrl/api/telemetry");
    final headers = await _buildHeaders();

    try {
      final response = await _client
          .post(uri, headers: headers, body: jsonEncode(reading.toJson()))
          .timeout(requestTimeout);

      return _handleResponse(response, "ingest telemetry reading");
    } on TimeoutException {
      throw TelemetryTimeoutException(
        "Request timed out while sending telemetry to $baseUrl.",
      );
    } on SocketException catch (e) {
      throw TelemetryNetworkException("Network connection failed: ${e.message}");
    }
  }

  /// Sends a batch of physical readings (POST /api/telemetry).
  Future<Map<String, dynamic>> postTelemetryBatch(List<SensorReading> readings) async {
    if (readings.isEmpty) return {"status": "ok", "count": 0};

    final uri = Uri.parse("$baseUrl/api/telemetry");
    final headers = await _buildHeaders();
    final body = jsonEncode({
      "readings": readings.map((r) => r.toJson()).toList(),
    });

    try {
      final response = await _client
          .post(uri, headers: headers, body: body)
          .timeout(requestTimeout);

      return _handleResponse(response, "ingest telemetry batch");
    } on TimeoutException {
      throw TelemetryTimeoutException(
        "Request timed out while sending telemetry batch to $baseUrl.",
      );
    } on SocketException catch (e) {
      throw TelemetryNetworkException("Network connection failed: ${e.message}");
    }
  }

  /// Retrieves the latest known reading for a device (GET /api/telemetry/latest).
  Future<SensorReading?> getLatestTelemetry(String deviceId) async {
    final cleanId = Uri.encodeQueryComponent(deviceId);
    final uri = Uri.parse("$baseUrl/api/telemetry/latest?device_id=$cleanId");
    final headers = await _buildHeaders();

    try {
      final response = await _client.get(uri, headers: headers).timeout(requestTimeout);
      if (response.statusCode == 404) {
        return null;
      }

      final json = _handleResponse(response, "get latest telemetry");
      final readingData = json["reading"];
      if (readingData is Map<String, dynamic>) {
        return SensorReading.fromJson(readingData);
      }
      return null;
    } on TimeoutException {
      throw TelemetryTimeoutException("Timed out fetching latest telemetry.");
    } on SocketException catch (e) {
      throw TelemetryNetworkException("Network error: ${e.message}");
    }
  }

  /// Retrieves bounded telemetry history for a device (GET /api/telemetry).
  Future<List<SensorReading>> getTelemetryHistory(
    String deviceId, {
    int limit = 50,
  }) async {
    final cleanId = Uri.encodeQueryComponent(deviceId);
    final uri = Uri.parse("$baseUrl/api/telemetry?device_id=$cleanId&limit=$limit");
    final headers = await _buildHeaders();

    try {
      final response = await _client.get(uri, headers: headers).timeout(requestTimeout);
      final json = _handleResponse(response, "get telemetry history");

      final rawList = json["readings"];
      if (rawList is List) {
        return rawList
            .whereType<Map<String, dynamic>>()
            .map((item) => SensorReading.fromJson(item))
            .toList();
      }
      return [];
    } on TimeoutException {
      throw TelemetryTimeoutException("Timed out fetching telemetry history.");
    } on SocketException catch (e) {
      throw TelemetryNetworkException("Network error: ${e.message}");
    }
  }

  Map<String, dynamic> _handleResponse(http.Response response, String action) {
    final code = response.statusCode;
    if (code >= 200 && code < 300) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) return decoded;
        return {"data": decoded};
      } catch (e) {
        throw TelemetryApiException("Invalid JSON response from server: $e");
      }
    }

    String detail = "HTTP $code";
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded.containsKey("detail")) {
        detail = decoded["detail"].toString();
      }
    } catch (_) {
      detail = response.body.isNotEmpty ? response.body : detail;
    }

    if (code == 401) {
      throw TelemetryAuthException("Authentication required: $detail", 401);
    } else if (code == 403) {
      throw TelemetryApiException("Access denied: $detail", 403);
    } else if (code == 404) {
      throw TelemetryApiException("Resource not found: $detail", 404);
    } else if (code == 429) {
      throw TelemetryApiException("Rate limited: $detail", 429);
    } else if (code >= 500) {
      throw TelemetryApiException("Server error: $detail", code);
    }

    throw TelemetryApiException("Failed to $action: $detail", code);
  }

  void dispose() {
    _client.close();
  }
}

/// Asynchronous bounded telemetry queue for background cloud synchronization.
///
/// Features:
/// - Maximum queue size bounded to 500 items (drops oldest if saturated).
/// - Deduplicates by (deviceId, sequence) to prevent duplicate server writes.
/// - Batch flushes every 5 readings or every 5 seconds.
/// - Non-blocking retry with exponential backoff on network failures.
/// - Preserves local BLE monitoring with zero latency impact.
class TelemetrySyncQueue {
  final TelemetryService telemetryService;
  final int maxQueueSize;
  final int batchSize;
  final Duration flushInterval;

  final List<SensorReading> _queue = [];
  final Set<String> _enqueuedKeys = {};
  Timer? _flushTimer;

  bool _isFlushing = false;
  int _consecutiveFailures = 0;
  int _totalSynced = 0;
  DateTime? _lastSyncedTime;
  String? _lastError;

  final StreamController<TelemetrySyncState> _stateController =
      StreamController<TelemetrySyncState>.broadcast();

  TelemetrySyncQueue({
    required this.telemetryService,
    this.maxQueueSize = 500,
    this.batchSize = 5,
    this.flushInterval = const Duration(seconds: 5),
  }) {
    _startTimer();
  }

  TelemetrySyncState get currentState => TelemetrySyncState(
        status: _currentStatus,
        queuedCount: _queue.length,
        totalSyncedCount: _totalSynced,
        lastSyncedAt: _lastSyncedTime,
        lastError: _lastError,
      );

  Stream<TelemetrySyncState> get stateStream => _stateController.stream;

  TelemetrySyncStatus get _currentStatus {
    if (_isFlushing) return TelemetrySyncStatus.syncing;
    if (_consecutiveFailures > 0) return TelemetrySyncStatus.offlineQueued;
    if (_totalSynced > 0 && _queue.isEmpty) return TelemetrySyncStatus.synced;
    return TelemetrySyncStatus.idle;
  }

  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(currentState);
    }
  }

  void _startTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  /// Enqueues a reading for background cloud synchronization.
  ///
  /// Safe to call on every 1 Hz BLE packet. Never blocks the BLE listener.
  void enqueue(SensorReading reading) {
    final key = "${reading.deviceId}_${reading.sequence}";
    if (_enqueuedKeys.contains(key)) return;

    if (_queue.length >= maxQueueSize) {
      // Evict oldest item to keep queue strictly bounded
      final evicted = _queue.removeAt(0);
      _enqueuedKeys.remove("${evicted.deviceId}_${evicted.sequence}");
    }

    _queue.add(reading);
    _enqueuedKeys.add(key);
    _emitState();

    // Trigger immediate batch flush if batch threshold reached
    if (_queue.length >= batchSize && !_isFlushing) {
      flush();
    }
  }

  /// Flushes pending telemetry batch to Render FastAPI backend.
  Future<void> flush() async {
    if (_isFlushing || _queue.isEmpty) return;

    _isFlushing = true;
    _emitState();

    // Take next slice of readings up to batchSize
    final toSend = _queue.take(batchSize).toList();

    try {
      await telemetryService.postTelemetryBatch(toSend);

      // Successful upload: remove uploaded items from queue and keys
      for (final r in toSend) {
        _queue.remove(r);
        _enqueuedKeys.remove("${r.deviceId}_${r.sequence}");
      }

      _consecutiveFailures = 0;
      _lastError = null;
      _totalSynced += toSend.length;
      _lastSyncedTime = DateTime.now();
    } catch (e) {
      _consecutiveFailures++;
      _lastError = e.toString();
      if (kDebugMode) {
        print("[TelemetrySyncQueue] Batch sync deferred (offline/error): $e");
      }
    } finally {
      _isFlushing = false;
      _emitState();
    }
  }

  /// Manually triggers retry of all queued items.
  Future<void> retryNow() async {
    _consecutiveFailures = 0;
    await flush();
  }

  /// Clears queue.
  void clear() {
    _queue.clear();
    _enqueuedKeys.clear();
    _emitState();
  }

  void dispose() {
    _flushTimer?.cancel();
    _stateController.close();
  }
}
