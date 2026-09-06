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
- MPU6050 — accelerometer & gyroscope
- BME280 — ambient temperature, humidity, pressure
- 0.96" SSD1306 OLED display
- I²C bus shared by all four sensors: SDA → GPIO 8, SCL → GPIO 9

## Repo layout

```
firmware/health_companion/   Arduino IDE sketch — the wearable firmware
app/health_companion/        Flutter app — BLE client, dashboard, storage
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

**Before running**, `flutter create .` generates a default
`android/app/src/main/AndroidManifest.xml` with no BLE permissions — add
these inside the `<manifest>` tag (above `<application>`), or scanning will
silently fail or the permission prompts in-app will do nothing:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />
```

Also bump `minSdkVersion` to at least `21` in `android/app/build.gradle`
(`flutter_blue_plus` requires it; the default template may set a lower
value).

Then:

```bash
flutter run
```

Run on a **physical Android phone**, not an emulator — BLE central support
on emulators is unreliable. Grant the Bluetooth and location permissions
when prompted (Android requires location permission for BLE scanning).

The app should discover the `HealthCompanion` wearable, connect, and show a
live dashboard of heart rate, SpO2, body temperature, and environmental
readings, with a recent heart-rate trend chart. Readings are stored locally
via Hive and persist across app restarts.

## Status

- [x] Sensors wired and bench-tested; dummy OLED watchface working
- [x] Firmware: BLE streaming of vitals/environment/motion
- [x] App: BLE connect + live dashboard + local history
- [ ] On-device CNNs (fall detection, vitals/heat-stress anomaly)
- [ ] Disaster heuristics (heat-index, cyclone pressure-drop)
- [ ] Offline maps with bundled hazard layer
- [ ] SOS to emergency contacts
