class TestRecord {
  final String testId;
  final String userId;
  final String deviceId;
  final String mode; // 'hardware' or 'demo'
  final DateTime startedAt;
  final DateTime completedAt;
  final String completionStatus; // 'completed', 'incomplete', 'interrupted', 'demo_completed'
  final List<Map<String, dynamic>> sensorReadings;
  final String screeningAssistanceStatus;
  final String screeningAssistanceDetails;
  final Map<String, dynamic> metrics;
  final bool syncedToFirestore;
  final DateTime createdAt;
  final String? notes;

  TestRecord({
    required this.testId,
    required this.userId,
    required this.deviceId,
    required this.mode,
    required this.startedAt,
    required this.completedAt,
    required this.completionStatus,
    required this.sensorReadings,
    required this.screeningAssistanceStatus,
    required this.screeningAssistanceDetails,
    required this.metrics,
    this.syncedToFirestore = false,
    DateTime? createdAt,
    this.notes,
  }) : createdAt = createdAt ?? DateTime.now();

  Duration get duration => completedAt.difference(startedAt);

  bool get isDemo => mode.toLowerCase() == 'demo';

  factory TestRecord.fromJson(Map<String, dynamic> json) {
    return TestRecord(
      testId: json['testId']?.toString() ?? '',
      userId: json['userId']?.toString() ?? 'anonymous',
      deviceId: json['deviceId']?.toString() ?? 'UNKNOWN',
      mode: json['mode']?.toString() ?? 'hardware',
      startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ?? DateTime.now(),
      completedAt: DateTime.tryParse(json['completedAt']?.toString() ?? '') ?? DateTime.now(),
      completionStatus: json['completionStatus']?.toString() ?? 'completed',
      sensorReadings: (json['sensorReadings'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [],
      screeningAssistanceStatus: json['screeningAssistanceStatus']?.toString() ?? 'Pending Review',
      screeningAssistanceDetails: json['screeningAssistanceDetails']?.toString() ?? '',
      metrics: Map<String, dynamic>.from(json['metrics'] as Map? ?? {}),
      syncedToFirestore: json['syncedToFirestore'] == true,
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      notes: json['notes']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'userId': userId,
        'deviceId': deviceId,
        'mode': mode,
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
        'completionStatus': completionStatus,
        'sensorReadings': sensorReadings,
        'screeningAssistanceStatus': screeningAssistanceStatus,
        'screeningAssistanceDetails': screeningAssistanceDetails,
        'metrics': metrics,
        'syncedToFirestore': syncedToFirestore,
        'createdAt': createdAt.toIso8601String(),
        if (notes != null) 'notes': notes,
      };

  TestRecord copyWith({
    String? testId,
    String? userId,
    String? deviceId,
    String? mode,
    DateTime? startedAt,
    DateTime? completedAt,
    String? completionStatus,
    List<Map<String, dynamic>>? sensorReadings,
    String? screeningAssistanceStatus,
    String? screeningAssistanceDetails,
    Map<String, dynamic>? metrics,
    bool? syncedToFirestore,
    DateTime? createdAt,
    String? notes,
  }) {
    return TestRecord(
      testId: testId ?? this.testId,
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      mode: mode ?? this.mode,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      completionStatus: completionStatus ?? this.completionStatus,
      sensorReadings: sensorReadings ?? this.sensorReadings,
      screeningAssistanceStatus: screeningAssistanceStatus ?? this.screeningAssistanceStatus,
      screeningAssistanceDetails: screeningAssistanceDetails ?? this.screeningAssistanceDetails,
      metrics: metrics ?? this.metrics,
      syncedToFirestore: syncedToFirestore ?? this.syncedToFirestore,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
    );
  }
}
