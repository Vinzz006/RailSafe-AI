import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/local_storage_service.dart';
import '../../services/prediction_api_service.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../auth/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _serviceUuidController = TextEditingController();
  final _dataCharUuidController = TextEditingController();
  final _cmdCharUuidController = TextEditingController();
  final _backendUrlController = TextEditingController();
  int _staleTimeout = 4;
  bool _isTestingBackend = false;
  String? _backendHealthStatus;
  bool? _backendHealthOk;

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _serviceUuidController.text = settings.serviceUuid;
    _dataCharUuidController.text = settings.dataCharUuid;
    _cmdCharUuidController.text = settings.cmdCharUuid;
    _backendUrlController.text = settings.backendUrl;
    _staleTimeout = settings.staleTimeoutSeconds;
  }

  @override
  void dispose() {
    _serviceUuidController.dispose();
    _dataCharUuidController.dispose();
    _cmdCharUuidController.dispose();
    _backendUrlController.dispose();
    super.dispose();
  }

  void _showFirebaseSetupGuide(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surfaceCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        expand: false,
        builder: (_, scrollController) => Padding(
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.cloud_upload_rounded, color: AppColors.primaryCyan),
                  const SizedBox(width: 10),
                  Text(
                    "Firebase Setup & Cloud Sync Guide",
                    style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "RailSafe AI works completely offline out of the box using local storage. To activate multi-device cloud synchronization with Firebase:",
                style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 16),
              _buildStep(
                "Step 1: Create Firebase Project",
                "Navigate to console.firebase.google.com and create a project named 'RailSafe AI'.",
              ),
              _buildStep(
                "Step 2: Register Android Application",
                "Add an Android app with package name:\n'com.railsafe.railsafe_ai'.",
              ),
              _buildStep(
                "Step 3: Download Configuration File",
                "Download 'google-services.json' and place it into:\n'android/app/google-services.json'.",
              ),
              _buildStep(
                "Step 4: Enable Authentication & Firestore",
                "In Firebase Console, enable 'Email/Password' under Authentication sign-in methods, and create a Cloud Firestore database in Native mode.",
              ),
              _buildStep(
                "Step 5: Apply Security Rules",
                "Deploy the provided 'firestore.rules' file to restrict record read/write operations strictly to authenticated user IDs.",
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: "Got It",
                isSecondary: true,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: AppColors.primaryBlue,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, size: 12, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final settings = Provider.of<SettingsProvider>(context);
    final user = auth.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          "Settings & Profile",
          style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User Profile Section
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "OFFICER PROFILE",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 26,
                          backgroundColor: AppColors.primaryBlue.withValues(alpha: 0.3),
                          child: const Icon(Icons.person, color: AppColors.primaryCyan, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user?.displayName ?? "Officer",
                                style: GoogleFonts.inter(
                                  color: AppColors.textPrimary,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                user?.email ?? "officer@railsafe.gov.in",
                                style: GoogleFonts.inter(
                                  color: AppColors.textSecondary,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                "${user?.role ?? 'Screening Inspector'} • ${user?.stationCode ?? 'NDLS'}",
                                style: GoogleFonts.inter(
                                  color: AppColors.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CustomButton(
                      text: "Sign Out",
                      icon: Icons.logout_rounded,
                      isDanger: true,
                      height: 42,
                      onPressed: () async {
                        await auth.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Cloud Sync & Firebase Status Card
              Container(
                padding: const EdgeInsets.all(18),
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
                        Text(
                          "CLOUD SYNCHRONIZATION",
                          style: GoogleFonts.orbitron(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.0,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: settings.isFirebaseConfigured
                                ? AppColors.statusSafe.withValues(alpha: 0.15)
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: settings.isFirebaseConfigured
                                  ? AppColors.statusSafe
                                  : AppColors.surfaceBorder,
                            ),
                          ),
                          child: Text(
                            settings.isFirebaseConfigured ? "CONNECTED" : "LOCAL OFFLINE",
                            style: GoogleFonts.inter(
                              color: settings.isFirebaseConfigured
                                  ? AppColors.statusSafe
                                  : AppColors.textMuted,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      settings.isFirebaseConfigured
                          ? "Firebase Authentication & Cloud Firestore are active. Completed test records sync securely."
                          : "Firebase is currently unconfigured. All tests and alerts are stored safely on device storage without internet reliance.",
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    CustomButton(
                      text: "View Firebase Setup Guide",
                      icon: Icons.integration_instructions_outlined,
                      isSecondary: true,
                      height: 40,
                      onPressed: () => _showFirebaseSetupGuide(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Python Backend Server Configuration Card
              Container(
                padding: const EdgeInsets.all(18),
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
                        Text(
                          "PYTHON BACKEND INFERENCE SERVER",
                          style: GoogleFonts.orbitron(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                            letterSpacing: 1.0,
                          ),
                        ),
                        if (_backendHealthOk != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _backendHealthOk!
                                  ? AppColors.statusSafe.withValues(alpha: 0.15)
                                  : AppColors.statusDanger.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _backendHealthOk!
                                    ? AppColors.statusSafe
                                    : AppColors.statusDanger,
                              ),
                            ),
                            child: Text(
                              _backendHealthOk! ? "HEALTHY" : "OFFLINE",
                              style: GoogleFonts.inter(
                                color: _backendHealthOk!
                                    ? AppColors.statusSafe
                                    : AppColors.statusDanger,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Offloads Random Forest ML inference (MQ-2, MQ-4, MQ-7) from Android to a secure FastAPI server. Protected by Firebase Bearer tokens.",
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    CustomTextField(
                      controller: _backendUrlController,
                      label: "Backend Server URL",
                      hint: "http://10.0.2.2:8000 or https://cloudrun.app",
                      prefixIcon: Icons.dns_outlined,
                    ),
                    if (_backendHealthStatus != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (_backendHealthOk == true
                                  ? AppColors.statusSafe
                                  : AppColors.statusDanger)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _backendHealthOk == true
                                ? AppColors.statusSafe
                                : AppColors.statusDanger,
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          _backendHealthStatus!,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: _backendHealthOk == true
                                ? AppColors.statusSafe
                                : AppColors.statusDanger,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: CustomButton(
                            text: _isTestingBackend ? "Testing..." : "Test Connection",
                            icon: Icons.network_check_rounded,
                            isSecondary: true,
                            height: 40,
                            isLoading: _isTestingBackend,
                            onPressed: _isTestingBackend
                                ? null
                                : () async {
                                    setState(() {
                                      _isTestingBackend = true;
                                      _backendHealthStatus = null;
                                      _backendHealthOk = null;
                                    });
                                    final storage = await LocalStorageService.getInstance();
                                    final api = PredictionApiService(storage);
                                    final res = await api.checkHealth(
                                      overrideUrl: _backendUrlController.text.trim(),
                                    );
                                    setState(() {
                                      _isTestingBackend = false;
                                      if (res["success"] == true) {
                                        _backendHealthOk = true;
                                        _backendHealthStatus =
                                            "Online! Model: ${res["model_name"]} (v${res["model_version"]})";
                                      } else {
                                        _backendHealthOk = false;
                                        _backendHealthStatus =
                                            res["message"]?.toString() ?? "Connection failed";
                                      }
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: CustomButton(
                            text: "Save URL",
                            icon: Icons.save_rounded,
                            height: 40,
                            onPressed: () async {
                              final newUrl = _backendUrlController.text.trim();
                              await settings.setBackendUrl(newUrl);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Backend server URL updated successfully!"),
                                    backgroundColor: AppColors.statusSafe,
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Demo Mode Configuration Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "DEMO MODE CONFIGURATION",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        "Enable Demo Simulation Mode",
                        style: GoogleFonts.inter(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        "Produces synthetic telemetry when physical ESP32 is absent.",
                        style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      value: settings.isDemoModeEnabled,
                      activeThumbColor: AppColors.statusWarning,
                      onChanged: (val) => settings.setDemoMode(val),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Simulation Scenario Profile:",
                      style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildScenarioOption(
                            label: "Nominal Ambient",
                            value: 'nominal',
                            current: settings.demoScenario,
                            onSelect: () => settings.setDemoScenario('nominal'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildScenarioOption(
                            label: "Trace Anomaly Peak",
                            value: 'anomaly',
                            current: settings.demoScenario,
                            onSelect: () => settings.setDemoScenario('anomaly'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Hardware Protocol & UUIDs Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ESP32 BLE PROTOCOL CONFIGURATION",
                      style: GoogleFonts.orbitron(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Adjust GATT characteristic UUIDs to correspond with your custom ESP32 firmware build.",
                      style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    CustomTextField(
                      label: "Service UUID",
                      controller: _serviceUuidController,
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      label: "Data Characteristic UUID (Notify)",
                      controller: _dataCharUuidController,
                    ),
                    const SizedBox(height: 12),
                    CustomTextField(
                      label: "Command Characteristic UUID (Write)",
                      controller: _cmdCharUuidController,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Stale Data Timeout: ${_staleTimeout}s",
                          style: GoogleFonts.inter(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Slider(
                          value: _staleTimeout.toDouble(),
                          min: 2,
                          max: 10,
                          divisions: 8,
                          activeColor: AppColors.primaryCyan,
                          inactiveColor: AppColors.surface,
                          onChanged: (val) {
                            setState(() => _staleTimeout = val.round());
                            settings.setStaleTimeout(val.round());
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    CustomButton(
                      text: "Save Protocol Settings",
                      isSecondary: true,
                      height: 42,
                      onPressed: () async {
                        await settings.updateBleUuids(
                          serviceUuid: _serviceUuidController.text,
                          dataCharUuid: _dataCharUuidController.text,
                          cmdCharUuid: _cmdCharUuidController.text,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AppColors.statusSafe,
                              content: Text("BLE protocol parameters updated."),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // App Version & About
              Center(
                child: Column(
                  children: [
                    Text(
                      "${AppConstants.appName} • ${AppConstants.appVersion}",
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppConstants.appDepartment,
                      style: GoogleFonts.inter(
                        color: AppColors.textMuted.withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScenarioOption({
    required String label,
    required String value,
    required String current,
    required VoidCallback onSelect,
  }) {
    final isSelected = value == current;
    return GestureDetector(
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue.withValues(alpha: 0.25)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primaryCyan : AppColors.surfaceBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: isSelected ? AppColors.primaryCyan : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
