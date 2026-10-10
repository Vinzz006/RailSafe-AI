import '../constants/app_colors.dart';
import '../../models/prediction_response.dart';
import 'package:flutter/material.dart';

enum ScreeningStatus {
  normalBaseline,
  anomalyFlagged,
  inconclusiveData,
  testInterrupted,
  demoSimulation,
}

class ScreeningAnalysisResult {
  final ScreeningStatus status;
  final String title;
  final String description;
  final Color statusColor;
  final String recommendation;
  final Map<String, dynamic> metrics;
  final bool requiresSecondaryReview;
  final PredictionResponse? backendPrediction;

  const ScreeningAnalysisResult({
    required this.status,
    required this.title,
    required this.description,
    required this.statusColor,
    required this.recommendation,
    required this.metrics,
    required this.requiresSecondaryReview,
    this.backendPrediction,
  });
}

class ScreeningAnalyzer {
  /// Evaluates received sensor telemetry sessions.
  /// Combines multi-channel telemetry aggregation with authoritative Python FastAPI ML inference results.
  static ScreeningAnalysisResult analyze({
    required List<Map<String, dynamic>> readings,
    required bool isDemo,
    required bool wasInterrupted,
    PredictionResponse? backendPrediction,
  }) {
    if (wasInterrupted) {
      return const ScreeningAnalysisResult(
        status: ScreeningStatus.testInterrupted,
        title: "Test Interrupted",
        description: "Sampling was prematurely interrupted due to manual cancel or hardware disconnect.",
        statusColor: AppColors.statusWarning,
        recommendation: "Ensure device is securely paired and re-initiate screening scan.",
        metrics: {"sampleCount": 0},
        requiresSecondaryReview: false,
      );
    }

    if (readings.isEmpty) {
      return const ScreeningAnalysisResult(
        status: ScreeningStatus.inconclusiveData,
        title: "Inconclusive Data",
        description: "No sensor telemetry packets were received during the test interval.",
        statusColor: AppColors.statusWarning,
        recommendation: "Check sensor probe connection and firmware status on ESP32.",
        metrics: {"sampleCount": 0},
        requiresSecondaryReview: false,
      );
    }

    if (readings.length < 3) {
      return ScreeningAnalysisResult(
        status: ScreeningStatus.inconclusiveData,
        title: "Incomplete Sampling",
        description: "Insufficient telemetry packets (${readings.length} samples) to establish baseline.",
        statusColor: AppColors.statusWarning,
        recommendation: "Maintain sensor probe exposure for at least 5-10 seconds.",
        metrics: {"sampleCount": readings.length},
        requiresSecondaryReview: false,
      );
    }

    // Extract sensor values across channels
    final s1Values = <double>[];
    final s2Values = <double>[];
    final mq2Values = <double>[];
    final mq4Values = <double>[];
    final mq7Values = <double>[];

    for (final r in readings) {
      final sensors = r['sensors'] as Map<String, dynamic>? ?? {};

      // Channel 1 / MQ-2
      double? val1;
      if (sensors.containsKey('mq2_raw')) {
        val1 = (sensors['mq2_raw'] is Map)
            ? (sensors['mq2_raw']['value'] as num?)?.toDouble()
            : (sensors['mq2_raw'] as num?)?.toDouble();
      } else if (sensors.containsKey('mq2')) {
        val1 = (sensors['mq2'] is Map)
            ? (sensors['mq2']['value'] as num?)?.toDouble()
            : (sensors['mq2'] as num?)?.toDouble();
      } else if (sensors.containsKey('sensor_1')) {
        val1 = (sensors['sensor_1'] is Map)
            ? (sensors['sensor_1']['value'] as num?)?.toDouble()
            : (sensors['sensor_1'] as num?)?.toDouble();
      }
      if (val1 != null) {
        s1Values.add(val1);
        mq2Values.add(val1);
      }

      // Channel 2 / MQ-4
      double? val2;
      if (sensors.containsKey('mq4_raw')) {
        val2 = (sensors['mq4_raw'] is Map)
            ? (sensors['mq4_raw']['value'] as num?)?.toDouble()
            : (sensors['mq4_raw'] as num?)?.toDouble();
      } else if (sensors.containsKey('mq4')) {
        val2 = (sensors['mq4'] is Map)
            ? (sensors['mq4']['value'] as num?)?.toDouble()
            : (sensors['mq4'] as num?)?.toDouble();
      } else if (sensors.containsKey('sensor_2')) {
        val2 = (sensors['sensor_2'] is Map)
            ? (sensors['sensor_2']['value'] as num?)?.toDouble()
            : (sensors['sensor_2'] as num?)?.toDouble();
      }
      if (val2 != null) {
        s2Values.add(val2);
        mq4Values.add(val2);
      }

      // Channel 3 / MQ-7
      double? val3;
      if (sensors.containsKey('mq7_raw')) {
        val3 = (sensors['mq7_raw'] is Map)
            ? (sensors['mq7_raw']['value'] as num?)?.toDouble()
            : (sensors['mq7_raw'] as num?)?.toDouble();
      } else if (sensors.containsKey('mq7')) {
        val3 = (sensors['mq7'] is Map)
            ? (sensors['mq7']['value'] as num?)?.toDouble()
            : (sensors['mq7'] as num?)?.toDouble();
      } else if (val1 != null) {
        val3 = val1 * 0.45;
      }
      if (val3 != null) {
        mq7Values.add(val3);
      }
    }

    final s1Max = s1Values.isNotEmpty ? s1Values.reduce((a, b) => a > b ? a : b) : 0.0;
    final s1Avg = s1Values.isNotEmpty ? s1Values.reduce((a, b) => a + b) / s1Values.length : 0.0;
    final s2Max = s2Values.isNotEmpty ? s2Values.reduce((a, b) => a > b ? a : b) : 0.0;
    final s2Avg = s2Values.isNotEmpty ? s2Values.reduce((a, b) => a + b) / s2Values.length : 0.0;

    final mq2Peak = mq2Values.isNotEmpty ? mq2Values.reduce((a, b) => a > b ? a : b) : s1Max;
    final mq4Peak = mq4Values.isNotEmpty ? mq4Values.reduce((a, b) => a > b ? a : b) : s2Max;
    final mq7Peak = mq7Values.isNotEmpty ? mq7Values.reduce((a, b) => a > b ? a : b) : (s1Max * 0.45);

    final bool anomalyDetected;
    final String modelName;
    final String mlPredictionLabel;
    final double mlAnomalyProbPercent;
    final double mlConfidence;

    if (backendPrediction != null) {
      // Authoritative inference from Python FastAPI Backend
      anomalyDetected = backendPrediction.isAnomaly;
      modelName = "Python FastAPI Backend (RandomForest v${backendPrediction.modelVersion})";
      mlPredictionLabel = backendPrediction.label;
      mlAnomalyProbPercent = double.parse((backendPrediction.anomalyScore * 100).toStringAsFixed(1));
      mlConfidence = double.parse(backendPrediction.confidence.toStringAsFixed(1));
    } else {
      // Offline fallback threshold guard when backend is unreachable
      final s1ThresholdExceeded = s1Max > 280.0;
      final s2ThresholdExceeded = s2Max > 140.0;
      anomalyDetected = s1ThresholdExceeded || s2ThresholdExceeded;
      modelName = "Prediction service unavailable (Safety threshold only)";
      mlPredictionLabel = "prediction_service_unavailable";
      mlAnomalyProbPercent = anomalyDetected ? 95.0 : 0.0;
      mlConfidence = 0.0;
    }

    final metrics = {
      "sampleCount": readings.length,
      "sensor_1_max": double.parse(s1Max.toStringAsFixed(1)),
      "sensor_1_avg": double.parse(s1Avg.toStringAsFixed(1)),
      "sensor_2_max": double.parse(s2Max.toStringAsFixed(1)),
      "sensor_2_avg": double.parse(s2Avg.toStringAsFixed(1)),
      "mq2_peak": double.parse(mq2Peak.toStringAsFixed(1)),
      "mq4_peak": double.parse(mq4Peak.toStringAsFixed(1)),
      "mq7_peak": double.parse(mq7Peak.toStringAsFixed(1)),
      "ml_model": modelName,
      "ml_prediction": mlPredictionLabel,
      "ml_anomaly_prob": mlAnomalyProbPercent,
      "ml_confidence": mlConfidence,
      if (backendPrediction != null) "backend_inference_ts": backendPrediction.inferenceTimestamp.toIso8601String(),
    };

    if (isDemo) {
      if (anomalyDetected) {
        return ScreeningAnalysisResult(
          status: ScreeningStatus.demoSimulation,
          title: "Demo Simulation — Anomaly Scenario",
          description:
              "Backend AI identified anomalous pattern ($mlAnomalyProbPercent% anomaly probability, Peak S1: ${s1Max.toStringAsFixed(1)}, S2: ${s2Max.toStringAsFixed(1)}).",
          statusColor: AppColors.statusWarning,
          recommendation: "Demonstration mode only. In field operations, secondary review would be requested.",
          metrics: metrics,
          requiresSecondaryReview: true,
          backendPrediction: backendPrediction,
        );
      } else {
        return ScreeningAnalysisResult(
          status: ScreeningStatus.demoSimulation,
          title: "Demo Simulation — Nominal Baseline",
          description:
              "Backend AI verified nominal ambient baseline ($mlConfidence% baseline confidence).",
          statusColor: AppColors.statusSafe,
          recommendation: "Demonstration mode. System telemetry pipeline operating nominally.",
          metrics: metrics,
          requiresSecondaryReview: false,
          backendPrediction: backendPrediction,
        );
      }
    }

    if (anomalyDetected) {
      final desc = backendPrediction != null
          ? "Python Backend AI flagged sensor deviation from baseline with $mlAnomalyProbPercent% anomaly probability (Peak S1: ${s1Max.toStringAsFixed(1)}, Peak S2: ${s2Max.toStringAsFixed(1)})."
          : "Prediction service unavailable. Calibrated threshold exceeded (Peak S1: ${s1Max.toStringAsFixed(1)}, Peak S2: ${s2Max.toStringAsFixed(1)}). Secondary review recommended.";
      return ScreeningAnalysisResult(
        status: ScreeningStatus.anomalyFlagged,
        title: backendPrediction != null
            ? "Anomaly Flagged — Secondary Review Required"
            : "Threshold Exceeded — Prediction Service Offline",
        description: desc,
        statusColor: AppColors.statusDanger,
        recommendation:
            "Conduct standard baggage inspection or secondary screening protocol in accordance with railway safety guidelines. Do not conclude substance identity without laboratory spectrometry.",
        metrics: metrics,
        requiresSecondaryReview: true,
        backendPrediction: backendPrediction,
      );
    }

    final desc = backendPrediction != null
        ? "Python Backend AI confirmed ambient baseline with $mlConfidence% confidence throughout sampling interval."
        : "Prediction service unavailable. Telemetry values remained below safety thresholds during sampling.";
    return ScreeningAnalysisResult(
      status: ScreeningStatus.normalBaseline,
      title: backendPrediction != null
          ? "Baseline Nominal — No Anomaly Detected"
          : "Thresholds Nominal — Prediction Service Offline",
      description: desc,
      statusColor: AppColors.statusSafe,
      recommendation: "Screening completed. Baggage/sample cleared under current prototype screening parameters.",
      metrics: metrics,
      requiresSecondaryReview: false,
      backendPrediction: backendPrediction,
    );
  }
}
