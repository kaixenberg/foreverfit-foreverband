# Personal Health Companion — SIH '26, Problem ID 26181

A privacy-preserving, offline-first personal health companion: an ESP32-S3
wearable streams sensor data over BLE to a phone, which does all the
processing on-device — no cloud dependency required for core functionality.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design, BLE
protocol spec, and the roadmap for ML-based anomaly detection, disaster
heuristics, offline maps, and SOS.

## Hardware

- ESP32-S3 N16R8 dev board (16MB flash, 8MB octal PSRAM)
- MAX30101 — heart rate & SpO2
- MAX30205 — body temperature (not working on this build; firmware uses a
  stubbed value, see `readBodyTempC()` in `health_companion.ino`)
- MPU6050 — accelerometer & gyroscope (**dead on this breadboard build** —
  confirmed via I2C scan; app's fall detector currently runs on phone-only
  motion data instead, see `ARCHITECTURE.md`)
- BME280 — ambient temperature, humidity, pressure
- 0.96" SSD1306 OLED display
- I²C bus shared by all four sensors: SDA → GPIO 8, SCL → GPIO 9

## Repo layout

```
firmware/health_companion/   Arduino IDE sketch — the wearable firmware
app/health_companion/        Flutter app — BLE client, dashboard, map, storage
ml/                          Fall-detection model training pipeline (see ml/README.md)
ARCHITECTURE.md              Full system design + protocol spec + roadmap
```

## Firmware setup

Built with **Arduino IDE** + **ESP32 Arduino Core 3.3.11**.

1. **Board setup** (Tools menu in Arduino IDE):
   - Board: `ESP32S3 Dev Module`
   - USB CDC On Boot: `Enabled` (required for Serial over the native
     USB-Serial/JTAG port — without this, `/dev/ttyACM0` won't show output)
   - Flash Size: `16MB`
   - PSRAM: `OPI PSRAM`
   - Port: `/dev/ttyACM0`
   - Upload Speed: `921600` (drop to `115200` if uploads fail)
2. **Install libraries** via Library Manager (Sketch → Include Library →
   Manage Libraries), search and install:
   - `NimBLE-Arduino` (h2zero) — install the latest (2.x); the sketch targets
     the current 2.x callback API.
   - `Adafruit BME280 Library`
   - `Adafruit Unified Sensor`
   - `Adafruit MPU6050`
   - `Adafruit SSD1306`
   - `Adafruit GFX Library`
   - `SparkFun MAX3010x Pulse and Proximity Sensor Library`
3. Open `firmware/health_companion/health_companion.ino`. The wiring config
   block near the top (`I2C_SDA`, `I2C_SCL`, `OLED_I2C_ADDR`,
   `BME280_I2C_ADDR`) already matches the wiring above — only change it if
   your wiring differs.
4. Upload, then open the Serial Monitor at **115200 baud**. You should see
   each sensor's init status (`OK`/`FAILED`) and `[BLE] advertising
   started`. The OLED should show the watchface with a `BLE: advertising` /
   `BLE: connected` line.

## App setup

Requires the [Flutter SDK](https://flutter.dev/). This repo ships the
`pubspec.yaml` and all `lib/` sources; run `flutter create .` once to
generate the missing native Android/iOS project scaffolding (it will not
overwrite the existing `pubspec.yaml` or `lib/` files):

```bash
cd app/health_companion
flutter create .
flutter pub get
```

The generated `android/AndroidManifest.xml` is committed to this repo with
the BLE permissions (`BLUETOOTH_SCAN`, `BLUETOOTH_CONNECT`,
`ACCESS_FINE_LOCATION`) already added — `flutter create .` won't overwrite
it since the file already exists. `minSdkVersion` uses the Flutter tool's
own default (`flutter.minSdkVersion` in `build.gradle.kts`), which is well
above the `21` `flutter_blue_plus` requires on any current Flutter SDK, so
no manual bump is needed.

Then:

```bash
flutter run
```

Run on a **physical Android phone**, not an emulator — BLE central support
on emulators is unreliable. Grant the Bluetooth and location permissions
when prompted (Android requires location permission for BLE scanning).

The app opens into a bottom-nav shell (Dashboard / Map / Health Log) that
works with or without the wearable connected — see ARCHITECTURE.md's "App
navigation" section. The Dashboard tab discovers/connects the
`HealthCompanion` wearable via a "Connect" button and shows heart rate,
SpO2, body temperature, and environmental readings with a recent
heart-rate trend chart when connected (placeholders otherwise); readings
persist locally via Hive. It also reads the phone's own
accelerometer/gyroscope and runs an on-device fall-detection CNN — see
[ARCHITECTURE.md](ARCHITECTURE.md) and [ml/README.md](ml/README.md) for
how that model was trained. Currently phone-only (the wearable's MPU6050
is dead on this build — see Hardware above); the original wrist+phone
fusion design resumes once that's replaced. A detected fall latches an
alert banner open until dismissed or a 10s dummy emergency-call
escalation fires. The Map tab shows a GPS-centered, India-focused
disaster-risk view (earthquake/cyclone/flood/rain) that works fully
offline (cached tiles + a static state-level hazard baseline) and prefers
live data (Open-Meteo, USGS) when online.

## Status

- [x] Sensors wired and bench-tested (HR/SpO2, env, OLED watchface); MPU6050
      confirmed dead via I2C scan — motion now comes from the phone only
- [x] Firmware: BLE streaming of vitals/environment (motion channel idle
      until the wearable's IMU is replaced)
- [x] App: bottom-nav shell (Dashboard/Map/Health Log), all reachable
      without a wearable; BLE connect + live dashboard + local history
      confirmed working end-to-end on a physical Android phone
- [x] On-device fall-detection CNN (currently phone-only, 94% recall on
      held-out subjects; wrist+phone fusion on hold pending IMU repair —
      see `ml/`), with a latched alert + 10s countdown to a dummy
      emergency-call escalation — real SMS/call wiring not yet built
- [x] Disaster-risk map: GPS + India state-level hazard baseline + live
      Open-Meteo/USGS data with offline fallback — see ARCHITECTURE.md
- [ ] On-device vitals/heat-stress anomaly CNN
- [ ] Wearable-sensor disaster heuristics (BME280 heat-index, pressure
      drop-rate) once the wearable's IMU is replaced
- [ ] Health tracking (weight/height/meds/insulin) — placeholder tab only
- [ ] Real SOS (SMS/call) — countdown/escalation UX built, dummy action only
