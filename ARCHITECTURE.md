# Architecture — Personal Health Companion (SIH '26 #26181)

## System overview

```
┌────────────────────────┐        BLE        ┌──────────────────────────────┐
│  ESP32-S3 wearable      │ ─── notify ───▶  │  Phone (Flutter app)          │
│  MAX30101 (HR/SpO2)     │                   │  - BLE central                │
│  MPU6050 (accel/gyro)   │                   │  - on-device inference (CNN)  │
│  BME280 (env)           │                   │  - local storage (Hive)       │
│  MAX30205 (stub)        │                   │  - offline maps               │
│  0.96" OLED watchface   │                   │  - dashboard, alerts, SOS      │
└────────────────────────┘                   └──────────────────────────────┘
                                                        │ optional, only when
                                                        │ connectivity exists
                                                        ▼
                                            AQI/weather APIs, webhook/SMS relay
```

Design principle: **the wearable is a dumb sensor hub.** All interpretation —
anomaly detection, risk scoring, disaster classification — happens on the
phone, on-device, so the system keeps working with no internet and the raw
physiological data never has to leave the user's device unless they choose to
share it.

## BLE protocol (implemented)

Custom GATT service, three `notify`-only characteristics. All multi-byte
fields are **little-endian**, matching the ESP32's native order — Dart parses
with `ByteData.getX(offset, Endian.little)`. This spec is the single source
of truth; the firmware (`firmware/health_companion/health_companion.ino`) and app
(`app/health_companion/lib/ble/protocol.dart`) must be changed together.

| UUID | Name | Rate | Layout |
|---|---|---|---|
| `6e400001-...` | Service | — | — |
| `6e400002-...` | Vitals | ~1 Hz | `uint32 tMs; float heartRate; float spo2; float bodyTempC;` (16 bytes) |
| `6e400003-...` | Environment | ~1 Hz | `uint32 tMs; float ambientTempC; float humidity; float pressureHPa;` (16 bytes) |
| `6e400004-...` | Motion | ~20 Hz | `uint32 tMs; float ax,ay,az; float gx,gy,gz;` (28 bytes) |

Motion is notified faster than the others because fall-detection needs
enough samples per window (~40–60 samples over 2–3s) to see the
free-fall-then-impact signature.

**Known limitations to fix as this evolves:**
- SpO2 is a rough, uncalibrated AC/DC ratio estimate (`110 - 25*R`), not a
  clinically valid reading — fine for a relative risk signal, not diagnosis.
- Body temperature is a stubbed simulation (`readBodyTempC()` in
  `health_companion.ino`) because the MAX30205 on hand doesn't work. Swap in
  a real driver call there if it's replaced.

## On-device fall-detection CNN (implemented, currently phone-only)

**Update**: the wearable's MPU6050 died on the breadboard build (confirmed
via an I2C bus scan added to `health_companion.ino` — `scanI2CBus()`
found no device at all where it should be), so the app currently runs a
**phone-only** fall-detection model rather than the wrist+phone fusion
this section originally described. The wrist+phone design and pipeline
are kept intact and documented below — they're the better long-term
approach and easy to resume once the wearable's IMU is replaced — but
right now `fall_detector_service.dart` loads
`fall_detector_phone_only.tflite`, trained on real phone accelerometer +
a waist-sensor gyro proxy (see `ml/README.md`), and needs no BLE
connection to work at all. Held-out test performance: 99% accuracy, 88%
fall precision, 94% fall recall — see `ml/README.md` for the labeling fix
(only windows containing the actual impact are labeled Fall, not every
window in a Fall trial) that a live test on real hardware caught and
this number reflects.

Original design, on hold: a small 1D-CNN fuses the wearable's wrist
motion (streaming over BLE at 20Hz) with the phone's own accelerometer
for a second, independent view of the same physical event — a wrist-only
signal can't easily tell "arm swung hard" from "whole body fell," but a
synchronized phone signal resolves that ambiguity.

- **Training data**: [UMAFall](https://figshare.com/articles/dataset/UMA_ADL_FALL_Dataset_zip/4214283)
  (Casilari et al.) — 19 subjects, 746 short single-movement trials (208
  falls, ~507 ADLs), with synchronized wrist + phone-pocket sensors. Chosen
  after directly inspecting the raw CSVs (not just the paper) to confirm
  the phone channel really is simultaneous with the wrist channel for the
  same fall events — no other public dataset has this combination (checked
  WEDA-FALL, MobiFall, FallAllD; see `ml/README.md`).
- **9 trained channels**: wrist accel(x,y,z) + wrist gyro(x,y,z) + phone
  accel(x,y,z) — not 12. UMAFall's phone channel has no gyroscope (a
  hardware limitation of the phone used to collect it in 2016), and no
  dataset anywhere pairs wrist + phone-gyro for the same falls. Training a
  channel that's always zero would leave its weights at random
  initialization, worse than omitting it.
- **The phone's real gyroscope isn't wasted**, though: a fast phone
  rotation is itself physical evidence of a tumble, so it corroborates a
  borderline CNN score via a rule-based check rather than a fabricated
  trained input — see `fall_detector_service.dart`.
- **Two unit mismatches** were found by inspecting raw values (not just
  docs) and corrected during training data prep: the dataset's
  accelerometer is in **G** and gyroscope in **deg/s**; `Adafruit_MPU6050`
  (firmware) and `sensors_plus` (phone) both report **m/s²** and **rad/s**
  natively. Skipping this wouldn't error — it would train a model on the
  wrong scale that looks fine in evaluation and fails on real device data.
- **Labels only mark windows that actually contain the impact**, not every
  window in a Fall trial (each trial is ~15s but the tumble itself is only
  1-2s) — see `ml/README.md` for how a live hardware test caught this the
  first time around. Held-out test performance (subjects never seen in
  training): 94% accuracy, 58% fall precision, 90% fall recall — a real,
  honest result from a 19-subject dataset, not a clinical-grade guarantee,
  and this version's threshold choice (below) predates the labeling fix
  and should be revisited before this model is put back into the app.
- Full pipeline (`ml/download_dataset.py` → `prepare_windows.py` →
  `train_fall_model.py` → `convert_to_tflite.py`) and rationale in
  `ml/README.md`. Output: `app/health_companion/assets/models/fall_detector.tflite`.
- **Alert UX**: detection latches an alert open (deliberately independent
  of the live cnnProb, which drops back to normal within ~1s of the phone
  settling — an earlier version auto-dismissed the banner before a real
  user could react). A 10s countdown gives the user a chance to tap "I'm
  OK"; if ignored, it escalates to a **dummy** emergency call (logged
  only, no real call placed) — see `fall_detector_service.dart`. Wiring
  that escalation to a real SMS/call is the SOS item below, not yet built.

## App navigation (implemented)

The app opens into `HomeShell` (`lib/screens/home_shell.dart`), a bottom
`NavigationBar` with three tabs — Dashboard, Map, Health Log (placeholder)
— all reachable with or without a wearable connected. Previously the app
opened straight into the BLE scan screen and `DashboardScreen` bounced
back to it whenever disconnected, which made features that don't need a
wearable at all (fall detection, and now the map) unreachable without
one. `ScanConnectScreen` is now a pushed route reached via a "Connect"
button/banner on the dashboard, not the app's home.

## Disaster risk map (implemented, phone-only, no wearable needed)

GPS-driven, India-focused disaster awareness: live data when online,
falling back to cached-then-static data when not — see
`lib/disaster/disaster_service.dart` and `lib/screens/map_screen.dart`.

- **Live signals** (fetched fresh when online, each independently cached
  with a timestamp for offline fallback):
  - [Open-Meteo](https://open-meteo.com/) for today's max precipitation
    probability and current wind speed — free, no API key, no signup,
    verified with a live test call before use.
  - USGS Earthquake API for M4.0+ events within 200km in the last 30
    days — free, global, no key, verified with a live test call (returned
    a real M4.3 event near Barkot, India).
  - [Nominatim](https://nominatim.org/) (OpenStreetMap) reverse geocoding
    to resolve GPS → state name, respecting its usage policy (only
    re-queried after >2km of movement or a 10-minute cooldown, with a
    descriptive User-Agent header — not queried on every GPS update).
- **Static offline baseline** (`lib/disaster/india_hazard_data.dart`): a
  hardcoded state-level table of seismic zone (BIS IS 1893:2016,
  approximate — a state's predominant zone, not district-level), cyclone
  exposure, and flood-proneness. Used as the fallback of last resort (no
  cache, never been online) and to add static context alongside live
  weather always. Chosen over bundling an official dataset after
  data.gov.in's seismic-zone resource returned HTTP 403 on direct fetch,
  and the only India-wide flood dataset actually confirmed downloadable
  via GitHub's API (not just a page's description of it — a smaller
  ready-made district/state flood-risk JSON that a page summary described
  turned out not to actually exist as a release asset when checked
  against the real API) was a 28.6MB historical flood-event file not
  worth bundling for this pass.
- **Data-first, offline-fallback rule, applied uniformly**: attempt each
  live HTTP call with a short timeout; on success, use it and cache it;
  on failure, fall back to the last cached value (shown with a
  "cached from Nm/h/d ago" label so staleness is visible, never silently
  presented as live); if there's never been a successful fetch, fall back
  to the static table alone. No connectivity-check package — attempting
  the fetch and catching failure *is* the check, and more accurate than a
  package that can report "connected" on a network with no real internet.
- **Offline map tiles**: `flutter_map` + `flutter_map_cache` (chosen over
  the heavier `flutter_map_tile_caching` — this app's pattern is "cache
  what's actually been viewed while online," not bulk region
  pre-downloads) backed by `http_cache_file_store` in the app's
  persistent support directory (not a temp dir, which the OS can clear).
- **Warning banner**: shown when precipitation probability >70%, a
  nearby M4.5+ quake in the last 30 days, or high wind in a cyclone-prone
  state — dismissible, no countdown/escalation (an area-awareness
  warning, not the fall detector's emergency-response flow).

## Roadmap (not yet implemented)

UI stubs exist for everything below (Dashboard's Wellness/Activity/
Baseline cards + SOS button, Map's Air Quality row, Health Log's
tracking tiles, Settings' emergency contact form) so the shape of the
full app is visible even where the logic isn't built yet.

### 1. AI/ML opportunities, roughly in priority order

- **Activity-conditioned vitals anomaly detection** (highest value per
  effort): a lightweight activity classifier (walking/running/sitting/
  still) over the accel+gyro stream already flowing for fall detection —
  same infrastructure, reused. Lets HR/SpO2 anomaly checks know "elevated
  HR while running is normal, elevated HR while sitting still isn't,"
  directly cutting false positives in whatever anomaly detection exists.
- **Personalized baseline learning**: NOT necessarily a CNN — a rolling
  per-user mean/std (z-score deviation from *this user's own* resting
  HR/SpO2 over the past week) catches "unusual for you" in a way a fixed
  global threshold can't, is simple statistics, and is more honest about
  what it is than dressing it up as deep learning.
- **On-device vitals/heat-stress anomaly CNN**: multi-class classifier
  over a sliding window (e.g. last 2–5 minutes) of HR, SpO2, body temp,
  ambient temp, humidity. Training data: **WESAD** (wearable
  stress/affect, has physiological signals under thermal/physical
  stress) as a starting point, plus heat-index-labeled synthetic
  augmentation since WESAD alone won't cover heat-stress specifically.
  Output classes: normal / possible heat stress / possible dehydration /
  possible respiratory or cardiac concern. Same small-CNN-via-TFLite
  approach as the fall detector — expect another dataset-reality-check
  along the way, same as UMAFall and the flood data both needed.
- **Composite wellness/risk score**: combining HR/SpO2/temp/environment
  into one number for the dashboard. Start with a transparent calibrated
  formula (no training data needed, explainable to judges) — only reach
  for a learned model if the formula demonstrably underperforms.
- Deliberately not pursuing: an on-device LLM/chatbot layer. Heavy for a
  phone app on this timeline, and cuts against the offline-first,
  privacy-preserving pitch if it ever needs cloud inference.

### 2. Gaps against the original problem statement

- **Air quality**: mentioned in the original brief (pollution events,
  respiratory risk) but never integrated — WAQI or OpenWeatherMap's air
  pollution API would slot into `DisasterService` the same way
  Open-Meteo does.
- **Sleep tracking**: named in the problem statement's "Continuous Health
  Monitoring," not built.
- **Trend/history views**: the dashboard's HR sparkline is the only trend
  view — nothing like a daily summary or "today vs. your week," which
  the problem statement's "Personal Wellness Dashboard" section calls
  for.
- **Manual SOS button**: currently the only emergency trigger is the
  fall detector firing automatically. Someone conscious during a medical
  episode has no way to proactively ask for help.

### 3. Full-screen imminent-disaster warning with safety guidance

The current warning (Map screen banner) is a dismissible, non-blocking
notice for "elevated risk" — fine for area awareness, not urgent enough
for a genuinely imminent event. Missing a harder-to-miss tier: a
full-screen modal requiring explicit acknowledgment, with concrete
per-hazard actionable guidance, not just a risk label:
- Earthquake: "Drop, Cover, Hold On — get under a sturdy table"
- Flood: "Move to higher ground immediately"
- Cyclone/storm: "Stay indoors, away from windows"
- Heat wave: "Stay hydrated, avoid outdoor activity"

Needs its own, stricter trigger threshold distinct from `hasWarning`
(e.g. a very high precip probability *and* flood-prone, or a close
M5.5+ quake, not just "elevated risk") — reusing the existing banner's
threshold as-is would cause alert fatigue by firing this at the same
rate as the low-key banner. The per-hazard "what to do" text is static
and bundled, needs no data source, similar in spirit to the offline
safety-checklist idea in the health-tracking gap above.

### 4. Wearable-sensor disaster heuristics

The disaster map above uses live weather + static state data, not the
wearable's own sensors yet. Two refinements once the wearable's IMU is
back (see fall-detection CNN's "on hold" state):
- **Heat-wave risk**: standard heat-index formula from `ambientTempC` +
  `humidity` (BME280, already streaming over BLE), thresholded per IMD
  heat-wave guidance — more locally accurate than the phone-GPS-based
  Open-Meteo call for a wearable actually on the body.
- **Cyclone/storm risk refinement**: BME280 pressure **drop-rate** over a
  rolling window (a fast, sustained fall in hPa/hour is a classic
  pre-storm signal) as a supplementary signal alongside the map's
  wind-speed-based check.

### 5. Health tracking (weight, height, meds, insulin, etc.)

`HealthLogScreen` now shows stub tiles for each of these (tapping any
shows "coming soon"). Ideas gathered so far: core tracking (weight/height
with auto-BMI, blood pressure, blood glucose, insulin dosing log,
medication reminders, sleep, hydration, symptom journal); safety-oriented
additions that double as real SOS infrastructure (a **Medical ID** card —
blood type, allergies, conditions, current meds, visible to a responder
in an emergency; proper **emergency contacts management**, which item 6
below needs anyway — a stub form exists on the new Settings tab;
caregiver/family sharing for remote monitoring); and disaster tie-ins
(flag extra heat-stress risk for a diabetic during a heatwave, extra
caution for a respiratory condition on a high-AQI day; a bundled offline
"what to do during X" checklist needing no data at all — the same
checklist content item 3 above needs, so build it once and reuse it).

### 6. SOS / emergency assistance

Since "network is icing on the cake," SOS must work over the cellular
network without data connectivity:
- `url_launcher` with `sms:` and `tel:` URIs to reach emergency contacts
  (stored locally, never synced) with the user's GPS coordinates —
  SMS/calls don't need mobile data.
- **The cancellable countdown + escalation trigger is already implemented**
  (`FallDetectorService`: 10s countdown, "I'm OK" to cancel, escalates
  otherwise) — currently ends in a dummy logged action, not a real
  call/SMS. Wiring `_triggerEmergencyCall()` to actually reach an
  emergency contact via `url_launcher` (`sms:`/`tel:`) with GPS
  coordinates is what's left.
- **Settings tab + emergency contact form** now exist as a UI stub
  (`SettingsScreen`) — not persisted yet, just the layout.
- **Manual SOS button** is stubbed on the Dashboard (see gap #2 above) —
  tapping it currently just shows what it'll do, doesn't trigger anything
  real yet.
- An online webhook/push notification path can be added later as a
  supplementary channel, never a dependency.

## Repo layout

```
sih26-health-companion/
├── firmware/health_companion/   # Arduino IDE sketch (ESP32-S3, Arduino Core 3.3.11)
│   └── health_companion.ino
├── ml/                           # fall-detector training pipeline (see ml/README.md)
│   ├── download_dataset.py
│   ├── prepare_windows_phone_only.py, train_fall_model_phone_only.py,
│   │   convert_to_tflite_phone_only.py   # currently active
│   ├── prepare_windows.py, train_fall_model.py, convert_to_tflite.py  # on hold
│   └── data/                     # gitignored — regenerate by rerunning the pipeline
└── app/health_companion/        # Flutter app
    ├── assets/models/fall_detector_phone_only.tflite  # currently loaded
    ├── assets/models/fall_detector.tflite              # on hold
    └── lib/
        ├── main.dart
        ├── ble/{protocol.dart, ble_service.dart}
        ├── sensors/phone_motion_service.dart
        ├── ml/fall_detector_service.dart
        ├── disaster/{disaster_service.dart, india_hazard_data.dart}
        ├── models/sensor_reading.dart
        ├── storage/history_store.dart
        ├── screens/
        │   ├── home_shell.dart          # bottom-nav shell, app's home route
        │   ├── dashboard_screen.dart
        │   ├── map_screen.dart
        │   ├── health_log_screen.dart   # placeholder
        │   └── scan_connect_screen.dart # pushed route, not the home route
        └── widgets/metric_card.dart
```
