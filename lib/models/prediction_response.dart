class PredictionResponse {
  final String deviceId;
  final int sequence;
  final String prediction; // "anomaly" or "nominal"
  final String label; // "anomaly_synthetic" or "normal_synthetic"
  final double anomalyScore;
  final double normalScore;
  final double confidence;
  final bool reviewRequired;
  final String modelVersion;
  final DateTime inferenceTimestamp;
  final Map<String, double> inputFeatures;
  final String? userId;

  PredictionResponse({
    required this.deviceId,
    required this.sequence,
    required this.prediction,
    required this.label,
    required this.anomalyScore,
    required this.normalScore,
    required this.confidence,
    required this.reviewRequired,
    required this.modelVersion,
    required this.inferenceTimestamp,
    required this.inputFeatures,
    this.userId,
  });

  bool get isAnomaly => prediction == "anomaly" || reviewRequired;

  factory PredictionResponse.fromJson(Map<String, dynamic> json) {
    DateTime ts;
    try {
      final rawTs = json['inferenceTimestamp']?.toString();
      ts = rawTs != null ? DateTime.parse(rawTs) : DateTime.now();
    } catch (_) {
      ts = DateTime.now();
    }

    final rawFeatures = json['inputFeatures'];
    final featuresMap = <String, double>{};
    if (rawFeatures is Map<String, dynamic>) {
      rawFeatures.forEach((k, v) {
        if (v is num) {
          featuresMap[k] = v.toDouble();
        }
      });
    }

    return PredictionResponse(
      deviceId: json['deviceId']?.toString() ?? 'UNKNOWN-DEVICE',
      sequence: (json['sequence'] as num?)?.toInt() ?? 0,
      prediction: json['prediction']?.toString() ?? 'nominal',
      label: json['label']?.toString() ?? 'normal_synthetic',
      anomalyScore: (json['anomalyScore'] as num?)?.toDouble() ?? 0.0,
      normalScore: (json['normalScore'] as num?)?.toDouble() ?? 1.0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      reviewRequired: json['reviewRequired'] == true,
      modelVersion: json['modelVersion']?.toString() ?? '1.0.0',
      inferenceTimestamp: ts,
      inputFeatures: featuresMap,
      userId: json['userId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'sequence': sequence,
        'prediction': prediction,
        'label': label,
        'anomalyScore': anomalyScore,
        'normalScore': normalScore,
        'confidence': confidence,
        'reviewRequired': reviewRequired,
        'modelVersion': modelVersion,
        'inferenceTimestamp': inferenceTimestamp.toIso8601String(),
        'inputFeatures': inputFeatures,
        if (userId != null) 'userId': userId,
      };
}
