class AppConstants {
  static const String appName = "RailSafe AI";
  static const String appSubtitle = "Handheld Screening Assistance";
  static const String appDepartment = "Indian Railways Research & Prototype";
  static const String appVersion = "1.0.0 (Hackathon Edition)";

  // SharedPreferences Keys
  static const String keyDemoMode = "demo_mode_enabled";
  static const String keyServiceUuid = "custom_service_uuid";
  static const String keyDataCharUuid = "custom_data_char_uuid";
  static const String keyCmdCharUuid = "custom_cmd_char_uuid";
  static const String keyStaleTimeoutSec = "stale_timeout_sec";
  static const String keySavedTests = "offline_saved_tests_json";
  static const String keySavedAlerts = "offline_saved_alerts_json";
  static const String keyCachedUser = "cached_user_profile";
  static const String keyDemoScenario = "demo_simulation_scenario";
  static const String keyBackendUrl = "backend_api_url";
  static const String defaultBackendUrl = "http://10.0.2.2:8000";

  // Screening Assistance Disclaimer
  static const String prototypeDisclaimer =
      "PROTOTYPE NOTICE: RailSafe AI provides assistive screening indications for research and hardware evaluation. "
      "Readings reflect prototype sensor outputs and must not be treated as certified chemical identification without authorized laboratory verification.";
}
