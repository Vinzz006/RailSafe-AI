import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../services/railguard_api_service.dart';
import '../../widgets/custom_button.dart';

class RailGuardAlertDetailScreen extends StatefulWidget {
  final RailGuardAlertModel alert;

  const RailGuardAlertDetailScreen({super.key, required this.alert});

  @override
  State<RailGuardAlertDetailScreen> createState() => _RailGuardAlertDetailScreenState();
}

class _RailGuardAlertDetailScreenState extends State<RailGuardAlertDetailScreen> {
  late RailGuardAlertModel _currentAlert;
  Future<Uint8List>? _snapshotBytesFuture;
  bool _isSubmittingReview = false;
  String? _actionError;

  @override
  void initState() {
    super.initState();
    _currentAlert = widget.alert;
    _loadSnapshot();
  }

  void _loadSnapshot() {
    final apiService = Provider.of<RailGuardApiService>(context, listen: false);
    setState(() {
      _snapshotBytesFuture = apiService.fetchSnapshotBytes(_currentAlert.id);
    });
  }

  Future<void> _submitReview(String newStatus) async {
    if (_isSubmittingReview) return;
    setState(() {
      _isSubmittingReview = true;
      _actionError = null;
    });

    final apiService = Provider.of<RailGuardApiService>(context, listen: false);
    try {
      final updated = await apiService.reviewAlert(_currentAlert.id, newStatus);
      if (mounted) {
        setState(() {
          _currentAlert = updated;
          _isSubmittingReview = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'verified'
                  ? "Alert verified successfully."
                  : "Alert marked as false alarm.",
            ),
            backgroundColor: newStatus == 'verified'
                ? AppColors.statusDanger
                : AppColors.statusSafe,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmittingReview = false;
          _actionError = e.toString().replaceAll("Exception: ", "");
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Alert Details #${_currentAlert.trackId}",
          style: GoogleFonts.inter(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Safety Disclaimer Notice
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.statusWarning.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.statusWarning,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "SCREENING ASSISTANCE NOTICE",
                            style: GoogleFonts.orbitron(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.statusWarning,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _currentAlert.disclaimer,
                            style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 11.5,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Evidence Snapshot Preview Card
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.camera_alt_outlined,
                                color: AppColors.primaryCyan,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "SNAPSHOT EVIDENCE",
                                style: GoogleFonts.orbitron(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ),
                          _buildReviewBadge(_currentAlert.reviewStatus),
                        ],
                      ),
                    ),
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Container(
                        color: Colors.black26,
                        child: FutureBuilder<Uint8List>(
                          future: _snapshotBytesFuture,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: AppColors.primaryCyan,
                                  strokeWidth: 2.5,
                                ),
                              );
                            }

                            if (snapshot.hasError || !snapshot.hasData) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.image_not_supported_outlined,
                                        color: AppColors.textMuted,
                                        size: 40,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        "Evidence snapshot unavailable",
                                        style: GoogleFonts.inter(
                                          color: AppColors.textSecondary,
                                          fontSize: 12,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextButton.icon(
                                        icon: const Icon(Icons.refresh, size: 16),
                                        label: const Text("Retry"),
                                        onPressed: _loadSnapshot,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            return GestureDetector(
                              onTap: () {
                                _showFullScreenImage(context, snapshot.data!);
                              },
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                  ),
                                  Positioned(
                                    bottom: 8,
                                    right: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.zoom_in,
                                            size: 14,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            "Tap to zoom",
                                            style: GoogleFonts.inter(
                                              color: Colors.white,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Alert Metadata Information Card
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
                      "EVENT ATTRIBUTES",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _buildMetaRow("Camera Source", _currentAlert.cameraId, Icons.videocam_outlined),
                    _buildMetaRow("Track ID", "#${_currentAlert.trackId}", Icons.tag),
                    _buildMetaRow("Detected Object", _currentAlert.objectClass.toUpperCase(), Icons.luggage_outlined),
                    _buildMetaRow(
                      "Unattended Duration",
                      "${_currentAlert.eventDuration.toStringAsFixed(1)} seconds",
                      Icons.timer_outlined,
                    ),
                    _buildMetaRow(
                      "Timestamp",
                      "${DateFormatter.formatDate(_currentAlert.timestamp)} ${DateFormatter.formatTime(_currentAlert.timestamp)}",
                      Icons.schedule,
                    ),
                    _buildMetaRow("Condition", _currentAlert.reason, Icons.info_outline),
                    if (_currentAlert.reviewedBy != null)
                      _buildMetaRow(
                        "Reviewed By",
                        _currentAlert.reviewedBy!,
                        Icons.verified_user_outlined,
                      ),
                    if (_currentAlert.reviewedAt != null)
                      _buildMetaRow(
                        "Reviewed At",
                        DateFormatter.formatTime(_currentAlert.reviewedAt!),
                        Icons.check_circle_outline,
                      ),
                    if (_currentAlert.isCleared)
                      _buildMetaRow(
                        "Platform Status",
                        "Luggage Retrieved/Moved (${DateFormatter.formatTime(_currentAlert.clearedTimestamp!)})",
                        Icons.assignment_turned_in_outlined,
                      ),
                  ],
                ),
              ),

              if (_actionError != null) ...[
                const SizedBox(height: 12),
                Container(
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
                          _actionError!,
                          style: GoogleFonts.inter(
                            color: AppColors.statusDanger,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Operator Review Actions
              Text(
                "OPERATOR REVIEW ACTIONS",
                style: GoogleFonts.orbitron(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: CustomButton(
                      text: _currentAlert.isVerified ? "Verified (Active)" : "Mark Verified",
                      icon: Icons.check_circle_rounded,
                      isDanger: true,
                      height: 48,
                      isLoading: _isSubmittingReview && _currentAlert.reviewStatus != 'verified',
                      onPressed: _isSubmittingReview
                          ? null
                          : () => _submitReview('verified'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CustomButton(
                      text: _currentAlert.isFalseAlarm
                          ? "False Alarm (Active)"
                          : "Mark False Alarm",
                      icon: Icons.cancel_outlined,
                      isSecondary: true,
                      height: 48,
                      isLoading: _isSubmittingReview && _currentAlert.reviewStatus != 'false_alarm',
                      onPressed: _isSubmittingReview
                          ? null
                          : () => _submitReview('false_alarm'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textMuted),
          const SizedBox(width: 10),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: AppColors.textSecondary,
                fontSize: 12.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.inter(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBadge(String status) {
    Color color;
    String text;
    if (status == 'verified') {
      color = AppColors.statusDanger;
      text = "VERIFIED";
    } else if (status == 'false_alarm') {
      color = AppColors.primaryBlue;
      text = "FALSE ALARM";
    } else {
      color = AppColors.statusWarning;
      text = "UNREVIEWED";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color, width: 0.8),
      ),
      child: Text(
        text,
        style: GoogleFonts.orbitron(
          color: color,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, Uint8List bytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
