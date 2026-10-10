import 'package:flutter/material.dart';

class AppColors {
  // Deep railway navy & charcoal palette
  static const Color background = Color(0xFF0A0F1D);
  static const Color surface = Color(0xFF131D31);
  static const Color surfaceCard = Color(0xFF18243E);
  static const Color surfaceCardElevated = Color(0xFF1E2E4E);
  static const Color surfaceBorder = Color(0xFF263A63);
  static const Color surfaceBorderGlow = Color(0xFF355288);

  // Brand Accents
  static const Color primaryCyan = Color(0xFF00E5FF);
  static const Color primaryBlue = Color(0xFF1E88E5);
  static const Color accentTeal = Color(0xFF00E5BA);
  static const Color accentIndigo = Color(0xFF5E60CE);

  // Status & Safety Indicators
  static const Color statusSafe = Color(0xFF00E676);
  static const Color statusWarning = Color(0xFFFFB300);
  static const Color statusDanger = Color(0xFFFF3D57);
  static const Color statusInfo = Color(0xFF29B6F6);

  // Typography Colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textCyan = Color(0xFF38BDF8);

  // Gradients
  static const LinearGradient brandGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF1E88E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF142038), Color(0xFF182643)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient alertGradient = LinearGradient(
    colors: [Color(0x33FF3D57), Color(0x11FF3D57)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0x33FFB300), Color(0x11FFB300)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient safeGradient = LinearGradient(
    colors: [Color(0x3300E676), Color(0x1100E676)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
