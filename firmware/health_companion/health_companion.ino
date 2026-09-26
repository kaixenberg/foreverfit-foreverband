// ForeverFit — "ForeverBand" wearable firmware (ESP32-S3)
//
// Reads MAX30102 (HR/SpO2 — PPG pipeline ported from the bench-tuned
// max30102_pulse_spo2_v4.ino sketch, see PPG_SAMPLE_RATE; optional
// dummy values, see USE_DUMMY_HR_SPO2), MPU6050
// (accel/gyro — on its own isolated I2C bus, `Wire1`/MPU_SDA/MPU_SCL,
// not the main bus with everything else below, and read with a small
// raw-register driver rather than Adafruit_MPU6050 — see `MPU_SDA`'s
// and `mpuBegin()`'s comments for why), BME280 (env), a DS18B20 on a
// 1-Wire bus (body temp — the MAX30205 this replaced never worked on
// this build; only reported while a finger is present, same as
// HR/SpO2), drives two OLED watch faces
// (BOOT button toggles between them — see BOOT_BUTTON_PIN), and streams
// everything to the phone over BLE. The phone also writes the current
// time back over BLE (see CHAR_TIME_UUID) so the primary watch face can
// show a real clock/date without an RTC or network access of its own.
//
// Wire payload structs below MUST stay byte-for-byte in sync with
// app/health_companion/lib/ble/protocol.dart — see ARCHITECTURE.md for the
// authoritative protocol spec.

#include <Arduino.h>
#include <Wire.h>
#include <NimBLEDevice.h>
#include <Adafruit_BME280.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <MAX30105.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include <functional>

// ---------------------------------------------------------------------------
// Wiring config — adjust these to match your actual wiring.
// ---------------------------------------------------------------------------
#define I2C_SDA 8
#define I2C_SCL 9
#define OLED_WIDTH 128
#define OLED_HEIGHT 64
#define OLED_I2C_ADDR 0x3C
#define BME280_I2C_ADDR 0x76

// MPU6050 gets its own I2C bus (the ESP32-S3's second hardware I2C
// peripheral, `Wire1`) instead of sharing SDA/SCL above with BME280/
// MAX30102/OLED — isolating it from the other 3 devices was the first
// thing tried while diagnosing a consistent (every attempt, not
// intermittent) `Adafruit_MPU6050::begin()` failure. Turned out not to
// be the actual cause (a live WHO_AM_I register readback on this exact
// module — see `mpuBegin()` below — found 0x70, the MPU6500's chip ID,
// not the real MPU6050's 0x68, which Adafruit_MPU6050 strictly checks
// and rejects; the "MPU6050" module in hand is actually a rebadged
// MPU6500, common in the cheap sensor market, register-compatible for
// raw accel/gyro but reporting a different identity), but isolation is
// harmless to keep regardless and rules out bus-sharing as a variable
// for future debugging. Pick different pins here if 5/6 are already
// used for something else on your specific board.
#define MPU_SDA 5
#define MPU_SCL 6

// DS18B20 body-temp probe — single-wire bus, needs its own GPIO (not on
// the I2C bus with everything else).
#define ONE_WIRE_PIN 4

// GPIO0 — the ESP32-S3 DevKit's built-in BOOT button. Only used at power-on
// to enter flash mode; free to read as a normal button once the sketch is
// running, so this needs no extra wiring. Active LOW (INPUT_PULLUP), used
// here to toggle between the primary and secondary watch faces.
#define BOOT_BUTTON_PIN 0


// Spoofs HR/SpO2 to a plausible healthy resting range instead of the real
// MAX30102 PPG output — a demo fallback for when skin contact/ambient
// light make the real pipeline unusable on stage. Real contact detection
// (PPG_FINGER_THRESHOLD) still gates it: no finger still means no reading;
// only the BPM/SpO2 numbers are fake. Off now that the replacement
// MAX30102 + the v4 pipeline give mostly reliable real readings.
#define USE_DUMMY_HR_SPO2 0

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
  uint8_t fingerPresent; // 0/1 — skin contact (PPG_FINGER_THRESHOLD).
                          // Without this the app can't tell "0 bpm because
                          // no finger" from an actual reading of 0, which
                          // both looks like a false medical warning and
                          // would bias any stats computed from history.
  uint8_t ppgFlags;       // PPG_FLAG_* bits below. Contact alone isn't a
                          // reading: the pipeline needs ~2 s to settle and
                          // PPG_READY_BEATS good beats before HR/SpO2 mean
                          // anything, and those are 0 until then.
};

const uint8_t PPG_FLAG_HR_READY = 1 << 0;
const uint8_t PPG_FLAG_SPO2_READY = 1 << 1;
const uint8_t PPG_FLAG_SETTLING = 1 << 2;
const uint8_t PPG_FLAG_SATURATED = 1 << 3; // LED too bright for this fit/skin

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
  // Developer/demo override — bypasses the fingerPresent contact check
  // that otherwise gates body temp (see readBodyTempC() below). Off by
  // default: body temp normally only counts as a real reading while the
  // MAX30102 also detects contact, since it's the only way this firmware
  // has to tell "on a wrist" from "lying on a table."
  uint8_t ignoreBodyTempContactCheck; // 0/1
};

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
Adafruit_BME280 bme;
Adafruit_SSD1306 display(OLED_WIDTH, OLED_HEIGHT, &Wire, -1);
MAX30105 particleSensor;
OneWire oneWire(ONE_WIRE_PIN);
DallasTemperature ds18b20(&oneWire);

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
bool ds18b20Ok = false;

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
bool ignoreBodyTempContactCheck = false;

// --- HR + SpO2: MAX30102 PPG pipeline, ported from the bench-tuned
// standalone sketch max30102_pulse_spo2_v4.ino. Timing is counted in SENSOR
// SAMPLES (100 Hz from the chip's own clock), never millis(), so loop()
// jitter from BLE/OLED/DS18B20 work can't distort beat intervals. The
// constants below are that sketch's tuned values — change them there first,
// bench-verify, then copy across. ---
const float PPG_SAMPLE_RATE = 100.0;          // 400 Hz internal, averaged by 4
const uint32_t PPG_FINGER_THRESHOLD = 10000;  // raw IR below this = no contact
const uint32_t PPG_SATURATION_LEVEL = 250000; // 18-bit ADC max is 262143
const float PPG_SETTLE_SECONDS = 2.0;         // DC baseline settles after contact
const int PPG_READY_BEATS = 4;                // values only reported after this many good beats

const float PPG_DC_ALPHA_FAST = 0.05; // baseline tracking while settling
const float PPG_DC_ALPHA      = 0.03; // afterwards (~0.5 Hz high-pass, follows drift)
const float PPG_LP_ALPHA      = 0.25; // smoothing (low-pass ~4.5 Hz)
const float PPG_ENV_DECAY     = 0.995; // how fast the peak envelope forgets old peaks
const float PPG_MIN_AMPLITUDE = 20;    // absolute floor for the beat threshold (ADC counts)

const float PPG_MIN_BPM = 45;
const float PPG_MAX_BPM = 180;
const uint32_t PPG_REFRACTORY_SAMPLES = (uint32_t)(PPG_SAMPLE_RATE * 60.0 / PPG_MAX_BPM);

const float PPG_OUTLIER_FRACTION = 0.25; // beat >25% off the running average is suspect
const int   PPG_MAX_REJECTS      = 3;    // ...unless it happens this many times in a row (real HR change)

// Plausible range for the red/IR ratio-of-ratios R (anything outside is noise).
const float PPG_R_MIN = 0.2;
const float PPG_R_MAX = 1.6;

// Watch-specific addition (not in the bench sketch, which only ever sat on
// a still finger): if no GOOD beat has been accepted for this long — wrist
// motion, loose strap — drop back to "measuring" instead of freezing the
// last average on screen and in the app as if it were still live.
const float PPG_STALE_SECONDS = 5.0;

// One optical channel (IR or Red): DC baseline, filtered AC pulse, and the
// AC peak-to-peak over the current beat (for SpO2's ratio-of-ratios).
struct PpgChannel {
  float dc = 0;
  float lp = 0;
  float maxV = -1e9;
  float minV = 1e9;

  void reset(float x) { dc = x; lp = 0; newWindow(); }

  float update(float x, float alpha) {
    dc += alpha * (x - dc);
    float ac = dc - x;              // inverted: more blood = positive
    lp += PPG_LP_ALPHA * (ac - lp);
    return lp;
  }

  void track() {
    if (lp > maxV) maxV = lp;
    if (lp < minV) minV = lp;
  }

  float peakToPeak() { return maxV - minV; }
  void newWindow() { maxV = -1e9; minV = 1e9; }
};

PpgChannel irCh, redCh;

float ppgPrevSig = 0, ppgPeakEnv = 0;
bool ppgArmed = false;
bool ppgSettledAnnounced = false;
uint32_t ppgSampleIndex = 0;
uint32_t ppgLastBeatSample = 0;     // last threshold crossing (accepted or not)
uint32_t ppgLastGoodBeatSample = 0; // last beat that actually fed the averages
uint32_t ppgSettleUntil = 0;
uint32_t ppgLastSaturatedSample = 0;
bool ppgEverSaturated = false;
uint32_t ppgLostSamples = 0;        // FIFO overflow count, for the debug line

const int PPG_RATE_SIZE = 6;
float ppgRates[PPG_RATE_SIZE];
int ppgRateCount = 0, ppgRateSpot = 0, ppgRejectCount = 0;
float ppgBpmAvg = 0;

float ppgRValues[PPG_RATE_SIZE];
int ppgRCount = 0, ppgRSpot = 0;
float ppgSpo2 = 0;

// Published results — what notifyVitals()/the OLED read. Only non-zero once
// the matching *Ready flag is true; 0 always means "no value", never a
// measured 0.
float currentBpm = 0;
float currentSpo2 = 0;
bool fingerPresent = false;
bool hrReady = false;
bool spo2Ready = false;
float lastBodyTempC = 36.8;

uint32_t lastVitalsNotify = 0, lastEnvNotify = 0, lastMotionNotify = 0, lastOledUpdate = 0;

// ---------------------------------------------------------------------------
// DS18B20 body temp (replaced the MAX30205, which never worked on this
// build). Conversion takes ~750ms at the default 12-bit resolution, and
// setupSensors() enables setWaitForConversion(false), so this pipelines the
// read across calls instead of blocking loop() (which also has to service
// BLE motion notifies at ~20Hz for fall detection): each call returns the
// PREVIOUS conversion's result, then immediately kicks off the next one.
// notifyVitals() only calls this once a second (VITALS_INTERVAL_MS), well
// past the ~750ms conversion time, so the result is always ready.
// ---------------------------------------------------------------------------
float readBodyTempC() {
  static float lastVal = 36.8f;
  static bool conversionStarted = false;

  if (conversionStarted) {
    float t = ds18b20.getTempCByIndex(0);
    if (t != DEVICE_DISCONNECTED_C) lastVal = t;
  }
  ds18b20.requestTemperatures();
  conversionStarted = true;
  return lastVal;
}

// ---------------------------------------------------------------------------
// Dummy HR/SpO2 (see USE_DUMMY_HR_SPO2 above) — overrides currentBpm/
// currentSpo2 in place, right before anything reads them, so neither the
// real PPG pipeline below nor its FIFO draining (still needed every loop
// to keep the sensor's buffer from overflowing) had to change
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
  hrReady = spo2Ready = true;
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
    ignoreBodyTempContactCheck = pkt.ignoreBodyTempContactCheck != 0;
    lastFaceCycleMs = millis();

    Serial.printf("[WATCH] settings: face=%d autoCycle=%d/%us 24h=%d "
                  "dateFmt=%d seconds=%d ignoreBodyTempContact=%d\n",
                  pkt.selectedFace, autoCycleEnabled, autoCycleIntervalSec,
                  use24HourFormat, dateFormatSetting, showSecondsSetting,
                  ignoreBodyTempContactCheck);
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
void scanI2CBus(TwoWire& wire, const char* label) {
  Serial.printf("[I2C] Scanning %s bus...\n", label);
  int found = 0;
  for (uint8_t addr = 0x08; addr < 0x78; addr++) {
    wire.beginTransmission(addr);
    if (wire.endTransmission() == 0) {
      Serial.printf("[I2C]   %s: device found at 0x%02X\n", label, addr);
      found++;
    }
  }
  Serial.printf("[I2C] %s scan complete, %d device(s) found\n", label, found);
}

// ---------------------------------------------------------------------------
// Retries a sensor's own init() a few times with a short delay between
// attempts — a single bad I2C transaction during setup doesn't have to
// be fatal. Originally added while diagnosing an MPU6050 init failure
// that turned out to be a consistent chip-identity mismatch, not an
// intermittent bus problem (see `MPU_SDA`'s and `mpuBegin()`'s
// comments) — a retry loop was never actually going to fix that
// specific issue (consistent failures don't get better on attempt 2),
// but it's a harmless, standard mitigation to keep for any sensor's
// occasional bad transaction, and is still used for the MAX30102 below.
// ---------------------------------------------------------------------------
bool retrySensorInit(const char* label, int maxAttempts,
                      std::function<bool()> init) {
  for (int attempt = 1; attempt <= maxAttempts; attempt++) {
    if (init()) {
      if (attempt > 1) {
        Serial.printf("[%s] init OK on attempt %d/%d\n", label, attempt,
                      maxAttempts);
      }
      return true;
    }
    if (attempt < maxAttempts) delay(50);
  }
  return false;
}

// ---------------------------------------------------------------------------
// Raw MPU6050/6500-register driver — replaces Adafruit_MPU6050 here.
// That library's own begin() reads the WHO_AM_I register (0x75) and
// rejects anything that doesn't read back exactly 0x68, the real
// MPU6050's chip id. A live readback on this specific "MPU6050" module
// found 0x70 instead — the MPU6500's id, not the MPU6050's. MPU6500 is
// a newer, pin- and register-compatible successor for the core
// accel/gyro registers used here (power management, range config, the
// 14-byte accel+temp+gyro burst read starting at 0x3B) — it's a common
// substitution in cheap breakout boards sold as "MPU6050" — so raw
// register access (same approach as a standalone bench sketch that
// worked fine talking to this exact module) reads it correctly; only
// Adafruit's specific identity check was ever the problem, not the
// chip, the wiring, or the bus.
// ---------------------------------------------------------------------------
#define MPU_I2C_ADDR 0x68
#define MPU_REG_PWR_MGMT_1 0x6B
#define MPU_REG_GYRO_CONFIG 0x1B
#define MPU_REG_ACCEL_CONFIG 0x1C
#define MPU_REG_ACCEL_XOUT_H 0x3B

// ±4g / ±500 deg/s — matches this project's previous Adafruit_MPU6050
// range config (MPU6050_RANGE_4_G / MPU6050_RANGE_500_DEG): wide enough
// to avoid clipping on a real fall impact (this project has measured
// post-impact spikes up to ~4g on the phone alone — see
// fall_inference.dart) while keeping better resolution than a wider
// range would. Sensitivity constants (LSB per unit) are the standard
// MPU6050/6500 datasheet values for these exact range settings — not
// something to guess if the range config below ever changes.
#define MPU_ACCEL_LSB_PER_G 8192.0f
#define MPU_GYRO_LSB_PER_DPS 65.5f
#define MPU_GRAVITY_MS2 9.80665f

bool mpuWriteReg(uint8_t reg, uint8_t value) {
  Wire1.beginTransmission(MPU_I2C_ADDR);
  Wire1.write(reg);
  Wire1.write(value);
  return Wire1.endTransmission() == 0;
}

// Wakes the sensor (it powers on in sleep mode) and sets the accel/gyro
// ranges above. Deliberately does NOT check WHO_AM_I — see this
// section's own comment for why that check is the wrong thing to do
// for this specific module.
bool mpuBegin() {
  uint8_t whoAmI = 0;
  Wire1.beginTransmission(MPU_I2C_ADDR);
  Wire1.write(0x75); // WHO_AM_I — read and logged for visibility only,
  Wire1.endTransmission(false); // never gates success/failure below.
  if (Wire1.requestFrom((uint8_t)MPU_I2C_ADDR, (uint8_t)1) == 1) {
    whoAmI = Wire1.read();
  }
  Serial.printf("[MPU6050] WHO_AM_I = 0x%02X (0x68 = genuine MPU6050, "
                "0x70 = MPU6500 in a MPU6050-labeled module — either is "
                "fine, this driver doesn't check it)\n",
                whoAmI);

  if (!mpuWriteReg(MPU_REG_PWR_MGMT_1, 0x00)) return false; // wake up
  delay(10);
  if (!mpuWriteReg(MPU_REG_ACCEL_CONFIG, 0x08)) return false; // ±4g
  if (!mpuWriteReg(MPU_REG_GYRO_CONFIG, 0x08)) return false; // ±500 dps
  return true;
}

// One burst read of the 14 contiguous accel+temp+gyro registers
// starting at ACCEL_XOUT_H, converted to the same physical units
// (m/s², rad/s) Adafruit_MPU6050/the training data use — a burst read
// keeps all 6 values from the same instant, rather than 3 separate
// transactions that could straddle a sample boundary. The 2 temperature
// bytes in the middle of the burst are read and discarded; this
// firmware's real body-temp reading comes from the DS18B20, not this
// chip's built-in (uncalibrated, die-temperature) sensor.
bool mpuReadMotion(float& ax, float& ay, float& az, float& gx, float& gy,
                    float& gz) {
  Wire1.beginTransmission(MPU_I2C_ADDR);
  Wire1.write(MPU_REG_ACCEL_XOUT_H);
  if (Wire1.endTransmission(false) != 0) return false;
  if (Wire1.requestFrom((uint8_t)MPU_I2C_ADDR, (uint8_t)14) != 14) return false;

  int16_t rawAx = (Wire1.read() << 8) | Wire1.read();
  int16_t rawAy = (Wire1.read() << 8) | Wire1.read();
  int16_t rawAz = (Wire1.read() << 8) | Wire1.read();
  Wire1.read();
  Wire1.read(); // discard temperature
  int16_t rawGx = (Wire1.read() << 8) | Wire1.read();
  int16_t rawGy = (Wire1.read() << 8) | Wire1.read();
  int16_t rawGz = (Wire1.read() << 8) | Wire1.read();

  ax = (rawAx / MPU_ACCEL_LSB_PER_G) * MPU_GRAVITY_MS2;
  ay = (rawAy / MPU_ACCEL_LSB_PER_G) * MPU_GRAVITY_MS2;
  az = (rawAz / MPU_ACCEL_LSB_PER_G) * MPU_GRAVITY_MS2;
  gx = (rawGx / MPU_GYRO_LSB_PER_DPS) * (PI / 180.0f);
  gy = (rawGy / MPU_GYRO_LSB_PER_DPS) * (PI / 180.0f);
  gz = (rawGz / MPU_GYRO_LSB_PER_DPS) * (PI / 180.0f);
  return true;
}

// ---------------------------------------------------------------------------
// Sensor setup
// ---------------------------------------------------------------------------
void setupSensors() {
  scanI2CBus(Wire, "main");
  scanI2CBus(Wire1, "MPU6050");

  bmeOk = bme.begin(BME280_I2C_ADDR, &Wire);
  Serial.printf("[BME280] init %s\n", bmeOk ? "OK" : "FAILED");

  mpuOk = retrySensorInit("MPU6050", 5, [] { return mpuBegin(); });
  Serial.printf("[MPU6050] init %s\n", mpuOk ? "OK" : "FAILED");

  maxOk = retrySensorInit("MAX30102", 5,
                          [] { return particleSensor.begin(Wire, I2C_SPEED_FAST); });
  if (maxOk) {
    // Same config as the bench-tuned v4 sketch: ~25 mA on Red and IR
    // (equal currents keep SpO2's ratio-of-ratios meaningful), 4-sample
    // averaging, Red+IR only, 400 Hz internal -> 100 Hz out
    // (PPG_SAMPLE_RATE), 411 us / 18-bit, 16384 nA full scale. If the
    // "[HR] ... SATURATED" debug line appears, lower Red separately with
    // particleSensor.setPulseAmplitudeRed().
    particleSensor.setup(0x7F, 4, 2, 400, 411, 16384);
    particleSensor.setPulseAmplitudeGreen(0);
  }
  Serial.printf("[MAX30102] init %s\n", maxOk ? "OK" : "FAILED");

  pinMode(ONE_WIRE_PIN, INPUT_PULLUP);
  ds18b20.begin();
  ds18b20.setWaitForConversion(false); // non-blocking — see readBodyTempC()
  ds18b20Ok = ds18b20.getDeviceCount() > 0;
  Serial.printf("[DS18B20] init %s\n", ds18b20Ok ? "OK" : "FAILED");

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
// HR / SpO2 — MAX30102 PPG processing (see the PPG_* constants above).
// ---------------------------------------------------------------------------
void ppgClearRates() {
  ppgRateCount = ppgRateSpot = ppgRejectCount = 0;
  ppgBpmAvg = 0;
}

void ppgClearSpo2() {
  ppgRCount = ppgRSpot = 0;
  ppgSpo2 = 0;
}

void ppgResetDetector() {
  ppgPrevSig = ppgPeakEnv = 0;
  ppgArmed = false;
  ppgSettledAnnounced = false;
  ppgLastBeatSample = 0;
  ppgLastGoodBeatSample = 0;
  ppgClearRates();
  ppgClearSpo2();
}

void ppgAddRate(float r) {
  ppgRates[ppgRateSpot] = r;
  ppgRateSpot = (ppgRateSpot + 1) % PPG_RATE_SIZE;
  if (ppgRateCount < PPG_RATE_SIZE) ppgRateCount++;
  float sum = 0;
  for (int i = 0; i < ppgRateCount; i++) sum += ppgRates[i];
  ppgBpmAvg = sum / ppgRateCount;
}

// Ratio of ratios over the beat that just ended -> SpO2. Uses Maxim's
// reference-design empirical curve — UNCALIBRATED for this board, so it's
// a relative risk signal, not a clinical reading.
void ppgUpdateSpo2() {
  float irPP = irCh.peakToPeak();
  float redPP = redCh.peakToPeak();
  if (irPP <= 0 || redPP <= 0 || irCh.dc <= 0 || redCh.dc <= 0) return;

  float R = (redPP / redCh.dc) / (irPP / irCh.dc);
  if (R < PPG_R_MIN || R > PPG_R_MAX) return;

  ppgRValues[ppgRSpot] = R;
  ppgRSpot = (ppgRSpot + 1) % PPG_RATE_SIZE;
  if (ppgRCount < PPG_RATE_SIZE) ppgRCount++;

  float sum = 0;
  for (int i = 0; i < ppgRCount; i++) sum += ppgRValues[i];
  float rAvg = sum / ppgRCount;

  ppgSpo2 = -45.060 * rAvg * rAvg + 30.354 * rAvg + 94.845;
  ppgSpo2 = constrain(ppgSpo2, 0.0f, 100.0f);
}

bool ppgSettling() { return fingerPresent && ppgSampleIndex < ppgSettleUntil; }
bool ppgSaturatedRecently() {
  return ppgEverSaturated &&
         ppgSampleIndex - ppgLastSaturatedSample < (uint32_t)PPG_SAMPLE_RATE;
}

// Invalidates the beat interval currently being timed, without touching the
// averages — used after dropped samples, where the next interval would
// otherwise span a gap of unknown shape.
void ppgBreakBeatTiming() {
  ppgLastBeatSample = 0;
  ppgArmed = false;
  irCh.newWindow();
  redCh.newWindow();
}

void ppgProcessSample(uint32_t red, uint32_t ir) {
  ppgSampleIndex++;

  // ---------- Contact detection ----------
  if (ir < PPG_FINGER_THRESHOLD) {
    if (fingerPresent) {
      fingerPresent = false;
      ppgResetDetector();
    }
    return;
  }
  if (!fingerPresent) {
    fingerPresent = true;
    ppgResetDetector();
    irCh.reset(ir);
    redCh.reset(red);
    ppgSettleUntil = ppgSampleIndex + (uint32_t)(PPG_SETTLE_SECONDS * PPG_SAMPLE_RATE);
  }

  if (ir > PPG_SATURATION_LEVEL || red > PPG_SATURATION_LEVEL) {
    ppgEverSaturated = true;
    ppgLastSaturatedSample = ppgSampleIndex;
  }

  bool settling = ppgSampleIndex < ppgSettleUntil;
  float alpha = settling ? PPG_DC_ALPHA_FAST : PPG_DC_ALPHA;

  // ---------- Filtering ----------
  float sig = irCh.update(ir, alpha); // IR drives beat detection
  redCh.update(red, alpha);

  if (settling) {
    ppgPrevSig = sig;
    return;
  }
  if (!ppgSettledAnnounced) {
    ppgSettledAnnounced = true;
    ppgLastGoodBeatSample = ppgSampleIndex; // start the staleness clock here
    irCh.newWindow();
    redCh.newWindow();
  }

  irCh.track();
  redCh.track();

  // ---------- Adaptive threshold ----------
  ppgPeakEnv *= PPG_ENV_DECAY;
  if (sig > ppgPeakEnv) ppgPeakEnv = sig;
  float threshold = max(ppgPeakEnv * 0.5f, PPG_MIN_AMPLITUDE);

  if (sig < 0) ppgArmed = true;

  if (ppgArmed && ppgPrevSig < threshold && sig >= threshold) {
    uint32_t since = ppgSampleIndex - ppgLastBeatSample;
    if (ppgLastBeatSample == 0 || since >= PPG_REFRACTORY_SAMPLES) {
      ppgArmed = false;
      bool beat = false;

      if (ppgLastBeatSample != 0) {
        float instBpm = 60.0 * PPG_SAMPLE_RATE / since;
        if (instBpm >= PPG_MIN_BPM && instBpm <= PPG_MAX_BPM) {
          bool outlier = ppgRateCount >= 3 &&
                         fabs(instBpm - ppgBpmAvg) > PPG_OUTLIER_FRACTION * ppgBpmAvg;
          if (!outlier) {
            ppgRejectCount = 0;
            ppgAddRate(instBpm);
            beat = true;
          } else if (++ppgRejectCount >= PPG_MAX_REJECTS) {
            // Several "outliers" in a row = the heart rate really changed.
            ppgClearRates();
            ppgAddRate(instBpm);
            beat = true;
          }
        }
      }

      // One full beat window just ended: use it for SpO2 if the beat was good.
      if (beat) {
        ppgUpdateSpo2();
        ppgLastGoodBeatSample = ppgSampleIndex;
      }
      irCh.newWindow();
      redCh.newWindow();
      ppgLastBeatSample = ppgSampleIndex;
    }
  }
  ppgPrevSig = sig;

  // ---------- Staleness (watch-specific, see PPG_STALE_SECONDS) ----------
  if (ppgSampleIndex - ppgLastGoodBeatSample >
      (uint32_t)(PPG_STALE_SECONDS * PPG_SAMPLE_RATE)) {
    ppgClearRates();
    ppgClearSpo2();
    ppgLastGoodBeatSample = ppgSampleIndex;
  }
}

// Reads the MAX30102's FIFO directly instead of via MAX30105::check() —
// the SparkFun library buffers only 4 samples (STORAGE_SIZE), i.e. 40 ms at
// 100 Hz, and silently overwrites older ones, while this loop also does
// OLED/DS18B20/BLE work that can take longer than that. The chip's own FIFO
// holds 32 samples (320 ms), and its overflow counter says exactly how many
// were lost if even that runs out, so beat timing can be protected.
const uint8_t MAX3010X_ADDR = 0x57;
const uint8_t REG_FIFO_WR_PTR = 0x04;
const uint8_t REG_FIFO_OVF = 0x05;
const uint8_t REG_FIFO_RD_PTR = 0x06;
const uint8_t REG_FIFO_DATA = 0x07;
const int PPG_BYTES_PER_SAMPLE = 6; // Red (3 bytes) then IR (3 bytes), ledMode 2

bool max3010xReadReg(uint8_t reg, uint8_t& out) {
  Wire.beginTransmission(MAX3010X_ADDR);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(MAX3010X_ADDR, (uint8_t)1) != 1) return false;
  out = Wire.read();
  return true;
}

// One 3-byte, MSB-first FIFO value. Separate statements on purpose: the
// order operands of `|` are evaluated in is unspecified in C++, so three
// Wire.read() calls in one expression could assemble bytes out of order.
uint32_t readFifo18Bit() {
  uint32_t v = (uint32_t)Wire.read() << 16;
  v |= (uint32_t)Wire.read() << 8;
  v |= (uint32_t)Wire.read();
  return v & 0x3FFFF;
}

void pollHeartRateSensor() {
  if (!maxOk) return;

  uint8_t wr, ovf, rd;
  if (!max3010xReadReg(REG_FIFO_WR_PTR, wr) || !max3010xReadReg(REG_FIFO_OVF, ovf) ||
      !max3010xReadReg(REG_FIFO_RD_PTR, rd)) {
    return;
  }
  int count = (wr - rd) & 0x1F;
  if (ovf > 0) {
    // FIFO filled up and rolled over: all 32 slots hold samples (WR == RD
    // reads as 0 in that case) and `ovf` newer-than-read ones were lost.
    if (count == 0) count = 32;
    ppgLostSamples += ovf;
    ppgSampleIndex += ovf; // keep sample-clock time honest across the gap
    ppgBreakBeatTiming();
  }

  while (count > 0) {
    int chunk = min(count, 21); // 21 * 6 = 126 bytes, under the 128-byte Wire buffer
    Wire.beginTransmission(MAX3010X_ADDR);
    Wire.write(REG_FIFO_DATA);
    if (Wire.endTransmission(false) != 0) return;
    int bytes = chunk * PPG_BYTES_PER_SAMPLE;
    if (Wire.requestFrom(MAX3010X_ADDR, (uint8_t)bytes) != bytes) return;
    for (int i = 0; i < chunk; i++) {
      uint32_t red = readFifo18Bit();
      uint32_t ir = readFifo18Bit();
      ppgProcessSample(red, ir);
    }
    count -= chunk;
  }

  hrReady = fingerPresent && ppgRateCount >= PPG_READY_BEATS;
  spo2Ready = fingerPresent && ppgRCount >= PPG_READY_BEATS;
  currentBpm = hrReady ? ppgBpmAvg : 0;
  currentSpo2 = spo2Ready ? ppgSpo2 : 0;

  static uint32_t lastDebugMs = 0;
  uint32_t nowDbg = millis();
  if (nowDbg - lastDebugMs >= 1000) {
    lastDebugMs = nowDbg;
    Serial.printf("[HR] IRdc=%.0f Reddc=%.0f finger=%s %s beats=%d/%d BPM=%.1f SpO2=%.1f%s lost=%lu\n",
                  irCh.dc, redCh.dc, fingerPresent ? "yes" : "no",
                  ppgSettling() ? "settling" : (hrReady ? "ready" : "measuring"),
                  ppgRateCount, PPG_READY_BEATS, currentBpm, currentSpo2,
                  ppgSaturatedRecently() ? " SATURATED(lower LED current)" : "",
                  (unsigned long)ppgLostSamples);
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
  // Body temp is gated on the MAX30102's finger-presence detection, same
  // as HR/SpO2 — it's the only signal this firmware has for "is the watch
  // actually on a wrist," and a DS18B20 sitting on a table would otherwise
  // report a plausible-looking but meaningless "body" temperature.
  // ignoreBodyTempContactCheck (see WatchSettingsPacket) is a
  // developer/demo override for when that sensor is unavailable/broken;
  // the app disables the low/high-temp WARNING outright while it's on,
  // rather than trusting an unverified reading — see dashboard_screen.dart.
  bool bodyTempContactOk = fingerPresent || ignoreBodyTempContactCheck;
  lastBodyTempC = (ds18b20Ok && bodyTempContactOk) ? readBodyTempC() : 0;
  pkt.bodyTempC = lastBodyTempC;
  pkt.fingerPresent = fingerPresent ? 1 : 0;
  pkt.ppgFlags = (hrReady ? PPG_FLAG_HR_READY : 0) |
                 (spo2Ready ? PPG_FLAG_SPO2_READY : 0) |
                 (ppgSettling() ? PPG_FLAG_SETTLING : 0) |
                 (ppgSaturatedRecently() ? PPG_FLAG_SATURATED : 0);
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
  // Read into plain locals, not directly into the packed MotionPacket's
  // fields — GCC won't bind a reference to a field of a
  // __attribute__((packed)) struct (a potentially-unaligned address),
  // so mpuReadMotion() can't write straight into pkt.ax etc.
  float ax, ay, az, gx, gy, gz;
  // A failed burst read (a dropped/NACKed I2C transaction) skips this
  // notify entirely rather than sending stale/zeroed values as if they
  // were real — same "don't report a fake reading" stance as every
  // other sensor in this firmware.
  if (!mpuReadMotion(ax, ay, az, gx, gy, gz)) return;

  MotionPacket pkt;
  pkt.tMs = millis();
  pkt.ax = ax;
  pkt.ay = ay;
  pkt.az = az;
  pkt.gx = gx;
  pkt.gy = gy;
  pkt.gz = gz;
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

  // HR/SpO2 need contact, ~2 s of settling, then PPG_READY_BEATS good
  // beats before they mean anything — show which stage it's in rather than
  // a bare "--" or a half-formed number. Hold still while it measures.
  if (!fingerPresent) {
    display.println("HR: -- (no finger)");
    display.println("SpO2: --");
  } else if (ppgSettling()) {
    display.println("HR: settling...");
    display.println("SpO2: hold still");
  } else {
    if (hrReady) {
      display.printf("HR: %.0f bpm\n", currentBpm);
    } else {
      display.printf("HR: measuring %d/%d\n", ppgRateCount, PPG_READY_BEATS);
    }
    if (spo2Ready) {
      display.printf("SpO2: %.0f %%\n", currentSpo2);
    } else {
      display.println("SpO2: ... %");
    }
  }
  if (ppgSaturatedRecently()) display.println("PPG: too bright");
  // Body temp has its own contact gate (see notifyVitals()) — same
  // fingerPresent/ignoreBodyTempContactCheck logic, own line, own message,
  // not nested under the HR/SpO2 finger check above.
  if (!ds18b20Ok) {
    display.println("Body: sensor unavailable");
  } else if (!fingerPresent && !ignoreBodyTempContactCheck) {
    display.println("Body: -- (no contact)");
  } else {
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
  // Mode (400kHz) because it's suspected of causing sensor init to fail
  // on this breadboard build: 3 I2C devices sharing one bus over jumper
  // wires has marginal signal integrity at 400kHz. Revisit if/when this
  // moves to a proper PCB with short traces and correctly-sized pull-ups.
  Wire1.begin(MPU_SDA, MPU_SCL); // MPU6050's own isolated bus — see its define above.
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
