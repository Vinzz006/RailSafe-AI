import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class _DecisionTree {
  final List<int> features;
  final List<double> thresholds;
  final List<int> left;
  final List<int> right;
  final List<double> anomalyProb;

  _DecisionTree({
    required this.features,
    required this.thresholds,
    required this.left,
    required this.right,
    required this.anomalyProb,
  });

  double predictAnomaly(List<double> sample) {
    int curr = 0;
    while (features[curr] != -2) {
      final featIdx = features[curr];
      if (sample[featIdx] <= thresholds[curr]) {
        curr = left[curr];
      } else {
        curr = right[curr];
      }
    }
    return anomalyProb[curr];
  }
}

class MlPredictionResult {
  final String label;
  final double anomalyProbability;
  final double normalProbability;
  final bool isAnomaly;
  final double confidence;
  final Map<String, double> inputFeatures;
  final String modelName;

  const MlPredictionResult({
    required this.label,
    required this.anomalyProbability,
    required this.normalProbability,
    required this.isAnomaly,
    required this.confidence,
    required this.inputFeatures,
    required this.modelName,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'anomalyProbability': double.parse(anomalyProbability.toStringAsFixed(4)),
        'normalProbability': double.parse(normalProbability.toStringAsFixed(4)),
        'isAnomaly': isAnomaly,
        'confidence': double.parse(confidence.toStringAsFixed(1)),
        'inputFeatures': inputFeatures,
        'modelName': modelName,
      };
}

class MlInferenceService {
  static final MlInferenceService _instance = MlInferenceService._internal();
  factory MlInferenceService() => _instance;
  MlInferenceService._internal();

  String _modelName = "RailSafe Random Forest Classifier";
  String _version = "1.0.0";
  List<String> _features = ["mq2_raw", "mq4_raw", "mq7_raw"];
  List<String> _classes = ["anomaly_synthetic", "normal_synthetic"];
  final List<_DecisionTree> _trees = [];
  bool _isLoaded = false;

  bool get isLoaded => _isLoaded;
  String get modelName => _modelName;
  String get version => _version;
  int get estimatorCount => _trees.length;
  List<String> get features => List.unmodifiable(_features);
  List<String> get classes => List.unmodifiable(_classes);

  /// Initializes the embedded Random Forest model from Flutter assets.
  Future<bool> initialize({String assetPath = 'assets/models/railsafe_rf_model.json'}) async {
    if (_isLoaded) return true;

    try {
      final jsonString = await rootBundle.loadString(assetPath);
      loadFromString(jsonString);
      debugPrint("[ML] Successfully loaded Random Forest model with ${_trees.length} trees.");
      return true;
    } catch (e) {
      debugPrint("[ML] Error loading model from assets: $e. Operating with fallback rule engine.");
      return false;
    }
  }

  /// Parses model structure directly from JSON string (supports unit tests & direct injections).
  void loadFromString(String jsonString) {
    final Map<String, dynamic> data = jsonDecode(jsonString);
    _modelName = data['model_name'] as String? ?? "RailSafe Random Forest Classifier";
    _version = data['version'] as String? ?? "1.0.0";

    if (data['features'] is List) {
      _features = (data['features'] as List).map((e) => e.toString()).toList();
    }
    if (data['classes'] is List) {
      _classes = (data['classes'] as List).map((e) => e.toString()).toList();
    }

    _trees.clear();
    final rawTrees = data['trees'] as List<dynamic>? ?? [];
    for (final t in rawTrees) {
      final tMap = t as Map<String, dynamic>;
      final rawFeats = (tMap['features'] as List).cast<int>();
      final rawThresh = (tMap['thresholds'] as List).map((n) => (n as num).toDouble()).toList();
      final rawLeft = (tMap['left'] as List).cast<int>();
      final rawRight = (tMap['right'] as List).cast<int>();
      final rawAnom = (tMap['anomaly_prob'] as List).map((n) => (n as num).toDouble()).toList();

      _trees.add(
        _DecisionTree(
          features: rawFeats,
          thresholds: rawThresh,
          left: rawLeft,
          right: rawRight,
          anomalyProb: rawAnom,
        ),
      );
    }

    _isLoaded = _trees.isNotEmpty;
  }

  /// Runs real-time inference on the 3 sensor channels: mq2, mq4, and mq7.
  MlPredictionResult predict({
    required double mq2,
    required double mq4,
    required double mq7,
  }) {
    final input = [mq2, mq4, mq7];
    final featureMap = {
      'mq2_raw': mq2,
      'mq4_raw': mq4,
      'mq7_raw': mq7,
    };

    if (!_isLoaded || _trees.isEmpty) {
      // Heuristic fallback matching model behavior if model asset hasn't completed loading
      final isElevated = mq2 > 280.0 || mq4 > 140.0 || mq7 > 100.0;
      final anomProb = isElevated ? 0.95 : 0.05;
      return MlPredictionResult(
        label: isElevated ? "anomaly_synthetic" : "normal_synthetic",
        anomalyProbability: anomProb,
        normalProbability: 1.0 - anomProb,
        isAnomaly: isElevated,
        confidence: 95.0,
        inputFeatures: featureMap,
        modelName: "$_modelName (Fallback)",
      );
    }

    double totalAnomalyProb = 0.0;
    for (final tree in _trees) {
      totalAnomalyProb += tree.predictAnomaly(input);
    }

    final avgAnomalyProb = totalAnomalyProb / _trees.length;
    final avgNormalProb = 1.0 - avgAnomalyProb;
    final isAnomaly = avgAnomalyProb >= 0.5;
    final label = isAnomaly ? "anomaly_synthetic" : "normal_synthetic";
    final confidence = (isAnomaly ? avgAnomalyProb : avgNormalProb) * 100.0;

    return MlPredictionResult(
      label: label,
      anomalyProbability: avgAnomalyProb,
      normalProbability: avgNormalProb,
      isAnomaly: isAnomaly,
      confidence: confidence,
      inputFeatures: featureMap,
      modelName: _modelName,
    );
  }
}
