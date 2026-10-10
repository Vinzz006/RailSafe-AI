import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/test_record.dart';
import '../../providers/auth_provider.dart';
import '../../providers/test_provider.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/status_badge.dart';
import 'test_detail_screen.dart';

class TestHistoryScreen extends StatefulWidget {
  const TestHistoryScreen({super.key});

  @override
  State<TestHistoryScreen> createState() => _TestHistoryScreenState();
}

class _TestHistoryScreenState extends State<TestHistoryScreen> {
  String _filter = 'all'; // 'all', 'hardware', 'demo', 'flagged'

  @override
  Widget build(BuildContext context) {
    final testProv = Provider.of<TestProvider>(context);
    final auth = Provider.of<AuthProvider>(context);
    final allTests = testProv.savedTests;

    final filteredTests = allTests.where((t) {
      if (_filter == 'hardware') return !t.isDemo;
      if (_filter == 'demo') return t.isDemo;
      if (_filter == 'flagged') return t.screeningAssistanceStatus.contains("Anomaly");
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Screening Test History",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          // Cloud sync action
          IconButton(
            icon: testProv.isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: "Sync with Cloud Firestore",
            onPressed: testProv.isSyncing
                ? null
                : () async {
                    final uid = auth.currentUser?.uid ?? "officer";
                    final res = await testProv.syncPendingTests(uid);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: res.success ? AppColors.statusSafe : AppColors.statusWarning,
                          content: Text(res.message),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Filter Pills
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.surface,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip("All Tests (${allTests.length})", 'all'),
                    const SizedBox(width: 8),
                    _buildFilterChip("Hardware", 'hardware'),
                    const SizedBox(width: 8),
                    _buildFilterChip("Demo Mode", 'demo'),
                    const SizedBox(width: 8),
                    _buildFilterChip("Flagged Anomalies", 'flagged'),
                  ],
                ),
              ),
            ),

            // List of tests
            Expanded(
              child: filteredTests.isEmpty
                  ? EmptyStateView(
                      icon: Icons.history_rounded,
                      title: "No Test Records Found",
                      description: _filter == 'all'
                          ? "Complete a screening test session from the Live Monitoring screen to save records."
                          : "No records match the selected filter category.",
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredTests.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final test = filteredTests[index];
                        return _buildTestCard(context, test, testProv);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryBlue : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryCyan : AppColors.surfaceBorder,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildTestCard(BuildContext context, TestRecord test, TestProvider testProv) {
    final isFlagged = test.screeningAssistanceStatus.contains("Anomaly");
    final statusColor = isFlagged ? AppColors.statusDanger : AppColors.statusSafe;

    return Dismissible(
      key: Key(test.testId),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.statusDanger.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Colors.white),
      ),
      onDismissed: (_) {
        testProv.deleteTest(test.testId);
      },
      child: GestureDetector(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TestDetailScreen(record: test)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFlagged
                  ? AppColors.statusDanger.withValues(alpha: 0.5)
                  : AppColors.surfaceBorder,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    test.testId,
                    style: GoogleFonts.orbitron(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      if (test.isDemo)
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
                      StatusBadge.syncStatus(test.syncedToFirestore),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                test.screeningAssistanceStatus,
                style: GoogleFonts.inter(
                  color: statusColor,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildMiniMetric(
                    "Peak S1",
                    "${test.metrics['sensor_1_max'] ?? '--'} ppm",
                  ),
                  const SizedBox(width: 16),
                  _buildMiniMetric(
                    "Peak S2",
                    "${test.metrics['sensor_2_max'] ?? '--'} mV",
                  ),
                  const SizedBox(width: 16),
                  _buildMiniMetric(
                    "Samples",
                    "${test.sensorReadings.length}",
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Device: ${test.deviceId}",
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                  Text(
                    DateFormatter.formatDateTime(test.completedAt),
                    style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniMetric(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 10),
        ),
        Text(
          value,
          style: GoogleFonts.inter(
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
