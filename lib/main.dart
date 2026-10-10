import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/constants/app_colors.dart';
import 'firebase_options.dart';
import 'providers/alerts_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/ble_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/test_provider.dart';
import 'services/auth_service.dart';
import 'services/ble_service.dart';
import 'services/firestore_service.dart';
import 'services/local_storage_service.dart';
import 'services/simulation_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set immersive dark status and navigation bar styling
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.background,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Initialize persistent offline local storage
  final storageService = await LocalStorageService.getInstance();

  // Initialize Firebase with platform-specific options; graceful offline fallback
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("[FIREBASE] Optional cloud initialization: $e (Operating in Offline Local Storage mode)");
  }

  // Initialize service dependencies
  final authService = AuthService(storageService);
  await authService.initialize();

  final firestoreService = FirestoreService(storageService);
  firestoreService.initialize();

  final bleService = BleService();
  final simulationService = SimulationService();

  // Initialize core application providers
  final alertsProvider = AlertsProvider(storageService, firestoreService);
  final testProvider = TestProvider(
    bleService,
    simulationService,
    storageService,
    firestoreService,
    alertsProvider,
  );
  final authProvider = AuthProvider(authService, firestoreService);
  final bleProvider = BleProvider(bleService);
  final settingsProvider = SettingsProvider(
    storageService,
    bleService,
    simulationService,
    firestoreService,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: bleProvider),
        ChangeNotifierProvider.value(value: settingsProvider),
        ChangeNotifierProvider.value(value: alertsProvider),
        ChangeNotifierProvider.value(value: testProvider),
      ],
      child: const RailSafeApp(),
    ),
  );
}
