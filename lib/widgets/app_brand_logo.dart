import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/constants/app_colors.dart';

class AppBrandLogo extends StatelessWidget {
  final double size;
  final bool showSubtitle;
  final bool compact;

  const AppBrandLogo({
    super.key,
    this.size = 56,
    this.showSubtitle = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final emblem = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFF1E3A8A),
            Color(0xFF0F172A),
          ],
        ),
        border: Border.all(color: AppColors.primaryCyan.withValues(alpha: 0.6), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryCyan.withValues(alpha: 0.25),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: CustomPaint(
          size: Size(size * 0.65, size * 0.65),
          painter: _RailSafeEmblemPainter(),
        ),
      ),
    );

    if (compact) {
      return emblem;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        emblem,
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              "RAILSAFE",
              style: GoogleFonts.orbitron(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                gradient: AppColors.brandGradient,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "AI",
                style: GoogleFonts.orbitron(
                  color: AppColors.background,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ],
        ),
        if (showSubtitle) ...[
          const SizedBox(height: 4),
          Text(
            "HANDHELD SCREENING ASSISTANCE",
            style: GoogleFonts.inter(
              color: AppColors.primaryCyan,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "INDIAN RAILWAYS PROTOTYPE",
            style: GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ],
    );
  }
}

class _RailSafeEmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final railPaint = Paint()
      ..color = AppColors.primaryCyan
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    final beamPaint = Paint()
      ..color = AppColors.accentTeal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    final dotPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // Draw converging railway tracks
    final path = Path();
    // Left track
    path.moveTo(w * 0.18, h * 0.88);
    path.lineTo(w * 0.44, h * 0.28);
    // Right track
    path.moveTo(w * 0.82, h * 0.88);
    path.lineTo(w * 0.56, h * 0.28);

    canvas.drawPath(path, railPaint);

    // Sleepers (railway cross ties)
    canvas.drawLine(Offset(w * 0.25, h * 0.78), Offset(w * 0.75, h * 0.78), railPaint);
    canvas.drawLine(Offset(w * 0.32, h * 0.60), Offset(w * 0.68, h * 0.60), railPaint);
    canvas.drawLine(Offset(w * 0.38, h * 0.44), Offset(w * 0.62, h * 0.44), railPaint);

    // AI Scanner focal radar arc at convergence apex
    final arcRect = Rect.fromCircle(center: Offset(w * 0.5, h * 0.26), radius: w * 0.24);
    canvas.drawArc(arcRect, 3.14 * 1.15, 3.14 * 0.7, false, beamPaint);

    // Center focal sensor diode
    canvas.drawCircle(Offset(w * 0.5, h * 0.26), 3.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
