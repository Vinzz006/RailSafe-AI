import '../constants/app_colors.dart';
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

  const ScreeningAnalysisResult({
    required this.status,
    required this.title,
    required this.description,
    required this.statusColor,
    required this.recommendation,
    required this.metrics,
    required this.requiresSecondaryReview,
  });
}

class ScreeningAnalyzer {
  /// Evaluates received sensor telemetry without claiming chemical confirmation.
  /// Evaluates threshold shifts, rate-of-rise, and sample completeness.
  static ScreeningAnalysisResult analyze({
    required List<Map<String, dynamic>> readings,
    required bool isDemo,
    required bool wasInterrupted,
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

    // Extract sensor values
    final s1Values = <double>[];
    final s2Values = <double>[];

    for (final r in readings) {
      final sensors = r['sensors'] as Map<String, dynamic>? ?? {};
      if (sensors.containsKey('sensor_1')) {
        final val = (sensors['sensor_1']?['value'] as num?)?.toDouble();
        if (val != null) s1Values.add(val);
      }
      if (sensors.containsKey('sensor_2')) {
        final val = (sensors['sensor_2']?['value'] as num?)?.toDouble();
        if (val != null) s2Values.add(val);
      }
    }

    final s1Max = s1Values.isNotEmpty ? s1Values.reduce((a, b) => a > b ? a : b) : 0.0;
    final s1Avg = s1Values.isNotEmpty ? s1Values.reduce((a, b) => a + b) / s1Values.length : 0.0;
    final s2Max = s2Values.isNotEmpty ? s2Values.reduce((a, b) => a > b ? a : b) : 0.0;
    final s2Avg = s2Values.isNotEmpty ? s2Values.reduce((a, b) => a + b) / s2Values.length : 0.0;

    // Prototype rule:
    // If Sensor 1 peak exceeds 300.0 or Sensor 2 peak exceeds 150.0,
    // trigger screening flag "Anomaly flagged — secondary review required".
    final s1ThresholdExceeded = s1Max > 280.0;
    final s2ThresholdExceeded = s2Max > 140.0;

    final metrics = {
      "sampleCount": readings.length,
      "sensor_1_max": double.parse(s1Max.toStringAsFixed(1)),
      "sensor_1_avg": double.parse(s1Avg.toStringAsFixed(1)),
      "sensor_2_max": double.parse(s2Max.toStringAsFixed(1)),
      "sensor_2_avg": double.parse(s2Avg.toStringAsFixed(1)),
    };

    if (isDemo) {
      if (s1ThresholdExceeded || s2ThresholdExceeded) {
        return ScreeningAnalysisResult(
          status: ScreeningStatus.demoSimulation,
          title: "Demo Simulation — Anomaly Scenario",
          description: "Simulated test generated peak readings exceeding threshold parameters.",
          statusColor: AppColors.statusWarning,
          recommendation: "Demonstration mode only. In field operations, secondary review would be requested.",
          metrics: metrics,
          requiresSecondaryReview: true,
        );
      } else {
        return ScreeningAnalysisResult(
          status: ScreeningStatus.demoSimulation,
          title: "Demo Simulation — Nominal Baseline",
          description: "Simulated test completed with normal baseline readings.",
          statusColor: AppColors.statusSafe,
          recommendation: "Demonstration mode. System telemetry pipeline operating nominally.",
          metrics: metrics,
          requiresSecondaryReview: false,
        );
      }
    }

    if (s1ThresholdExceeded || s2ThresholdExceeded) {
      return ScreeningAnalysisResult(
        status: ScreeningStatus.anomalyFlagged,
        title: "Anomaly Flagged — Secondary Review Required",
        description:
            "Sensor telemetry exhibited deviation beyond calibrated ambient thresholds (Peak S1: ${s1Max.toStringAsFixed(1)}, Peak S2: ${s2Max.toStringAsFixed(1)}).",
        statusColor: AppColors.statusDanger,
        recommendation:
            "Conduct standard baggage inspection or secondary screening protocol in accordance with railway safety guidelines. Do not conclude substance identity without laboratory spectrometry.",
        metrics: metrics,
        requiresSecondaryReview: true,
      );
    }

    return ScreeningAnalysisResult(
      status: ScreeningStatus.normalBaseline,
      title: "Baseline Nominal — No Anomaly Detected",
      description: "Sensor measurements remained within expected ambient tolerance throughout sampling interval.",
      statusColor: AppColors.statusSafe,
      recommendation: "Screening completed. Baggage/sample cleared under current prototype threshold parameters.",
      metrics: metrics,
      requiresSecondaryReview: false,
    );
  }
}
