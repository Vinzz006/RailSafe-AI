class DeviceInfo {
  final String id;
  final String name;
  final int rssi;
  final bool isConnectable;
  final DateTime lastSeen;
  final List<String> serviceUuids;

  DeviceInfo({
    required this.id,
    required this.name,
    required this.rssi,
    this.isConnectable = true,
    DateTime? lastSeen,
    this.serviceUuids = const [],
  }) : lastSeen = lastSeen ?? DateTime.now();

  String get displayName => name.isNotEmpty ? name : "Unknown Peripheral ($id)";

  String get signalStrength {
    if (rssi >= -60) return "Strong";
    if (rssi >= -75) return "Good";
    if (rssi >= -85) return "Fair";
    return "Weak";
  }
}
