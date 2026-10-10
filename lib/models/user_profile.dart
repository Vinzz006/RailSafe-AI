class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String role;
  final String stationCode;
  final DateTime createdAt;
  final bool isDemoUser;

  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.role = "Screening Inspector",
    this.stationCode = "NDLS (New Delhi)",
    DateTime? createdAt,
    this.isDemoUser = false,
  }) : createdAt = createdAt ?? DateTime.now();

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      uid: json['uid']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? 'Officer',
      role: json['role']?.toString() ?? 'Screening Inspector',
      stationCode: json['stationCode']?.toString() ?? 'NDLS (New Delhi)',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      isDemoUser: json['isDemoUser'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'email': email,
        'displayName': displayName,
        'role': role,
        'stationCode': stationCode,
        'createdAt': createdAt.toIso8601String(),
        'isDemoUser': isDemoUser,
      };

  static UserProfile createDemoUser() {
    return UserProfile(
      uid: "demo-officer-01",
      email: "inspector.demo@railsafe.indianrailways.gov.in",
      displayName: "Officer Rajesh Kumar",
      role: "Railway Security / RPF Inspector",
      stationCode: "NDLS - New Delhi Central",
      isDemoUser: true,
    );
  }
}
