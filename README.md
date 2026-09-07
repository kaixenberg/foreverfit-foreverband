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

The app opens straight into a single Dashboard — no bottom nav/tabs — that
works with or without the wearable connected — see ARCHITECTURE.md's "App
navigation" section. It discovers/connects the `HealthCompanion` wearable
via a "Connect" button/banner and shows heart rate, SpO2, body
temperature, and environmental readings (falling back to online weather
when the wearable isn't connected) with a recent heart-rate trend chart;
readings persist locally via Hive. It also reads the phone's own
accelerometer/gyroscope and runs an on-device fall-detection CNN — see
[ARCHITECTURE.md](ARCHITECTURE.md) and [ml/README.md](ml/README.md) for
how that model was trained. Currently phone-only (the wearable's MPU6050
is dead on this build — see Hardware above); the original wrist+phone
fusion design resumes once that's replaced. A detected fall latches an
alert banner open until dismissed or a 10s dummy emergency-call
escalation fires. A "Body & activity" section tracks weight, height, BMI,
body fat, hydration, and phone step count locally (no Health Connect). A
dashboard nav card leads to the GPS-centered, India-focused disaster-risk
map (earthquake/cyclone/flood/rain) that works fully offline (cached
tiles + a static state-level hazard baseline) and prefers live data
(Open-Meteo, USGS) when online.

## Status

- [x] Sensors wired and bench-tested (HR/SpO2, env, OLED watchface); MPU6050
      confirmed dead via I2C scan — motion now comes from the phone only
- [x] Firmware: BLE streaming of vitals/environment (motion channel idle
      until the wearable's IMU is replaced)
- [x] App: single-dashboard navigation (no tabs) — Map, Health Log, and
      Settings are all pushed routes reached from the Dashboard, all
      reachable without a wearable; BLE connect + live dashboard + local
      history confirmed working end-to-end on a physical Android phone
- [x] On-device fall-detection CNN (currently phone-only, 94% recall on
      held-out subjects; wrist+phone fusion on hold pending IMU repair —
      see `ml/`), with a latched alert + 10s countdown to a dummy
      emergency-call escalation — real SMS/call wiring not yet built
- [x] Manual SOS button (Dashboard) — raises the same alert/countdown/
      dummy-call flow as an auto-detected fall, distinguished in the
      banner text; real SMS/call wiring is the same open item as above
- [x] Disaster-risk map: GPS + India state-level hazard baseline + live
      Open-Meteo/USGS data with offline fallback — see ARCHITECTURE.md
- [x] Full-screen imminent-disaster warning with per-hazard safety
      guidance (e.g. "get under a table" for earthquakes) and a siren
      that plays through Android's alarm stream at max volume even when
      the phone is silenced — stricter trigger than the Map banner, plus
      a manual preview in Settings since real conditions rarely cross it
      live — see ARCHITECTURE.md
- [x] Activity-conditioned vitals anomaly detection: on-device 3-class
      CNN (still/walking/running, 99.9% held-out accuracy — see `ml/`)
      gates the Dashboard's HR warning threshold by what the user is
      currently doing, fills the "Activity" card. **Known gap**: live
      testing found "running" rarely gets picked on-device despite the
      held-out metrics above — two candidate causes (dataset's jogging
      trials are thinner than other classes; possible sensor-rate
      mismatch between training assumption and real device delivery) are
      documented with a diagnostic log line in `ml/README.md`, not yet
      confirmed
- [x] Graceful degradation UX: Dashboard's ambient temp/humidity/pressure
      fall back wearable → online weather → "--" instead of only ever
      showing wearable-or-nothing; Map shows an "Enable location" prompt
      instead of erroring when location is off, and falls back through
      last-known/cached position rather than failing immediately;
      Bluetooth-off now shows a "Turn on Bluetooth" button instead of a
      raw error — see ARCHITECTURE.md
- [x] Personalized (per-user) baseline learning: rolling 7-day mean/std
      of resting HR from local history, flags >2 personal std-devs from
      *this user's own* baseline, fills the "Baseline" card
- [x] Composite wellness score: transparent formula (not a trained
      model) combining HR/SpO2/body-temp/heat-index into the "Wellness"
      card; tap it for a detail screen explaining why, signal by signal
      (`WellnessDetailScreen`)
- [x] Warm visual theme (`lib/theme/app_theme.dart`) — rounded cards,
      circular icon badges, colored accent strips, pill buttons —
      applied app-wide; one idea (score + reasoning screen shape) drawn
      from a reviewed reference app, reimplemented from scratch in Dart,
      no code copied (see ARCHITECTURE.md)
- [x] Body & activity tracking, local storage (no Health Connect): weight,
      height, BMI (computed), body fat %, and hydration (with one-tap
      quick-add) log to Hive via `MetricsStore`; phone step count via the
      hardware step counter (`pedometer`), daily-reset logic handled
      locally, with a growing daily-history archive — see ARCHITECTURE.md
- [x] Per-metric history: tapping a Body & activity card opens a shared
      chart+stats+period-selector screen (7 days/30 days/all time) with
      average/min/max/change — one generic screen reused for all five
      metrics, not five bespoke ones — see ARCHITECTURE.md
- [x] Dashboard performance pass: `context.select` scoped rebuilds
      instead of one `context.watch` per provider, plus isolating the
      Steps card into its own widget — fixes visible lag found in live
      device testing, caused by the whole dashboard rebuilding on every
      fall-probability tick, activity-confidence tick, and (worst) every
      single step — see ARCHITECTURE.md
- [x] Heat-index formula (`lib/utils/heat_index.dart`) — the on-device
      heat-stress CNN originally planned was dropped after its dataset
      (WESAD) turned out to be a dead end on direct verification (dead
      links, and signals that don't match this app's sensors); a
      transparent NOAA/Rothfusz formula was built instead — see
      `ml/README.md`
- [x] UI stubs for everything below (Map's Air Quality row, Health Log's
      remaining tracking tiles, Settings' emergency contact form) —
      visible, not yet wired to real data/logic
- [ ] Air quality integration
- [ ] Sleep tracking
- [ ] Trend/daily-summary views
- [ ] Wearable-sensor disaster heuristics (heat-index formula now exists
      — this item is wiring it to the wearable's own BME280 instead of
      phone GPS, plus BME280 pressure drop-rate) once the wearable's IMU
      is replaced
- [ ] Remaining health tracking (blood pressure/glucose/insulin/meds/
      sleep/Medical ID) — UI stub only, reachable via the Dashboard's
      "More health tracking" card. Weight/height/body fat/hydration/steps
      are implemented, see above
- [ ] Real SOS (SMS/call + emergency contact storage) — countdown/
      escalation UX and manual trigger are wired end-to-end, but still
      end in a dummy logged action, not a real call/SMS
