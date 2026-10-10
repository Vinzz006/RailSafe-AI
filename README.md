# RailSafe AI — Handheld Screening Assistance Application

![Platform](https://img.shields.io/badge/Platform-Android-green.svg)
![Framework](https://img.shields.io/badge/Framework-Flutter%203.47-blue.svg)
![Language](https://img.shields.io/badge/Language-Dart%203.13-teal.svg)
![Hardware](https://img.shields.io/badge/Hardware-ESP32%20BLE-orange.svg)
![Security](https://img.shields.io/badge/Cloud-Firebase%20Auth%20%26%20Firestore-red.svg)

**RailSafe AI** is a modern Android mobile application developed for a 30-hour hardware hackathon prototype. The application interfaces with a physical handheld screening-assistance device powered by an **ESP32 microcontroller** over **Bluetooth Low Energy (BLE)** to provide real-time telemetry, screening assistance flags, and test record logging for research and future development across **Indian Railways**.

---

## 1. System Architecture & Data Pipeline

```
+------------------------------------+
| Physical Sensors (VOC / Diff Ion)  |
+------------------------------------+
                  | Analog ADC Readings
+------------------------------------+
| ESP32 Firmware (GATT BLE Server)   |
+------------------------------------+
                  | Delimited JSON Notifications (1 Hz)
+------------------------------------+
| Flutter BLE Service (Central)      |
+------------------------------------+
                  | Stream Parsing & Buffer Assembly
+------------------------------------+
| Live Monitoring UI & Real-Time Graph|
+------------------------------------+
                  | Test Stop & Screening Rule Analysis
+------------------------------------+
| Local Storage & Offline Queue      |
+------------------------------------+
                  | Auto Sync (When Configured & Online)
+------------------------------------+
| Cloud Firestore & Firebase Auth    |
+------------------------------------+
```

---

## 2. Key Features

- **Real-Time BLE Telemetry Stream:** Connects to ESP32 GATT server, requests 512-byte MTU, frames incoming chunks, and parses multi-channel JSON telemetry packets at 1 Hz.
- **Dynamic Real-Time Graph:** Powered by `fl_chart`, visualizing Sensor 1 (VOC/Aerosol) and Sensor 2 (Differential Probe) curves with live timestamp intervals.
- **Dedicated Demo Simulation Mode:** Persistent, prominent `"DEMO MODE — SIMULATED DATA"` banner and synthetic data generator allowing full presentation capabilities when hardware is absent. Includes selectable scenarios: *Nominal Ambient* vs *Trace Anomaly Elevation*.
- **Embedded Random Forest ML Engine:** On-device 100-tree edge intelligence trained across MQ-2, MQ-4, and MQ-7 multi-sensor arrays (`railsafe_rf_model.pkl` / `assets/models/railsafe_rf_model.json`). Performs ultra-fast, zero-dependency Dart inference with 100% mathematical equivalence to Scikit-Learn.
- **Ethical Screening Analysis:** Classifies tests into transparent categories (*Baseline Nominal*, *Anomaly Flagged — Secondary Review Required*, *Inconclusive Data*, or *Test Interrupted*). Does not claim confirmed chemical identification without certified laboratory spectrometry.
- **Offline-First Persistence:** Test records and system alerts are immediately saved to local on-device storage. When Cloud Firestore is configured and online, records automatically sync without duplicate writes.
- **System Event & Alerts Hub:** Tracks device connections, disconnections, sampling thresholds, and cloud synchronization events with severity badges.
- **Configurable BLE Protocol:** Customize Service UUID, Telemetry UUID, Command UUID, and Stale Data thresholds directly within app settings.

---

## 3. Screen Overview

1. **Splash Screen:** Animated brand mark with railway tracks and AI scanning motif; automatically resolves authentication status.
2. **Login & Registration:** Secure email/password entry, validation, Firebase Auth integration, and a **"Hackathon Quick Access" Demo Officer** button for immediate judging demos.
3. **Home Dashboard:** Hardware connection badge, active telemetry status, latest screening record summary, saved test counter, Demo Mode toggle, and primary "Start Test" trigger.
4. **Device Connection Screen:** Nearby BLE peripheral scanning with signal strength (RSSI), connect/disconnect controls, Android permission management, and retry options.
5. **Live Monitoring Screen:** Real-time sensor cards, live telemetry graph, sequence counter, stale data detection, and Start/Stop test controls.
6. **Test Result Screen:** Complete session evaluation, peak and average metrics, interactive telemetry trace, inspector remarks/notes input, and offline/cloud save actions.
7. **Test History & Detail Screens:** Searchable, filterable list of all completed hardware and demo tests with synchronization status indicators and full detail inspectors.
8. **Alerts Screen:** Chronological log of hardware and application events with severity indicators and clear-all capabilities.
9. **Settings & Profile:** Officer credentials, Firebase cloud status, Demo Mode scenario selection, and custom BLE GATT UUID configuration.

---

## 4. Hardware & BLE Protocol

### Project Default GATT UUIDs

- **Service UUID:** `12345678-1234-5678-1234-56789abcdef0`
- **Telemetry Characteristic (Notify):** `12345678-1234-5678-1234-56789abcdef1`
- **Command Characteristic (Write):** `12345678-1234-5678-1234-56789abcdef2`

### Telemetry JSON Format

```json
{
  "deviceId": "RAILSAFE-ESP32-01",
  "timestamp": "2026-10-10T08:30:00Z",
  "sequence": 1,
  "mode": "hardware",
  "sensors": {
    "sensor_1": {
      "value": 128.4,
      "unit": "ppm",
      "label": "Sensor 1 (VOC/Aerosol)"
    },
    "sensor_2": {
      "value": 46.2,
      "unit": "mV",
      "label": "Sensor 2 (Differential Probe)"
    }
  },
  "status": "ok"
}
```

Full details and packet framing mechanisms are documented in [`docs/ESP32_PROTOCOL.md`](docs/ESP32_PROTOCOL.md).
Arduino C++ firmware source code is located in [`firmware/railsafe_esp32_firmware.ino`](firmware/railsafe_esp32_firmware.ino).

---

## 5. Firebase Configuration & Security Rules

RailSafe AI works completely offline out of the box using local storage. To activate multi-device cloud synchronization:

1. Create a project at [Firebase Console](https://console.firebase.google.com).
2. Register an Android app with package name `com.railsafe.railsafe_ai`.
3. Download `google-services.json` and place it in `android/app/google-services.json` (see template in `android/app/google-services.json.example`).
4. Enable **Email/Password** authentication under *Authentication > Sign-in method*.
5. Enable **Cloud Firestore** in Native mode.
6. Deploy the included security rules located in [`firestore.rules`](firestore.rules).

---

## 6. Development & Build Instructions

### Prerequisites

- Flutter SDK 3.47+ with Dart 3.13+
- Android SDK (API 34/36)
- Java 17+ (or Java 21)

### Run Automated Static Analysis

```bash
flutter analyze
```

### Run Automated Tests

```bash
flutter test
```

### Run Locally on an Android Device / Emulator

```bash
flutter run
```

### Build Android Debug APK

```bash
flutter build apk --debug
```

The compiled APK will be generated at:
`build/app/outputs/flutter-apk/app-debug.apk`

### Install APK to an Android Phone

Connect your Android phone via USB with USB Debugging enabled:

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

---

## 7. Hackathon Presentation Walkthrough

1. **Quick Launch:** Open the app and tap **"Continue as Demo Officer"** on the login screen for instant access.
2. **Demo Presentation Mode:**
   - On the Dashboard, verify **Demo Simulation Mode** is enabled.
   - Tap **"Start Screening Test"** to open Live Monitoring.
   - Tap **"Start Screening Sampling"** to watch live telemetry packets stream and graph in real time.
   - Tap **"Stop Test & Analyze"** to review the screening assessment, peak metrics, and recommendation banner.
   - Tap **"Save Test Record"** to store the test locally and queue it for cloud synchronization.
3. **Physical Hardware Demonstration:**
   - Power on the ESP32 flashed with `firmware/railsafe_esp32_firmware.ino`.
   - On the Dashboard, toggle Demo Mode off and tap **"Connect Device"**.
   - Select `RAILSAFE-ESP32-01` from discovered peripherals and tap **"Connect"**.
   - Navigate to Live Monitoring to inspect physical analog sensor readings streaming live over BLE.

---

## 8. Disclaimer & Research Prototype Notice

*PROTOTYPE NOTICE: RailSafe AI provides assistive screening indications for research, academic evaluation, and hardware demonstration purposes. Sensor readings reflect prototype hardware telemetry and must never be treated as certified substance identification without validated laboratory spectrometry and authorized railway safety protocols.*
