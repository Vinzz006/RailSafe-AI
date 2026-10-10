import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/test_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/realtime_sensor_chart.dart';
import '../../widgets/sensor_gauge_card.dart';
import '../../widgets/status_badge.dart';
import '../device_connection/device_connection_screen.dart';
import '../test_result/test_result_screen.dart';

class LiveMonitoringScreen extends StatelessWidget {
  const LiveMonitoringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final ble = Provider.of<BleProvider>(context);
    final testProv = Provider.of<TestProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);

    final isDemo = settings.isDemoModeEnabled;
    final isDeviceReady = isDemo || ble.isConnected;
    final latest = testProv.latestReading;
    final isTesting = testProv.isTesting;

    // Calculate peaks for active session
    double? s1Peak;
    double? s2Peak;
    double? s1Avg;
    double? s2Avg;

    if (testProv.currentSessionReadings.isNotEmpty) {
      final s1List = testProv.currentSessionReadings
          .map((r) => r.sensor1Value)
          .whereType<double>()
          .toList();
      final s2List = testProv.currentSessionReadings
          .map((r) => r.sensor2Value)
          .whereType<double>()
          .toList();

      if (s1List.isNotEmpty) {
        s1Peak = s1List.reduce((a, b) => a > b ? a : b);
        s1Avg = s1List.reduce((a, b) => a + b) / s1List.length;
      }
      if (s2List.isNotEmpty) {
        s2Peak = s2List.reduce((a, b) => a > b ? a : b);
        s2Avg = s2List.reduce((a, b) => a + b) / s2List.length;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Live Telemetry & Screening",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (!isDemo && !ble.isConnected)
            TextButton.icon(
              icon: const Icon(Icons.bluetooth_rounded, size: 16),
              label: const Text("Connect"),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const DeviceConnectionScreen(),
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // DEMO MODE BANNER (Mandatory, persistent & unmistakable when active)
              if (isDemo)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.statusWarning.withValues(alpha: 0.7),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: AppColors.statusWarning, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "DEMO MODE — SIMULATED DATA ACTIVE",
                              style: GoogleFonts.inter(
                                color: AppColors.statusWarning,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              "Telemetry is generated synthetically (${settings.demoScenario.toUpperCase()}). No physical hardware required.",
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              // Hardware / Session Status Bar
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isTesting
                                ? AppColors.statusSafe
                                : (isDeviceReady ? AppColors.statusInfo : AppColors.textMuted),
                            boxShadow: isTesting
                                ? [
                                    BoxShadow(
                                      color: AppColors.statusSafe.withValues(alpha: 0.8),
                                      blurRadius: 6,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isTesting
                                  ? (isDemo ? "SIMULATION SAMPLING ACTIVE" : "LIVE BLE SAMPLING ACTIVE")
                                  : "STANDBY READY",
                              style: GoogleFonts.orbitron(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: isTesting ? AppColors.textPrimary : AppColors.textSecondary,
                                letterSpacing: 0.8,
                              ),
                            ),
                            Text(
                              isDemo
                                  ? "Device: RAILSAFE-DEMO-SIM"
                                  : (ble.connectedDeviceName != null
                                      ? "Device: ${ble.connectedDeviceName}"
                                      : "Hardware Disconnected"),
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: AppColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (isTesting)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          DateFormatter.formatDuration(testProv.elapsedDuration),
                          style: GoogleFonts.orbitron(
                            color: AppColors.primaryCyan,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      )
                    else
                      StatusBadge.ble(ble.status, deviceName: ble.connectedDeviceName),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // Realtime Telemetry Graph
              RealtimeSensorChart(
                readings: testProv.currentSessionReadings,
                isDemo: isDemo,
                isLive: isTesting,
              ),

              const SizedBox(height: 14),

              // Sensor Gauges Grid
              Row(
                children: [
                  Expanded(
                    child: SensorGaugeCard(
                      title: "Sensor 1 (VOC/Aerosol)",
                      channelKey: "sensor_1",
                      currentValue: latest?.sensor1Value,
                      unit: latest?.sensors['sensor_1']?.unit ?? "raw",
                      warningThreshold: 280.0,
                      maxGaugeValue: 500.0,
                      sessionPeak: s1Peak,
                      sessionAvg: s1Avg,
                      isStale: !isDemo && ble.hasStaleData,
                      primaryColor: AppColors.primaryCyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SensorGaugeCard(
                      title: "Sensor 2 (Differential)",
                      channelKey: "sensor_2",
                      currentValue: latest?.sensor2Value,
                      unit: latest?.sensors['sensor_2']?.unit ?? "raw",
                      warningThreshold: 140.0,
                      maxGaugeValue: 250.0,
                      sessionPeak: s2Peak,
                      sessionAvg: s2Avg,
                      isStale: !isDemo && ble.hasStaleData,
                      primaryColor: AppColors.accentTeal,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Packet Metadata Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      latest != null
                          ? "Packet #${latest.sequence} • Status: ${latest.status}"
                          : "Packets Received: ${testProv.currentSessionReadings.length}",
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                    Text(
                      latest != null
                          ? DateFormatter.formatCompactTime(latest.timestamp)
                          : "--:--:--",
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Test Controls Section
              if (!isTesting) ...[
                if (!isDeviceReady)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.textMuted, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            "Connect ESP32 hardware via BLE, or toggle Demo Mode in Dashboard to test with simulated readings.",
                            style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                CustomButton(
                  text: "Start Screening Sampling",
                  icon: Icons.play_arrow_rounded,
                  height: 52,
                  onPressed: isDeviceReady
                      ? () async {
                          final uid = auth.currentUser?.uid ?? "officer";
                          await testProv.startTest(isDemo: isDemo, userId: uid);
                        }
                      : null,
                ),
              ] else ...[
                CustomButton(
                  text: "Stop Test & Analyze",
                  icon: Icons.stop_rounded,
                  isDanger: true,
                  height: 52,
                  onPressed: () async {
                    final uid = auth.currentUser?.uid ?? "officer";
                    final completedRecord = await testProv.stopTest(userId: uid);
                    if (completedRecord != null && context.mounted) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TestResultScreen(
                            record: completedRecord,
                            analysis: testProv.lastAnalysisResult,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
