import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';

enum AlertSeverity {
  info,
  success,
  warning,
  danger,
}

class AppAlert {
  final String id;
  final String type;
  final String title;
  final String message;
  final AlertSeverity severity;
  final DateTime timestamp;
  final String? relatedTestId;

  AppAlert({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.severity,
    DateTime? timestamp,
    this.relatedTestId,
  }) : timestamp = timestamp ?? DateTime.now();

  Color get color {
    switch (severity) {
      case AlertSeverity.success:
        return AppColors.statusSafe;
      case AlertSeverity.warning:
        return AppColors.statusWarning;
      case AlertSeverity.danger:
        return AppColors.statusDanger;
      case AlertSeverity.info:
        return AppColors.statusInfo;
    }
  }

  IconData get icon {
    switch (severity) {
      case AlertSeverity.success:
        return Icons.check_circle_rounded;
      case AlertSeverity.warning:
        return Icons.warning_amber_rounded;
      case AlertSeverity.danger:
        return Icons.error_outline_rounded;
      case AlertSeverity.info:
        return Icons.info_outline_rounded;
    }
  }

  factory AppAlert.fromJson(Map<String, dynamic> json) {
    AlertSeverity sev = AlertSeverity.info;
    final sevStr = json['severity']?.toString().toLowerCase();
    if (sevStr == 'success') sev = AlertSeverity.success;
    if (sevStr == 'warning') sev = AlertSeverity.warning;
    if (sevStr == 'danger') sev = AlertSeverity.danger;

    return AppAlert(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? 'system',
      title: json['title']?.toString() ?? 'System Event',
      message: json['message']?.toString() ?? '',
      severity: sev,
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
      relatedTestId: json['relatedTestId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'title': title,
        'message': message,
        'severity': severity.name,
        'timestamp': timestamp.toIso8601String(),
        if (relatedTestId != null) 'relatedTestId': relatedTestId,
      };
}
