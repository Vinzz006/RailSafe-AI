import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_colors.dart';

class SensorGaugeCard extends StatelessWidget {
  final String title;
  final String channelKey;
  final double? currentValue;
  final String unit;
  final double warningThreshold;
  final double maxGaugeValue;
  final double? sessionPeak;
  final double? sessionAvg;
  final bool isStale;
  final Color primaryColor;

  const SensorGaugeCard({
    super.key,
    required this.title,
    required this.channelKey,
    required this.currentValue,
    required this.unit,
    this.warningThreshold = 280.0,
    this.maxGaugeValue = 500.0,
    this.sessionPeak,
    this.sessionAvg,
    this.isStale = false,
    this.primaryColor = AppColors.primaryCyan,
  });

  @override
  Widget build(BuildContext context) {
    final val = currentValue ?? 0.0;
    final isElevated = val >= warningThreshold;
    final progress = (val / maxGaugeValue).clamp(0.0, 1.0);
    final activeColor = isElevated ? AppColors.statusDanger : primaryColor;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isElevated
              ? AppColors.statusDanger.withValues(alpha: 0.7)
              : AppColors.surfaceBorder,
          width: isElevated ? 1.5 : 1,
        ),
        boxShadow: isElevated
            ? [
                BoxShadow(
                  color: AppColors.statusDanger.withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isStale)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.statusWarning.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "STALE",
                    style: GoogleFonts.inter(
                      color: AppColors.statusWarning,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              else if (isElevated)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.statusDanger.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    "ELEVATED",
                    style: GoogleFonts.inter(
                      color: AppColors.statusDanger,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                currentValue != null ? val.toStringAsFixed(1) : "--.-",
                style: GoogleFonts.orbitron(
                  color: currentValue != null ? activeColor : AppColors.textMuted,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                unit,
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Visual level meter
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surface,
              valueColor: AlwaysStoppedAnimation<Color>(activeColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Peak: ${sessionPeak != null ? sessionPeak!.toStringAsFixed(1) : '--'} $unit",
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
              Text(
                "Avg: ${sessionAvg != null ? sessionAvg!.toStringAsFixed(1) : '--'} $unit",
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
