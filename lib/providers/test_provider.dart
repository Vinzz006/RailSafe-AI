import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/ble_constants.dart';
import '../core/errors/app_error.dart';
import '../core/utils/screening_analyzer.dart';
import '../models/app_alert.dart';
import '../models/prediction_response.dart';
import '../models/sensor_reading.dart';
import '../models/test_record.dart';
import '../services/auth_service.dart';
import '../services/ble_service.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../services/prediction_api_service.dart';
import '../services/simulation_service.dart';
import 'alerts_provider.dart';

class TestProvider extends ChangeNotifier {
  final BleService _bleService;
  final SimulationService _simulationService;
  final LocalStorageService _storage;
  final FirestoreService _firestore;
  final AlertsProvider _alertsProvider;
  final PredictionApiService _predictionApi;
  final AuthService _authService;

  bool _isTesting = false;
  String _testMode = 'hardware'; // 'hardware' or 'demo'
  String? _currentTestId;
  DateTime? _testStartTime;
  Duration _elapsedDuration = Duration.zero;
  Timer? _durationTimer;

  SensorReading? _latestReading;
  final List<SensorReading> _currentSessionReadings = [];
  TestRecord? _lastCompletedTest;
  ScreeningAnalysisResult? _lastAnalysisResult;
  List<TestRecord> _savedTests = [];
  bool _isSyncing = false;

  bool _isPredicting = false;
  String? _predictionError;
  int _lastPredictedSequence = -1;
  PredictionResponse? _lastBackendPrediction;

  StreamSubscription? _bleReadingSub;
  StreamSubscription? _simReadingSub;
  StreamSubscription? _bleStatusSub;

  final Uuid _uuid = const Uuid();

  TestProvider(
    this._bleService,
    this._simulationService,
    this._storage,
    this._firestore,
    this._alertsProvider,
    this._predictionApi,
    this._authService,
  ) {
    _loadSavedTests();
    _listenToBleStatus();
  }

  bool get isTesting => _isTesting;
  String get testMode => _testMode;
  bool get isDemoTest => _testMode == 'demo';
  String? get currentTestId => _currentTestId;
  DateTime? get testStartTime => _testStartTime;
  Duration get elapsedDuration => _elapsedDuration;
  SensorReading? get latestReading => _latestReading;
  List<SensorReading> get currentSessionReadings => List.unmodifiable(_currentSessionReadings);
  TestRecord? get lastCompletedTest => _lastCompletedTest;
  ScreeningAnalysisResult? get lastAnalysisResult => _lastAnalysisResult;
  List<TestRecord> get savedTests => _savedTests;
  bool get isSyncing => _isSyncing;
  bool get isPredicting => _isPredicting;
  String? get predictionError => _predictionError;
  PredictionResponse? get lastBackendPrediction => _lastBackendPrediction;

  void _loadSavedTests() {
    _savedTests = _storage.getSavedTests();
    notifyListeners();
  }

  void _listenToBleStatus() {
    _bleStatusSub = _bleService.statusStream.listen((status) {
      // If hardware disconnects during an active hardware test, handle interruption
      if (_isTesting && _testMode == 'hardware' && status == BleStatus.disconnected) {
        _handleTestInterruption("Hardware peripheral disconnected during active test.");
      }
    });
  }

  /// Starts a new screening test session
  Future<bool> startTest({required bool isDemo, required String userId}) async {
    if (_isTesting) return false;

    _testMode = isDemo ? 'demo' : 'hardware';
    _currentTestId = "TEST-${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}-${_uuid.v4().substring(0, 6).toUpperCase()}";
    _testStartTime = DateTime.now();
    _elapsedDuration = Duration.zero;
    _currentSessionReadings.clear();
    _latestReading = null;
    _lastCompletedTest = null;
    _lastAnalysisResult = null;
    _lastBackendPrediction = null;
    _predictionError = null;
    _lastPredictedSequence = -1;
    _isTesting = true;

    // Start elapsed duration stopwatch timer
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_testStartTime != null) {
        _elapsedDuration = DateTime.now().difference(_testStartTime!);
        notifyListeners();
      }
    });

    if (isDemo) {
      _simReadingSub?.cancel();
      _simulationService.startSimulation();
      _simReadingSub = _simulationService.readingStream.listen((reading) {
        _onNewReading(reading);
      });

      await _alertsProvider.addAlert(
        type: "demo_test_started",
        title: "Demo Test Initiated",
        message: "Simulation test session $_currentTestId started with synthetic telemetry.",
        severity: AlertSeverity.info,
        userId: userId,
        relatedTestId: _currentTestId,
      );
    } else {
      if (!_bleService.isConnected) {
        _isTesting = false;
        _durationTimer?.cancel();
        notifyListeners();
        return false;
      }

      // Try sending start command to ESP32 firmware if supported
      await _bleService.sendCommand(BleConstants.cmdStartTest);

      _bleReadingSub?.cancel();
      _bleReadingSub = _bleService.readingStream.listen((reading) {
        _onNewReading(reading);
      });

      await _alertsProvider.addAlert(
        type: "hardware_test_started",
        title: "Hardware Test Started",
        message: "Live test session $_currentTestId started via BLE from ${_bleService.connectedDeviceName ?? 'ESP32'}.",
        severity: AlertSeverity.info,
        userId: userId,
        relatedTestId: _currentTestId,
      );
    }

    notifyListeners();
    return true;
  }

  void _onNewReading(SensorReading reading) {
    if (!_isTesting) return;
    _latestReading = reading;
    _currentSessionReadings.add(reading);
    notifyListeners();
  }

  /// Stops current test session, calls Python backend for inference, and records screening analysis
  Future<TestRecord?> stopTest({required String userId, bool wasInterrupted = false}) async {
    if (!_isTesting) return _lastCompletedTest;

    _durationTimer?.cancel();
    _isTesting = false;

    if (_testMode == 'demo') {
      _simReadingSub?.cancel();
      _simulationService.stopSimulation();
    } else {
      _bleReadingSub?.cancel();
      await _bleService.sendCommand(BleConstants.cmdStopTest);
    }

    final completedAt = DateTime.now();
    final deviceId = _testMode == 'demo'
        ? "RAILSAFE-DEMO-SIM"
        : (_bleService.connectedDeviceName ?? _bleService.connectedDevice?.remoteId.str ?? "ESP32-UNKNOWN");

    final rawJsonList = _currentSessionReadings.map((r) => r.toJson()).toList();

    PredictionResponse? backendPrediction;

    // Call Python backend inference if session has valid readings and was not interrupted
    if (!wasInterrupted && _currentSessionReadings.length >= 3) {
      _isPredicting = true;
      notifyListeners();

      try {
        final lastReading = _currentSessionReadings.last;
        final seq = lastReading.sequence;

        // Prevent duplicate inference requests for the same sequence
        if (seq != _lastPredictedSequence) {
          _lastPredictedSequence = seq;

          double mq2Peak = 0.0;
          double mq4Peak = 0.0;
          double mq7Peak = 0.0;

          for (final r in _currentSessionReadings) {
            final v2 = r.mq2Value;
            final v4 = r.mq4Value;
            final v7 = r.mq7Value;
            if (v2 != null && v2 > mq2Peak) mq2Peak = v2;
            if (v4 != null && v4 > mq4Peak) mq4Peak = v4;
            if (v7 != null && v7 > mq7Peak) mq7Peak = v7;
          }

          if (_testMode == 'hardware' && _currentSessionReadings.any((r) => r.hasMissingTelemetry)) {
            throw BackendPredictionException(
              "Hardware telemetry incomplete: Missing physical sensor channels in screening session.",
              statusCode: 400,
            );
          }

          final token = await _authService.getIdToken() ?? "DEMO_OFFICER_TOKEN";
          backendPrediction = await _predictionApi.predict(
            deviceId: deviceId,
            sequence: seq,
            timestamp: completedAt,
            mq2: mq2Peak,
            mq4: mq4Peak,
            mq7: mq7Peak,
            idToken: token,
          );
          _lastBackendPrediction = backendPrediction;
          _predictionError = null;
        } else {
          backendPrediction = _lastBackendPrediction;
        }
      } catch (e) {
        debugPrint("[TEST_PROVIDER] Backend prediction notice: $e");
        _predictionError = e.toString();
        await _alertsProvider.addAlert(
          type: "backend_prediction_error",
          title: "Prediction Service Notice",
          message: "Unable to reach Python backend: $e. Applied calibrated fallback threshold guard.",
          severity: AlertSeverity.warning,
          userId: userId,
          relatedTestId: _currentTestId,
        );
      } finally {
        _isPredicting = false;
        notifyListeners();
      }
    }

    // Run safe screening analysis incorporating backend ML prediction
    final analysis = ScreeningAnalyzer.analyze(
      readings: rawJsonList,
      isDemo: _testMode == 'demo',
      wasInterrupted: wasInterrupted,
      backendPrediction: backendPrediction,
    );
    _lastAnalysisResult = analysis;

    String completionStatus;
    if (wasInterrupted) {
      completionStatus = 'interrupted';
    } else if (_testMode == 'demo') {
      completionStatus = 'demo_completed';
    } else if (_currentSessionReadings.isEmpty || _currentSessionReadings.length < 3) {
      completionStatus = 'incomplete';
    } else {
      completionStatus = 'completed';
    }

    final testRecord = TestRecord(
      testId: _currentTestId ?? "TEST-${DateTime.now().millisecondsSinceEpoch}",
      userId: userId,
      deviceId: deviceId,
      mode: _testMode,
      startedAt: _testStartTime ?? completedAt.subtract(_elapsedDuration),
      completedAt: completedAt,
      completionStatus: completionStatus,
      sensorReadings: rawJsonList,
      screeningAssistanceStatus: analysis.title,
      screeningAssistanceDetails: analysis.description,
      metrics: analysis.metrics,
      syncedToFirestore: false,
    );

    _lastCompletedTest = testRecord;
    notifyListeners();

    // Emit event alert
    await _alertsProvider.addAlert(
      type: wasInterrupted ? "test_interrupted" : "test_completed",
      title: wasInterrupted ? "Screening Interrupted" : "Screening Test Completed",
      message: "Test ${testRecord.testId} finished: ${analysis.title}",
      severity: analysis.requiresSecondaryReview ? AlertSeverity.warning : AlertSeverity.success,
      userId: userId,
      relatedTestId: testRecord.testId,
    );

    return testRecord;
  }

  void _handleTestInterruption(String reason) {
    if (!_isTesting) return;
    stopTest(userId: _lastCompletedTest?.userId ?? "officer", wasInterrupted: true);
    _alertsProvider.addAlert(
      type: "hardware_disconnected",
      title: "BLE Hardware Disconnected",
      message: reason,
      severity: AlertSeverity.danger,
    );
  }

  /// Explicitly saves the completed test to offline storage and syncs to Firestore
  Future<bool> saveCurrentTest({String? notes}) async {
    if (_lastCompletedTest == null) return false;

    var recordToSave = _lastCompletedTest!;
    if (notes != null && notes.isNotEmpty) {
      recordToSave = recordToSave.copyWith(notes: notes);
    }

    final synced = await _firestore.saveTestRecord(recordToSave);
    _lastCompletedTest = recordToSave.copyWith(syncedToFirestore: synced);

    _loadSavedTests();
    notifyListeners();
    return true;
  }

  Future<void> deleteTest(String testId) async {
    await _storage.deleteTest(testId);
    _loadSavedTests();
  }

  Future<FirestoreSyncResult> syncPendingTests(String userId) async {
    _isSyncing = true;
    notifyListeners();

    final result = await _firestore.syncPendingTests(userId);
    _loadSavedTests();
    _isSyncing = false;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _bleReadingSub?.cancel();
    _simReadingSub?.cancel();
    _bleStatusSub?.cancel();
    super.dispose();
  }
}
