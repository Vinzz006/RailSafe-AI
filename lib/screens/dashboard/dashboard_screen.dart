import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/utils/date_formatter.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ble_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/test_provider.dart';
import '../../widgets/app_brand_logo.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/status_badge.dart';
import '../alerts/alerts_screen.dart';
import '../device_connection/device_connection_screen.dart';
import '../live_monitoring/live_monitoring_screen.dart';
import '../settings/settings_screen.dart';
import '../test_history/test_detail_screen.dart';
import '../test_history/test_history_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final ble = Provider.of<BleProvider>(context);
    final testProv = Provider.of<TestProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final alerts = Provider.of<AlertsProvider>(context);

    final user = auth.currentUser;
    final savedTests = testProv.savedTests;
    final latestTest = savedTests.isNotEmpty ? savedTests.first : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Row(
          children: [
            const AppBrandLogo(size: 32, compact: true),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "RAILSAFE AI",
                  style: GoogleFonts.orbitron(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  user?.stationCode ?? "Indian Railways",
                  style: GoogleFonts.inter(
                    fontSize: 10.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Alerts button with badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none_rounded),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AlertsScreen()),
                  );
                },
              ),
              if (alerts.alerts.isNotEmpty)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: AppColors.statusDanger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
                  ),
                ),
            ],
          ),
          // Settings button
          IconButton(
            icon: const Icon(Icons.tune_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primaryCyan,
          backgroundColor: AppColors.surfaceCard,
          onRefresh: () async {
            if (user != null) {
              await testProv.syncPendingTests(user.uid);
            }
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Welcome Officer Banner
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.cardGradient,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.surfaceBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primaryCyan.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.security_rounded,
                          color: AppColors.primaryCyan,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Welcome, ${user?.displayName ?? 'Screening Officer'}",
                              style: GoogleFonts.inter(
                                color: AppColors.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user?.role ?? "RPF Screening Officer",
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Hardware Connection Status Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ble.isConnected
                          ? AppColors.statusSafe.withValues(alpha: 0.5)
                          : AppColors.surfaceBorder,
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
                                ble.isConnected
                                    ? Icons.bluetooth_connected_rounded
                                    : Icons.bluetooth_disabled_rounded,
                                color: ble.isConnected
                                    ? AppColors.statusSafe
                                    : AppColors.textMuted,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "HARDWARE STATUS",
                                style: GoogleFonts.orbitron(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          StatusBadge.ble(
                            ble.status,
                            deviceName: ble.connectedDeviceName,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        ble.isConnected
                            ? "Connected to ESP32: ${ble.connectedDeviceName ?? 'ESP32 Device'}. Ready for live telemetry."
                            : "No physical screening hardware connected over Bluetooth Low Energy.",
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: CustomButton(
                              text: ble.isConnected ? "Manage Device" : "Connect Device",
                              icon: Icons.bluetooth_searching_rounded,
                              isSecondary: true,
                              height: 42,
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const DeviceConnectionScreen(),
                                  ),
                                );
                              },
                            ),
                          ),
                          if (ble.isConnected) ...[
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: "Disconnect",
                              icon: const Icon(Icons.close_rounded, color: AppColors.statusDanger),
                              style: IconButton.styleFrom(
                                backgroundColor: AppColors.statusDanger.withValues(alpha: 0.1),
                              ),
                              onPressed: () async {
                                await ble.disconnect();
                              },
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // Demo Mode Toggle Card
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: settings.isDemoModeEnabled
                        ? AppColors.statusWarning.withValues(alpha: 0.08)
                        : AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: settings.isDemoModeEnabled
                          ? AppColors.statusWarning.withValues(alpha: 0.5)
                          : AppColors.surfaceBorder,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: settings.isDemoModeEnabled
                              ? AppColors.statusWarning.withValues(alpha: 0.2)
                              : AppColors.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.science_rounded,
                          color: settings.isDemoModeEnabled
                              ? AppColors.statusWarning
                              : AppColors.textMuted,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "Demo Simulation Mode",
                                  style: GoogleFonts.inter(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (settings.isDemoModeEnabled) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: AppColors.statusWarning.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "ACTIVE",
                                      style: GoogleFonts.inter(
                                        color: AppColors.statusWarning,
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              "Simulates telemetry when ESP32 is offline (${settings.demoScenario.toUpperCase()})",
                              style: GoogleFonts.inter(
                                color: AppColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: settings.isDemoModeEnabled,
                        activeThumbColor: AppColors.statusWarning,
                        activeTrackColor: AppColors.statusWarning.withValues(alpha: 0.3),
                        inactiveThumbColor: AppColors.textMuted,
                        inactiveTrackColor: AppColors.surface,
                        onChanged: (val) {
                          settings.setDemoMode(val);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // Primary Start Test Action
                CustomButton(
                  text: testProv.isTesting ? "View Active Test" : "Start Screening Test",
                  icon: testProv.isTesting
                      ? Icons.sensors_rounded
                      : Icons.play_arrow_rounded,
                  height: 54,
                  onPressed: () {
                    // Navigate to Live Monitoring Screen
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LiveMonitoringScreen(),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                // Quick Statistics Row
                Row(
                  children: [
                    Expanded(
                      child: _buildMetricCard(
                        title: "SAVED TESTS",
                        value: savedTests.length.toString(),
                        icon: Icons.assignment_outlined,
                        color: AppColors.primaryCyan,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TestHistoryScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMetricCard(
                        title: "EVENTS & ALERTS",
                        value: alerts.alerts.length.toString(),
                        icon: Icons.notifications_active_outlined,
                        color: AppColors.statusWarning,
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AlertsScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // RailGuard Vision Surveillance Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.primaryCyan.withValues(alpha: 0.35),
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
                              const Icon(
                                Icons.videocam_outlined,
                                color: AppColors.primaryCyan,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "RAILGUARD VISION SURVEILLANCE",
                                style: GoogleFonts.orbitron(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primaryCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "RENDER CLOUD",
                              style: GoogleFonts.orbitron(
                                color: AppColors.primaryCyan,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        "Station unattended luggage early-warning prototype. Review camera snapshots, verify platform alerts, or flag false alarms.",
                        style: GoogleFonts.inter(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      CustomButton(
                        text: "Review Luggage Vision Alerts",
                        icon: Icons.luggage_outlined,
                        isSecondary: true,
                        height: 40,
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const AlertsScreen(initialTabIndex: 0),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Latest Test Result Card
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "LATEST SCREENING RECORD",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    if (savedTests.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const TestHistoryScreen(),
                            ),
                          );
                        },
                        child: Text(
                          "View All (${savedTests.length})",
                          style: GoogleFonts.inter(
                            color: AppColors.primaryCyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),

                if (latestTest != null)
                  GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => TestDetailScreen(record: latestTest),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.surfaceBorder),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                latestTest.testId,
                                style: GoogleFonts.orbitron(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Row(
                                children: [
                                  if (latestTest.isDemo)
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
                                  StatusBadge.syncStatus(latestTest.syncedToFirestore),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            latestTest.screeningAssistanceStatus,
                            style: GoogleFonts.inter(
                              color: latestTest.screeningAssistanceStatus.contains("Anomaly")
                                  ? AppColors.statusDanger
                                  : AppColors.statusSafe,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Device: ${latestTest.deviceId}",
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                              Text(
                                DateFormatter.formatDateTime(latestTest.completedAt),
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.surfaceBorder),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.note_alt_outlined, color: AppColors.textMuted, size: 32),
                          const SizedBox(height: 8),
                          Text(
                            "No Screening Tests Completed Yet",
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Initiate a test to log screening measurements.",
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 24),

                // Disclaimer Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.surfaceBorder.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          AppConstants.prototypeDisclaimer,
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                Icon(icon, color: color, size: 18),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: GoogleFonts.orbitron(
                color: AppColors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
