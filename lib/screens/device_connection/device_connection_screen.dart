import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/date_formatter.dart';
import '../../models/device_info.dart';
import '../../providers/ble_provider.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/empty_state_view.dart';
import '../../widgets/status_badge.dart';

class DeviceConnectionScreen extends StatefulWidget {
  const DeviceConnectionScreen({super.key});

  @override
  State<DeviceConnectionScreen> createState() => _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState extends State<DeviceConnectionScreen> {
  @override
  void initState() {
    super.initState();
    // Auto start scan when screen opens if not connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ble = Provider.of<BleProvider>(context, listen: false);
      if (!ble.isConnected && !ble.isScanning) {
        ble.startScan();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ble = Provider.of<BleProvider>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Hardware Connection",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (ble.isScanning)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryCyan),
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: "Rescan",
              onPressed: () {
                ble.startScan();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Connection Status Overview
              Container(
                padding: const EdgeInsets.all(18),
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
                        Text(
                          "HARDWARE STATUS",
                          style: GoogleFonts.orbitron(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.0,
                          ),
                        ),
                        StatusBadge.ble(
                          ble.status,
                          deviceName: ble.connectedDeviceName,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (ble.isConnected) ...[
                      Text(
                        "Active Peripheral: ${ble.connectedDeviceName ?? 'ESP32 Device'}",
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ble.lastDataReceivedAt != null
                            ? "Last Telemetry: ${DateFormatter.formatTime(ble.lastDataReceivedAt!)}"
                            : "Awaiting first telemetry packet from hardware.",
                        style: GoogleFonts.inter(
                          color: ble.hasStaleData ? AppColors.statusWarning : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 14),
                      CustomButton(
                        text: "Disconnect Device",
                        isDanger: true,
                        icon: Icons.bluetooth_disabled_rounded,
                        height: 42,
                        onPressed: () async {
                          await ble.disconnect();
                        },
                      ),
                    ] else ...[
                      Text(
                        "Ensure your ESP32 handheld screening device is powered on and advertising BLE service.",
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
                              text: ble.isScanning ? "Stop Scanning" : "Scan for Devices",
                              icon: ble.isScanning ? Icons.stop_rounded : Icons.radar_rounded,
                              isSecondary: ble.isScanning,
                              height: 42,
                              onPressed: () {
                                if (ble.isScanning) {
                                  ble.stopScan();
                                } else {
                                  ble.startScan();
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Error notification banner if any
              if (ble.errorMessage != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.statusDanger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.statusDanger.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded,
                          color: AppColors.statusDanger, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          ble.errorMessage!,
                          style: GoogleFonts.inter(
                            color: AppColors.statusDanger,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          ble.clearError();
                          ble.startScan();
                        },
                        child: const Text("Retry"),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Discovered devices section title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "DISCOVERED BLE DEVICES",
                    style: GoogleFonts.orbitron(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    "${ble.discoveredDevices.length} found",
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Device List or Empty State
              Expanded(
                child: ble.discoveredDevices.isEmpty
                    ? (ble.isScanning
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 16),
                                Text(
                                  "Scanning for ESP32 and handheld screening hardware...",
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : EmptyStateView(
                            icon: Icons.bluetooth_searching_rounded,
                            title: "No Compatible Devices Found",
                            description:
                                "No BLE peripherals detected nearby. Verify that the ESP32 is powered on, within 10 meters, and not already paired to another phone.",
                            actionText: "Scan Again",
                            onAction: () => ble.startScan(),
                          ))
                    : ListView.separated(
                        itemCount: ble.discoveredDevices.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final device = ble.discoveredDevices[index];
                          return _buildDeviceTile(context, device, ble);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceTile(BuildContext context, DeviceInfo device, BleProvider ble) {
    final isESP32 = device.name.toUpperCase().contains("ESP32") ||
        device.name.toUpperCase().contains("RAILSAFE") ||
        device.name.toUpperCase().contains("SCREEN");

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isESP32
              ? AppColors.primaryCyan.withValues(alpha: 0.4)
              : AppColors.surfaceBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isESP32
                  ? AppColors.primaryBlue.withValues(alpha: 0.2)
                  : AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isESP32 ? Icons.memory_rounded : Icons.bluetooth_rounded,
              color: isESP32 ? AppColors.primaryCyan : AppColors.textMuted,
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
                    Flexible(
                      child: Text(
                        device.displayName,
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isESP32) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.primaryCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          "RECOMMENDED",
                          style: GoogleFonts.inter(
                            color: AppColors.primaryCyan,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  "UUID / MAC: ${device.id} • RSSI: ${device.rssi} dBm (${device.signalStrength})",
                  style: GoogleFonts.inter(
                    color: AppColors.textMuted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CustomButton(
            text: "Connect",
            fullWidth: false,
            height: 36,
            isLoading: ble.isConnecting,
            onPressed: () async {
              final ok = await ble.connect(device.id);
              if (ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.statusSafe,
                    content: Text("Connected to ${device.displayName}"),
                  ),
                );
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}
