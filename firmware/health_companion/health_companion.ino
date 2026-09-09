// ForeverFit — "ForeverBand" wearable firmware (ESP32-S3)
//
// Reads MAX30101 (HR/SpO2 — real finger-presence detection, optionally
// dummy/spoofed BPM+SpO2 values, see USE_DUMMY_HR_SPO2), MPU6050
// (accel/gyro), BME280 (env), a stubbed MAX30205 (body temp — real
// sensor not working on this build, only reported while a finger is
// present, same as HR/SpO2), drives two OLED watch faces (BOOT button
// toggles between them — see BOOT_BUTTON_PIN), and streams everything to
// the phone over BLE. The phone also writes the current time back over
// BLE (see CHAR_TIME_UUID) so the primary watch face can show a real
// clock/date without an RTC or network access of its own.
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

// ---------------------------------------------------------------------------
// Wiring config — adjust these to match your actual wiring.
// ---------------------------------------------------------------------------
#define I2C_SDA 8
#define I2C_SCL 9
#define OLED_WIDTH 128
#define OLED_HEIGHT 64
#define OLED_I2C_ADDR 0x3C
#define BME280_I2C_ADDR 0x76

// GPIO0 — the ESP32-S3 DevKit's built-in BOOT button. Only used at power-on
// to enter flash mode; free to read as a normal button once the sketch is
// running, so this needs no extra wiring. Active LOW (INPUT_PULLUP), used
// here to toggle between the primary and secondary watch faces.
#define BOOT_BUTTON_PIN 0

// IR DC-baseline magnitude below which we treat the sensor as "no
// finger/wrist contact". 50000 matches SparkFun/Maxim's own MAX3010x
// reference examples; watch the "[HR] IRdc=..." serial debug line and
// adjust this if your specific board's LED coupling runs noticeably higher
// or lower at rest.
#define FINGER_PRESENT_IR_THRESHOLD 50000

// Spoofs HR/SpO2 to a plausible healthy resting range instead of the real
// MAX30101 beat-detection output — for demo reliability, since skin
// contact quality/ambient light can make the real algorithm noisy on
// stage. Real finger-presence detection (FINGER_PRESENT_IR_THRESHOLD,
// still driven by actual IR DC baseline) is UNCHANGED and still gates
// this: no finger still means no reading, same as the real sensor path —
// only the computed BPM/SpO2 numbers are fake, not "is someone wearing
// it." Set to 0 to use the real bench-tested algorithm's output instead.
#define USE_DUMMY_HR_SPO2 1

// ---------------------------------------------------------------------------
// BLE — custom "ForeverBand" service: three notify characteristics plus two
// write-only characteristics (phone -> wearable time sync, watch settings).
// ---------------------------------------------------------------------------
#define SERVICE_UUID           "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_VITALS_UUID       "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_ENV_UUID          "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_MOTION_UUID       "6e400004-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_TIME_UUID         "6e400005-b5a3-f393-e0a9-e50e24dcca9e"
#define CHAR_WATCH_SETTINGS_UUID "6e400006-b5a3-f393-e0a9-e50e24dcca9e"
#define BLE_DEVICE_NAME        "ForeverBand"

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
  uint8_t fingerPresent; // 0/1 — see FINGER_PRESENT_IR_THRESHOLD above.
                          // Without this the app can't tell "0 bpm because
                          // no finger" from an actual reading of 0, which
                          // both looks like a false medical warning and
                          // would bias any stats computed from history.
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

// Phone -> wearable, WRITE only (never notified back). weekday is
// 0=Sunday..6=Saturday — see protocol.dart's buildTimeSyncPacket().
struct __attribute__((packed)) TimeSyncPacket {
  uint8_t hour;
  uint8_t minute;
  uint8_t second;
  uint8_t day;
  uint8_t month;
  uint16_t year;
  uint8_t weekday;
};

// Phone -> wearable, WRITE only. Field meanings/order MUST match
// lib/models/watch_settings.dart + protocol.dart's
// buildWatchSettingsPacket() exactly — selectedFace/dateFormat are raw
// enum indices, not free-form values.
struct __attribute__((packed)) WatchSettingsPacket {
  uint8_t selectedFace;        // 0=primary, 1=secondary
  uint8_t autoCycleEnabled;    // 0/1
  uint16_t autoCycleIntervalSec;
  uint8_t use24HourFormat;     // 0/1
  uint8_t dateFormat;          // 0..3, see formatDate() below
  uint8_t showSeconds;         // 0/1
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
NimBLECharacteristic* timeChar = nullptr;
NimBLECharacteristic* watchSettingsChar = nullptr;
bool deviceConnected = false;

bool bmeOk = false;
bool mpuOk = false;
bool oledOk = false;
bool maxOk = false;

// --- Time sync (see TimeSyncPacket above) and watch-face state ---
bool timeSynced = false;
uint32_t timeSyncMillis = 0; // millis() at the moment of the last sync
uint8_t syncedHour = 0, syncedMinute = 0, syncedSecond = 0;
uint8_t syncedDay = 1, syncedMonth = 1, syncedWeekday = 0;
uint16_t syncedYear = 2026;

bool showSecondaryFace = false;
bool lastButtonReading = HIGH; // INPUT_PULLUP: HIGH = not pressed
uint32_t lastButtonChangeMs = 0;
const uint32_t BUTTON_DEBOUNCE_MS = 250;

// --- Watch settings pushed from the phone (see WatchSettingsPacket above)
// — defaults here match WatchSettings.defaults in watch_settings.dart, so
// the very first boot (before any BLE write ever arrives) already looks
// the same as what the app would push anyway. ---
bool autoCycleEnabled = false;
uint16_t autoCycleIntervalSec = 10;
uint32_t lastFaceCycleMs = 0;
bool use24HourFormat = true;
uint8_t dateFormatSetting = 1; // 1 = weekdayShortWithYear, see formatDate()
bool showSecondsSetting = false;

// --- HR + SpO2 via DC removal, AC low-pass filtering, and per-beat peak
// detection. Bench-tested against a standalone reference sketch before
// being ported in here — see git history for the earlier, less reliable
// zero-crossing + fixed-window approach this replaces. ---
float irDC = 0, redDC = 0;
bool dcInit = false;
const float DC_ALPHA = 0.05;   // baseline (DC) tracking speed
const float LP_ALPHA = 0.3;    // AC signal smoothing

float irACFilt = 0, redACFilt = 0;
float lastFilteredIr = 0;
bool rising = false;
uint32_t lastBeatTime = 0;
const uint32_t MIN_BEAT_INTERVAL_MS = 300;  // caps at 200bpm, rejects double-triggers
const uint32_t MAX_BEAT_INTERVAL_MS = 2000; // below 30bpm treat as no-beat

const int IBI_HISTORY = 2;
uint32_t ibiHistory[IBI_HISTORY] = {0};
int ibiIndex = 0;
int ibiCount = 0;

// Peak/trough of the filtered signal within the CURRENT beat cycle — ties
// the AC amplitude used for SpO2 to a real physiological cycle rather than
// a fixed time window that motion artifact can dominate.
float irPeakVal = -1e9, irTroughVal = 1e9;
float redPeakVal = -1e9, redTroughVal = 1e9;

// Rough, UNCALIBRATED SpO2 estimate (standard ratio-of-ratios formula) —
// fine as a relative risk signal, not a clinically valid reading.
const int AMP_HISTORY = 5;
float irAmpHistory[AMP_HISTORY] = {0};
float redAmpHistory[AMP_HISTORY] = {0};
float irDCAtBeat[AMP_HISTORY] = {0};
float redDCAtBeat[AMP_HISTORY] = {0};
int ampIndex = 0;
int ampCount = 0;

float currentBpm = 0;
float currentSpo2 = 0; // 0 = no reading yet / no contact, not a real SpO2 value
bool fingerPresent = false;
float lastBodyTempC = 36.8;

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
// Dummy HR/SpO2 (see USE_DUMMY_HR_SPO2 above) — overrides currentBpm/
// currentSpo2 in place, right before anything reads them, so neither the
// real peak-detection algorithm above nor its FIFO draining (still needed
// every loop to keep the sensor's buffer from overflowing) had to change
// at all. Same smooth-random-walk-around-a-baseline style as
// readBodyTempC()'s existing stub. Only overrides while fingerPresent is
// true — with no finger, the real algorithm has already zeroed both via
// resetHrSpo2State(), and this leaves that alone.
// ---------------------------------------------------------------------------
void applyDummyVitalsIfEnabled() {
  if (!USE_DUMMY_HR_SPO2 || !fingerPresent) return;

  static float dummyBpm = 74.0f;
  static float dummySpo2 = 98.0f;

  dummyBpm += (random(-30, 31) / 10.0f);  // +/- 3.0 bpm jitter
  dummyBpm = constrain(dummyBpm, 65.0f, 85.0f);
  dummySpo2 += (random(-10, 11) / 10.0f); // +/- 1.0% jitter
  dummySpo2 = constrain(dummySpo2, 96.0f, 99.0f);

  currentBpm = dummyBpm;
  currentSpo2 = dummySpo2;
}

// ---------------------------------------------------------------------------
// Time sync (see TimeSyncPacket above) — the phone writes the current
// time whenever it connects and every few minutes after that (see
// BleService._syncTime in the app). Stored as a synced reference point
// plus the millis() timestamp of that sync, so currentTime() below can
// derive "now" between syncs without needing an RTC.
// ---------------------------------------------------------------------------
bool isLeapYear(uint16_t y) {
  return (y % 4 == 0 && y % 100 != 0) || (y % 400 == 0);
}

uint8_t daysInMonth(uint8_t month, uint16_t year) {
  static const uint8_t days[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (month < 1 || month > 12) return 30;
  if (month == 2 && isLeapYear(year)) return 29;
  return days[month - 1];
}

// Advances the synced wall-clock time by the milliseconds elapsed since
// the last sync. Read-only — doesn't mutate the synced* globals, so this
// can be called as often as needed (once per OLED refresh) without
// drifting the reference point itself.
void currentTime(uint8_t& h, uint8_t& m, uint8_t& s, uint8_t& day,
                  uint8_t& month, uint16_t& year, uint8_t& weekday) {
  uint32_t elapsedSec = (millis() - timeSyncMillis) / 1000;
  uint32_t totalSec = syncedSecond + elapsedSec;
  s = totalSec % 60;
  uint32_t totalMin = syncedMinute + totalSec / 60;
  m = totalMin % 60;
  uint32_t totalHour = syncedHour + totalMin / 60;
  h = totalHour % 24;
  uint32_t daysElapsed = totalHour / 24;

  day = syncedDay;
  month = syncedMonth;
  year = syncedYear;
  weekday = (syncedWeekday + daysElapsed) % 7;

  while (daysElapsed > 0) {
    uint8_t dim = daysInMonth(month, year);
    if (day + daysElapsed <= dim) {
      day += daysElapsed;
      daysElapsed = 0;
    } else {
      daysElapsed -= (dim - day + 1);
      day = 1;
      month++;
      if (month > 12) {
        month = 1;
        year++;
      }
    }
  }
}

class TimeCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override {
    NimBLEAttValue value = c->getValue();
    if (value.length() < sizeof(TimeSyncPacket)) return;
    TimeSyncPacket pkt;
    memcpy(&pkt, value.data(), sizeof(TimeSyncPacket));

    syncedHour = pkt.hour;
    syncedMinute = pkt.minute;
    syncedSecond = pkt.second;
    syncedDay = pkt.day;
    syncedMonth = pkt.month;
    syncedYear = pkt.year;
    syncedWeekday = pkt.weekday;
    timeSyncMillis = millis();
    timeSynced = true;

    Serial.printf("[TIME] synced %04d-%02d-%02d %02d:%02d:%02d\n", syncedYear,
                  syncedMonth, syncedDay, syncedHour, syncedMinute, syncedSecond);
  }
};

// Applies the phone's watch-face preferences immediately on write — the
// face selection takes effect right away (not just on the next redraw),
// and lastFaceCycleMs resets so a freshly-changed auto-cycle interval
// starts counting from now, not from whenever the last cycle happened to
// be under the old interval.
class WatchSettingsCallbacks : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo& connInfo) override {
    NimBLEAttValue value = c->getValue();
    if (value.length() < sizeof(WatchSettingsPacket)) return;
    WatchSettingsPacket pkt;
    memcpy(&pkt, value.data(), sizeof(WatchSettingsPacket));

    showSecondaryFace = pkt.selectedFace != 0;
    autoCycleEnabled = pkt.autoCycleEnabled != 0;
    autoCycleIntervalSec = pkt.autoCycleIntervalSec;
    use24HourFormat = pkt.use24HourFormat != 0;
    dateFormatSetting = pkt.dateFormat;
    showSecondsSetting = pkt.showSeconds != 0;
    lastFaceCycleMs = millis();

    Serial.printf("[WATCH] settings: face=%d autoCycle=%d/%us 24h=%d "
                  "dateFmt=%d seconds=%d\n",
                  pkt.selectedFace, autoCycleEnabled, autoCycleIntervalSec,
                  use24HourFormat, dateFormatSetting, showSecondsSetting);
  }
};

// ---------------------------------------------------------------------------
// BOOT button — toggles which watch face updateOled() draws. Polled once
// per loop() with simple debounce; no interrupt needed at this poll rate.
// ---------------------------------------------------------------------------
void pollBootButton() {
  int reading = digitalRead(BOOT_BUTTON_PIN);
  uint32_t now = millis();
  if (reading != lastButtonReading && (now - lastButtonChangeMs) > BUTTON_DEBOUNCE_MS) {
    lastButtonChangeMs = now;
    lastButtonReading = reading;
    if (reading == LOW) { // BOOT button is active LOW
      showSecondaryFace = !showSecondaryFace;
      lastFaceCycleMs = now; // a manual switch shouldn't get immediately
                              // undone by an auto-cycle that was already
                              // close to due
      Serial.printf("[BUTTON] switched to %s face\n",
                    showSecondaryFace ? "secondary" : "primary");
    }
  }
}

// ---------------------------------------------------------------------------
// Auto-cycle — flips the active face on a timer when enabled, independent
// of (but resettable by) the BOOT button above. Polled once per loop().
// ---------------------------------------------------------------------------
void pollAutoCycle() {
  if (!autoCycleEnabled) return;
  uint32_t now = millis();
  if (now - lastFaceCycleMs >= (uint32_t)autoCycleIntervalSec * 1000) {
    showSecondaryFace = !showSecondaryFace;
    lastFaceCycleMs = now;
  }
}

// ---------------------------------------------------------------------------
// BLE server callbacks
// ---------------------------------------------------------------------------
class ServerCallbacks : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override {
    deviceConnected = true;
    Serial.println("[BLE] Central connected");
  }
  void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override {
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
  timeChar = service->createCharacteristic(
      CHAR_TIME_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  timeChar->setCallbacks(new TimeCallbacks());
  watchSettingsChar = service->createCharacteristic(
      CHAR_WATCH_SETTINGS_UUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR);
  watchSettingsChar->setCallbacks(new WatchSettingsCallbacks());

  service->start();

  NimBLEAdvertising* advertising = NimBLEDevice::getAdvertising();
  advertising->addServiceUUID(SERVICE_UUID);
  NimBLEDevice::startAdvertising();
  Serial.println("[BLE] advertising started");
}

// ---------------------------------------------------------------------------
// I2C bus scan — diagnostic only. Prints every address that ACKs, so we
// can tell wiring/power/address problems apart from a genuinely dead
// sensor without guessing.
// ---------------------------------------------------------------------------
void scanI2CBus() {
  Serial.println("[I2C] Scanning bus...");
  int found = 0;
  for (uint8_t addr = 0x08; addr < 0x78; addr++) {
    Wire.beginTransmission(addr);
    if (Wire.endTransmission() == 0) {
      Serial.printf("[I2C]   device found at 0x%02X\n", addr);
      found++;
    }
  }
  Serial.printf("[I2C] Scan complete, %d device(s) found\n", found);
}

// ---------------------------------------------------------------------------
// Sensor setup
// ---------------------------------------------------------------------------
void setupSensors() {
  scanI2CBus();

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
    // ledMode=2 (Red+IR only, no Green); sampleAverage=8 for hardware-level
    // noise reduction; powerLevel=0x1F sets Red and IR to the SAME current
    // so the redAc/redDc vs irAc/irDc ratio used for SpO2 is meaningful —
    // bench-verified to sit in a good unclipped range on this hardware.
    particleSensor.setup(0x1F, 8, 2, 100, 411, 4096);
  }
  Serial.printf("[MAX30101] init %s\n", maxOk ? "OK" : "FAILED");

  oledOk = display.begin(SSD1306_SWITCHCAPVCC, OLED_I2C_ADDR);
  if (oledOk) {
    display.clearDisplay();
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(0, 0);
    display.println("ForeverFit");
    display.println("booting...");
    display.display();
  }
  Serial.printf("[OLED] init %s\n", oledOk ? "OK" : "FAILED");
}

// ---------------------------------------------------------------------------
// Turn accumulated beat/amplitude history into currentBpm / currentSpo2.
// Called after each newly-accepted beat.
// ---------------------------------------------------------------------------
void recomputeVitalsFromHistory() {
  if (ibiCount > 0) {
    uint32_t sum = 0;
    for (int i = 0; i < ibiCount; i++) sum += ibiHistory[i];
    float avgIbi = (float)sum / ibiCount;
    currentBpm = 60000.0f / avgIbi;
  }

  if (ampCount >= 1) {
    float irAmpSum = 0, redAmpSum = 0, irDcSum = 0, redDcSum = 0;
    for (int i = 0; i < ampCount; i++) {
      irAmpSum += irAmpHistory[i];
      redAmpSum += redAmpHistory[i];
      irDcSum += irDCAtBeat[i];
      redDcSum += redDCAtBeat[i];
    }
    float irAcAvg = irAmpSum / ampCount;
    float redAcAvg = redAmpSum / ampCount;
    float irDcAvg = irDcSum / ampCount;
    float redDcAvg = redDcSum / ampCount;

    // Guard against divide-by-noise on a too-weak or too-faint signal.
    if (irAcAvg >= 3 && redAcAvg >= 3 && irDcAvg >= 1000 && redDcAvg >= 1000) {
      float r = (redAcAvg / redDcAvg) / (irAcAvg / irDcAvg);
      float spo2 = 110.0f - 25.0f * r;
      currentSpo2 = constrain(spo2, 0.0f, 100.0f);
    }
  }
}

void resetHrSpo2State() {
  currentBpm = 0;
  currentSpo2 = 0;
  ibiCount = 0;
  ibiIndex = 0;
  ampCount = 0;
  ampIndex = 0;
  irACFilt = redACFilt = 0;
  lastFilteredIr = 0;
  rising = false;
  lastBeatTime = 0;
  irPeakVal = redPeakVal = -1e9;
  irTroughVal = redTroughVal = 1e9;
}

// ---------------------------------------------------------------------------
// HR / SpO2 sampling — drains the sensor's FIFO every loop iteration so no
// samples are dropped. DC-removal + peak detection adapted from a
// bench-tested reference sketch (06_hr_spo2_fast_readout.ino).
// ---------------------------------------------------------------------------
void pollHeartRateSensor() {
  if (!maxOk) return;

  particleSensor.check();

  while (particleSensor.available()) {
    long irRaw = particleSensor.getFIFOIR();
    long redRaw = particleSensor.getFIFORed();
    particleSensor.nextSample();

    // --- DC tracking (slow EMA = baseline) ---
    if (!dcInit) {
      irDC = irRaw;
      redDC = redRaw;
      dcInit = true;
    }
    irDC += (irRaw - irDC) * DC_ALPHA;
    redDC += (redRaw - redDC) * DC_ALPHA;

    fingerPresent = irDC >= FINGER_PRESENT_IR_THRESHOLD;
    if (!fingerPresent) {
      resetHrSpo2State();
      continue;
    }

    float irACraw = irRaw - irDC;
    float redACraw = redRaw - redDC;

    // --- Light smoothing on the AC component to reduce sample noise ---
    irACFilt += (irACraw - irACFilt) * LP_ALPHA;
    redACFilt += (redACraw - redACFilt) * LP_ALPHA;

    // --- track peak/trough of THIS beat cycle for both channels (for SpO2) ---
    if (irACFilt > irPeakVal) irPeakVal = irACFilt;
    if (irACFilt < irTroughVal) irTroughVal = irACFilt;
    if (redACFilt > redPeakVal) redPeakVal = redACFilt;
    if (redACFilt < redTroughVal) redTroughVal = redACFilt;

    // --- Peak detection on filtered IR AC signal ---
    float delta = irACFilt - lastFilteredIr;
    if (delta > 0 && !rising) {
      rising = true;
    } else if (delta < 0 && rising) {
      // Local max just occurred -> potential beat.
      rising = false;
      uint32_t now = millis();
      uint32_t interval = now - lastBeatTime;

      if (lastFilteredIr > 5) { // reject near-flat/noise-only cycles
        if (interval >= MIN_BEAT_INTERVAL_MS && interval <= MAX_BEAT_INTERVAL_MS &&
            lastBeatTime != 0) {
          ibiHistory[ibiIndex] = interval;
          ibiIndex = (ibiIndex + 1) % IBI_HISTORY;
          if (ibiCount < IBI_HISTORY) ibiCount++;

          float irAmpThisBeat = irPeakVal - irTroughVal;
          float redAmpThisBeat = redPeakVal - redTroughVal;
          // A real single-beat AC swing on a DC baseline of this magnitude
          // is typically tens to low-thousands, not tens of thousands.
          if (irAmpThisBeat > 0 && irAmpThisBeat < 20000 && redAmpThisBeat > 0 &&
              redAmpThisBeat < 20000) {
            irAmpHistory[ampIndex] = irAmpThisBeat;
            redAmpHistory[ampIndex] = redAmpThisBeat;
            irDCAtBeat[ampIndex] = irDC;
            redDCAtBeat[ampIndex] = redDC;
            ampIndex = (ampIndex + 1) % AMP_HISTORY;
            if (ampCount < AMP_HISTORY) ampCount++;
          }

          recomputeVitalsFromHistory();
        }
        lastBeatTime = now;
      }
      irPeakVal = -1e9;
      irTroughVal = 1e9;
      redPeakVal = -1e9;
      redTroughVal = 1e9;
    }
    lastFilteredIr = irACFilt;
  }

  static uint32_t lastDebugMs = 0;
  uint32_t nowDbg = millis();
  if (nowDbg - lastDebugMs >= 500) {
    lastDebugMs = nowDbg;
    Serial.printf("[HR] IRdc=%.0f Reddc=%.0f finger=%s BPM=%.0f SpO2=%.0f\n", irDC,
                  redDC, fingerPresent ? "yes" : "no", currentBpm, currentSpo2);
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
  // Only report body temp alongside HR/SpO2, i.e. while there's actual
  // skin contact — a real integrated wearable sensor package wouldn't
  // give you a temperature reading without contact either, and the app
  // side already treats 0 here the same way it treats 0 bpm/SpO2: "no
  // reading," not a real (and alarming) value — see dashboard_screen.dart.
  lastBodyTempC = fingerPresent ? readBodyTempC() : 0;
  pkt.bodyTempC = lastBodyTempC;
  pkt.fingerPresent = fingerPresent ? 1 : 0;
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
// OLED — two watch faces, toggled by the BOOT button (pollBootButton()).
// ---------------------------------------------------------------------------
const char* WEEKDAY_NAMES[] = {"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"};
const char* MONTH_NAMES[] = {"Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"};

/// Prints the date portion of the primary face per dateFormatSetting —
/// index order MUST match WatchDateFormat in watch_settings.dart.
void printDate(uint8_t weekday, uint8_t day, uint8_t month, uint16_t year) {
  switch (dateFormatSetting) {
    case 0: // weekdayShort: "Wed, Sep 09"
      display.printf("%s, %s %02d", WEEKDAY_NAMES[weekday],
                      MONTH_NAMES[month - 1], day);
      break;
    case 2: // dayMonthYearSlash: "09/09/2026"
      display.printf("%02d/%02d/%04d", day, month, year);
      break;
    case 3: // monthDayYearSlash: "09/09/2026" (US ordering)
      display.printf("%02d/%02d/%04d", month, day, year);
      break;
    case 1: // weekdayShortWithYear
    default:
      display.printf("%s, %s %02d %04d", WEEKDAY_NAMES[weekday],
                      MONTH_NAMES[month - 1], day, year);
      break;
  }
}

/// Primary face: a real clock (synced from the phone — see TimeCallbacks),
/// date, and BME280 ambient stats, the way an actual smartwatch face looks
/// rather than a debug readout. A small dot top-right stands in for a BLE
/// icon (filled = connected, hollow = advertising only) so this face
/// doesn't need a whole text line just for connection status the way the
/// secondary face does.
void drawPrimaryFace() {
  display.clearDisplay();

  if (deviceConnected) {
    display.fillCircle(122, 4, 3, SSD1306_WHITE);
  } else {
    display.drawCircle(122, 4, 3, SSD1306_WHITE);
  }

  if (timeSynced) {
    uint8_t h, m, s, day, month, weekday;
    uint16_t year;
    currentTime(h, m, s, day, month, year, weekday);

    uint8_t displayHour = h;
    if (!use24HourFormat) {
      displayHour = h % 12;
      if (displayHour == 0) displayHour = 12;
    }

    // "HH:MM:SS" (8 chars) only fits this display at textSize(2) — at
    // textSize(3) it would run past the right edge. Dropping to
    // textSize(2) only when seconds are actually shown keeps the normal
    // "HH:MM" clock as big as possible otherwise.
    if (showSecondsSetting) {
      display.setTextSize(2);
      display.setCursor(4, 8);
      display.printf("%2d:%02d:%02d", displayHour, m, s);
    } else {
      display.setTextSize(3);
      display.setCursor(19, 4);
      display.printf("%2d:%02d", displayHour, m);
    }

    if (!use24HourFormat) {
      display.setTextSize(1);
      display.setCursor(100, 10);
      display.print(h < 12 ? "AM" : "PM");
    }

    display.drawFastHLine(4, 36, 120, SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(4, 43);
    printDate(weekday, day, month, year);
  } else {
    display.setTextSize(3);
    display.setCursor(19, 4);
    display.print("--:--");
    display.drawFastHLine(4, 36, 120, SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(4, 43);
    display.print("Open the app to sync time");
  }

  display.setCursor(4, 55);
  if (bmeOk) {
    display.printf("%.1fC  %.0f%%  %.0fhPa", bme.readTemperature(),
                    bme.readHumidity(), bme.readPressure() / 100.0f);
  } else {
    display.print("Env sensor unavailable");
  }

  display.display();
}

/// Secondary face: the detailed HR/SpO2/body-temp/env readout the single
/// face used to always show — unchanged content, just no longer the only
/// option.
void drawSecondaryFace() {
  display.clearDisplay();
  display.setCursor(0, 0);
  display.setTextSize(1);

  display.printf("BLE: %s\n", deviceConnected ? "connected" : "advertising");
  display.println();

  if (!fingerPresent) {
    display.println("HR: -- (no finger)");
    display.println("SpO2: --");
    display.println("Body: --");
  } else {
    // Rolling averages need a few beats before they're a stable reading —
    // show a loading indicator until each has enough history. Skipped
    // entirely in dummy mode (USE_DUMMY_HR_SPO2), which has a value from
    // the first loop iteration with a finger present.
    if (!USE_DUMMY_HR_SPO2 && ibiCount < IBI_HISTORY) {
      display.println("HR: ... bpm");
    } else {
      display.printf("HR: %.0f bpm\n", currentBpm);
    }
    if (!USE_DUMMY_HR_SPO2 && ampCount < AMP_HISTORY) {
      display.println("SpO2: ... %");
    } else {
      display.printf("SpO2: %.0f %%\n", currentSpo2);
    }
    display.printf("Body: %.1f C\n", lastBodyTempC);
  }
  if (bmeOk) {
    display.printf("Amb: %.1f C  %.0f%%\n", bme.readTemperature(), bme.readHumidity());
    display.printf("P: %.0f hPa\n", bme.readPressure() / 100.0f);
  }
  display.display();
}

void updateOled() {
  if (!oledOk) return;
  if (showSecondaryFace) {
    drawSecondaryFace();
  } else {
    drawPrimaryFace();
  }
}

// ---------------------------------------------------------------------------
void setup() {
  Serial.begin(115200);
  delay(300);
  Serial.println("\n[BOOT] ForeverFit / ForeverBand");

  Wire.begin(I2C_SDA, I2C_SCL);
  // Standard Mode (100kHz, the Wire library default) — reverted from Fast
  // Mode (400kHz) because it's suspected of causing MPU6050 init to fail
  // on this breadboard build: 4 I2C devices sharing one bus over jumper
  // wires has marginal signal integrity at 400kHz. Revisit if/when this
  // moves to a proper PCB with short traces and correctly-sized pull-ups.
  randomSeed(analogRead(0));

  pinMode(BOOT_BUTTON_PIN, INPUT_PULLUP);

  setupSensors();
  setupBle();
}

void loop() {
  pollHeartRateSensor(); // every iteration — don't miss FIFO samples
  applyDummyVitalsIfEnabled();
  pollBootButton();
  pollAutoCycle();

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
