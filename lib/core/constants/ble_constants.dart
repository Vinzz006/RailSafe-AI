class BleConstants {
  // Service and Characteristic UUIDs specified in RailSafe AI architecture
  static const String defaultServiceUuid = "12345678-1234-5678-1234-56789abcdef0";
  static const String defaultDataCharacteristicUuid = "12345678-1234-5678-1234-56789abcdef1";
  static const String defaultCommandCharacteristicUuid = "12345678-1234-5678-1234-56789abcdef2";

  // Device advertising names filter
  static const List<String> recognizedPrefixes = [
    "RAILSAFE",
    "ESP32",
    "SCREEN-AI",
    "IR-SCANNER",
  ];

  // Timing constants
  static const Duration scanTimeout = Duration(seconds: 12);
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration staleDataThreshold = Duration(seconds: 4);

  // Commands supported by prototype ESP32 firmware
  static const String cmdStartTest = "CMD:START_TEST";
  static const String cmdStopTest = "CMD:STOP_TEST";
  static const String cmdPing = "CMD:PING";
  static const String cmdCalibrate = "CMD:CALIBRATE";
}
