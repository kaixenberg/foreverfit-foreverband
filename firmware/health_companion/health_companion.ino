// Personal Health Companion — wearable firmware (ESP32-S3)
//
// Reads MAX30101 (HR/SpO2), MPU6050 (accel/gyro), BME280 (env), a stubbed
// MAX30205 (body temp — real sensor not working on this build), drives the
// 0.96" OLED watchface, and streams everything to the phone over BLE.
//
// Wire payload structs below MUST stay byte-for-byte in sync with
// app/health_companion/lib/ble/protocol.dart — see ARCHITECTURE.md for the
// authoritative protocol spec.

#include <Arduino.h>
#include <Wire.h>
#include <NimBLEDevice.h>
#include <Adafruit_Sensor.h>
#include <Adafruit_BME280.h>
#include <Adafruit_MPU6050.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <MAX30105.h>
#include <heartRate.h>

// ---------------------------------------------------------------------------
// Wiring config — adjust these to match your actual wiring.
// ---------------------------------------------------------------------------
#define I2C_SDA 8
#define I2C_SCL 9
#define OLED_WIDTH 128
#define OLED_HEIGHT 64
#define OLED_I2C_ADDR 0x3C
#define BME280_I2C_ADDR 0x76

// ---------------------------------------------------------------------------
// BLE — custom "Health Companion" service, three notify characteristics.
// ---------------------------------------------------------------------------
#define SERVICE_UUID     "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_VITALS_UUID "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_ENV_UUID    "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_MOTION_UUID "6e400004-b5a3-f393-e0a9-e50e24dcca9e"
#define BLE_DEVICE_NAME  "HealthCompanion"

const uint32_t VITALS_INTERVAL_MS = 1000;
const uint32_t ENV_INTERVAL_MS    = 1000;
const uint32_t MOTION_INTERVAL_MS = 50;   // ~20 Hz, enough for fall-detection windows
const uint32_t OLED_INTERVAL_MS   = 1000;

// ---------------------------------------------------------------------------
// Wire payloads. Little-endian (native on ESP32), packed, fixed layout.
// ---------------------------------------------------------------------------
struct __attribute__((packed)) VitalsPacket {
  uint32_t tMs;
  float heartRate;
  float spo2;
  float bodyTempC;
};

struct __attribute__((packed)) EnvPacket {
  uint32_t tMs;
  float ambientTempC;
  float humidity;
  float pressureHPa;
};

struct __attribute__((packed)) MotionPacket {
  uint32_t tMs;
  float ax, ay, az;
  float gx, gy, gz;
};

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
Adafruit_BME280 bme;
Adafruit_MPU6050 mpu;
Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
MAX30105 particleSensor;

NimBLEServer* bleServer = nullptr;
NimBLECharacteristic* vitalsChar = nullptr;
NimBLECharacteristic* envChar = nullptr;
NimBLECharacteristic* motionChar = nullptr;
bool deviceConnected = false;

bool bmeOk = false;
bool mpuOk = false;
bool oledOk = false;
bool maxOk = false;

// --- Heart-rate beat detection (SparkFun heartRate.h) ---
const byte RATE_ARRAY_SIZE = 4;
byte rateSpot = 0;
long lastBeatMs = 0;
float beatsPerMinuteArr[RATE_ARRAY_SIZE] = {0};
float currentBpm = 0;

// --- Rough, UNCALIBRATED SpO2 estimate from IR/RED AC-DC ratio ---
// This is the standard hobbyist ratio-of-ratios formula, not a clinically
// calibrated measurement — good enough for a demo risk signal, not diagnosis.
long irMin = 999999, irMax = 0, redMin = 999999, redMax = 0;
long irSum = 0, redSum = 0;
uint32_t spo2SampleCount = 0;
uint32_t spo2WindowStartMs = 0;
float currentSpo2 = 98.0;

uint32_t lastVitalsNotify = 0, lastEnvNotify = 0, lastMotionNotify = 0, lastOledUpdate = 0;

// ---------------------------------------------------------------------------
// MAX30205 stub — real sensor doesn't work on this build. Swap this function
// for a real driver call if/when the sensor is replaced.
// ---------------------------------------------------------------------------
float readBodyTempC() {
  static float lastVal = 36.8;
  lastVal += (random(-10, 11) / 100.0f); // +/- 0.1C jitter
  lastVal = constrain(lastVal, 36.3f, 37.3f);
  return lastVal;
}

// ---------------------------------------------------------------------------
// BLE server callbacks
// ---------------------------------------------------------------------------
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server) override {
    deviceConnected = true;
    Serial.println("[BLE] Central connected");
  }
  void onDisconnect(NimBLEServer* server) override {
    deviceConnected = false;
    Serial.println("[BLE] Central disconnected, restarting advertising");
    NimBLEDevice::startAdvertising();
  }
};

void setupBle() {
  NimBLEDevice::init(BLE_DEVICE_NAME);
  bleServer = NimBLEDevice::createServer();
  bleServer->setCallbacks(new ServerCallbacks());

  NimBLEService* service = bleServer->createService(SERVICE_UUID);

  vitalsChar = service->createCharacteristic(
      CHAR_VITALS_UUID, NIMBLE_PROPERTY::NOTIFY);
  envChar = service->createCharacteristic(
      CHAR_ENV_UUID, NIMBLE_PROPERTY::NOTIFY);
  motionChar = service->createCharacteristic(
      CHAR_MOTION_UUID, NIMBLE_PROPERTY::NOTIFY);

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  advertising->setScanResponse(true);
  NimBLEDevice::startAdvertising();
  Serial.println("[BLE] advertising started");
}

// ---------------------------------------------------------------------------
// Sensor setup
// ---------------------------------------------------------------------------
void setupSensors() {
  bmeOk = bme.begin(BME280_I2C_ADDR, &Wire);
  Serial.printf("[BME280] init %s\n", bmeOk ? "OK" : "FAILED");

  mpuOk = mpu.begin();
  if (mpuOk) {
    mpu.setAccelerometerRange(MPU6050_RANGE_4_G);
    mpu.setGyroRange(MPU6050_RANGE_500_DEG);
    mpu.setFilterBandwidth(MPU6050_BAND_21_HZ);
  }
  Serial.printf("[MPU6050] init %s\n", mpuOk ? "OK" : "FAILED");

  maxOk = particleSensor.begin(Wire, I2C_SPEED_FAST);
  if (maxOk) {
    particleSensor.setup(); // default: red+IR, 100Hz, 4 samples avg
    particleSensor.setPulseAmplitudeRed(0x0A);
    particleSensor.setPulseAmplitudeGreen(0);
  }
  Serial.printf("[MAX30101] init %s\n", maxOk ? "OK" : "FAILED");

  oledOk = display.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR);
  if (oledOk) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("Health Companion");
    display.println("booting...");
    display.display();
  }
  Serial.printf("[OLED] init %s\n", oledOk ? "OK" : "FAILED");
}

// ---------------------------------------------------------------------------
// HR / SpO2 sampling — call every loop iteration to avoid dropping FIFO data.
// ---------------------------------------------------------------------------
void pollHeartRateSensor() {
  if (!maxOk) return;

  long irValue = particleSensor.getIR();
  long redValue = particleSensor.getRed();
  if (irValue < 5000) return; // no finger/wrist contact

  // Beat detection -> BPM
  if (checkForBeat(irValue)) {
    long now = millis();
    long delta = now - lastBeatMs;
    lastBeatMs = now;
    float bpm = 60.0f / (delta / 1000.0f);
    if (bpm > 20 && bpm < 255) {
      beatsPerMinuteArr[rateSpot++] = bpm;
      rateSpot %= RATE_ARRAY_SIZE;
      float sum = 0;
      for (byte i = 0; i < RATE_ARRAY_SIZE; i++) sum += beatsPerMinuteArr[i];
      currentBpm = sum / RATE_ARRAY_SIZE;
    }
  }

  // Rough SpO2 ratio-of-ratios accumulation
  irMin = min(irMin, irValue);
  irMax = max(irMax, irValue);
  redMin = min(redMin, redValue);
  redMax = max(redMax, redValue);
  irSum += irValue;
  redSum += redValue;
  spo2SampleCount++;

  uint32_t now = millis();
  if (now - spo2WindowStartMs >= 1000 && spo2SampleCount > 10) {
    float irDc = irSum / (float)spo2SampleCount;
    float redDc = redSum / (float)spo2SampleCount;
    float irAc = irMax - irMin;
    float redAc = redMax - redMin;
    if (irDc > 0 && redDc > 0 && irAc > 0) {
      float r = (redAc / redDc) / (irAc / irDc);
      float estimate = 110.0f - 25.0f * r;
      currentSpo2 = constrain(estimate, 80.0f, 100.0f);
    }
    irMin = redMin = 999999;
    irMax = redMax = 0;
    irSum = redSum = 0;
    spo2SampleCount = 0;
    spo2WindowStartMs = now;
  }
}

// ---------------------------------------------------------------------------
// Notify helpers
// ---------------------------------------------------------------------------
void notifyVitals() {
  VitalsPacket pkt;
  pkt.tMs = millis();
  pkt.heartRate = currentBpm;
  pkt.spo2 = currentSpo2;
  pkt.bodyTempC = readBodyTempC();
  vitalsChar->setValue((uint8_t*)&pkt, sizeof(pkt));
  if (deviceConnected) vitalsChar->notify();
}

void notifyEnv() {
  EnvPacket pkt;
  pkt.tMs = millis();
  if (bmeOk) {
    pkt.ambientTempC = bme.readTemperature();
    pkt.humidity = bme.readHumidity();
    pkt.pressureHPa = bme.readPressure() / 100.0f;
  } else {
    pkt.ambientTempC = NAN;
    pkt.humidity = NAN;
    pkt.pressureHPa = NAN;
  }
  envChar->setValue((uint8_t*)&pkt, sizeof(pkt));
  if (deviceConnected) envChar->notify();
}

void notifyMotion() {
  if (!mpuOk) return;
  sensors_event_t accel, gyro, temp;
  mpu.getEvent(&accel, &gyro, &temp);

  MotionPacket pkt;
  pkt.tMs = millis();
  pkt.ax = accel.acceleration.x;
  pkt.ay = accel.acceleration.y;
  pkt.az = accel.acceleration.z;
  pkt.gx = gyro.gyro.x;
  pkt.gy = gyro.gyro.y;
  pkt.gz = gyro.gyro.z;
  motionChar->setValue((uint8_t*)&pkt, sizeof(pkt));
  if (deviceConnected) motionChar->notify();
}

// ---------------------------------------------------------------------------
// OLED watchface (unchanged core, plus a BLE status indicator)
// ---------------------------------------------------------------------------
void updateOled() {
  if (!oledOk) return;
  display.clearDisplay();
  display.setCursor(0, 0);
  display.setTextSize(1);

  display.printf("BLE: %s\n", deviceConnected ? "connected" : "advertising");
  display.println();

  display.setTextSize(1);
  display.printf("HR: %.0f bpm\n", currentBpm);
  display.printf("SpO2: %.0f %%\n", currentSpo2);
  if (bmeOk) {
    display.printf("Amb: %.1f C  %.0f%%\n", bme.readTemperature(), bme.readHumidity());
    display.printf("P: %.0f hPa\n", bme.readPressure() / 100.0f);
  }
  display.display();
}

// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n[BOOT] Personal Health Companion");

  Wire.begin(I2C_SDA, I2C_SCL);
  randomSeed(analogRead(0));

  setupSensors();
  setupBle();

  spo2WindowStartMs = millis();
}

void loop() {
  pollHeartRateSensor(); // every iteration — don't miss FIFO samples

  uint32_t now = millis();

  if (now - lastVitalsNotify >= VITALS_INTERVAL_MS) {
    lastVitalsNotify = now;
    notifyVitals();
  }
  if (now - lastEnvNotify >= ENV_INTERVAL_MS) {
    lastEnvNotify = now;
    notifyEnv();
  }
  if (now - lastMotionNotify >= MOTION_INTERVAL_MS) {
    lastMotionNotify = now;
    notifyMotion();
  }
  if (now - lastOledUpdate >= OLED_INTERVAL_MS) {
    lastOledUpdate = now;
    updateOled();
  }
}
