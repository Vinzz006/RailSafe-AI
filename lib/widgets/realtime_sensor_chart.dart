import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_colors.dart';
import '../models/sensor_reading.dart';

class RealtimeSensorChart extends StatelessWidget {
  final List<SensorReading> readings;
  final bool isDemo;
  final bool isLive;

  const RealtimeSensorChart({
    super.key,
    required this.readings,
    this.isDemo = false,
    this.isLive = true,
  });

  @override
  Widget build(BuildContext context) {
    if (readings.isEmpty) {
      return Container(
        height: 240,
        decoration: BoxDecoration(
          color: AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.surfaceBorder),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLive ? Icons.show_chart_rounded : Icons.hourglass_empty_rounded,
                size: 38,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 10),
              Text(
                isLive ? "Awaiting Telemetry Packets..." : "No Sensor Readings Recorded",
                style: GoogleFonts.inter(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                isDemo
                    ? "Start Demo Test to stream simulated packets"
                    : "Connect ESP32 via BLE to stream real-time data",
                style: GoogleFonts.inter(
                  color: AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Keep up to 30 most recent data points for smooth responsive charting
    final displayData = readings.length > 30
        ? readings.sublist(readings.length - 30)
        : readings;

    final s1Spots = <FlSpot>[];
    final s2Spots = <FlSpot>[];

    double maxY = 100.0;

    for (int i = 0; i < displayData.length; i++) {
      final r = displayData[i];
      final s1Val = r.sensor1Value ?? 0.0;
      final s2Val = r.sensor2Value ?? 0.0;

      s1Spots.add(FlSpot(i.toDouble(), s1Val));
      s2Spots.add(FlSpot(i.toDouble(), s2Val));

      if (s1Val > maxY) maxY = s1Val * 1.15;
      if (s2Val > maxY) maxY = s2Val * 1.15;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isLive ? AppColors.statusSafe : AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isLive ? "REAL-TIME TELEMETRY TRACE" : "TELEMETRY OVERVIEW",
                    style: GoogleFonts.orbitron(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildLegendIndicator("S1 (VOC)", AppColors.primaryCyan),
                  const SizedBox(width: 14),
                  _buildLegendIndicator("S2 (Diff)", AppColors.accentTeal),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxY > 200 ? 50 : 25,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: AppColors.surfaceBorder.withValues(alpha: 0.6),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (displayData.length / 5).clamp(1.0, 10.0),
                      getTitlesWidget: (value, meta) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            "${value.toInt()}s",
                            style: GoogleFonts.inter(
                              color: AppColors.textMuted,
                              fontSize: 9.5,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: GoogleFonts.inter(
                            color: AppColors.textMuted,
                            fontSize: 9.5,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (displayData.length - 1).toDouble() > 0 ? (displayData.length - 1).toDouble() : 1.0,
                minY: 0,
                maxY: maxY,
                lineBarsData: [
                  LineChartBarData(
                    spots: s1Spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: AppColors.primaryCyan,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryCyan.withValues(alpha: 0.25),
                          AppColors.primaryCyan.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  LineChartBarData(
                    spots: s2Spots,
                    isCurved: true,
                    curveSmoothness: 0.25,
                    color: AppColors.accentTeal,
                    barWidth: 2.0,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.accentTeal.withValues(alpha: 0.15),
                          AppColors.accentTeal.withValues(alpha: 0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
