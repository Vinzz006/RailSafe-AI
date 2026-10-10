import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/app_alert.dart';
import '../../providers/alerts_provider.dart';
import '../../services/railguard_api_service.dart';
import '../../widgets/empty_state_view.dart';
import 'railguard_alert_detail_screen.dart';

class AlertsScreen extends StatefulWidget {
  final int initialTabIndex;

  const AlertsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<RailGuardAlertModel> _visionAlerts = [];
  bool _isLoadingVision = false;
  String? _visionError;
  String _selectedFilter = 'all'; // 'all', 'unreviewed', 'verified', 'false_alarm'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
    _loadVisionAlerts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadVisionAlerts() async {
    final apiService = Provider.of<RailGuardApiService>(context, listen: false);
    setState(() {
      _isLoadingVision = true;
      _visionError = null;
    });

    try {
      final alerts = await apiService.getAlerts(
        limit: 50,
        unreviewedOnly: _selectedFilter == 'unreviewed',
        status: (_selectedFilter == 'verified' || _selectedFilter == 'false_alarm')
            ? _selectedFilter
            : null,
      );
      if (mounted) {
        setState(() {
          _visionAlerts = alerts;
          _isLoadingVision = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _visionError = e.toString().replaceAll("Exception: ", "");
          _isLoadingVision = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final alertsProv = Provider.of<AlertsProvider>(context);
    final systemAlerts = alertsProv.alerts;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Station Alerts & Screening",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.primaryCyan,
          indicatorWeight: 3,
          labelColor: AppColors.primaryCyan,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
          tabs: [
            Tab(
              icon: const Icon(Icons.luggage_outlined, size: 20),
              text: "Luggage Vision (${_visionAlerts.length})",
            ),
            Tab(
              icon: const Icon(Icons.sensors_rounded, size: 20),
              text: "Sensors & Events (${systemAlerts.length})",
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh Alerts",
            onPressed: _loadVisionAlerts,
          ),
          if (systemAlerts.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear_all_rounded),
              tooltip: "Clear Sensor Alerts",
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.surfaceCard,
                    title: const Text("Clear Sensor Alerts"),
                    content: const Text("Clear all logged hardware and telemetry events?"),
                    actions: [
                      TextButton(
                        child: const Text("Cancel"),
                        onPressed: () => Navigator.of(ctx).pop(false),
                      ),
                      TextButton(
                        child: const Text("Clear All", style: TextStyle(color: AppColors.statusDanger)),
                        onPressed: () => Navigator.of(ctx).pop(true),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await alertsProv.clearAlerts();
                }
              },
            ),
        ],
      ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildVisionAlertsTab(),
            _buildSystemAlertsTab(systemAlerts),
          ],
        ),
      ),
    );
  }

  Widget _buildVisionAlertsTab() {
    return RefreshIndicator(
      color: AppColors.primaryCyan,
      backgroundColor: AppColors.surfaceCard,
      onRefresh: _loadVisionAlerts,
      child: Column(
        children: [
          // Filter Chips
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: Row(
              children: [
                _buildFilterChip("All", 'all'),
                const SizedBox(width: 8),
                _buildFilterChip("Unreviewed", 'unreviewed'),
                const SizedBox(width: 8),
                _buildFilterChip("Verified", 'verified'),
                const SizedBox(width: 8),
                _buildFilterChip("False Alarm", 'false_alarm'),
              ],
            ),
          ),

          // Error Banner if present
          if (_visionError != null)
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.statusDanger.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.statusDanger),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: AppColors.statusDanger, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _visionError!,
                      style: GoogleFonts.inter(
                        color: AppColors.statusDanger,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadVisionAlerts,
                    child: const Text("Retry", style: TextStyle(color: AppColors.primaryCyan)),
                  ),
                ],
              ),
            ),

          // Alerts List or Empty
          Expanded(
            child: _isLoadingVision && _visionAlerts.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primaryCyan),
                  )
                : _visionAlerts.isEmpty
                    ? const EmptyStateView(
                        icon: Icons.luggage_outlined,
                        title: "No Luggage Alerts",
                        description:
                            "No unattended luggage alerts recorded. Real-time detections from station cameras will appear here.",
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: _visionAlerts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final alert = _visionAlerts[index];
                          return _buildVisionAlertCard(alert);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = value;
        });
        _loadVisionAlerts();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryCyan.withValues(alpha: 0.2)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primaryCyan : AppColors.surfaceBorder,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: isSelected ? AppColors.primaryCyan : AppColors.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildVisionAlertCard(RailGuardAlertModel alert) {
    Color statusColor;
    String statusText;
    if (alert.isVerified) {
      statusColor = AppColors.statusDanger;
      statusText = "VERIFIED";
    } else if (alert.isFalseAlarm) {
      statusColor = AppColors.primaryBlue;
      statusText = "FALSE ALARM";
    } else {
      statusColor = AppColors.statusWarning;
      statusText = "UNREVIEWED";
    }

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RailGuardAlertDetailScreen(alert: alert),
          ),
        );
        _loadVisionAlerts();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: statusColor.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.luggage_rounded, color: statusColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${alert.objectClass.toUpperCase()} (#${alert.trackId})",
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: statusColor, width: 0.6),
                        ),
                        child: Text(
                          statusText,
                          style: GoogleFonts.orbitron(
                            color: statusColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${alert.reason} on ${alert.cameraId}. Unattended: ${alert.eventDuration.toStringAsFixed(1)}s",
                    style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "${DateFormatter.formatDate(alert.timestamp)} ${DateFormatter.formatTime(alert.timestamp)}",
                        style: GoogleFonts.inter(
                          color: AppColors.textMuted,
                          fontSize: 10.5,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            "Review Evidence",
                            style: GoogleFonts.inter(
                              color: AppColors.primaryCyan,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 14, color: AppColors.primaryCyan),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemAlertsTab(List<AppAlert> alerts) {
    if (alerts.isEmpty) {
      return const EmptyStateView(
        icon: Icons.notifications_none_rounded,
        title: "No System Alerts",
        description: "Hardware connection changes, test completions, and system events will appear here.",
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: alerts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final alert = alerts[index];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: alert.color.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: alert.color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(alert.icon, color: alert.color, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          alert.title,
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          DateFormatter.formatTime(alert.timestamp),
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      alert.message,
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    if (alert.relatedTestId != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "Ref: ${alert.relatedTestId}",
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
