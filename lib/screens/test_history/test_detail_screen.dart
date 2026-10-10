import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/sensor_reading.dart';
import '../../models/test_record.dart';
import '../../providers/test_provider.dart';
import '../../widgets/realtime_sensor_chart.dart';
import '../../widgets/status_badge.dart';

class TestDetailScreen extends StatelessWidget {
  final TestRecord record;

  const TestDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final testProv = Provider.of<TestProvider>(context, listen: false);
    final isFlagged = record.screeningAssistanceStatus.contains("Anomaly");
    final statusColor = isFlagged ? AppColors.statusDanger : AppColors.statusSafe;

    final parsedReadings = record.sensorReadings
        .map((m) => SensorReading.fromJson(m))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          record.testId,
          style: GoogleFonts.orbitron(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.statusDanger),
            tooltip: "Delete Record",
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: AppColors.surfaceCard,
                  title: const Text("Delete Record"),
                  content: const Text("Are you sure you want to remove this test record?"),
                  actions: [
                    TextButton(
                      child: const Text("Cancel"),
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                    TextButton(
                      child: const Text("Delete", style: TextStyle(color: AppColors.statusDanger)),
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await testProv.deleteTest(record.testId);
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Result Status Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: statusColor.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isFlagged ? Icons.warning_rounded : Icons.verified_rounded,
                              color: statusColor,
                              size: 22,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "SCREENING ASSESSMENT",
                              style: GoogleFonts.orbitron(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: statusColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (record.isDemo)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.statusWarning.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  "DEMO",
                                  style: GoogleFonts.inter(
                                    color: AppColors.statusWarning,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            StatusBadge.syncStatus(record.syncedToFirestore),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      record.screeningAssistanceStatus,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (record.screeningAssistanceDetails.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        record.screeningAssistanceDetails,
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Recorded Telemetry Graph
              RealtimeSensorChart(
                readings: parsedReadings,
                isDemo: record.isDemo,
                isLive: false,
              ),

              const SizedBox(height: 16),

              // Detailed Telemetry Metrics Table
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "RECORD METRICS",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildMetaRow("Hardware / Device ID", record.deviceId),
                    _buildMetaRow("Sampling Duration", DateFormatter.formatDuration(record.duration)),
                    _buildMetaRow("Total Telemetry Samples", "${record.sensorReadings.length} packets"),
                    _buildMetaRow("Started Timestamp", DateFormatter.formatDateTime(record.startedAt)),
                    _buildMetaRow("Completed Timestamp", DateFormatter.formatDateTime(record.completedAt)),
                    const Divider(height: 20),
                    _buildMetaRow("Peak Sensor 1 (VOC)", "${record.metrics['sensor_1_max'] ?? '--'} ppm"),
                    _buildMetaRow("Average Sensor 1 (VOC)", "${record.metrics['sensor_1_avg'] ?? '--'} ppm"),
                    _buildMetaRow("Peak Sensor 2 (Diff)", "${record.metrics['sensor_2_max'] ?? '--'} mV"),
                    _buildMetaRow("Average Sensor 2 (Diff)", "${record.metrics['sensor_2_avg'] ?? '--'} mV"),
                    if (record.metrics.containsKey('ml_prediction')) ...[
                      const Divider(height: 20),
                      _buildMetaRow(
                        "AI Screening Model",
                        "${record.metrics['ml_model'] ?? 'Random Forest'}",
                      ),
                      _buildMetaRow(
                        "ML Classification",
                        record.metrics['ml_prediction'] == 'prediction_service_unavailable'
                            ? "SERVICE UNAVAILABLE"
                            : (record.metrics['ml_prediction'] == 'anomaly_synthetic' || record.metrics['ml_prediction'] == 'anomaly'
                                ? "ANOMALY FLAGGED"
                                : "NOMINAL BASELINE"),
                      ),
                      _buildMetaRow(
                        "Anomaly Probability",
                        "${record.metrics['ml_anomaly_prob'] ?? '--'}%",
                      ),
                      _buildMetaRow(
                        "Model Confidence",
                        "${record.metrics['ml_confidence'] ?? '--'}%",
                      ),
                    ],
                  ],
                ),
              ),

              if (record.notes != null && record.notes!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "INSPECTOR NOTES",
                        style: GoogleFonts.orbitron(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        record.notes!,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Disclaimer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  AppConstants.prototypeDisclaimer,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          Text(
            value,
            style: GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
