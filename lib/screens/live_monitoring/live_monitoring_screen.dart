import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/test_provider.dart';
import '../../services/telemetry_service.dart';
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

    // Calculate peaks & averages across current session readings
    double? s1Peak;
    double? s2Peak;
    double? s3Peak;
    double? s1Avg;
    double? s2Avg;
    double? s3Avg;

    if (testProv.currentSessionReadings.isNotEmpty) {
      final s1List = testProv.currentSessionReadings
          .map((r) => r.mq2Value ?? r.sensor1Value)
          .whereType<double>()
          .toList();
      final s2List = testProv.currentSessionReadings
          .map((r) => r.mq4Value ?? r.sensor2Value)
          .whereType<double>()
          .toList();
      final s3List = testProv.currentSessionReadings
          .map((r) => r.mq7Value ?? r.sensor3Value)
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
      if (s3List.isNotEmpty) {
        s3Peak = s3List.reduce((a, b) => a > b ? a : b);
        s3Avg = s3List.reduce((a, b) => a + b) / s3List.length;
      }
    }

    final hasMissingChannels = !isDemo && latest != null && latest.hasMissingTelemetry;
    final isStale = !isDemo && ble.hasStaleData;

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
                  margin: const EdgeInsets.only(bottom: 12),
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

              // MISSING TELEMETRY WARNING (Physical Mode)
              if (hasMissingChannels)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.statusDanger.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.statusDanger.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.statusDanger, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "HARDWARE TELEMETRY INCOMPLETE",
                              style: GoogleFonts.inter(
                                color: AppColors.statusDanger,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              "Missing channel(s): ${latest.missingChannels.join(', ')}. Values are not fabricated.",
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

              // STALE TELEMETRY WARNING
              if (isStale)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.statusWarning.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.access_time_filled_rounded,
                          color: AppColors.statusWarning, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Telemetry Stale: No packet received for >5s from ESP32. Check peripheral link.",
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
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
                                  : (ble.isConnected ? "BLE MONITORING (STANDBY)" : "STANDBY READY"),
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
                isLive: isTesting || ble.isConnected,
              ),

              const SizedBox(height: 14),

              // Sensor Gauges Grid (All 3 Channels)
              Row(
                children: [
                  Expanded(
                    child: SensorGaugeCard(
                      title: isDemo ? "Sensor 1 (VOC)" : "MQ-2 (Gas/Smoke)",
                      channelKey: isDemo ? "sensor_1" : "mq2_raw",
                      currentValue: isDemo ? latest?.sensor1Value : latest?.mq2Value,
                      unit: isDemo ? "raw" : "ADC count",
                      warningThreshold: isDemo ? 280.0 : 2500.0,
                      maxGaugeValue: isDemo ? 500.0 : 4095.0,
                      sessionPeak: s1Peak,
                      sessionAvg: s1Avg,
                      isStale: isStale,
                      primaryColor: AppColors.primaryCyan,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SensorGaugeCard(
                      title: isDemo ? "Sensor 2 (Diff)" : "MQ-4 (Methane)",
                      channelKey: isDemo ? "sensor_2" : "mq4_raw",
                      currentValue: isDemo ? latest?.sensor2Value : latest?.mq4Value,
                      unit: isDemo ? "raw" : "ADC count",
                      warningThreshold: isDemo ? 140.0 : 2000.0,
                      maxGaugeValue: isDemo ? 250.0 : 4095.0,
                      sessionPeak: s2Peak,
                      sessionAvg: s2Avg,
                      isStale: isStale,
                      primaryColor: AppColors.accentTeal,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SensorGaugeCard(
                title: isDemo ? "Sensor 3 (CO Reference)" : "MQ-7 (Carbon Monoxide)",
                channelKey: isDemo ? "sensor_3" : "mq7_raw",
                currentValue: isDemo ? latest?.sensor3Value : latest?.mq7Value,
                unit: isDemo ? "raw" : "ADC count",
                warningThreshold: isDemo ? 180.0 : 1800.0,
                maxGaugeValue: isDemo ? 300.0 : 4095.0,
                sessionPeak: s3Peak,
                sessionAvg: s3Avg,
                isStale: isStale,
                primaryColor: AppColors.statusWarning,
              ),

              const SizedBox(height: 14),

              // Packet Metadata Bar & Cloud Sync State
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          latest != null
                              ? "Packet #${latest.sequence} • Mode: ${latest.mode.toUpperCase()}"
                              : "Packets: ${testProv.currentSessionReadings.length}",
                          style: GoogleFonts.inter(
                            color: AppColors.textSecondary,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 8),
                    const Divider(height: 1, color: AppColors.surfaceBorder),
                    const SizedBox(height: 8),
                    // Cloud Sync Status Row
                    _buildCloudSyncStatusRow(testProv.telemetryQueue),
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

  Widget _buildCloudSyncStatusRow(TelemetrySyncQueue? queue) {
    if (queue == null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Cloud Sync: Local Standby",
            style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
          ),
          const Icon(Icons.cloud_queue_rounded, size: 14, color: AppColors.textMuted),
        ],
      );
    }

    return StreamBuilder<TelemetrySyncState>(
      stream: queue.stateStream,
      initialData: queue.currentState,
      builder: (context, snapshot) {
        final state = snapshot.data ?? queue.currentState;

        Color statusColor = AppColors.textMuted;
        String statusText = "Cloud Idle";
        IconData statusIcon = Icons.cloud_done_rounded;

        switch (state.status) {
          case TelemetrySyncStatus.syncing:
            statusColor = AppColors.primaryCyan;
            statusText = "Syncing with Render (${state.queuedCount} queued)...";
            statusIcon = Icons.cloud_sync_rounded;
            break;
          case TelemetrySyncStatus.synced:
            statusColor = AppColors.statusSafe;
            statusText = "Render RTDB Synced (${state.totalSyncedCount} frames)";
            statusIcon = Icons.cloud_done_rounded;
            break;
          case TelemetrySyncStatus.offlineQueued:
            statusColor = AppColors.statusWarning;
            statusText = "Offline Queued (${state.queuedCount} pending)";
            statusIcon = Icons.cloud_off_rounded;
            break;
          case TelemetrySyncStatus.error:
            statusColor = AppColors.statusDanger;
            statusText = "Sync Error (${state.queuedCount} queued)";
            statusIcon = Icons.error_outline_rounded;
            break;
          case TelemetrySyncStatus.idle:
            statusColor = AppColors.textSecondary;
            statusText = state.totalSyncedCount > 0
                ? "Synced (${state.totalSyncedCount} frames)"
                : "Cloud Sync Ready";
            statusIcon = Icons.cloud_queue_rounded;
            break;
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  statusText,
                  style: GoogleFonts.inter(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (state.isOffline || state.hasError)
              InkWell(
                onTap: () => queue.retryNow(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text(
                    "Retry",
                    style: GoogleFonts.inter(
                      color: AppColors.primaryCyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
