import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/screening_analyzer.dart';
import '../../models/sensor_reading.dart';
import '../../models/test_record.dart';
import '../../providers/test_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/realtime_sensor_chart.dart';
import '../../widgets/status_badge.dart';

class TestResultScreen extends StatefulWidget {
  final TestRecord record;
  final ScreeningAnalysisResult? analysis;

  const TestResultScreen({
    super.key,
    required this.record,
    this.analysis,
  });

  @override
  State<TestResultScreen> createState() => _TestResultScreenState();
}

class _TestResultScreenState extends State<TestResultScreen> {
  final _notesController = TextEditingController();
  bool _isSaved = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSaveTest() async {
    setState(() => _isSaving = true);
    final testProv = Provider.of<TestProvider>(context, listen: false);
    await testProv.saveCurrentTest(notes: _notesController.text.trim());
    if (mounted) {
      setState(() {
        _isSaving = false;
        _isSaved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.statusSafe,
          content: Text("Screening test record saved successfully."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final analysis = widget.analysis ??
        ScreeningAnalyzer.analyze(
          readings: record.sensorReadings,
          isDemo: record.isDemo,
          wasInterrupted: record.completionStatus == 'interrupted',
        );

    final parsedReadings = record.sensorReadings
        .map((m) => SensorReading.fromJson(m))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Screening Assessment",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Screening Result Assessment Banner
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: analysis.statusColor.withValues(alpha: 0.7),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: analysis.statusColor.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ],
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
                              analysis.requiresSecondaryReview
                                  ? Icons.warning_rounded
                                  : Icons.verified_rounded,
                              color: analysis.statusColor,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "SCREENING INDICATION",
                              style: GoogleFonts.orbitron(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: analysis.statusColor,
                                letterSpacing: 1.0,
                              ),
                            ),
                          ],
                        ),
                        if (record.isDemo)
                          StatusBadge.demoMode(compact: true)
                        else
                          StatusBadge(
                            label: record.completionStatus.toUpperCase(),
                            color: analysis.statusColor,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      analysis.title,
                      style: GoogleFonts.inter(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      analysis.description,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, size: 18, color: analysis.statusColor),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              analysis.recommendation,
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Recorded Telemetry Chart
              RealtimeSensorChart(
                readings: parsedReadings,
                isDemo: record.isDemo,
                isLive: false,
              ),

              const SizedBox(height: 16),

              // Telemetry Summary Metrics Card
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
                      "TEST METRICS & METADATA",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildMetaRow("Test ID", record.testId),
                    _buildMetaRow("Device Model", record.deviceId),
                    _buildMetaRow("Test Mode", record.isDemo ? "Demo Simulation" : "BLE Hardware"),
                    _buildMetaRow("Started At", DateFormatter.formatDateTime(record.startedAt)),
                    _buildMetaRow("Completed At", DateFormatter.formatDateTime(record.completedAt)),
                    _buildMetaRow("Duration", DateFormatter.formatDuration(record.duration)),
                    _buildMetaRow("Total Samples", "${record.sensorReadings.length} packets"),
                    const Divider(height: 20),
                    _buildMetaRow(
                      "Peak Sensor 1 (VOC)",
                      "${record.metrics['sensor_1_max'] ?? '--'} ppm",
                    ),
                    _buildMetaRow(
                      "Avg Sensor 1 (VOC)",
                      "${record.metrics['sensor_1_avg'] ?? '--'} ppm",
                    ),
                    _buildMetaRow(
                      "Peak Sensor 2 (Diff)",
                      "${record.metrics['sensor_2_max'] ?? '--'} mV",
                    ),
                    _buildMetaRow(
                      "Avg Sensor 2 (Diff)",
                      "${record.metrics['sensor_2_avg'] ?? '--'} mV",
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Notes & Inspector Remarks
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
                      "INSPECTOR NOTES & OBSERVATIONS",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      label: "Screening Notes (Optional)",
                      hint: "e.g., Baggage check on Platform 4, passenger cleared.",
                      controller: _notesController,
                      maxLines: 2,
                      enabled: !_isSaved,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Actions Row
              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: _isSaved ? "Saved" : "Save Test Record",
                      icon: _isSaved ? Icons.check_circle_rounded : Icons.save_rounded,
                      isLoading: _isSaving,
                      onPressed: _isSaved ? null : _handleSaveTest,
                    ),
                  ),
                  const SizedBox(width: 12),
                  CustomButton(
                    text: "Done",
                    fullWidth: false,
                    isSecondary: true,
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      if (!_isSaved) {
                        await _handleSaveTest();
                      }
                      if (!mounted) return;
                      navigator.pop();
                    },
                  ),
                ],
              ),

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
            style: GoogleFonts.inter(
              color: AppColors.textSecondary,
              fontSize: 12.5,
            ),
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
