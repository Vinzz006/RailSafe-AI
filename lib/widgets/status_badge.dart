import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../services/ble_service.dart';

class StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool isPulsing;
  final bool outlined;

  const StatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.isPulsing = false,
    this.outlined = false,
  });

  factory StatusBadge.ble(BleStatus status, {String? deviceName}) {
    switch (status) {
      case BleStatus.connected:
        return StatusBadge(
          label: deviceName != null && deviceName.isNotEmpty
              ? "Connected: $deviceName"
              : "BLE Hardware Connected",
          color: AppColors.statusSafe,
          icon: Icons.bluetooth_connected_rounded,
          isPulsing: true,
        );
      case BleStatus.connecting:
        return const StatusBadge(
          label: "Connecting to ESP32...",
          color: AppColors.statusWarning,
          icon: Icons.bluetooth_searching_rounded,
          isPulsing: true,
        );
      case BleStatus.scanning:
        return const StatusBadge(
          label: "Scanning for BLE Peripherals...",
          color: AppColors.primaryCyan,
          icon: Icons.radar_rounded,
          isPulsing: true,
        );
      case BleStatus.disconnecting:
        return const StatusBadge(
          label: "Disconnecting...",
          color: AppColors.textMuted,
          icon: Icons.bluetooth_disabled_rounded,
        );
      case BleStatus.disconnected:
        return const StatusBadge(
          label: "No BLE Hardware Connected",
          color: AppColors.textMuted,
          icon: Icons.bluetooth_disabled_rounded,
        );
    }
  }

  factory StatusBadge.demoMode({bool compact = false}) {
    return StatusBadge(
      label: compact ? "DEMO MODE" : "DEMO MODE — SIMULATED DATA",
      color: AppColors.statusWarning,
      icon: Icons.science_outlined,
      outlined: false,
    );
  }

  factory StatusBadge.syncStatus(bool isSynced) {
    if (isSynced) {
      return const StatusBadge(
        label: "Synced to Cloud",
        color: AppColors.statusSafe,
        icon: Icons.cloud_done_rounded,
      );
    } else {
      return const StatusBadge(
        label: "Local Storage (Unsynced)",
        color: AppColors.textSecondary,
        icon: Icons.cloud_off_rounded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: outlined ? 0.6 : 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
          ] else if (isPulsing) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
