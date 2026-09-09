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
| `6e400002-...` | Vitals | ~1 Hz | `uint32 tMs; float heartRate; float spo2; float bodyTempC; uint8 fingerPresent;` (17 bytes) |
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

**`fingerPresent` flag (fixed a real bias bug)**: the firmware zeroes
`heartRate`/`spo2` when the MAX30101 doesn't detect finger/wrist contact
(`FINGER_PRESENT_IR_THRESHOLD`) — the OLED already showed "no finger" in
that state, but the app had no way to tell "0 because no finger" from "an
actual reading of 0" until this flag was added. Without it: the Dashboard
showed a false "Heart rate" warning (0 < the 50bpm floor) whenever the
sensor briefly lost contact, and every no-finger sample would have been
persisted to history as a real 0 reading, which is exactly the kind of
thing that quietly biases `BaselineService`'s rolling mean/std and the
composite wellness score. Fix: `BleService._onVitals()` now only calls
`historyStore.addVitals()` when `fingerPresent` is true, and
`DashboardScreen` shows "no finger" instead of a bpm/percent value and
skips the HR/SpO2 warning checks entirely in that state.

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

## App navigation (implemented, single-dashboard — no bottom nav)

First launch goes through `OnboardingGate` → `OnboardingScreen` before
anything else (permissions, then profile & medical info — see "Onboarding
+ categorized Settings" below); after that, `DashboardScreen` is the
app's home route directly (`main.dart`'s `home:`) — no shell, no bottom
`NavigationBar`. Replaced the earlier
three-tab layout (`home_shell.dart`, deleted) after reviewing a cloned
reference app (`app/mobile-app` — OpenVitals, see the "Visual design"
section above) whose single-dashboard-with-widget-grid pattern reads as
more information-dense than tabs for an app with this many small stats.
Everything else is a pushed route reached from the dashboard: `Settings`
via an app-bar gear icon, the disaster `MapScreen` via a dedicated nav
card (shows the current warning inline when there is one, not just a
generic link — see `_DisasterMapNavCard`), `ScanConnectScreen` via the
Connect banner/button, and every metric/health-log card opens its own
history or management screen directly (see "Body & activity metrics"
and "Health log" below) — there's no longer an intermediate
`HealthLogScreen` stub list; everything it used to stub out is real now.
All of it is reachable with or without a wearable connected, same as
before — `DashboardScreen` never bounces to `ScanConnectScreen`
automatically.

`BleService` tracks `FlutterBluePlus.adapterState` directly (initialized
from `adapterStateNow`, kept live via the `adapterState` stream) instead
of only surfacing a raw scan-failure exception when Bluetooth is off.
`ScanConnectScreen` checks this before anything else and shows a "Turn on
Bluetooth" button (`FlutterBluePlus.turnOn()`, which raises the system
enable-Bluetooth dialog directly) rather than an unactionable error
string.

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
  - Open-Meteo's separate [Air Quality API](https://open-meteo.com/en/docs/air-quality-api)
    (`air-quality-api.open-meteo.com`, a different host from the weather
    forecast one, same no-key/no-signup terms) for US AQI + PM2.5/PM10 —
    verified live (returned a real AQI 203 "Very Unhealthy" reading for
    Delhi). Closes the "air quality" gap from the original problem
    statement, which was open until now. No static offline baseline for
    this one, unlike seismic zone/cyclone/flood-prone below — AQI swings
    hour to hour with traffic/weather/season, so a hardcoded "this state
    is usually X" table would be actively misleading rather than merely
    approximate; it's live-or-cached only, same as precipitation/wind.
    AQI > 150 ("Unhealthy") now also feeds the Map's existing warning
    banner, alongside heavy rain/nearby quakes/high wind.
  - [Nominatim](https://nominatim.org/) (OpenStreetMap) reverse geocoding
    to resolve GPS → state name, respecting its usage policy (only
    re-queried after >2km of movement or a 10-minute cooldown, with a
    descriptive User-Agent header — not queried on every GPS update).
  - **Rapid barometric pressure fall** (`lib/disaster/pressure_trend.dart`):
    every `refresh()` records one pressure sample — the wearable's live
    BME280 reading when connected, falling back to Open-Meteo's current
    `pressure_msl` (and the other way round if the preferred source is
    momentarily unavailable), per the same `AmbientSourcePreference`
    setting already used for the Dashboard's ambient cards
    (`sensor_precedence_screen.dart`) — into a rolling 6h history in the
    disaster Hive cache. A fall of ≥3 hPa within the last 3 hours (a
    widely used marine/aviation "rapid pressure fall" warning threshold —
    the UK Met Office and Australian BoM both use a comparable trigger
    for small-craft warnings) is treated as a genuine, live early-warning
    signal that a storm is approaching, independent of any forecast
    probability. Requires ≥2h of accumulated history before it can fire,
    so a fresh install/reconnect can't misread a couple of noisy samples
    a few minutes apart as a "fall." **Known limitation**: a wearable's
    BME280 also responds to altitude (stairs, an elevator, a car climbing
    a hill), which a fixed weather station never sees — this isn't
    corrected for, so a real altitude change during the 3h window could
    read as a false pressure-drop signal. Documented, not hidden, per
    this project's existing pattern for platform-integration caveats.
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
  nearby M4.5+ quake in the last 30 days, high wind in a cyclone-prone
  state, or AQI >150 ("Unhealthy") — dismissible, no countdown/escalation
  (an area-awareness warning, not the fall detector's emergency-response
  flow, and not wired into the full-screen imminent-warning/siren system
  either — air quality is a real health risk but not the same acute,
  drop-everything category as an earthquake or flood, so it stays at
  this lower-key tier for now).
- **Position fallback chain** (`DisasterService._getPosition()`): live GPS
  first; if location services are off or a fix fails, `Geolocator.
  getLastKnownPosition()` (the OS's cached fix, available even with
  services currently off if one was obtained before); if that's also
  unavailable, this app's own last-successfully-used lat/lon from the
  Hive cache. Only once all three fail does the screen show an error —
  previously it errored the moment location was off, with no fallback at
  all. `DisasterService.positionIsStale` flags when a fallback position
  is in use (shown as "(approximate)" next to the location name), and
  `locationServiceEnabled` (checked fresh each refresh) drives a Map
  banner with a one-tap `Geolocator.openLocationSettings()` button when
  it's off, instead of a bare error.
- **Ambient temp/humidity/pressure as a Dashboard fallback**: Open-Meteo's
  `current` call was extended with `temperature_2m`, `relative_humidity_2m`,
  `pressure_msl` (verified live: same units as the wearable's BME280 — °C,
  %, hPa — no conversion needed) alongside the existing precipitation/wind
  fields. `DashboardScreen` now resolves these three cards as wearable
  sensor → online weather → "--", instead of only ever showing the
  wearable value or nothing; the unit label gets an "(online)" suffix
  when the value came from Open-Meteo rather than the wearable, and the
  heat-index/heat-stress warnings use whichever value is actually being
  shown so a hot online-sourced reading still visibly flags.

## Full-screen imminent-disaster warning (implemented)

A harder-to-miss tier above the Map screen's dismissible banner, for when
a hazard crosses a much stricter threshold — `DisasterRisk.imminentHazards`
in `lib/disaster/disaster_service.dart` requires a nearby M5.5+ quake (vs.
the banner's M4.5+), >60 km/h wind in a cyclone-prone state (vs.
>40 km/h), or a rapid barometric pressure fall (≥3 hPa in 3h — see the
disaster risk map section above) — deliberately much rarer than the
banner so it doesn't cause alert fatigue.

Deliberately restricted to genuine *live/detected* signals only — a
nearby quake that already happened, wind currently being observed,
pressure currently falling — rather than a forecast probability paired
with a static "this area is prone to X" flag. Earlier this fired on
">85% rain probability forecast for today, in a flood-prone state," but
that combination is a coarse statistical approximation, not evidence a
flood is actually imminent right now, so it was moved back down to the
low-key Map banner tier (`hasWarning`/`warningMessage`, unconditional on
flood-proneness) instead of the full-screen warning.

- **`ImminentWarningGate`** (`lib/disaster/imminent_warning_gate.dart`)
  wraps the whole app (`main.dart`), watches `DisasterService`, and pushes
  `ImminentWarningScreen` full-screen the moment a *new* hazard set
  crosses the threshold (deduped so it doesn't re-push on every refresh
  while the same hazard is still active).
- **`ImminentWarningScreen`** (`lib/screens/imminent_warning_screen.dart`)
  blocks the back gesture (`PopScope(canPop: false)`) — the only way out
  is the explicit "I understand" button — and shows static, bundled
  per-hazard guidance (`lib/disaster/hazard_type.dart`): Drop/Cover/Hold
  On for earthquakes, stay indoors for cyclones, move indoors/secure
  loose objects for an approaching storm (rapid pressure fall), hydration/
  heat-exhaustion signs for heat waves (heat wave has guidance text ready
  but no live trigger yet — `DisasterService` doesn't track a heat-index
  threshold as a hazard, only as a Dashboard warning). Flood guidance
  still exists (`HazardType.flood`) for the manual preview list below,
  even though nothing currently triggers it live.
- **Siren audio**: loops through Android's `STREAM_ALARM` (not the
  ringer/media stream), via `lib/services/alarm_sound_service.dart`
  (`audioplayers` with `AndroidUsageType.alarm`) plus a small native
  `MethodChannel` (`MainActivity.kt`) that temporarily forces
  `STREAM_ALARM` to max volume for the duration of the warning and
  restores the user's previous alarm volume when dismissed — the same
  mechanism alarm-clock apps use to be heard over silent/DND mode. The
  siren tone (`assets/sounds/alarm_siren.wav`) is synthesized, not a
  downloaded sample.
- **Manual preview**: since real conditions rarely cross the imminent
  threshold live, `SettingsScreen` has a "Preview disaster warnings"
  section that opens the full-screen warning (with siren) for any hazard
  type on demand — this is the reliable way to demo the feature.

## AI/ML: activity gating, personalized baseline, wellness score (implemented)

All four items originally scoped in the AI/ML roadmap were attempted, in
priority order; three landed as designed and the fourth pivoted after
direct verification ruled out its planned dataset. See `ml/README.md` for
the full training-pipeline writeups.

- **Activity-conditioned vitals anomaly detection**
  (`lib/ml/activity_classifier_service.dart`): a 3-class 1D-CNN
  (still/walking/running) over the same 60-sample/20Hz accel+gyro window
  infrastructure the fall detector already uses, trained on the
  MotionSense dataset (24 subjects, MIT licensed — verified as a real,
  directly-downloadable repo before use, see `ml/README.md`). 99.9% test
  accuracy on held-out subjects — much higher than fall detection's,
  because sustained activity patterns over a 3s window are an easier
  signal than a brief impact. `heartRateCeiling()`
  (`lib/domain/health_thresholds.dart` — the single shared source of
  truth for this and every other clinical threshold, also consumed by
  the insight engine below) uses the live activity to set the HR warning
  threshold: 120bpm at rest, 140bpm walking, 180bpm running — replacing
  one fixed threshold that couldn't tell "elevated because you're
  running" from "elevated at rest."
- **Personalized baseline learning** (`lib/services/baseline_service.dart`):
  deliberately *not* a CNN — a rolling mean/std of this user's own resting
  heart rate over the past 7 days (min 20 samples before it activates),
  from the same `HistoryStore` Hive box the Heart rate card's history
  screen also reads. Flags a live reading more than 2 personal standard
  deviations from *this user's* baseline, catching "unusual for you" in a way no
  fixed global threshold can — plain statistics, and more honest about
  what it is than dressing it up as deep learning.
- **On-device heat-stress detection** — investigated as a WESAD-trained
  CNN, not built that way: WESAD's documented host and its commonly-cited
  mirror both returned `404` on direct verification, and the remaining
  path (Kaggle, ~2.5GB) has chest/wrist ECG/EMG/EDA signals that don't
  map onto what this app's wearable actually streams — the same shape of
  dead end as the flood dataset earlier. Built instead:
  `lib/utils/heat_index.dart`, a transparent NOAA/Rothfusz heat-index
  formula over the wearable's real ambient temp + humidity readings,
  feeding both the Ambient Temp card's warning and the wellness score
  below. See `ml/README.md` for the full verification trail.
- **Composite wellness score** (`DashboardScreen._wellnessScore()`): a
  transparent calibrated formula, not a trained model — no labeled
  "wellness score" data exists to train on anyway, and a formula is
  explainable to judges in a way a black-box score isn't. Starts at 100,
  deducts per concerning signal currently showing (HR -25, SpO2 -30, body
  temp -20, ambient heat index -10, heat-stress combination -15), shown
  in the Dashboard's Wellness card.
- Deliberately not pursuing: an on-device LLM/chatbot layer. Heavy for a
  phone app on this timeline, and cuts against the offline-first,
  privacy-preserving pitch if it ever needs cloud inference.

## Visual design + Wellness detail screen (implemented)

A cloned reference app (`app/mobile-app/` — OpenVitals, a native
Kotlin/Health-Connect app, AGPL-3.0, gitignored here and never committed —
see the repo's own README for what it is) was reviewed for possible reuse.
Verdict: not reusable as a codebase (100% Kotlin vs. this app's 100%
Dart/Flutter — "wiring in" our BLE/ML/disaster code would mean a full
rewrite, not a port) and its AGPL license would obligate relicensing any
derivative. Two things *were* worth pulling in, both reimplemented from
scratch in Dart — no OpenVitals code was copied:

- **Visual language** (`lib/theme/app_theme.dart`): a warm cream/peach
  palette, large-radius cards, circular icon badges, a colored accent
  strip per stat card, and pill-shaped buttons — replacing the previous
  default Material 3 teal seed theme. Applied app-wide via `ThemeData`
  (card/button/nav-bar/input themes), so individual screens needed no
  per-widget changes beyond `MetricCard` itself (icon badge + accent
  strip + optional `onTap`) and swapping two hardcoded `Colors.red`
  error texts for `colorScheme.error`.
- **Wellness detail screen** (`lib/screens/wellness_detail_screen.dart`):
  tapping the Dashboard's Wellness card now opens a screen explaining the
  score — a headline, a plain-English reasoning paragraph, and a
  per-signal breakdown (heart rate, SpO2, body temp, ambient heat index,
  heat-stress combination), each with its own detail text. Backed by
  `lib/models/wellness_snapshot.dart`, built once in `DashboardScreen`
  from the same warning flags that already feed the wellness-score
  formula, so the card and the detail screen can never disagree. The
  score-plus-reasoning *shape* of this screen is the one idea taken from
  OpenVitals' Daily Readiness screen; the content, data, and code are
  this app's own.

## Body & activity metrics (implemented, local storage — no Health Connect)

A second pass at OpenVitals, this time asked to consider its full feature
set (39 dashboard widgets, 11 settings sections, GPS/watch/import/export
subsystems — see its `docs/features/feature-map.md`). Verdict, given
before starting: porting "every feature" isn't realistic in the time
available, and more importantly almost none of it is custom logic to
port in the first place — nearly every OpenVitals metric is a thin
display layer over **Health Connect**, Android's system health data
store, which this app doesn't integrate with and has a fundamentally
different data model from (BLE-wearable + phone-sensor first, not
Health-Connect-aggregation first). Scoped down to: the single-dashboard
*shape* (see "App navigation" above) plus a handful of the manual-entry
metrics, built for real against this app's own local storage instead of
Health Connect:

- **`lib/storage/metrics_store.dart`**: a `ChangeNotifier` Hive store
  (same offline-first pattern as `HistoryStore`) for weight and height
  log entries, plus hydration entries — every entry is timestamped
  (`at`), not just a "latest value" cache. `bmi` is computed from the
  latest logged weight + height (no separate stored field); `bmiHistory()`
  pairs the full weight history against whatever height was on record
  at-or-before each weigh-in (height rarely changes for an adult, so
  this is realistically driven by the weight series). `historyOfType()`
  and `hydrationDailyTotals()` expose the full timestamped history as
  `MetricPoint`s for charting.
- **Body fat is derived, not logged** (`lib/domain/body_composition.dart`,
  `computeBodyFatPercent`): the Deurenberg et al. 1991 formula from BMI +
  age (`UserProfileStore.dateOfBirth`) + sex (`UserProfileStore.sex`) —
  another transparent formula rather than a trained model, same pattern
  as the wellness score/baseline/heat index. Returns null (not a guess)
  without a saved date of birth. "Other"/"Prefer not to say"/unset sex
  splits the difference between the formula's male/female terms rather
  than assuming one. There's no longer a manual body-fat entry dialog —
  `BodyFatHistoryScreen` charts the computed value against `bmiHistory()`
  instead (age/sex applied uniformly across the whole history, so the
  chart's shape mirrors the BMI trend). `BmiHistoryScreen` is new too —
  the BMI card previously had no history screen at all.
- **`lib/services/step_counter_service.dart`**: the phone's own hardware
  step counter (`pedometer` package, Android `TYPE_STEP_COUNTER`), not
  Health Connect and not the wearable (no step sensor on it). That sensor
  reports a cumulative count since last boot, not since midnight, so this
  stores a "steps at start of today" baseline in Hive and reports the
  difference — persisted so a restart mid-day doesn't reset it. Needs the
  `ACTIVITY_RECOGNITION` runtime permission (Android 10+), requested in
  `start()`. Each day's final total is archived into a `step_daily_history`
  box when the next day starts, so a trend builds going forward (no
  retroactive backfill — the sensor only ever reports "since boot").
- **`lib/screens/metric_history_screen.dart`**: one generic chart + stats
  + period-selector screen, reused for every metric (weight, height,
  body fat, hydration, steps, heart rate) rather than a bespoke screen
  per metric:
  - **Time Period card**: preset chips (Last 7 Days/Last Month/Last 3
    Months/All Time) plus a **Custom Range** button
    (`showDateRangePicker`) for an arbitrary start/end.
  - **Summary row**: Avg / Range (min–max combined into one value, not
    two separate tiles) / Change (colored + trending-up/down icon based
    on sign).
  - **Chart**: `fl_chart` with real axis titles (Y-axis values, X-axis
    dates sampled at ~4 points across the range), a light horizontal
    grid, a shaded area under the curve, a dashed least-squares linear
    trend line behind the real data line, and `LineTouchData` tooltips
    (tap a point for its exact value + date). Each metric gets its own
    line color (`accentColor` param) matching its Dashboard card's accent
    for visual continuity between the card and its chart.
  - **Statistics card**: Average / Total Entries / Minimum / Maximum as a
    2x2 icon+label+value grid.
  `lib/screens/metric_detail_screens.dart` has the six thin per-metric
  wrappers that each just supply data + accent color + an optional "log a
  new value" action (a shared dialog for weight/height/body-fat via
  `lib/widgets/log_value_dialog.dart`, quick-add chips for hydration,
  nothing for steps/heart rate since neither is manually logged). Tapping
  a Dashboard card now opens its history screen rather than a log dialog
  directly, so logging and trend-viewing share one entry point.
- **Dashboard card layout**: Wellness overview (3 cards) is a
  horizontally scrollable row of fixed-width rectangular cards (`_CardRow`
  in `dashboard_screen.dart`) — 3-per-row `GridView`s were truncating
  labels ("Well…", "Basel…"). Body & activity (7 cards: steps, heart
  rate, weight, height, BMI, body fat, hydration) outgrew a single row,
  so it's a swipeable, paged 2-column x 3-row grid with a dot-page
  indicator instead (`_PagedCardGrid`) — the OpenVitals
  dashboard-carousel pattern, reimplemented from scratch (AGPL, no code
  copied). Heart rate appears both here and in the top vitals grid
  (deliberate duplication, not an oversight: the vitals grid is the
  always-visible, no-swipe-needed safety-critical one; this one is the
  "all your stats, one consistent tap-through interaction" one) — every
  card in both places, heart rate included, opens the same generic
  `MetricHistoryScreen` (`HeartRateHistoryScreen` in
  `metric_detail_screens.dart`, reading `HistoryStore.heartRateHistory()`)
  rather than a bespoke inline chart. There used to be a standalone
  "Heart rate — recent" sparkline permanently on the dashboard; it's
  gone now that every metric, heart rate included, follows the same
  tap-a-card-to-see-its-trend pattern instead of one metric getting
  special-cased screen space.
- **`HealthLogScreen` is gone** — every metric it used to stub out is a
  real Dashboard card now (blood pressure, glucose, insulin, sleep, and
  Medical ID landed alongside weight/height/body fat/hydration in the
  next section below), so the intermediate "everything not yet built"
  list has nothing left to list. Its Settings entry was removed too.

### Performance: scoped rebuilds instead of one `context.watch` per service

Live testing on a physical device (POCO F7) found the dashboard visibly
laggy once this section landed. Root cause: `DashboardScreen` used
`context.watch<T>()` on every provider wholesale, so *any* field changing
on *any* of them rebuilt the entire screen — every `MetricCard`, every
`GridView`, the chart — regardless of whether that field was even shown.
Three services tick fast enough for this to matter: `FallDetectorService`
(every 500ms), `ActivityClassifierService` (every 1s), and, newly,
`StepCounterService` (on every single step while walking — the most
likely actual culprit, since it's the one that changed between "fine"
and "laggy"). Fixed by watching only what the screen's own layout
depends on:
- `context.select<FallDetectorService, bool>((s) => s.alertActive)` for
  the banner-or-not decision; `_FallAlertBanner` itself now watches the
  service internally (only mounted while an alert is active, so its own
  per-second rebuild is cheap and scoped).
- `context.select<ActivityClassifierService, Activity?>((s) => s.current)`
  — the screen needs the classified activity (it drives the HR
  ceiling), not the raw per-tick confidence score.
- `context.select<BaselineService, double?>((s) => s.heartRateMean)` for
  display; `context.read` for the `isAnomalous()` method call, which
  doesn't need to trigger a rebuild on its own.
- `_StepsCard` is its own small widget that watches `StepCounterService`
  directly, so a step only rebuilds that one card, not the dashboard.

`BleService` and `MetricsStore` are still watched wholesale — vitals/env
genuinely need to be live, and metrics only change on an explicit user
log action, both legitimately infrequent-or-necessary.

## Health log (implemented, local storage — no Health Connect)

The six items `HealthLogScreen` used to stub out are all real now:
blood pressure, blood glucose, insulin, medications, sleep, and Medical
ID. `lib/storage/health_log_store.dart` (a `ChangeNotifier` Hive store,
same pattern as `MetricsStore`) holds all six; `lib/screens/
metric_detail_screens.dart` gained four more thin `MetricHistoryScreen`
wrappers (blood pressure, blood glucose, insulin, sleep) and
`lib/screens/health_log_screens.dart` holds the two that don't fit that
pattern at all:

- **Blood pressure is two numbers per reading**, not one — the first
  metric that doesn't fit a single `MetricPoint` series.
  `MetricHistoryScreen` gained optional `secondaryPoints`/
  `secondaryLabel`/`secondaryColor` params: the chart draws both lines
  (systolic primary, diastolic secondary) with a small legend and a
  one-line secondary average note under the chart. The summary/
  statistics cards still describe the primary series only — a fully
  symmetric two-metric layout would roughly double the screen for this
  one caller, and systolic is the number that actually drives the
  medical urgency here anyway. `showBloodPressureDialog()`
  (`lib/widgets/log_value_dialog.dart`) is a two-field entry dialog.
- **Insulin** logs dose (the chartable `MetricPoint` value) *and* a type
  (rapid/long-acting/intermediate/mixed — a category, not a number, so
  it's captured but not charted) via `showInsulinDialog()`.
- **Medications is a list, not a metric** — `MedicationsScreen`
  (`health_log_screens.dart`) manages tracked medications (name/dosage/
  frequency) and lets the user mark a dose taken. The one genuinely
  chartable thing about medications is *adherence*, not the medications
  themselves, so "doses taken per day" gets the same
  `MetricHistoryScreen` treatment as everything else, reached via an
  app-bar action on `MedicationsScreen` rather than being its main
  focus.
- **Medical ID is a static profile, not time-series data** — there's no
  "average blood type." The underlying `MedicalIdProfile`/`saveMedicalId`
  API (still in `health_log_store.dart`) is a plain saved form (blood
  type, allergies, conditions, notes), never a `MetricHistoryScreen` — a
  chart/stats treatment would be meaningless here, not just extra work
  skipped. The standalone `MedicalIdScreen` that used to expose this has
  since been folded into `ProfileMedicalScreen` (see "Onboarding +
  categorized Settings" below) and deleted — one place to edit this
  data, not two; its Dashboard card was removed for the same reason.
- The remaining five are Dashboard cards in the same paged
  `_PagedCardGrid` as everything else — `HealthLogScreen` and its
  Settings entry are both gone; there's nothing left for an intermediate
  "more tracking" list to point to.

## AI-based insights & notifications (implemented)

A rule-based suggestion/warning layer across all three categories the
brief asked for — wellness/vitals anomalies, map/disaster events, and
tracking reminders — chosen explicitly over an on-device trained model or
LLM: it's the same "formula over black box" pattern as the wellness
score, personalized baseline, and heat index above, and there's no
labeled "should I warn this user" training data to learn from anyway.

- **`lib/domain/health_thresholds.dart`**: every clinical/reference
  threshold used anywhere in the app (HR ceiling/floor, SpO2 floor, body
  temp range, BP high/crisis, glucose range, sleep floor, AQI
  unhealthy/very-unhealthy) now lives in exactly one file, imported by
  both `DashboardScreen`'s card-level warn flags and the insight engine
  below — previously the HR ceiling logic and the SpO2/body-temp
  literals lived only in `DashboardScreen`, with no second consumer to
  keep in sync.
- **`lib/models/insight.dart`**: an `Insight` (id, title, message,
  `InsightSeverity` info/warning/critical, `InsightCategory`
  vitals/hazard/reminder, icon) — the shared type produced by the engine
  and consumed by both the Dashboard UI and the notification service.
- **`lib/domain/insight_engine.dart`**: `computeInsights(...)`, a pure
  function of live provider state → `List<Insight>`, covering:
  - *Vitals*: HR out of range or off personal baseline
    (`BaselineService.isAnomalous`), low SpO2, body temp out of range,
    blood pressure elevated/crisis, glucose out of range, short sleep.
  - *Hazards*: AQI unhealthy/very-unhealthy, flood risk (flood-prone
    state + high rain), cyclone risk (cyclone-prone state + high wind),
    nearby M4.0+ earthquake — reusing the same `DisasterService.risk`
    the Map screen already computes, not a second fetch.
  - *Reminders*: hydration (behind a time-of-day-proportional pace
    target, so it doesn't fire at 8am for not having drunk a full day's
    water yet) and medication (tracked medications with zero doses
    logged today).
- **`lib/services/notification_service.dart`**: thin wrapper around
  `flutter_local_notifications` (`^22.3.0`, API verified against the
  installed package source before use) — one Android notification
  channel, `POST_NOTIFICATIONS` runtime permission requested on init
  (Android 13+), severity mapped to `Importance`/`Priority`.
- **`lib/domain/insight_watcher_service.dart`**: a `ChangeNotifier` that
  recomputes insights whenever any input provider changes (BLE vitals,
  disaster risk, baseline, activity, health log, metrics) plus on a
  15-minute timer (needed for the reminders, which nothing else would
  trigger a recompute for). Notifies for each new or still-active
  warning/critical insight, cooled down per insight id (1 hour) so a
  persisting condition doesn't re-notify on every recompute; info-severity
  insights are shown but never push a notification. Exposes the current
  `List<Insight>` so the Dashboard can display it, not just be notified.
- **Dashboard surface**: an "Insights" card (`_InsightsSection` in
  `dashboard_screen.dart`) shows the current list — self-watches its own
  provider slice so an insight recompute doesn't rebuild the rest of the
  dashboard. Hidden entirely when there's nothing to show, rather than an
  empty-state card.

## AI-assisted medical emergency call (implemented)

Replaces `FallDetectorService`'s old dummy debugPrint stub with a real
emergency-response workflow: build a local, non-diagnostic summary from
data the app already has, call the device's emergency number, speak the
summary once the call is live, then call the saved emergency contact
(retrying up to 5 times), falling back to SMS if the contact never
answers. Triggered by both the auto-detected-fall and manual-SOS
countdowns (`FallDetectorService`), which already existed.

**Three Android platform ceilings shape the design — confirmed by
research, not implementation gaps to work around:**
1. No app — even the default dialer — can silently auto-dial the
   *emergency-services* number. Android always redirects an `ACTION_CALL`
   attempt on an emergency number to `ACTION_DIAL` (dialer pre-filled,
   user taps Call themselves), regardless of permissions held. The
   workflow's `callingEmergencyServices` state opens the dialer this way
   and proceeds once it detects the call went live — the closest
   compliant behavior, not a bug.
2. No normal app gets a precise "call answered" signal —
   `READ_PRECISE_PHONE_STATE` is system-signature-only, so only coarse
   `IDLE`/`OFFHOOK` call state is observable. "Contact answered" is
   therefore an honestly-documented heuristic
   (`EmergencyWorkflowService.answerGrace`, 6s default): off-hook
   persisting past that grace period is treated as answered; returning to
   idle first is treated as not-answered (covers rejected/failed/
   unreachable/no-answer alike). This is stated as a heuristic everywhere
   it's used — never presented as a certain "answered" fact.
3. TTS cannot be injected into a call's voice-audio path for a normal
   app — it plays acoustically over the device speaker. The workflow
   requests speakerphone (`AudioManager.isSpeakerphoneOn`, a normal audio
   API) once it believes the call is live, so the other party has the
   best chance of hearing the spoken announcement.

**Architecture** — all telephony primitives live in one hand-rolled
Kotlin channel (`MainActivity.kt`) rather than third-party call/SMS
plugins, which research found to be thin, often-unmaintained wrappers
around this exact API surface:
- `MethodChannel("com.example.health_companion/telephony")`:
  `getEmergencyNumbers()` (`TelephonyManager.getEmergencyNumberList()`,
  API 29+, falls back to `"112"`), `dialEmergencyNumber()`
  (`ACTION_DIAL`), `callContact()` (`ACTION_CALL`, a legitimate direct
  dial for a *non-emergency* number, needs `CALL_PHONE`),
  `setSpeakerphoneOn()`, `sendSms()` (`SmsManager`, needs `SEND_SMS`).
- `EventChannel("com.example.health_companion/telephony_events")`:
  `idle`/`offhook` call-state stream, version-gated
  (`TelephonyCallback`+`CallStateListener` for API 31+, `PhoneStateListener`
  below — this app's minSdk is 24) — needs `READ_PHONE_STATE`.
- `lib/services/telephony_service.dart` / `tts_service.dart`: Dart
  wrappers over the channel above and over `flutter_tts` (on-device,
  no network — the only new pub dependency this feature added).
- `lib/domain/emergency_location.dart`: a fresh, unthrottled GPS fix +
  full-address reverse-geocode (same Nominatim host/User-Agent
  convention as `DisasterService`, but its own call — that service's
  version is private, state-only, and cooldown-gated, wrong shape to
  reuse for a one-shot emergency request). Falls back to raw `"lat, lon"`
  text, then to "Location unavailable" — location never leaves the
  device except through the emergency call/contact call/SMS this feature
  itself drives.
- `lib/domain/emergency_summary_builder.dart`: builds one
  `EmergencySummary` (abnormal readings + how long each has stayed
  abnormal, computed by walking `HistoryStore.recentVitals()` backward
  against `health_thresholds.dart`'s existing shared constants +
  location + trigger reason) and three formatter functions (services
  script, contact-follow-up script, SMS text) from that single shared
  summary, so the three announcements can't drift out of wording sync.
  Falls back to a generic, explicitly non-diagnostic message when there
  isn't enough data — this app never invents a condition, only states
  measured values.
- `lib/domain/emergency_workflow_service.dart`: the `ChangeNotifier`
  state machine (`EmergencyWorkflowState`: idle → emergencyDetected →
  collectingData → gettingLocation → generatingMessage →
  callingEmergencyServices → announcingToEmergencyServices →
  waitingForEmergencyCallEnd → callingEmergencyContact/retryingContact →
  announcingToContact → smsFallback → completed, plus `failed` and
  `cancelled` as practical additions beyond the brief's suggested list).
  `start()` is a synchronous no-op while a run is already active — two
  near-simultaneous triggers collapse into one. Persists only
  `{state, attempt, triggeredAt}` to Hive after each transition, **never
  the generated scripts** (which contain the actual health values) — see
  Privacy below. On cold start, a non-terminal persisted record is
  surfaced to the UI as "a previous run didn't finish" but **not
  auto-resumed** — silently re-placing real calls after a relaunch would
  be more dangerous than helpful (see Deferred below).
- **Mock mode** (`EmergencyContactStore.mockMode`, defaults to `true`,
  requires an explicit confirmed opt-out in Settings): swaps in
  `MockTelephonyService`, which simulates the whole call/SMS flow
  (scriptable "answers on attempt N" / "never answers" via Settings) so
  the entire workflow is safely demoable without ever dialing or texting
  anything real — location and TTS still run for real in mock mode
  (both harmless) for a realistic demo. `EmergencyWorkflowService.start
  (forceMock: true)` powers Settings' "Preview emergency workflow"
  button, which always previews in mock mode regardless of the real
  setting.
- **UI**: `EmergencyCallScreen` + `EmergencyCallGate` mirror the existing
  `ImminentWarningScreen`/`ImminentWarningGate` pattern — full-screen,
  plain-language state label, the generated scripts shown for
  transparency, a Cancel action (best-effort — there's no platform API
  for a normal app to end a call it didn't place through its own in-call
  UI). `SettingsScreen`'s emergency-contact form is now really persisted
  (`EmergencyContactStore`, same Hive pattern as `HealthLogStore`).

**Privacy**: health data leaves the device only through the three
channels the workflow itself drives (the emergency call, the contact
call, the SMS) — nothing is uploaded, no cloud speech/LLM is used to
generate the announcement (all three scripts are built from local
string templates), and the operational log shown in `EmergencyCallScreen`
never contains raw vitals or the generated text, only step names.

**Deferred (MVP scope, given the demo deadline)** — noted here rather
than silently dropped:
- Auto-resume after an app process kill: the workflow surfaces an
  interrupted run instead of silently continuing it (see above) — this
  is a deliberate safety choice, not just an unfinished corner, but a
  true "pick back up exactly where it left off" resume was out of scope.
- The full formal 12-scenario test matrix from the feature's own spec:
  `test/domain/emergency_workflow_service_test.dart` covers 12 of them
  with hand-rolled fakes (`test/support/fakes.dart` — no new mocking
  dependency) exercising the real state machine — happy path, emergency
  call never connecting, no-answer/retry/answer-on-attempt-3, all 5
  attempts exhausted → SMS, location unavailable, missing CALL_PHONE/
  SEND_SMS permission, TTS failure, and duplicate simultaneous triggers.
  Not automated: on-device instrumentation of an actual process kill
  mid-run (covered only at the design level, per the point above).

## Onboarding + categorized Settings (implemented)

First launch now goes through a real flow instead of piecemeal
permission prompts scattered across whichever feature needed them
first, and Settings is now ~10 category screens instead of one
ever-growing flat list.

- **`OnboardingGate`** (`lib/domain/onboarding_gate.dart`) — outermost of
  the app's four gates (wraps `ImminentWarningGate`, which wraps
  `EmergencyCallGate`, which wraps `DashboardScreen`), same
  `_showing`-guarded push pattern as the other two, keyed on
  `!UserProfileStore.onboardingCompleted` — a one-shot condition that
  stays false forever once finished.
- **`OnboardingScreen`** (2 pages, `PopScope(canPop: false)` — mandatory
  until finished): a permissions page (rationale text per permission,
  live granted/denied status, "Continue" always enabled regardless — a
  denied permission degrades gracefully the same way it already does
  everywhere else in this app, never a hard block) and
  **`ProfileMedicalScreen`** (name/DOB/sex, weight/height, and the old
  Medical ID fields all on one form). That same screen is reused
  standalone from Settings → Profile & Medical for later edits — one
  form, two entry points, not two separate screens to keep in sync.
- **`lib/storage/user_profile_store.dart`** (new): name/DOB/sex/
  `onboardingCompleted` — deliberately doesn't duplicate weight/height
  (still `MetricsStore`, the same place the Dashboard cards read them
  from) or medical info (still `HealthLogStore.medicalId`).
- **`lib/storage/app_settings_store.dart`** (new): unit system, theme
  mode, OLED-black, ambient-sensor-source preference, and the three
  notification-category toggles — one Hive box, one document, same
  pattern as `EmergencyContactStore`. **Deliberately excluded from data
  export/import** (see below) — preference, not user data.
- **Settings home** (`lib/screens/settings_screen.dart`) is now a list of
  category tiles pushing dedicated screens under `lib/screens/settings/`:
  Profile & Medical, Units, Appearance, Data export & import, Wearable,
  Sensor precedence, Warning choices, Medical emergency (today's
  emergency-contact + hotline fields, migrated as-is), Permissions,
  Background permission, and Developer/demo (test mode + both full-screen
  preview buttons — moved out of the everyday flow).
- **Units** (`lib/domain/units.dart`): storage stays metric everywhere,
  unconditionally — these are pure display-formatting/input-parsing
  functions only, threaded into the Dashboard's Weight/Height/Hydration/
  Body-temp/Ambient-temp cards, their `MetricHistoryScreen`s, their log
  dialogs, and the Map's wind-speed row. Deliberately **not** converted
  (not part of the metric/imperial axis in most health apps): blood
  pressure, blood glucose, barometric pressure, heart rate, sleep hours,
  body fat %, steps.
- **Appearance**: Light/Dark/System (`ThemeMode`, now actually wired into
  `MaterialApp.themeMode` — previously hardcoded, defaulting to system
  with no user control at all) plus an OLED-black variant
  (`AppTheme.oledDark`, forces `surface`/`scaffoldBackgroundColor` to
  true black while keeping the existing warm accent palette, funneled
  through the same `_build()` every other appearance mode uses).
  **Material You dynamic color is a disabled "coming soon" row** — not
  wired to anything; adding it means a new `dynamic_color` dependency and
  a conditional theme graph, scoped out given the deadline.
- **Sensor precedence**: scoped to the one place the app currently has
  more than one source for the same reading — ambient temp/humidity/
  pressure (wearable BME280 vs. online weather). Everything else (heart
  rate/SpO2/body temp, GPS) has exactly one source today, so there's
  nothing else to prioritize yet; a reset button restores the default
  (prefer wearable, matching the old hardcoded behavior).
- **Warning choices**: 3 toggles matching the insight engine's existing
  categories (vitals, hazard, reminder) — `InsightWatcherService` filters
  `computeInsights()`'s output by these *before* both storing the list
  (so a disabled category disappears from the Dashboard's Insights card
  too) and before notifying. The full-screen imminent-disaster warning
  and the fall/SOS countdown are **not** covered here and can't be
  silenced — they're the safety-critical path, not a notification
  preference.
- **Permissions** (`lib/screens/settings/permissions_screen.dart`):
  read-only status (`Permission.x.status`, never `.request()` from this
  screen) for every permission the app uses, refreshed on resume; a
  "Request"/"Open app settings" action per row depending on current
  status.
- **Background permission**
  (`lib/screens/settings/background_permission_screen.dart`): a new
  `battery_optimization` Kotlin `MethodChannel` (`MainActivity.kt`, same
  convention as the existing `alarm_volume`/`telephony` channels) checks
  `PowerManager.isIgnoringBatteryOptimizations()` and can fire
  `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`. Explains plainly that
  some OEMs (Xiaomi/Huawei/etc.) also need a separate manual "autostart"
  allow this app can't request on the user's behalf.
- **Data export & import** (`lib/domain/backup_service.dart`): SAF-based
  (`saf_util` + `saf_stream` — the user picks a real destination/source
  each time, never app-internal storage) JSON export of every "user
  data" Hive box (a hardcoded canonical list — vitals/env history, body
  metrics, hydration, the Health Log boxes, emergency contact, step daily
  history, user profile), generic `{key: value}` dump per box so no
  per-box special-casing is needed. Import clears and repopulates every
  box in that list from the file, then tells the user to close and
  reopen the app — deliberately **not** attempting a live in-process
  refresh across ~6 independently-initialized stores, a much larger and
  more error-prone piece of work for a feature already scoped down.
  **Deliberately simplified, documented as roadmap, not silently
  dropped**: the export is plain-text JSON (no passphrase encryption),
  and there's no scheduled automatic backup — both would need real
  background-execution work (`workmanager`, with well-known Doze/OEM
  reliability caveats) and a key-derivation/encryption library
  (`cryptography`), out of scope for this pass.

## Background fall detection + full-screen escalation (implemented)

Fall detection and the full-screen disaster/emergency-call warnings
previously only worked while the app was in the foreground — everything
(sensor streams, the TFLite inference timer, the `Navigator`-push "gate"
pattern) was tied to a live, rebuilding widget tree. Confirmed by direct
research before building this: Android hard-stops continuous-mode sensor
delivery (accelerometer/gyroscope) to backgrounded apps on API 28+ —
there is no way to keep detecting falls in the background without a
**foreground service**.

**A fall never shows anything over the lock screen at the moment it's
detected.** It shows a high-priority *notification* first (vibration +
alarm-stream sound + an "I'm OK" action) and only escalates to bringing
the app forward — over the lock screen, if the phone is locked — after
that notification goes unanswered for 10 seconds. The app is never bound
or shown over the lock screen as a standing, app-wide setting; that
visibility is granted natively, scoped to the one Activity launch that
follows a genuine escalation, and revoked immediately after (see
`MainActivity.kt` below) — an earlier version of this feature set it
once at app startup and left it set, which meant the app could appear
over the lock screen on an ordinary relaunch with nothing wrong. The
escalation launch itself is a real Activity launch, not
`SYSTEM_ALERT_WINDOW`/"draw over other apps" — the same class of
solution alarm/calling apps use, reusing the existing screens completely
unmodified, and needing no extra "special access" permission grant.

- **`lib/ml/fall_inference.dart`**: the TFLite windowing/inference
  extracted out of `FallDetectorService` (unchanged model/threshold/
  channel order) into a small class with no `ChangeNotifier`/Provider
  dependency — used by *both* the foreground `FallDetectorService`
  (behavior unchanged) and the background task handler, so only the
  "what happens after a fall is detected" glue differs between them, not
  the model logic itself.
- **`flutter_foreground_task`** runs a persistent Android foreground
  service (`foregroundServiceType="health"`, the type Android 14 added
  specifically for continuous fitness/health sensor monitoring — this
  app's existing `ACTIVITY_RECOGNITION` permission is sufficient to
  start it, no new runtime permission needed). Manifest permissions:
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_HEALTH`, `WAKE_LOCK`,
  `VIBRATE`, plus the package's own `<service>` declaration.
- **`lib/services/notification_service.dart`**: the app's one existing
  `flutter_local_notifications` wrapper (previously used only for
  `InsightWatcherService`'s vitals/tracking notifications) gained
  `showEmergencyAlert()` on a dedicated `health_companion_emergency`
  channel, reused rather than duplicated — max importance/priority,
  `AndroidNotificationCategory.alarm` + `AudioAttributesUsage.alarm` (so
  the sound plays through the alarm audio stream, the same mechanism
  `AlarmSoundService` uses for the in-app disaster warning, rather than
  the notification stream), a custom vibration pattern, and the siren
  asset also bundled as an Android raw resource
  (`android/app/src/main/res/raw/alarm_siren.wav`, required for a custom
  notification sound — a Flutter asset alone isn't reachable from native
  notification code). This is the most a normal app is allowed to do to
  get through silent/Do Not Disturb — it deliberately does not request
  `channelBypassDnd`/notification-policy access, which would actually
  bypass DND rather than just use the alarm stream. `init()` now also
  accepts an optional `onNotificationResponse` callback, since the
  background isolate needs its own plugin instance and its own way to
  hear "I'm OK" taps (see below).
- **`lib/background/fall_detection_task_handler.dart`**: a `TaskHandler`
  running in the service's own background isolate. Owns a *second*
  `PhoneMotionService` + `FallInference` instance (both plain classes,
  reused completely unchanged) and its own `NotificationService`
  instance. On a detected fall:
  1. Calls `NotificationService.showEmergencyAlert()` — vibration +
     alarm-stream sound + an "I'm OK" action
     (`showsUserInterface: false`, so tapping it doesn't open the app).
     Does **not** wake the screen or launch anything yet.
  2. Starts a single 10-second `Timer` for the response window.
  3. Acknowledged within 10s (tapping either the action or the
     notification body — both fire the same `onDidReceiveNotification
     Response` callback) → cancels the timer and the notification.
  4. Unanswered after 10s → `FlutterForegroundTask.wakeUpScreen()` +
     `FlutterForegroundTask.launchApp('escalate_fall')`, which launches
     `MainActivity` (a plain `Intent.FLAG_ACTIVITY_NEW_TASK` launch —
     confirmed by reading the package's own native source, not assumed;
     neither this nor `wakeUpScreen()` depend on the foreground service
     actually being running) carrying a `route` extra.
  5. Also periodically (every 15 min, matching `InsightWatcherService`'s
     existing cadence) constructs a plain `DisasterService()..init()` —
     reusing 100% of its existing fetch/cache logic, zero new
     disaster-risk code — and if `risk.imminentHazards` is non-empty,
     fires the same wake+launch with `route: 'escalate_disaster'`.
     **Skips this check entirely whenever `FlutterForegroundTask.
     isAppOnForeground` is true** (the foregrounded app's own
     `DisasterService` already handles it live), and explicitly closes
     the `disaster_cache` Hive box again immediately after each check —
     see the Hive caveat below.
- **`MainActivity.kt`**: a new `escalation` channel. `onNewIntent`
  (covers a warm relaunch — `android:launchMode="singleTop"` was already
  set) and `configureFlutterEngine` (cold start) both read the launched
  intent's `route` extra via one shared `forwardEscalationRoute()` — this
  is Flutter's own "initial route" extra convention (the same one
  `FlutterForegroundTask.launchApp`/`PluginUtils.launchApp` sets), read
  directly here rather than relying on implicit Dart-side initial-route
  plumbing. That same function also calls `applyLockScreenVisibility()`
  — `setShowWhenLocked()`/`setTurnScreenOn()` on API 27+, the legacy
  `FLAG_SHOW_WHEN_LOCKED`/`FLAG_TURN_SCREEN_ON` window flags below that —
  passing `true` only when the intent actually carries an `escalate_*`
  route and `false` otherwise, on *every* launch (not just escalation
  ones), so the flag never lingers from a previous escalation into a
  later ordinary relaunch of the same (`singleTop`) Activity instance.
  The device stays locked underneath; this only draws the app's own UI
  on top of the keyguard for that one launch, the same way an incoming-
  call screen does, and dismisses nothing.
- **`lib/domain/background_escalation_gate.dart`**: listens on that
  channel. `route == 'escalate_fall'` calls `FallDetectorService.
  triggerBackgroundEscalatedCall()` — the same tail as the existing
  in-app `_triggerEmergencyCall()` (starts `EmergencyWorkflowService`,
  which then runs through `EmergencyCallGate`/`EmergencyCallScreen`
  completely unchanged), just skipping the 10-second in-app countdown
  since it already elapsed in the background. `route ==
  'escalate_disaster'` needs no special handling —
  `ImminentWarningGate` has a `WidgetsBindingObserver` that calls
  `DisasterService.refresh()` on `AppLifecycleState.resumed`, so it sees
  the fresh risk data and shows `ImminentWarningScreen` itself, the same
  way it already does for a live in-app detection. `route ==
  'escalate_demo'` calls `EmergencyWorkflowService.start(forceMock:
  true)` directly — see the demo trigger below.
- **`lib/background/background_monitoring_service.dart`**: starts/stops
  the service. Started automatically once onboarding completes (fall
  detection is a safety feature, not an opt-in extra) — Settings →
  Background permission has an explicit toggle to turn it back off,
  alongside the existing battery-optimization section.

**Developer/demo: lock-screen SOS escalation preview.** Settings →
Developer/demo has a "Trigger lock-screen SOS escalation" button
(`lib/domain/demo_escalation_trigger.dart`) for verifying the lock-screen
behavior on a real device without waiting for a real fall: it waits 10
seconds (logging a countdown via `debugPrint` each second, so the wait is
easy to verify while testing), then calls the exact same
`FlutterForegroundTask.wakeUpScreen()` + `launchApp('escalate_demo')`
pair the real fall alert uses after its own unanswered window. It never
touches `FallDetectorService`/`FallDetectionTaskHandler` or posts the
real emergency notification, and `BackgroundEscalationGate` routes
`'escalate_demo'` straight to `EmergencyWorkflowService.start(...,
forceMock: true)`, so it can never place a real call regardless of the
app's real test-mode setting — fully isolated from the real
fall-detection flow, per its own design brief.

**Documented limitations, not hidden:**
- The persistent "Monitoring for falls" notification while the service
  runs — Android does not allow hiding this, by design.
- A **narrow, deliberate duplication**: `PhoneMotionService` and
  `FallInference` each have a second live instance running in the
  background isolate, since a background task handler and the main
  UI isolate are genuinely separate Dart environments with no shared
  memory — mitigated by both being plain, dependency-free classes reused
  as-is rather than reimplemented.
- **Hive multi-isolate access** is a real, known hazard — the core fall-
  detection path is kept entirely Hive-free (confirmed: neither
  `PhoneMotionService` nor `FallDetectorService` touch Hive), and the one
  Hive-touching piece (the periodic disaster check) skips itself when the
  app is foregrounded and closes its box immediately after each check —
  a best-effort mitigation, not a guarantee, given two isolates could in
  principle still race.
- The emergency-alert notification's sound plays once per post, the
  normal Android behavior for a channel-driven notification sound — it
  does not loop the siren the way `AlarmSoundService` does for the
  in-app disaster warning. Adding that would mean running a second,
  independent audio system in the background isolate for a window
  that's already backed by vibration, sound, and (on unlock) the SOS
  screen itself; not done for this scope.
- No automated test coverage for the service/notification/Activity-
  launch integration itself — this is almost entirely platform surface
  that isn't meaningfully unit-testable (consistent with this project's
  existing precedent for other native-channel-heavy work). The one piece
  that *is* unit-tested: `FallInference`'s windowing logic
  (`test/ml/fall_inference_test.dart`).

## Roadmap (not yet implemented)

### 1. Wearable-sensor disaster heuristics

The disaster map above uses live weather + static state data, not the
wearable's own sensors yet. Two refinements once the wearable's IMU is
back (see fall-detection CNN's "on hold" state):
- **Heat-wave risk**: `lib/utils/heat_index.dart`'s formula already
  exists (built for the AI/ML wellness score above) — this item is just
  wiring it to the wearable's own `ambientTempC` + `humidity` (BME280,
  already streaming over BLE) instead of only the phone-GPS-based
  Open-Meteo call, more locally accurate for a device actually on the
  body, and thresholded per IMD heat-wave guidance for the disaster map
  specifically (vs. the dashboard's personal wellness framing).
- **Cyclone/storm risk refinement**: BME280 pressure **drop-rate** over a
  rolling window (a fast, sustained fall in hPa/hour is a classic
  pre-storm signal) as a supplementary signal alongside the map's
  wind-speed-based check.

### 2. Emergency-call hardening (see "AI-assisted medical emergency call"
above for what's already implemented)

- Real, automated process-death resume — today an interrupted run is
  surfaced to the user, not silently continued (a deliberate safety
  choice, see above), but a "pick back up with confirmation" flow would
  be more helpful than requiring a fresh manual trigger.
- The remaining scenario from the feature's own 12-scenario test spec
  (an actual on-device process kill mid-run) as an automated
  instrumentation test rather than a design-level argument only.
- Now that Medical ID is a real saved profile (see "Health log" above),
  the emergency summary could include blood type/allergies/conditions
  alongside vitals — not built yet, just newly possible.

### 3. Settings/backup hardening (see "Onboarding + categorized Settings"
above for what's already implemented)

- Passphrase encryption for exported backups (`cryptography` package —
  Argon2id/PBKDF2 key derivation + AES-GCM).
- Scheduled automatic backup (`workmanager`) — real Doze/App-Standby and
  OEM battery-manager restrictions mean this could never honestly promise
  exact timing, only "backs up periodically when the device is idle."
- Material You dynamic color (`dynamic_color` package) as an alternative
  to the app's own warm palette.
- Sensor precedence beyond the one existing multi-source case (ambient
  temp/humidity/pressure) — would need a second real multi-source sensor
  situation to exist first (e.g. a second wearable type reporting the
  same vitals).

## Repo layout

```
sih26-health-companion/
├── firmware/health_companion/   # Arduino IDE sketch (ESP32-S3, Arduino Core 3.3.11)
│   └── health_companion.ino
├── ml/                           # training pipelines (see ml/README.md)
│   ├── download_dataset.py
│   ├── prepare_windows_phone_only.py, train_fall_model_phone_only.py,
│   │   convert_to_tflite_phone_only.py   # fall detector, currently active
│   ├── prepare_windows.py, train_fall_model.py, convert_to_tflite.py  # fall detector, on hold
│   ├── download_activity_dataset.py, prepare_activity_windows.py,
│   │   train_activity_model.py, convert_activity_to_tflite.py  # activity classifier
│   └── data/                     # gitignored — regenerate by rerunning the pipelines
└── app/health_companion/        # Flutter app
    ├── assets/models/fall_detector_phone_only.tflite  # currently loaded
    ├── assets/models/fall_detector.tflite              # on hold
    ├── assets/models/activity_classifier.tflite
    ├── assets/sounds/alarm_siren.wav                   # synthesized, not downloaded
    └── lib/
        ├── main.dart
        ├── ble/{protocol.dart, ble_service.dart}
        ├── sensors/phone_motion_service.dart
        ├── ml/{fall_detector_service.dart, activity_classifier_service.dart}
        ├── services/{alarm_sound_service.dart, baseline_service.dart,
        │   step_counter_service.dart}
        ├── utils/heat_index.dart
        ├── theme/app_theme.dart
        ├── models/{sensor_reading.dart, wellness_snapshot.dart, metric_point.dart}
        ├── disaster/{disaster_service.dart, india_hazard_data.dart,
        │   hazard_type.dart, imminent_warning_gate.dart}
        ├── storage/{history_store.dart, metrics_store.dart, health_log_store.dart}
        ├── screens/
        │   ├── dashboard_screen.dart         # app's home route, no bottom nav
        │   ├── wellness_detail_screen.dart
        │   ├── metric_history_screen.dart    # generic chart+stats+period screen
        │   ├── metric_detail_screens.dart    # 9 thin per-metric wrappers around it
        │   ├── health_log_screens.dart       # Medications + Medical ID (not chart-based)
        │   ├── map_screen.dart               # pushed from a Dashboard nav card
        │   ├── settings_screen.dart          # wearable mgmt + emergency contact stub
        │   │                                  # + disaster-warning preview
        │   ├── imminent_warning_screen.dart
        │   └── scan_connect_screen.dart      # pushed route, not the home route
        └── widgets/{metric_card.dart, log_value_dialog.dart}
```
