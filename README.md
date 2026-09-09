# ForeverFit — SIH '26, Problem ID 26181

A privacy-preserving, offline-first personal health companion (working
name "Personal Health Companion" during early development, renamed to
ForeverFit): an ESP32-S3 wearable ("ForeverBand") streams sensor data
over BLE to a phone, which does all the processing on-device — no cloud
dependency required for core functionality.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design, BLE
protocol spec, and the roadmap for ML-based anomaly detection, disaster
heuristics, offline maps, and SOS.

## Hardware

- ESP32-S3 N16R8 dev board (16MB flash, 8MB octal PSRAM)
- MAX30101 — heart rate & SpO2 (real finger-presence detection; the BPM/
  SpO2 numbers themselves are spoofed to a healthy resting range by
  default for demo reliability — `USE_DUMMY_HR_SPO2` in
  `health_companion.ino`, flip to 0 for the real bench-tested algorithm)
- MAX30205 — body temperature (not working on this build; firmware uses a
  stubbed value, see `readBodyTempC()` in `health_companion.ino` — only
  reported while a finger is present, same as HR/SpO2)
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
alert banner open until dismissed or a 10s countdown escalates into the
AI-assisted emergency-call workflow (emergency-services call → emergency
contact, with retries → SMS fallback). A "Body & activity" section tracks weight, height, BMI,
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
- [x] App: single-dashboard navigation (no tabs) — Map, Settings, and
      every metric's own history/management screen are pushed routes
      reached from the Dashboard, all reachable without a wearable; BLE
      connect + live dashboard + local history confirmed working
      end-to-end on a physical Android phone
- [x] On-device fall-detection CNN (currently phone-only, 92% precision/
      92% recall on held-out subjects at a threshold dialed down from
      the model's 0.5 default to 0.8 — see `ml/README.md`'s "Threshold
      tuning"; wrist+phone fusion on hold pending IMU repair — see
      `ml/`), with a latched alert + 10s countdown that escalates into
      the real AI-assisted emergency-call workflow (see below)
- [x] Manual SOS button (Dashboard) — raises the same alert/countdown/
      emergency-call flow as an auto-detected fall, distinguished in the
      banner text
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
- [x] Body & activity tracking, local storage (no Health Connect): steps,
      heart rate, weight, height, BMI (computed, now with its own chart),
      body fat % (now derived from BMI + age + sex via the Deurenberg
      formula, not manually logged — see ARCHITECTURE.md), and hydration
      (with one-tap quick-add) in a swipeable, paged 2x3 card grid with a
      dot-page indicator; weight/height/hydration log to Hive via
      `MetricsStore`, steps via the hardware step counter (`pedometer`)
      with a growing daily-history archive — see ARCHITECTURE.md
- [x] Per-metric history: tapping any Body & activity or top-vitals-grid
      card opens a shared chart+stats+period-selector screen — preset
      chips (7/30/90 days/all time) plus a custom date-range picker, an
      avg/range/change summary, an interactive `fl_chart` graph (grid,
      axis labels, shaded area, dashed linear trend line, tap-for-value
      tooltips) colored to match the card's own accent, and an
      average/total-entries/min/max statistics grid — one generic screen
      reused for every metric. Replaces the old always-on-screen "Heart
      rate — recent" sparkline, which was the one metric getting
      special-cased dashboard space — see ARCHITECTURE.md
- [x] SpO2 and Body temp are now tappable too (they were the only two
      top-vitals-grid cards with no history view); Heart rate's card was
      removed from Body & activity since it's no longer a genuine second
      entry point, just a duplicate of the top vitals grid's — see
      ARCHITECTURE.md
- [x] Edit/delete for every manually-logged metric (weight, height,
      hydration, blood pressure, blood glucose, insulin, sleep): each
      history screen now shows a per-entry list below the chart with
      edit/delete actions, reusing the same log dialogs (pre-filled) for
      editing rather than a separate edit UI — see ARCHITECTURE.md
- [x] Dashboard performance pass: `context.select` scoped rebuilds
      instead of one `context.watch` per provider, plus isolating the
      Steps card into its own widget — fixes visible lag found in live
      device testing, caused by the whole dashboard rebuilding on every
      fall-probability tick, activity-confidence tick, and (worst) every
      single step — see ARCHITECTURE.md
- [x] Health log — every item that used to be a stub is real now: blood
      pressure (dual-line systolic/diastolic chart), blood glucose,
      insulin (dose + type), sleep (all four using the same
      MetricHistoryScreen chart), Medications (a list manager with
      mark-dose-taken and its own doses-per-day adherence chart), and
      Medical ID (a saved blood-type/allergies/conditions profile — no
      chart, since there's no such thing as an "average blood type").
      12 Body & activity cards total now, across 2 swipe pages.
      `HealthLogScreen` and its Settings entry are both gone — nothing
      left for an intermediate stub list to point to — see
      ARCHITECTURE.md
- [x] Heat-index formula (`lib/utils/heat_index.dart`) — the on-device
      heat-stress CNN originally planned was dropped after its dataset
      (WESAD) turned out to be a dead end on direct verification (dead
      links, and signals that don't match this app's sensors); a
      transparent NOAA/Rothfusz formula was built instead — see
      `ml/README.md`
- [x] Settings' emergency contact form (now real and wired — see the
      AI-assisted emergency call and onboarding/Settings items below), with
      an optional "Pick from contacts" button (address-book search,
      read-only, gated behind the same permission system as everything
      else the app requests) instead of typing the name/number by hand —
      see ARCHITECTURE.md
- [x] Air quality: US AQI + PM2.5/PM10 from Open-Meteo's air-quality API
      (free, no key, verified live) on the Map screen, live-or-cached
      only (no static baseline — AQI swings too fast hour to hour for a
      hardcoded per-state table to be honest); AQI >150 now also
      triggers the Map's warning banner — see ARCHITECTURE.md
- [x] AI-based suggestions/warnings + notifications: rule-based insight
      engine (`lib/domain/insight_engine.dart`) covering vitals anomalies,
      map/disaster events (AQI, flood, cyclone, nearby quake), and
      tracking reminders (hydration, medication); shown on the Dashboard
      and pushed as local notifications (`flutter_local_notifications`,
      cooldown per condition so a persisting warning doesn't spam) — see
      ARCHITECTURE.md
- [x] AI-assisted medical emergency call: on fall/manual-SOS, builds a
      local non-diagnostic summary from recorded vitals/history, opens
      the device's emergency number (`ACTION_DIAL` — Android reserves
      silent auto-dial of emergency numbers even from the default
      dialer), speaks the summary via on-device TTS once the call is
      live, then calls the saved emergency contact directly (up to 5
      attempts, "answered" inferred from off-hook persisting past a
      6s grace period — the platform gives no precise signal), falling
      back to SMS if never answered. Hand-rolled native Kotlin telephony
      channel (no third-party call/SMS plugin), explicit state machine
      (`EmergencyWorkflowService`), 13 passing unit tests against a fake
      telephony backend (the spec's scenarios plus 3 cancellation
      regression tests — cancel used to be able to get stuck mid-wait
      or mid-TTS-announcement) — mock mode on by default (real calls/SMS
      need an explicit confirmed opt-out in Settings) — see
      ARCHITECTURE.md for the three Android platform ceilings this
      works around and what's still deferred (auto-resume after a
      process kill; full 12-scenario instrumentation test)
- [x] Onboarding (permissions + profile/medical info on first launch) and
      a categorized Settings screen (~10 sections: Profile & Medical,
      Units, Appearance, Data export & import, Wearable, Sensor
      precedence, Warning choices, Medical emergency, Permissions,
      Background permission, Developer/demo) — see ARCHITECTURE.md for
      what's deliberately simplified (unencrypted/manual-only backup, no
      Material You, single-case sensor precedence)
- [x] Loading screen on every launch after the first: re-checks/
      re-requests any permission that's no longer granted (e.g. revoked
      in system Settings), showing the app's actual launcher icon — read
      live from the OS, not a bundled duplicate, so changing the app icon
      changes the loading screen automatically — see ARCHITECTURE.md
- [x] Background fall detection + full-screen escalation: a foreground
      service (`flutter_foreground_task`) keeps the same TFLite model
      running even while the app is backgrounded/screen off (confirmed
      Android hard-stops sensor delivery to backgrounded apps otherwise —
      there's no way around a foreground service for this); a detected
      fall shows a high-priority actionable notification (vibrates, plays
      an alarm through the alarm audio stream, "I'm OK" action) with a
      10s window, escalating to waking the screen and bringing the app
      forward — over the lock screen for that one launch only, never as
      a standing setting — to run the same emergency-call workflow if
      unaddressed. Disaster warnings escalate the same way from a
      periodic background risk check. A Settings → Developer/demo button
      previews the lock-screen escalation path (10s delay, then the same
      wake+launch) without ever touching the real fall-detection flow or
      placing a real call. Uses a real Activity launch, not
      `SYSTEM_ALERT_WINDOW`/"draw over other apps" — see ARCHITECTURE.md
      for why, and for the documented limitations (the mandatory
      persistent monitoring notification, a small unavoidable duplication
      between the foreground/background detectors, and the Hive
      multi-isolate coordination the background disaster check needs)
- [x] BMI now has its own history chart (previously the only Body &
      activity card without one); body fat is computed from BMI + age +
      sex (Deurenberg formula) instead of manually logged — see
      ARCHITECTURE.md
- [x] Wearable-sensor disaster heuristics: the full-screen imminent
      warning now includes a live "storm approaching" signal from a rapid
      barometric pressure fall (≥3 hPa in 3h, a real marine/aviation
      early-warning threshold), fed by the wearable's BME280 in
      conjunction with online weather data (same precedence/fallback
      setting as the Dashboard's ambient cards) — replacing the previous
      "high rain forecast in a flood-prone state" trigger, which was a
      coarse statistical approximation rather than a live detection, and
      which now stays at the low-key Map banner tier instead. See
      ARCHITECTURE.md for the full reasoning and the known altitude-
      sensitivity limitation
- [x] Rebranded to **ForeverFit** (app) / **ForeverBand** (wearable) —
      user-facing branding only, not the internal Dart package name.
      New hand-drawn logo (generated via SVG + `flutter_launcher_icons`,
      same warm palette as the rest of the app) now the real launcher
      icon everywhere, including the loading screen, which was already
      built last session to read it live from the OS. New About screen
      in Settings (name, version, GitHub placeholder) — see ARCHITECTURE.md
- [x] Two OLED watch faces on the wearable, toggled by its BOOT button:
      a primary clock/date/BME280 face (time synced from the phone over
      BLE — the ESP32 has no RTC of its own) and a secondary
      HR/SpO2/body-temp detail face (the previous single face). App now
      auto-connects to the wearable on launch instead of requiring a
      manual "Scan & Connect" tap — see ARCHITECTURE.md for the full
      protocol/firmware details, including a real `arduino-cli` compile
      check (not just a read-through) confirming the firmware builds
      clean
- [x] Auto-connect actually fixed, root cause found via `adb logcat` on
      a real device (not guessed): `flutter_blue_plus`'s `startScan()`
      resolves the instant a scan *starts*, not when it ends — the
      `timeout` param doesn't make the call awaitable for that long —
      so auto-connect was checking for a found device milliseconds after
      the scan began, real logs showed "scanning..." immediately
      followed by "no matching device found" ~120ms later, every time.
      Now waits for the plugin's own `isScanning` stream to genuinely go
      false before checking. The manual "Scan & Connect" screen had the
      identical latent bug (fixed too) — it just wasn't visible there
      since that screen reads a live, separately-updated device list
      rather than a single post-scan check. Also added explicit
      Bluetooth-permission checks, per-branch logging (`[BLE]
      autoConnect: ...`), and an app-resume retry along the way — see
      ARCHITECTURE.md for the full two-round debugging trail
- [x] Custom app-wide font (Nunito, bundled locally — not fetched at
      runtime, matching this app's offline-first rule) instead of the
      platform system font, a standing rule from here on; the
      "ForeverFit" header/wordmark is now bolder and larger than the
      theme's default AppBar title style — see ARCHITECTURE.md
