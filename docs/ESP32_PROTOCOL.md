# RailSafe AI — ESP32 Hardware-to-Mobile BLE Protocol

This document specifies the Bluetooth Low Energy (BLE) communication protocol between the physical **ESP32 Handheld Screening Assistance Device** and the **RailSafe AI** Flutter Android mobile application.

---

## 1. BLE Architecture & GATT Profiles

The ESP32 peripheral operates in GATT Server mode. The mobile application acts as a GATT Central client.

### Default GATT UUIDs

| Attribute | UUID | Type | Properties | Description |
|---|---|---|---|---|
| **Screening Service** | `12345678-1234-5678-1234-56789abcdef0` | Primary Service | — | Identifies RailSafe AI screening peripherals |
| **Telemetry Characteristic** | `12345678-1234-5678-1234-56789abcdef1` | Characteristic | `READ`, `NOTIFY` | Emits real-time sensor packets at 1 Hz |
| **Command Characteristic** | `12345678-1234-5678-1234-56789abcdef2` | Characteristic | `WRITE`, `WRITE_NO_RESP` | Accepts mobile operational control commands |

> **Note:** These UUIDs are configurable in the RailSafe AI mobile app settings (`Settings > ESP32 BLE Protocol Configuration`).

---

## 2. Telemetry JSON Payload Specification

Sensor data is formatted as a compact JSON string transmitted via BLE Notifications on the **Telemetry Characteristic**.

### Example Telemetry Packet

```json
{
  "deviceId": "RAILSAFE-ESP32-01",
  "timestamp": "2026-10-10T08:30:00Z",
  "sequence": 142,
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

### Field Definitions

| Field | Type | Description |
|---|---|---|
| `deviceId` | `string` | Unique hardware identifier or serial number (e.g., `RAILSAFE-ESP32-01`). |
| `timestamp` | `string` | ISO 8601 UTC timestamp or relative uptime string. |
| `sequence` | `integer` | Monotonically increasing packet counter starting at 1. |
| `mode` | `string` | Must be `"hardware"`. (Mobile simulated packets use `"demo"`). |
| `sensors` | `object` | Key-value dictionary containing telemetry channels. |
| `sensors.sensor_1` | `object` | Primary sensor channel (e.g., metal oxide VOC, semiconductor gas probe). |
| `sensors.sensor_2` | `object` | Secondary sensor channel (e.g., differential ion probe, particulate sensor). |
| `sensors.*.value` | `number` | Numeric floating-point reading. |
| `sensors.*.unit` | `string` | Measurement unit (`raw`, `ppm`, `mV`, `ug/m3`). |
| `status` | `string` | Hardware status code (`"ok"`, `"warming_up"`, `"calibrating"`, `"fault"`). |

---

## 3. MTU Size and Packet Framing Protocol

Standard Bluetooth LE default ATT MTU is **23 bytes** (carrying a maximum payload of 20 bytes). A full JSON packet typically requires **150 to 250 bytes**.

### Handling MTU on Both Sides

1. **MTU Negotiation:** Upon establishing a BLE connection, the RailSafe AI Android application issues `requestMtu(512)`. When accepted by the ESP32, notifications up to 512 bytes can be transmitted in a single packet.
2. **Chunking / Delimiter Framing:**
   The firmware appends a newline character (`\n`) to each JSON message:
   ```text
   {"deviceId":"RAILSAFE-ESP32-01","sequence":1,...}\n
   ```
   The mobile application maintains an internal buffer (`_packetBuffer`). If an ESP32 or phone operating system segments a packet across multiple notifications, the mobile app concatenates incoming chunks and triggers JSON decoding once the closing `\n` or balanced brackets `{ ... }` are received.

---

## 4. Hardware Command Control (Optional)

The mobile application sends text commands followed by `\n` to the **Command Characteristic**:

| Command String | Firmware Action |
|---|---|
| `CMD:START_TEST\n` | Resets sequence counter, pre-heats/primes sensors, and begins sampling stream. |
| `CMD:STOP_TEST\n` | Pauses active sampling and sets sensors to low-power standby mode. |
| `CMD:PING\n` | Responds with immediate diagnostic heartbeat packet. |
| `CMD:CALIBRATE\n` | Resets ambient zero baseline to current environmental atmosphere. |

---

## 5. Screening Flag Decision Rules (Prototype Logic)

The RailSafe AI application processes incoming sensor telemetry using the following transparent prototype rules:

1. **Normal Baseline (`NORMAL_BASELINE`):**
   - Peak Sensor 1 < 280.0 ppm
   - Peak Sensor 2 < 140.0 ppm
   - Minimum 3 valid sample packets received.
   - Status: *"Baseline Nominal — No Anomaly Detected"*.
2. **Anomaly Flagged (`ANOMALY_FLAGGED`):**
   - Peak Sensor 1 ≥ 280.0 ppm OR Peak Sensor 2 ≥ 140.0 ppm.
   - Status: *"Anomaly Flagged — Secondary Review Required"*.
   - Recommendation: Conduct standard secondary baggage check. **No definitive chemical claim is made without certified laboratory spectrometry.**
3. **Inconclusive Data (`INCONCLUSIVE_DATA`):**
   - Less than 3 telemetry packets received during test interval.
   - Recommendation: Re-scan maintaining probe proximity for at least 5-10 seconds.
4. **Interrupted (`TEST_INTERRUPTED`):**
   - BLE connection lost or prematurely terminated.
