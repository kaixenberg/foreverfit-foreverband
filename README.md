# Personal Health Companion — SIH '26, Problem ID 26181

A privacy-preserving, offline-first personal health companion: an ESP32-S3
wearable streams sensor data over BLE to a phone, which does all the
processing on-device — no cloud dependency required for core functionality.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design, BLE
protocol spec, and the roadmap for ML-based anomaly detection, disaster
heuristics, offline maps, and SOS.

## Hardware

- ESP32-S3
- MAX30101 — heart rate & SpO2
- MAX30205 — body temperature (not working on this build; firmware uses a
  stubbed value, see `readBodyTempC()` in `main.cpp`)
- MPU6050 — accelerometer & gyroscope
- BME280 — ambient temperature, humidity, pressure
- 0.96" SSD1306 OLED display

## Repo layout

```
firmware/health_companion/   PlatformIO project — the wearable firmware
app/health_companion/        Flutter app — BLE client, dashboard, storage
ARCHITECTURE.md              Full system design + protocol spec + roadmap
```

## Firmware setup

Requires [PlatformIO](https://platformio.org/) (CLI or the VS Code
extension).

1. Open `firmware/health_companion/src/main.cpp` and check the wiring
   config block near the top (`I2C_SDA`, `I2C_SCL`, `OLED_I2C_ADDR`,
   `BME280_I2C_ADDR`) matches your actual wiring.
2. Build and flash:

   ```bash
   cd firmware/health_companion
   pio run -t upload
   pio device monitor
   ```

3. The serial monitor should show each sensor's init status and
   `[BLE] advertising started`. The OLED should show the watchface with a
   `BLE: advertising` / `BLE: connected` line.

## App setup

Requires the [Flutter SDK](https://flutter.dev/). This repo ships the
`pubspec.yaml` and all `lib/` sources; run `flutter create .` once to
generate the missing native Android/iOS project scaffolding (it will not
overwrite the existing `pubspec.yaml` or `lib/` files):

```bash
cd app/health_companion
flutter create .
flutter pub get
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
