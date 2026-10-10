import 'dart:async';
import 'dart:math';
import '../models/sensor_reading.dart';

class SimulationService {
  Timer? _timer;
  final StreamController<SensorReading> _streamController =
      StreamController<SensorReading>.broadcast();
  int _sequence = 0;
  final Random _rng = Random();
  bool _isRunning = false;
  String _scenario = 'nominal'; // 'nominal' or 'anomaly'
  int _ticksInTest = 0;

  Stream<SensorReading> get readingStream => _streamController.stream;
  bool get isRunning => _isRunning;
  String get scenario => _scenario;

  void setScenario(String scenario) {
    _scenario = scenario;
  }

  void startSimulation({String? scenario}) {
    if (scenario != null) _scenario = scenario;
    stopSimulation();
    _isRunning = true;
    _sequence = 0;
    _ticksInTest = 0;

    _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      _sequence++;
      _ticksInTest++;

      double s1Val;
      double s2Val;

      if (_scenario == 'anomaly') {
        // Between ticks 4 and 10, simulate a clear transient rise
        if (_ticksInTest >= 4 && _ticksInTest <= 10) {
          final ramp = (_ticksInTest - 3) / 4.0;
          final peak = min(ramp, 1.0) * 310.0;
          s1Val = 70.0 + peak + (_rng.nextDouble() * 25.0);
          s2Val = 35.0 + (peak * 0.45) + (_rng.nextDouble() * 15.0);
        } else if (_ticksInTest > 10) {
          // Gradual decay
          final decay = max(0.0, 1.0 - (_ticksInTest - 10) * 0.15);
          s1Val = 70.0 + (310.0 * decay) + (_rng.nextDouble() * 10.0);
          s2Val = 35.0 + (140.0 * decay) + (_rng.nextDouble() * 8.0);
        } else {
          // Baseline ambient
          s1Val = 60.0 + (_rng.nextDouble() * 18.0);
          s2Val = 30.0 + (_rng.nextDouble() * 10.0);
        }
      } else {
        // Nominal ambient with small random drift
        s1Val = 55.0 + (_rng.nextDouble() * 15.0);
        s2Val = 28.0 + (_rng.nextDouble() * 8.0);
      }

      final readingJson = {
        "deviceId": "RAILSAFE-DEMO-SIM",
        "timestamp": DateTime.now().toUtc().toIso8601String(),
        "sequence": _sequence,
        "mode": "demo",
        "sensors": {
          "sensor_1": {
            "value": double.parse(s1Val.toStringAsFixed(1)),
            "unit": "ppm",
            "label": "Sensor 1 (VOC/Aerosol)",
          },
          "sensor_2": {
            "value": double.parse(s2Val.toStringAsFixed(1)),
            "unit": "mV",
            "label": "Sensor 2 (Differential Probe)",
          }
        },
        "status": "demo_ok"
      };

      final reading = SensorReading.fromJson(readingJson);
      if (!_streamController.isClosed) {
        _streamController.add(reading);
      }
    });
  }

  void stopSimulation() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    _ticksInTest = 0;
  }

  void dispose() {
    stopSimulation();
    _streamController.close();
  }
}
