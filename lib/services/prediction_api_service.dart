import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/errors/app_error.dart';
import '../models/prediction_response.dart';
import 'local_storage_service.dart';

class PredictionApiService {
  final LocalStorageService _storage;
  final http.Client _client;

  PredictionApiService(this._storage, {http.Client? client})
      : _client = client ?? http.Client();

  /// Default address for Android Emulator to connect to host computer's localhost:8000
  static const String defaultEmulatorBackendUrl = "http://10.0.2.2:8000";

  String get baseUrl => _storage.getBackendUrl();

  /// Queries GET /health endpoint to verify server status and model readiness
  Future<Map<String, dynamic>> checkHealth({String? overrideUrl}) async {
    final targetUrl = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$targetUrl/health");

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {
          "success": true,
          "status": decoded["status"],
          "model_loaded": decoded["model_loaded"] == true,
          "model_version": decoded["model_version"] ?? "1.0.0",
          "model_name": decoded["model_name"] ?? "RandomForestClassifier",
        };
      } else {
        return {
          "success": false,
          "message": "Server responded with HTTP ${response.statusCode}: ${response.body}",
        };
      }
    } on TimeoutException {
      return {
        "success": false,
        "message": "Connection timed out connecting to $targetUrl",
      };
    } on SocketException catch (e) {
      return {
        "success": false,
        "message": "Network socket failure: ${e.message}",
      };
    } catch (e) {
      return {
        "success": false,
        "message": "Failed to connect to backend: $e",
      };
    }
  }

  /// Sends sensor telemetry readings to POST /predict on the Python backend.
  /// Protected with the user's Firebase ID token.
  Future<PredictionResponse> predict({
    required String deviceId,
    required int sequence,
    required DateTime timestamp,
    required double mq2,
    required double mq4,
    required double mq7,
    required String idToken,
    String? overrideUrl,
  }) async {
    final targetUrl = (overrideUrl ?? baseUrl).trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse("$targetUrl/predict");

    final payload = {
      "deviceId": deviceId,
      "sequence": sequence,
      "timestamp": timestamp.toUtc().toIso8601String(),
      "sensors": {
        "mq2_raw": double.parse(mq2.toStringAsFixed(1)),
        "mq4_raw": double.parse(mq4.toStringAsFixed(1)),
        "mq7_raw": double.parse(mq7.toStringAsFixed(1)),
      },
    };

    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $idToken",
    };

    debugPrint("[PREDICTION_API] Submitting inference request to $uri (Seq #$sequence)");

    try {
      final response = await _client
          .post(
            uri,
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        debugPrint("[PREDICTION_API] Inference successful: ${decoded['prediction']} (score: ${decoded['anomalyScore']})");
        return PredictionResponse.fromJson(decoded);
      }

      if (response.statusCode == 401) {
        throw BackendPredictionException(
          "Authentication failed: Invalid or expired Firebase ID token.",
          statusCode: 401,
          details: response.body,
        );
      }

      if (response.statusCode == 422) {
        throw BackendPredictionException(
          "Telemetry validation rejected by server: ${response.body}",
          statusCode: 422,
          details: response.body,
        );
      }

      if (response.statusCode == 503) {
        throw BackendPredictionException(
          "Prediction service unavailable: Model not loaded on server.",
          statusCode: 503,
          details: response.body,
        );
      }

      throw BackendPredictionException(
        "Backend server error (${response.statusCode}): ${response.body}",
        statusCode: response.statusCode,
        details: response.body,
      );
    } on TimeoutException {
      throw BackendPredictionException(
        "Prediction request timed out. Python backend did not respond within 5 seconds.",
        statusCode: 408,
      );
    } on SocketException catch (e) {
      throw BackendPredictionException(
        "Unable to reach Python backend at $targetUrl: ${e.message}",
        statusCode: 0,
      );
    } on BackendPredictionException {
      rethrow;
    } catch (e) {
      throw BackendPredictionException(
        "Unexpected error communicating with prediction backend: $e",
        details: e.toString(),
      );
    }
  }

  void dispose() {
    _client.close();
  }
}
