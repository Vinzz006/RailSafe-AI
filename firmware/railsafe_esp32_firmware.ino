/*
 * ==============================================================================
 * RailSafe AI — Handheld Screening Assistance Device (ESP32 Firmware Example)
 * Target Hardware: ESP32-WROOM-32 / ESP32-S3
 * Framework: Arduino ESP32 BLE
 * ==============================================================================
 * Description:
 * This sketch demonstrates the BLE GATT server implementation for the RailSafe
 * AI handheld screening assistance prototype.
 *
 * It creates:
 *  - Primary Service (12345678-1234-5678-1234-56789abcdef0)
 *  - Telemetry Characteristic (Notify) (12345678-1234-5678-1234-56789abcdef1)
 *  - Command Characteristic (Write)  (12345678-1234-5678-1234-56789abcdef2)
 *
 * Incoming commands:
 *  - CMD:START_TEST -> begins emitting telemetry packets at 1 Hz
 *  - CMD:STOP_TEST  -> pauses telemetry emissions
 * ==============================================================================
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

#define DEVICE_NAME "RAILSAFE-ESP32-01"

// GATT Service and Characteristic UUIDs
#define SERVICE_UUID        "12345678-1234-5678-1234-56789abcdef0"
#define DATA_CHAR_UUID      "12345678-1234-5678-1234-56789abcdef1"
#define CMD_CHAR_UUID       "12345678-1234-5678-1234-56789abcdef2"

// Analog sensor pin configuration (Example pins on ESP32)
#define PIN_SENSOR_1 34  // Analog channel for VOC / Gas sensor probe
#define PIN_SENSOR_2 35  // Analog channel for Differential Ion / Thermal probe
#define LED_STATUS_PIN 2 // Built-in indicator LED

BLEServer* pServer = NULL;
BLECharacteristic* pDataCharacteristic = NULL;
BLECharacteristic* pCmdCharacteristic = NULL;

bool deviceConnected = false;
bool oldDeviceConnected = false;
bool isTesting = false;
uint32_t sequence = 0;
unsigned long lastTelemetryMillis = 0;

// Server Callback to track BLE connections
class ServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("[BLE] Mobile application connected!");
      digitalWrite(LED_STATUS_PIN, HIGH);
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      isTesting = false;
      Serial.println("[BLE] Mobile application disconnected.");
      digitalWrite(LED_STATUS_PIN, LOW);
    }
};

// Command Callback to handle remote instructions from RailSafe AI mobile app
class CommandCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      std::string rxValue = pCharacteristic->getValue();
      if (rxValue.length() > 0) {
        String cmd = String(rxValue.c_str());
        cmd.trim();
        Serial.print("[CMD RECEIVED] ");
        Serial.println(cmd);

        if (cmd == "CMD:START_TEST") {
          isTesting = true;
          sequence = 0;
          Serial.println("[SYSTEM] Starting active screening test...");
        } else if (cmd == "CMD:STOP_TEST") {
          isTesting = false;
          Serial.println("[SYSTEM] Stopping test. Returning to standby.");
        } else if (cmd == "CMD:PING") {
          Serial.println("[SYSTEM] Ping acknowledged.");
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("=========================================");
  Serial.println(" RailSafe AI — Handheld Screening Device ");
  Serial.println("=========================================");

  pinMode(LED_STATUS_PIN, OUTPUT);
  pinMode(PIN_SENSOR_1, INPUT);
  pinMode(PIN_SENSOR_2, INPUT);

  // Initialize BLE Device
  BLEDevice::init(DEVICE_NAME);

  // Optional: Set MTU to 512 for full JSON packets
  BLEDevice::setMTU(512);

  // Create BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // Create Primary Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create Telemetry Characteristic (Notify)
  pDataCharacteristic = pService->createCharacteristic(
                      DATA_CHAR_UUID,
                      BLECharacteristic::PROPERTY_READ |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pDataCharacteristic->addDescriptor(new BLE2902());

  // Create Command Characteristic (Write)
  pCmdCharacteristic = pService->createCharacteristic(
                     CMD_CHAR_UUID,
                     BLECharacteristic::PROPERTY_WRITE |
                     BLECharacteristic::PROPERTY_WRITE_NR
                   );
  pCmdCharacteristic->setCallbacks(new CommandCallbacks());

  // Start Service
  pService->start();

  // Configure and start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // iPhone/Android compatibility helper
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising active. Awaiting RailSafe AI app...");
}

void loop() {
  // Restart advertising if disconnected
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    Serial.println("[BLE] Re-started advertising...");
    oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Periodic Telemetry Transmission (1 Hz interval)
  if (deviceConnected && isTesting) {
    unsigned long currentMillis = millis();
    if (currentMillis - lastTelemetryMillis >= 1000) {
      lastTelemetryMillis = currentMillis;
      sequence++;

      // Read raw hardware sensors from ADC
      int raw1 = analogRead(PIN_SENSOR_1);
      int raw2 = analogRead(PIN_SENSOR_2);

      // Convert to calibrated physical engineering units
      // (Example: 12-bit ADC 0-4095 mapped to 0-500 ppm and 0-250 mV)
      float s1Val = (raw1 / 4095.0) * 500.0;
      float s2Val = (raw2 / 4095.0) * 250.0;

      // Construct JSON payload
      // Delimited with newline '\n' for framing across BLE chunk boundaries
      char payload[256];
      snprintf(payload, sizeof(payload),
        "{\"deviceId\":\"%s\",\"sequence\":%u,\"mode\":\"hardware\",\"sensors\":{\"sensor_1\":{\"value\":%.1f,\"unit\":\"ppm\"},\"sensor_2\":{\"value\":%.1f,\"unit\":\"mV\"}},\"status\":\"ok\"}\n",
        DEVICE_NAME,
        sequence,
        s1Val,
        s2Val
      );

      // Transmit BLE notification
      pDataCharacteristic->setValue((uint8_t*)payload, strlen(payload));
      pDataCharacteristic->notify();

      Serial.print("[TELEMETRY #");
      Serial.print(sequence);
      Serial.print("] ");
      Serial.println(payload);
    }
  }

  delay(20);
}
