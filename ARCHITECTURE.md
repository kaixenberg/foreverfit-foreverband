# Architecture — ForeverFit (SIH '26 #26181)

## System overview

```
┌────────────────────────┐        BLE        ┌──────────────────────────────┐
│  ESP32-S3 wearable      │ ─── notify ───▶  │  Phone (Flutter app)          │
│  MAX30101 (HR/SpO2)     │                   │  - BLE central                │
│  MPU6050 (accel/gyro)   │                   │  - on-device inference (CNN)  │
│  BME280 (env)           │                   │  - local storage (Hive)       │
│  DS18B20 (body temp)    │                   │  - offline maps               │
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

Custom GATT service ("ForeverBand"), three `notify`-only characteristics
plus one `write`-only characteristic. All multi-byte fields are
**little-endian**, matching the ESP32's native order — Dart parses with
`ByteData.getX(offset, Endian.little)`. This spec is the single source
of truth; the firmware (`firmware/health_companion/health_companion.ino`) and app
(`app/health_companion/lib/ble/protocol.dart`) must be changed together.

| UUID | Name | Direction | Rate | Layout |
|---|---|---|---|---|
| `6e400001-...` | Service | — | — | — |
| `6e400002-...` | Vitals | notify | ~1 Hz | `uint32 tMs; float heartRate; float spo2; float bodyTempC; uint8 fingerPresent;` (17 bytes) |
| `6e400003-...` | Environment | notify | ~1 Hz | `uint32 tMs; float ambientTempC; float humidity; float pressureHPa;` (16 bytes) |
| `6e400004-...` | Motion | notify | ~20 Hz | `uint32 tMs; float ax,ay,az; float gx,gy,gz;` (28 bytes) |
| `6e400005-...` | Time sync | write | on connect + every 5 min | `uint8 hour,minute,second,day,month; uint16 year; uint8 weekday(0=Sun)` (8 bytes) — see "Watch faces + time sync" below |
| `6e400006-...` | Watch settings | write | on connect + on change | `uint8 selectedFace; uint8 autoCycleEnabled; uint16 autoCycleIntervalSec; uint8 use24HourFormat; uint8 dateFormat; uint8 showSeconds; uint8 ignoreBodyTempContactCheck;` (8 bytes) — see "Watch customization" below |

Motion is notified faster than the others because fall-detection needs
enough samples per window (~40–60 samples over 2–3s) to see the
free-fall-then-impact signature.

**Known limitations to fix as this evolves:**
- SpO2 is a rough, uncalibrated AC/DC ratio estimate (`110 - 25*R`), not a
  clinically valid reading — fine for a relative risk signal, not diagnosis.
- Body temperature is now a real reading — a DS18B20 on its own 1-Wire GPIO
  (`readBodyTempC()` in `health_companion.ino`), after the MAX30205 on hand
  turned out not to work. Non-blocking: conversion (~750ms) is pipelined
  across the ~1Hz vitals-notify cadence instead of stalling `loop()`, which
  also has to service BLE motion notifies at ~20Hz for fall detection.
- **HR/SpO2 are spoofed by default** (`USE_DUMMY_HR_SPO2` in
  `health_companion.ino`, on by default) — a smooth random-walk around a
  healthy resting range (65-85 bpm, 96-99% SpO2) in place of the real
  MAX30101 beat-detection algorithm's output. For demo reliability: real
  skin-contact quality/ambient light can make the real algorithm noisy on
  stage, and this trades that away
  for a guaranteed "looks like a healthy wearable" reading. **The real
  algorithm itself is untouched and still bench-tested** — only the two
  output variables (`currentBpm`/`currentSpo2`) get overridden in place,
  right before anything reads them, so flipping `USE_DUMMY_HR_SPO2` to 0
  goes straight back to the real sensor's output with no other change.
  Finger-presence detection is real either way (still driven by the
  actual IR DC baseline) — dummy mode fakes the *numbers*, not "is
  someone wearing it."

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

**Body temperature is gated on `fingerPresent`, same signal as HR/SpO2 —
plus its own developer override and a settle-time gate.** It briefly
wasn't (decoupled entirely from finger contact so a real DS18B20 reading
wouldn't disappear just because the separate MAX30101/SpO2 sensor was
down), but that let a watch lying on a table report a plausible-looking,
completely meaningless "body" temperature and warn on it. `fingerPresent`
is the only signal this firmware has for "is the watch actually on a
wrist" — the DS18B20 itself can't tell — so body temp rides on it again
by default, with two additions to keep the earlier failure mode (a broken
SpO2 sensor silently killing body temp too) from recurring:
- **`ignoreBodyTempContactCheck`** (`WatchSettingsPacket`'s last byte,
  `WatchSettings.ignoreBodyTempContactCheck` on the Dart side) — a
  developer/demo toggle, off by default, exposed on
  `DeveloperDemoScreen`. When on: `health_companion.ino`'s
  `notifyVitals()`/`drawSecondaryFace()` report/show body temp regardless
  of `fingerPresent` (gated only on `ds18b20Ok`). Pushed to the wearable
  the same way every other watch setting is — `WatchSettingsStore` ->
  `BleService.syncWatchSettings()` -> the write-only
  `CHAR_WATCH_SETTINGS_UUID` characteristic.
  On the app side, `hasBodyTempReading` (`vitals.bodyTempC != 0`) is used
  purely for *displaying* a value (dashboard card, AI chat context) —
  that part stays independent of contact, same as before. But *warning*
  on that value (`bodyTempWarn` in `dashboard_screen.dart`/
  `insight_engine.dart`/`emergency_summary_builder.dart`) additionally
  requires `bodyTempWarnEligible`: contact confirmed (or the toggle is
  on) AND `bodyTempEquilibrationWindow` (1 minute, `health_thresholds.dart`)
  has passed since `BleService.connectedAt`. So turning the toggle on
  brings body temp *back* independent of contact for display purposes,
  but — since contact can no longer be used to sanity-check it —
  `bodyTempWarnEligible` is unconditionally false whenever the toggle is
  on, i.e. the low/high body-temp warning (and the heat-stress-combination
  warning, which also reads raw `bodyTempC`) never fires while it's on.
- **`bodyTempEquilibrationWindow`** (1 minute) — the DS18B20 needs time
  after the wearable connects to reach thermal equilibrium with the
  wrist; a reading taken right at connect time tends to still read closer
  to ambient/room temperature, which would otherwise flag as a false "low
  body temperature" warning. Applies even with the contact check bypassed
  (folded into `bodyTempWarnEligible`, which both `dashboard_screen.dart`
  and `insight_engine.dart` compute the same way — kept in sync so the
  two never disagree about whether a given reading is warn-worthy).
- `ble_service.dart`: `_onVitals()` persists a vitals record when
  *either* `fingerPresent` or `bodyTempC != 0` is true (not `fingerPresent`
  alone) — still needed because the toggle can make `bodyTempC` real while
  `fingerPresent` is false. `history_store.dart`'s
  `heartRateHistory()`/`spo2History()`/`bodyTempHistory()` each filter
  their own metric's 0 back out, so a record with one signal zeroed
  doesn't plot a fake dip on the other chart.
- `emergency_summary_builder.dart`'s `_abnormalDurationText` (the walk
  over *historical* records) only checks the body-temp range when
  `bodyTemp != 0` — a missing/zero `bodyTempC` used to default to `0`,
  which is `< bodyTempLowC` and so always read as "abnormally low."

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
connection to work at all. Held-out test performance at the model's
default 0.5 cutoff: 99% accuracy, 88% fall precision, 94% fall recall —
see `ml/README.md` for the labeling fix (only windows containing the
actual impact are labeled Fall, not every window in a Fall trial) that a
live test on real hardware caught and this number reflects.

**Dialed down after the user reported it felt too sensitive**: rather
than guess, re-ran the held-out test set through the already-trained
model at several cutoffs (no retraining) and picked the threshold that
actually maximizes precision without costing recall — 0.8, not 0.5; see
`ml/README.md`'s "Threshold tuning" section for the full sweep table
(92.0% precision at the same 92.0% recall as 0.7-0.75, vs. 88.2%/93.8%
at the old 0.5). `FallInference.threshold` was raised accordingly and
stayed there.

`_consecutiveTriggersToAlert` (both `fall_detector_service.dart` and
`fall_detection_task_handler.dart`, kept in sync) was also briefly raised
from 2 to 3 alongside it, then **reverted back to 2** after the user
found real falls stopped triggering reliably — stacking an unvalidated
debounce increase on top of the already-stricter, data-backed threshold
turned out to be too much at once. See `ml/README.md` for the full
reasoning and what to do if false positives are still a problem with
just the threshold change in place.

**Still too sensitive for two specific motions — root-caused with real
drop-test data, not guessed a third time.** The user reported the
detector still fired on a quick phone pickup and on short (~1ft) falls.
Followed the note above exactly: logged real `cnnProb` from a handful
of live pickup tests instead of adjusting another number blind. The
result ruled out both existing levers at once — the CNN reports
0.999-1.000 (not borderline at all) for a quick pickup, and because
inference runs on a 3s *sliding* window, a brief jerk stays visible to
every window it's inside for the model's entire ~3s window lifetime, so
it satisfies "N consecutive triggers" the same way a longer real fall
does; one test sustained `triggeredNow=true` for all 6 possible
consecutive ticks, the maximum the window mechanics allow. Neither
`threshold` nor `_consecutiveTriggersToAlert` can fix this — it's a
genuine training-data gap (UMAFall's non-fall class likely doesn't
have enough "grab the phone fast" examples), confirmed by data.

Added `FallInference.longestFreefallRun()` as a physically-grounded
corroboration instead, alongside the CNN (not replacing it — threshold
and consecutive-count are untouched at their real-data-validated
values): the longest continuous run of near-weightless accelerometer
samples (< 0.5g resultant magnitude) in the buffered window. A phone
being picked up is being accelerated toward a hand, not dropped — it
never reads weightless. A real fall does, and the duration of that
phase is a direct physical proxy for drop height via free-fall
kinematics (`t = sqrt(2h/g)`). Only meaningful now that
`PhoneMotionService` genuinely throttles to its intended ~20Hz (see the
performance-pass section above) — the duration math assumes a real,
known sample period.

**First cut (300ms) proved too low — raised to 700ms on real evidence,
then abandoned entirely once real fall-test data showed duration was
backwards, not just mistuned.** 300ms came from an assumed ~1ft fall
(~250ms) plus a small margin. A real logcat from deliberate quick/jerky
phone handling — no fall at all — showed `freefallMs` reaching **550ms**:
a sharp deceleration right after grabbing the phone can momentarily
cancel gravity in the accelerometer's reading almost the same way true
unsupported falling does, which the kinematic estimate alone didn't
account for. Raised to 700ms on that evidence, clear margin above the
550ms handling ceiling.

A further round of real testing then measured the other side: a
confidently-classified real drop test (`cnnProb` 0.999-1.000, sustained
across the model's full ~3s window) produced only **~50ms** of
`freefallMs` — over an order of magnitude short of the 700ms gate, and
*shorter* than the 550ms handling false-positive it was meant to
reject. Duration doesn't just need retuning here — for short falls on
this device/sampling rate it's the wrong signal, backed up by the
kinematics themselves (`t = sqrt(2·0.3/9.81) ≈ 247ms` for a 1ft drop,
below what a sharp handling jerk can produce).

Replaced with `FallInference.hasPostFreefallImpact()` /
`peakImpactGAfterFreefall()`: instead of "how long was the weightless
phase," gates on "was there a hard deceleration spike right after it" —
a real fall ends by hitting the ground, a pickup ends by decelerating
gently into a hand, a signal reasoned to not be inverted for short
falls the way duration was. The impact threshold (`_impactGThreshold`
in `fall_inference.dart`, **2.0g**) was a conservative literature
default (1.5g-3g is the commonly cited range), not yet swept against
this project's own impact data.

**A third round of real testing disproved that too.** A fast phone
pickup measured `peakImpactG` up to **4.02g** — well past the 2.0g
gate — meaning a hard catch decelerates the phone just as sharply as
many real falls would. Two corroboration signals in a row, each
reasoned from real physics, each disproven by the next round of real
device data.

**Final decision, given the demo deadline and no time left to validate
a third heuristic**: dropped corroboration entirely. `FallDetectorService`
and `FallDetectionTaskHandler` now gate purely on `threshold` +
`_consecutiveTriggersToAlert` — the only piece of this pipeline
actually validated against real held-out labeled data (92%/92%).
`longestFreefallRun`/`peakImpactGAfterFreefall`/`hasPostFreefallImpact`
stay in `fall_inference.dart`, and `freefallMs`/`peakImpactG` are still
logged on every inference for visibility, just no longer gated on. This
knowingly brings back the pickup/short-fall false-positive rate —
accepted because the existing 10s "I'm OK" countdown means a false
positive costs one tap, not a real emergency call, while a missed real
fall has no equivalent recovery. `ml/README.md` has the full
before/after reasoning across all three rounds.

Given that accepted tradeoff, Settings gained a dedicated **"Fall
detection"** screen (`lib/screens/settings/fall_detection_screen.dart`):
a master on/off toggle (`AppSettingsStore.fallDetectionEnabled`,
persisted, on by default since this is a safety feature — reads through
to `FallDetectorService.start()`/`.stop()`, which now support being
toggled at runtime, not just once at app startup) and a "Trigger fall
detection demo" button (`FallDetectorService.triggerFallDemo()`) that
shows the exact same alert banner/10s-countdown/dismiss flow a real
detection would, always forced into test mode so it can never place a
real call. Deliberately separate from the existing "Background
permission" screen's own toggle, which controls only the background
foreground-service variant.

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
    Feeds the Map/Dashboard warning banner and a notification — **not**
    the full-screen imminent-disaster tier (see that section below for
    why a weather condition, however live, is a different category from
    an incoming disaster).
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
the banner's M4.5+) or >60 km/h wind in a cyclone-prone state (vs.
>40 km/h) — deliberately much rarer than the banner so it doesn't cause
alert fatigue.

Scoped to genuine **incoming disasters** only — earthquake, cyclone —
not weather *conditions*, no matter how "live" the underlying signal is.
Two things used to also trigger this full-screen tier and were both
moved down to the low-key Map/Dashboard banner instead
(`hasWarning`/`warningMessage`) plus a notification
(`lib/domain/insight_engine.dart`'s matching `hazard.*` entries):
- **>85% rain probability forecast in a flood-prone state** — a coarse
  statistical approximation, not evidence a flood is actually imminent
  right now.
- **A rapid barometric pressure fall (≥3 hPa in 3h)** — genuinely live,
  but real user feedback made the actual distinction clear: "sudden
  weather change" isn't something you evacuate or take shelter for the
  way an earthquake or cyclone is, so it doesn't belong on the same
  full-screen, alarm-and-blocked-back-button tier. It's still a real
  signal worth surfacing — a notification plus the Dashboard banner is
  the right weight for it, not a siren.

- **`ImminentWarningGate`** (`lib/disaster/imminent_warning_gate.dart`)
  wraps the whole app (`main.dart`), watches `DisasterService`, and pushes
  `ImminentWarningScreen` full-screen the moment a *new* hazard set
  crosses the threshold (deduped so it doesn't re-push on every refresh
  while the same hazard is still active).
- **`ImminentWarningScreen`** (`lib/screens/imminent_warning_screen.dart`)
  blocks the back gesture (`PopScope(canPop: false)`) — the only way out
  is the explicit "I understand" button — and shows static, bundled
  per-hazard guidance (`lib/disaster/hazard_type.dart`): Drop/Cover/Hold
  On for earthquakes, stay indoors for cyclones. Flood, storm-approaching,
  and heat-wave guidance text all still exist for the manual preview list
  below, even though none of the three currently trigger this full-screen
  tier live — flood and pressure-fall deliberately (see above), heat wave
  because `DisasterService` doesn't track a heat-index threshold as a
  hazard at all, only as a Dashboard warning.
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
  - **Entries card (edit/delete)**: every metric that supports manual
    input — weight, height, hydration, blood pressure, blood glucose,
    insulin, sleep — also gets a per-entry list below the chart, newest
    first, each row with an edit (pencil) and delete (trash) action.
    BMI/body fat/steps/heart rate have no such list — they're derived or
    sensor-read, never entered directly, so there's nothing to edit.
    Needed exposing entry *identity*, not just chart-ready `(at, value)`
    pairs: `MetricsStore`/`HealthLogStore` already wrote every log via
    Hive's `Box.add()`, which silently assigns a stable auto-incrementing
    key per entry (never reused, even across deletes) — so no storage
    migration was needed, just new read/update/delete methods
    (`entriesOfType`/`hydrationEntries`/`bloodPressureEntries`/etc.,
    returning `StoredEntry` — key + timestamp + raw field map — from
    `lib/models/stored_entry.dart`) built on two small shared private
    helpers (`_entriesOf`/`_updateEntry`/`_deleteEntry`) added to each
    store. Edit re-opens the exact same dialog used to log a new entry
    (`lib/widgets/log_value_dialog.dart`, now accepting an optional
    `initialValue`/`initialSystolic`+`initialDiastolic`/`initialDose`+
    `initialType` to pre-fill it), not a duplicate edit UI. Delete asks
    for confirmation once, generically, inside `MetricHistoryScreen`
    itself (`_confirmDelete`) rather than per metric.
  `lib/screens/metric_detail_screens.dart` has the thin per-metric
  wrappers that each just supply data + accent color + an optional "log a
  new value" action (a shared dialog for weight/height/body-fat/blood
  pressure/glucose/insulin/sleep via `lib/widgets/log_value_dialog.dart`,
  quick-add chips for hydration, nothing for steps/heart rate since
  neither is manually logged) + entries/edit/delete wiring for the
  metrics that support it. Tapping a Dashboard card now opens its history
  screen rather than a log dialog directly, so logging, editing, and
  trend-viewing all share one entry point.
- **Dashboard card layout**: Wellness overview (3 cards) is a
  horizontally scrollable row of fixed-width rectangular cards (`_CardRow`
  in `dashboard_screen.dart`) — 3-per-row `GridView`s were truncating
  labels ("Well…", "Basel…"). Body & activity (weight, height, BMI, body
  fat, hydration, blood pressure, blood glucose, insulin, sleep,
  medications, plus steps) outgrew a single row, so it's a swipeable,
  paged 2-column x 3-row grid with a dot-page indicator instead
  (`_PagedCardGrid`) — the OpenVitals dashboard-carousel pattern,
  reimplemented from scratch (AGPL, no code copied). Every card here
  opens the same generic `MetricHistoryScreen` rather than a bespoke
  inline chart.
  - **Heart rate is no longer duplicated between here and the top vitals
    grid.** It used to appear in both — deliberately, at the time (the
    vitals grid as the always-visible safety-critical one, this grid as
    the "all your stats, one consistent tap-through interaction" one) —
    but that reasoning didn't hold up once every top-vitals-grid card
    became tappable too (see below), so it was just a genuine duplicate.
    Removed from Body & activity; the top vitals grid's Heart rate card
    is now the only entry point to `HeartRateHistoryScreen`.
  - **SpO2 and Body temp are now tappable too**, each opening a new
    `MetricHistoryScreen` the same way every other vitals-grid card
    already did — `SpO2HistoryScreen`/`BodyTempHistoryScreen`
    (`metric_detail_screens.dart`), reading two new `HistoryStore`
    methods (`spo2History()`/`bodyTempHistory()`, same shape as the
    existing `heartRateHistory()` — no separate log action, since
    neither is manually entered). Before this, SpO2/Body temp were the
    only two top-vitals-grid cards with no history view at all. There
    used to be a standalone "Heart rate — recent" sparkline permanently
    on the dashboard; it's long gone now that every vitals metric
    follows the same tap-a-card-to-see-its-trend pattern instead of one
    metric getting special-cased screen space.
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
  (`health_log_screens.dart`) manages tracked medications and lets the
  user mark a dose taken. The one genuinely chartable thing about
  medications is *adherence*, not the medications themselves, so "doses
  taken per day" gets the same `MetricHistoryScreen` treatment as
  everything else, reached via an app-bar action on `MedicationsScreen`
  rather than being its main focus. See "Medications overhaul" below for
  the full model/UI/reminder rework — this bullet describes the
  screen's shape more than its current feature set.
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

## Medications overhaul (implemented)

The original `Medication` model was three free-text fields (name,
dosage, a freeform "frequency" string like "Twice daily") and a flat
list with no search/sort/filter, no active/paused concept, and no real
reminder — `insight_engine.dart`'s existing "no doses logged today" rule
is a passive, low-priority nudge checked on a 15-minute recompute cycle,
not a notification at a specific time. Overhauled after being handed a
different personal project's medication-tracking `ViewModel` (Kotlin,
Room/Hilt) as a feature-shape reference; adapted to this app's actual
architecture (Provider/`ChangeNotifier`/Hive, no per-screen ViewModel
layer) rather than ported line-for-line.

- **`Medication`** (`health_log_store.dart`) gained `type`
  (`MedicationType` — pill/capsule/drops/liquid/injection/topical/
  unspecified, a closed set so the list can filter by it), `isActive`
  (pause/resume without deleting — and without losing dose-taken
  history or having to re-enter everything to resume), `notes`, and
  `schedules` (`List<MedicationSchedule>`, each just an hour+minute —
  daily dose times, not tied to a calendar date). The old freeform
  `dosage` string later split into `amount` + `unit`, with `unit`
  offered from a per-type list (`medicationUnitsByType` — e.g. Pill(s)
  offers `pill(s)`/`mg`, Drops offers only `drops`) rather than one
  global freeform unit field, so the form can't produce a nonsense
  combination like "5 drops" on a Pill(s) entry; `Medication.dosage` is
  now a computed `'$amount $unit'` getter kept around because most
  callers (the reminder body, the list subtitle) just want one
  human-readable string and don't need the split. Reading an
  older record without a `type`/`schedules`/`isActive`/`amount`/`unit`
  key falls back to sensible defaults (`unspecified`, empty, active,
  the old flat `dosage` text as `amount` with an empty `unit`) rather
  than crashing or silently dropping data — see `_medicationFromBox`.
  `saveMedication()` replaces the old `addMedication()`: same call
  creates (no `key`) or overwrites in place (existing `key`), so an edit
  keeps its dose-taken history and reminders tied to the same record
  instead of becoming a new one.
- **`MedicationsScreen`** (`health_log_screens.dart`) is now search +
  sort (most/fewest doses per day, name A-Z/Z-A) + filter (all/active/
  paused/each type, as a horizontal chip row) + long-press multi-select
  with a contextual "N selected" app bar (select-all, bulk delete with
  a confirm dialog). Per-item actions: a prominent "mark dose taken"
  button (unchanged from before), and a kebab menu with an explicit
  "Edit" item plus pause/resume and delete; tapping the card also opens
  the edit form directly (the kebab's "Edit" item exists so that's
  discoverable without relying on an unlabeled whole-card tap being
  obvious as the edit affordance). `MedicationEditScreen` (new file)
  handles both add and edit, shown via `showDialog` as a floating panel
  rather than a full-screen route — restyled to match a screenshot
  reference from a different personal project's medication tracker
  (name field, a type dropdown, an amount+unit row where the unit list
  is coupled to the currently-selected type, notes, then a "+ Add time"
  schedule section, Cancel/Save). Name, type, amount, unit, and at
  least one dose time are all mandatory (only notes is optional) —
  enforced by disabling Save (`onPressed: null`) until
  `_isValid` is true, rather than letting a save attempt through and
  pointing out what's missing afterward; the required-field set is
  recomputed on every keystroke/schedule change via listeners on the
  name/amount controllers plus `setState` on schedule add/remove.
  Active/paused is deliberately NOT exposed there, same as the
  reference project — it's a list-level action, and a new medication
  always starts active.
- **`MedicationReminderService`** (new,
  `lib/services/medication_reminder_service.dart`) fires a notification
  when a medication's dose time is reached. Registered as a `Provider`
  in `main.dart` with `lazy: false` (nothing in the widget tree reads
  it, so it would never construct otherwise), started once at app
  launch alongside `InsightWatcherService`.
  - **It polls the clock every 20s instead of scheduling an OS alarm —
    this was NOT the first design, and the first one is worth recording
    because of how thoroughly it was debugged before being abandoned.**
    The original implementation used `flutter_local_notifications`'
    `zonedSchedule()` (`AndroidScheduleMode.inexactAllowWhileIdle` +
    `matchDateTimeComponents: DateTimeComponents.time` for a daily
    repeat, deliberately not requesting `SCHEDULE_EXACT_ALARM` — same
    "don't ask for special access a normal app doesn't need" stance as
    `showEmergencyAlert`) plus `timezone`/`flutter_timezone` for correct
    wall-clock scheduling across DST. On the actual test device (a MIUI/
    Xiaomi phone) it silently never fired. Real on-device debugging via
    `adb`/`dumpsys` at every layer — not guessing — confirmed: the Dart
    `zonedSchedule()` call succeeded; the native Android alarm fired at
    exactly the right wall-clock time (`dumpsys power`/`dumpsys alarm`
    showed the `*alarm*` wakelock and the broadcast delivered straight
    to `flutter_local_notifications`' `ScheduledNotificationReceiver`);
    the receiver ran to completion and even successfully scheduled its
    own next-day occurrence (proving no crash). The notification itself
    still never posted — no exception, no log line, nothing `adb`
    without root could see. Two distinct MIUI-specific app-ops
    restrictions were found and fixed along the way (`cmd appops get`
    showing a custom `MIUIOP` for Autostart, then a second one stuck in
    an `"ask"` state that can't actually prompt from a background
    receiver with no UI to prompt on) — neither one was the actual fix.
    Whatever was left blocking it happens silently inside MIUI's
    `NotificationManagerService` fork, with no `adb`-queryable state
    found after exhausting every standard mechanism (permissions,
    app-ops, `deviceidle` whitelist, channel dump, notification
    archive). Effectively undebuggable further from outside Xiaomi's own
    ROM. The entire alarm-based pipeline was textbook-correct and still
    didn't work — a strong signal to stop trusting AlarmManager-based
    delivery on this class of device rather than keep patching a
    mechanism whose failure mode is invisible.
  - **What replaced it**: `MedicationReminderService` keeps a
    `Timer.periodic` (20s) that re-reads `HealthLogStore.medications`
    fresh on every tick and compares each active medication's
    `MedicationSchedule.hour/minute` against `DateTime.now()`. A match
    fires `NotificationService.showMedicationReminder()` — a plain
    immediate `.show()`, the exact call `InsightWatcherService` has used
    reliably all along (confirmed via the notification archive: insight
    notifications from this device DO show up; scheduled-alarm ones
    never did). No `AlarmManager`, no background broadcast receiver,
    nothing in MIUI's battery/notification management left to silently
    intercept. `timezone`/`flutter_timezone` were removed entirely —
    `DateTime.now()` is already device-local wall-clock time, no IANA
    lookup needed once nothing is calling `zonedSchedule` anymore.
  - **The honest trade-off**: this only fires while the app's Dart
    isolate is alive (open, or recently backgrounded before Android
    kills the process) — it will not wake the phone from a fully killed
    state the way a real OS alarm would have. Given the alarm-based
    version was supposed to work in exactly that killed-app case and
    silently didn't on the actual test hardware, an approach that
    reliably fires whenever the app is running is a real improvement
    over one that promised more than this device was actually honoring.
    `_firedToday` (a `Set<String>` of `'$medicationKey#$scheduleIndex'`)
    stops the same dose time from re-notifying on every 20s tick for the
    rest of that minute; it clears when the calendar date rolls over.
  - **Reminder ids are deterministic, not sequential** —
    `NotificationService.medicationReminderId(medicationKey,
    scheduleIndex)` hashes the pair into a fixed id, offset well above
    `showInsight`'s per-session auto-incrementing counter and the fixed
    `5001` fall-alert id so none of the three id spaces can collide.
    Firing again with the same id (e.g. a stray double-tick) just
    replaces the notification instead of stacking duplicates.
  - **Respects the existing "Tracking reminders" notification
    toggle** (`AppSettingsStore.notifyReminders`, `WarningChoicesScreen`)
    — the poll is a no-op while it's off, same category hydration
    reminders already use.
  - `DeveloperDemoScreen` has a "Send test medication reminder now"
    button — fires `showMedicationReminder()` immediately on the same
    channel, useful as a quick sanity check that this channel actually
    posts on a given device without waiting for a real dose time.

## Menstrual cycle tracking (implemented)

A seventh `health_log_store.dart` entry type, added after the six
above — period start/end date, flow intensity, and free-text notes,
plus a chart and a "Cycle" Dashboard card that stays visible for every
profile rather than being conditionally hidden.

- **The meaningful date is the period's own start date, not "now."**
  Every other entry type in this store stamps `'at': DateTime.now()`
  at write time because it's always logged in the moment (sleep last
  night, a BP reading just taken); a period is often logged a day or
  more after it actually started. `addCycleEntry()`/
  `updateCycleEntry()` set `'at'` to the *given* `startDate` instead —
  a one-line difference that keeps this a drop-in fit for the same
  `_entriesOf`/`_updateEntry`/`_deleteEntry` helpers every other metric
  here already uses, rather than needing its own bespoke storage path.
- **Cycle length and period length aren't stored fields — they're
  derived.** `cycleLengthHistory()` computes the day-gap between each
  logged start and the one before it (so there's always one fewer
  point than there are entries — nothing to measure the very first
  logged period against); `periodLengthHistory()` computes start-to-end
  day counts for entries that got an end date. Kept as derived reads
  rather than fields written alongside each entry, so there's no risk
  of a stored length silently drifting out of sync with the dates it
  was computed from.
- **Chart reuses the existing two-series `MetricHistoryScreen` layout**
  (`MenstrualCycleHistoryScreen` in `metric_detail_screens.dart`) —
  cycle length as the primary series, period length as the secondary
  one, the same `secondaryPoints`/`secondaryLabel`/`secondaryColor`
  mechanism blood pressure already uses above. No new chart code
  needed at all.
- **`averageCycleLengthDays`/`predictedNextPeriod`**: a simple average
  of up to the last 6 computed cycle lengths (enough to smooth out one
  irregular cycle without old data dominating it), and the latest
  logged start plus that average — both null until there are at least
  two logged starts to derive a cycle length from. Surfaced as a small
  info card above the "Log period" button rather than added to
  `MetricHistoryScreen` itself, which has no slot for this kind of
  metric-specific summary today.
- **`showCycleEntryDialog()`** (`lib/widgets/log_value_dialog.dart`) is
  the one dialog in that file with a date picker at all, for the reason
  above — start date (required, `firstDate: DateTime(2000)`, capped at
  today), an optional end date (capped to 14 days past today, to allow
  a same-day-or-next-day log), a flow dropdown (Light/Medium/Heavy,
  optional), and a free-text notes field — same `StatefulBuilder`
  pattern `showInsulinDialog()` already established for a dialog with
  more than one input.
- **The "Cycle" card is shown to everyone, not conditionally hidden —
  a new pattern for this Dashboard grid.** Every other card in
  `_PagedCardGrid` renders unconditionally; this is the first one that
  needed a "not really applicable to you" state instead of just
  showing or omitting itself. Rather than invent a special case,
  `MetricCard` gained a generic `disabled` flag (dims the whole card via
  `Opacity`, independent of the existing `warn`/error-red state) that
  any future card could reuse. Gated on `userProfile.sex == 'Male'`
  specifically — an unset, "Other", or "Prefer not to say" profile
  still gets the real, tappable card, since a sex field alone isn't a
  reliable enough signal that cycle tracking doesn't apply. Tapping the
  disabled card doesn't silently do nothing — `onTap` still fires and
  shows a `SnackBar` explaining why, with a pointer to where to change
  it if the profile is wrong, rather than leaving a dead-looking tap.

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
- **Pick from contacts** (`MedicalEmergencyScreen`): an optional
  "Pick from contacts" button next to the name/phone fields opens
  `ContactPickerScreen` (search + tap-to-fill), backed by
  [`flutter_contacts`](https://pub.dev/packages/flutter_contacts) —
  verified as the actively-maintained current version before adding
  (2.3.1, published within the last two months). Gated behind
  `Permission.contacts` like every other permission this app requests
  (added to the shared `requestablePermissions` list in
  `app_permissions.dart`, with rationale text explaining it's optional —
  see "Onboarding + categorized Settings" above), not a separate,
  ungoverned permission path. Contacts with no phone number at all are
  filtered out of the picker (nothing useful to fill in from them);
  picking a contact fills the name/phone fields but doesn't save them —
  "Save contact" still does that, so the user can review/edit first.
  Read-only: only `READ_CONTACTS` is requested, nothing is ever written
  back to the address book.

**Privacy**: health data leaves the device only through the three
channels the workflow itself drives (the emergency call, the contact
call, the SMS) — nothing is uploaded, no cloud speech/LLM is used to
generate the announcement (all three scripts are built from local
string templates), and the operational log shown in `EmergencyCallScreen`
never contains raw vitals or the generated text, only step names. The
same holds for contacts access above: reading the address book to fill
a form is entirely on-device, nothing from it is transmitted anywhere.

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

## Loading screen + permission re-check (implemented)

`LoadingScreen` (`lib/screens/loading_screen.dart`) is now the outermost
widget in `main.dart`'s `home:`, wrapping `BackgroundEscalationGate` (and
therefore everything else) — nothing else in the app builds until it's
done.

- **Permission re-check, skipped on a genuine first launch.** Onboarding
  already has its own dedicated permission page with per-permission
  rationale (see above); asking again here *first*, with no explanation,
  before the user has even reached that page, would just be a second,
  unexplained round of system dialogs. So this only runs its check when
  `UserProfileStore.onboardingCompleted` is already true — i.e. every
  launch *after* the first. For those, it walks `requestablePermissions`
  (see below) and calls `.request()` on anything not currently granted —
  this is what notices a permission got revoked in system Settings (or by
  the OS) and asks again, without the user needing to go find it
  themselves.
- **`lib/domain/app_permissions.dart` (new)**: the `requestablePermissions`
  list — the single source of truth for *which* permissions this app
  ever requests, now shared by three places that each used to hold their
  own private copy of the same 7-permission list: this loading screen,
  `OnboardingScreen`'s `_corePermissions` (now just imports it), and
  `PermissionsScreen`'s `_trackedPermissions` map (whose keys were always
  the identical set, just not sourced from one place). Per-permission
  rationale/title text stays screen-local (onboarding's explanatory copy
  and Settings' status-row copy legitimately read differently) — only
  the enum list itself was worth unifying. Extends the standing rule from
  "Onboarding + categorized Settings" above: a new `Permission.x` now
  means adding it to this one list first, then its rationale in
  `onboarding_screen.dart` and its status row in `permissions_screen.dart`.
- **The icon is read from the OS at runtime, not bundled as a second
  Flutter asset.** A new `app_icon` Kotlin `MethodChannel`
  (`MainActivity.kt`, same convention as every other hand-rolled channel
  here) calls `packageManager.getApplicationIcon(packageName)` — already
  the fully-composited adaptive icon on API 26+ — draws it to a bitmap if
  it isn't already one, and returns PNG bytes over the channel;
  `lib/services/app_icon_service.dart` wraps the Dart side, and
  `LoadingScreen` renders it via `Image.memory`. This means changing the
  app icon (the adaptive-icon XML, the mipmap PNGs) automatically changes
  the loading screen's icon too, with nothing to keep in sync — there's
  only one icon, not a launcher copy and a Flutter-asset copy that could
  drift apart. Falls back to a plain `Icons.favorite` glyph if the
  channel call fails (e.g. a non-Android platform, or mid-fetch).

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

## Rebrand: ForeverFit/ForeverBand, logo, About, watch faces, auto-connect (implemented)

The app and wearable were renamed from "Personal Health Companion" /
"HealthCompanion" to **ForeverFit** / **ForeverBand** — user-facing
branding only (AppBar/loading-screen title, onboarding welcome copy,
Android app label, BLE device name/error text). The Dart package name
(`health_companion`) and the `HealthCompanionProtocol` class name were
deliberately **not** renamed — that would touch every `import
'package:health_companion/...'` across ~80 files for zero user-visible
benefit, pure internal-identifier churn.

- **Logo/app icon**: a hand-drawn SVG (heart outline + an EKG pulse line
  cutting through it, in the app's existing warm coral palette —
  `AppTheme`'s `primary`/`onPrimary` colors, not a new palette) rasterized
  via `rsvg-convert` to `assets/icon/icon.png` (opaque, 1024x1024) and
  `assets/icon/icon_foreground.png` (transparent, same glyph, for the
  Android adaptive-icon foreground layer). `flutter_launcher_icons`
  (dev dependency, config in `pubspec.yaml`) generates every mipmap
  density plus the `mipmap-anydpi-v26/ic_launcher.xml` adaptive-icon
  definition from those two sources — regenerate with `dart run
  flutter_launcher_icons` after changing either source image.
  **`LoadingScreen` already reads the resulting launcher icon live from
  the OS at runtime** (see "Loading screen + permission re-check" above,
  built in an earlier session specifically for this) rather than bundling
  a third copy of it — so the splash screen picked up the new logo
  automatically, no code change needed there.
- **About screen** (`lib/screens/settings/about_screen.dart`, new
  Settings category): name, the same live-from-OS icon, version (from
  `package_info_plus`), and a GitHub row — currently a disabled
  placeholder ("Not public yet"), not a real link, since there's no
  public repo yet; update it once one exists rather than leaving a dead
  link now.
- **Two OLED watch faces** (`health_companion.ino`), toggled by the
  ESP32-S3 DevKit's built-in **BOOT button** (GPIO0) — chosen because
  it's already present on every board with zero extra wiring, unlike a
  dedicated button; free to read as a normal input once past power-on,
  where its flash-mode role ends. Debounced poll in `loop()`
  (`pollBootButton()`), not an interrupt — the 1Hz OLED refresh rate
  makes that unnecessary.
  - **Primary face** (`drawPrimaryFace()`): a real `HH:MM` clock (large,
    `setTextSize(3)`), the date (`Weekday, Mon DD YYYY`), BME280 ambient
    stats (temp/humidity/pressure) at the bottom, and a small dot
    top-right standing in for a BLE-connection icon (filled = connected,
    hollow = advertising only) — an actual smartwatch-style face instead
    of a plain debug readout. Shows "--:--" and "Open the app to sync
    time" instead of a wrong/frozen clock if the wearable has never
    received a time sync (e.g. fresh boot, never yet connected to the
    phone).
  - **Secondary face** (`drawSecondaryFace()`): the detailed HR/SpO2/
    body-temp/BLE/env readout the single face used to always show —
    content unchanged, just no longer the only option.
- **Time sync, phone -> wearable** (`CHAR_TIME_UUID`, write-only, see the
  BLE protocol table above): the ESP32 has no RTC and no network access,
  so it can't know the real time/date on its own. `BleService._syncTime()`
  writes the phone's current local time once right after connecting and
  every 5 minutes after that (best-effort — a failed write doesn't fail
  the connection, the watch face just falls back to "--:--" until the
  next successful sync). Firmware stores the synced value plus the
  `millis()` timestamp of that sync (`timeSyncMillis`) and derives "now"
  by adding elapsed milliseconds on every read (`currentTime()`) — proper
  carry logic through minutes/hours/days/months/leap years (not just a
  wraparound hack), so a demo running past midnight still shows the
  right date.
- **Auto-connect on launch** (`BleService.autoConnect()`): scans (already
  filtered to the app's own service UUID at the OS level, same as the
  existing manual "Scan & Connect" flow) and connects to the first match,
  instead of requiring a manual tap every single launch. A no-op if
  already connected/connecting/scanning, or if Bluetooth is off —
  nothing silently retries in a loop in that case, matching how every
  other permission/hardware-unavailable case in this app degrades (show
  the real state, don't fake progress).
  - **First fix attempt**: the original version called this once from
    `main.dart`'s `_App` build via `addPostFrameCallback`, on the very
    first frame — raced against `FlutterBluePlus`'s adapter-state
    stream, an async round-trip to the native side not guaranteed to
    land before the first frame, and `_App` doesn't watch `BleService`
    so nothing rebuilt to retry once it did. Moved the trigger into
    `BleService`'s own constructor, listening for the adapter-state
    stream to report `on`.
  - **Still didn't reliably work — a second, deeper fix.** Reading
    `flutter_blue_plus`'s actual source (not just its public API)
    clarified the listener alone should already fire promptly on
    subscription (`adapterState`'s stream replays its current value to
    every new listener, confirmed in `flutter_blue_plus.dart`) — so the
    remaining gap was almost certainly `autoConnect()` racing a
    **not-yet-granted runtime permission** at that exact moment
    (`BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`, requested by `LoadingScreen`
    on a separate, not-strictly-ordered path) and then never retrying,
    the same *shape* of race as before at a different layer. Two
    changes: (1) `autoConnect()` now checks `Permission.bluetoothScan`/
    `Permission.bluetoothConnect` explicitly before scanning, instead of
    letting a denied permission throw into a silently-swallowed
    `catch`, and logs (`debugPrint('[BLE] autoConnect: ...')`) every
    branch it takes — a missing permission, no device found, and a
    successful connect all used to look identically like "nothing
    happened," now they're distinguishable via `flutter logs`/logcat.
    (2) `BleService` now also mixes in `WidgetsBindingObserver` and
    retries `autoConnect()` on every `AppLifecycleState.resumed` — a
    genuine retry loop (bounded by actual app-foreground events, not a
    timer) that self-heals if the very first attempt raced anything,
    permission-related or otherwise. `autoConnect()`'s own guards make
    repeated calls cheap no-ops once connected.
  - **The actual root cause — found via `adb logcat` on the user's real
    device, not guessed.** The `[BLE]` log lines from the fix above
    showed `autoConnect: scanning...` immediately followed
    (~120ms later — nowhere near the 8s scan window) by
    `autoConnect: no matching device found within timeout`, every single
    time, while a manual "Scan & Connect" moments later succeeded fine.
    Reading `flutter_blue_plus`'s own source (`FlutterBluePlus.startScan`
    in `flutter_blue_plus.dart`) explained why: **`startScan()`'s
    returned `Future` resolves the instant the scan *starts*, not when
    it ends** — the `timeout` parameter only schedules an internal
    `stopScan()` call for later; it does not make the call awaitable for
    that duration. `autoConnect()` was awaiting `startScan()` and then
    immediately checking whether a device had been found — checking
    within milliseconds of the scan actually starting, not after any
    real window to discover the wearable's advertisement. The existing
    manual-scan `startScan()` method had the exact same defect (`status`
    flipped back to `disconnected` within milliseconds of tapping
    "Scan"), it just wasn't as visible there because the scan screen
    reads the live, separately-updated `discovered` list rather than a
    single post-scan check — the underlying scan genuinely kept running
    in the background regardless of what `status` said. **Fixed in both
    methods**: after the `startScan()` call, if `FlutterBluePlus
    .isScanningNow` is still true, now `await`s
    `FlutterBluePlus.isScanning.where((s) => s == false).first` — the
    plugin's own "isScanning" stream, which only flips to `false` once
    scanning genuinely stops (either the internal timeout timer, or an
    explicit `stopScan()` call after a match is found) — before checking
    results or resetting `status`.
  - **If this still doesn't work**, the `[BLE] autoConnect: ...` log
    lines (`adb logcat` filtered to `[BLE]`, or `flutter logs`) are still
    the next debugging step — they say exactly which guard is stopping
    it, whether the scan threw, or whether it genuinely found nothing
    within the real 8-second window this time.
- **Custom app-wide font**: never the platform system font, a standing
  rule from here on per explicit user instruction.
  [Nunito](https://github.com/google/fonts/tree/main/ofl/nunito)
  (SIL Open Font License), chosen for rounded terminals matching this
  theme's existing large-radius/pill-button/circular-badge visual
  language. Bundled locally as a single variable-weight TTF
  (`assets/fonts/Nunito-Variable.ttf`, weight axis 200-1000, declared at
  several logical weights in `pubspec.yaml` pointing at the same file —
  the standard Flutter pattern for one variable font) rather than
  fetched at runtime via the `google_fonts` package, which this app's
  offline-first rule rules out. Applied once, centrally, via
  `AppTheme.fontFamily`/`ThemeData(fontFamily: ...)` — every screen
  inherits it through the theme, nothing sets a font per-widget.
- **"ForeverFit" header, made a real brand moment**: the Dashboard
  AppBar title and the loading screen's wordmark both went from the
  theme's default AppBar title style (`headlineSmall`/w800) to an
  explicit `headlineMedium`/w900 override at the call site — bigger and
  bolder than the theme default, and set directly rather than relying on
  `AppBarTheme` resolution, so the result doesn't depend on how that
  theme property happens to cascade.
- **Firmware verified with a real compile**, not just read through —
  `arduino-cli compile --fqbn esp32:esp32:esp32s3` against this repo's
  already-configured ESP32 core + libraries succeeds with no new
  warnings or errors (only two pre-existing, unrelated ones: a library-
  internal macro redefinition, and a deprecated-but-harmless
  `NimBLEService::start()` call). Still needs a real on-device flash/test
  for anything actual hardware interaction can't be verified by
  compilation alone (BOOT-button debounce feel, OLED layout at actual
  contrast/viewing angle, whether the time-sync write round-trips
  correctly over a real BLE link).

## Watch customization (implemented)

The two OLED watch faces (see "Rebrand" above) were previously
fixed-format — always 24-hour, always the same date layout, switchable
only by pressing BOOT on the wearable itself. This adds phone-side
control over how the primary face looks and how the two faces switch,
over the new `6e400006-...` characteristic (BLE protocol table above).

- **`WatchSettings`** (`lib/models/watch_settings.dart`): the six
  user-facing options — `selectedFace` (`WatchFace.primary/secondary`),
  `autoCycleEnabled`/`autoCycleIntervalSeconds` (5-60s), `use24HourFormat`,
  `dateFormat` (`WatchDateFormat`, four presets: weekday-short,
  weekday-short-with-year [default, matches the original hardcoded
  format], DD/MM/YYYY, MM/DD/YYYY), and `showSeconds`. Both enums' index
  order is **wire format**, not just a Dart implementation detail — it's
  sent as a raw byte and must stay in sync with the `switch` statements
  in `health_companion.ino`'s `WatchSettingsCallbacks`/`printDate()`.
- **`WatchSettingsStore`** (`lib/storage/watch_settings_store.dart`):
  same single-Hive-document pattern as `AppSettingsStore` — persists
  locally, does not itself talk to BLE (`BleService` owns that, so the
  store stays testable without a live connection).
- **`WatchSettingsScreen`** (`lib/screens/settings/watch_settings_screen.dart`,
  reachable from Settings → Wearable → "Watch customization" and from a
  new watch-shaped icon button in the Dashboard AppBar): every control
  writes through `WatchSettingsStore.update()` then calls
  `BleService.syncWatchSettings()` immediately if connected; if not
  connected, the change is saved and pushed automatically the next time
  `BleService.connect()` succeeds (mirrors the existing `_syncTime()`
  on-connect behavior). A stub "Check for firmware update" row (disabled,
  "Not available yet") follows this project's established stub-tile
  convention (see the About screen's GitHub row) — no OTA mechanism
  exists yet.
- **Firmware** (`health_companion.ino`): `WatchSettingsCallbacks::onWrite`
  unpacks the 7-byte `WatchSettingsPacket` into the existing
  `showSecondaryFace` toggle plus five new globals. `pollAutoCycle()`
  (called from `loop()` alongside the existing `pollBootButton()`) flips
  `showSecondaryFace` on a `millis()`-based interval when
  `autoCycleEnabled` is set; a manual BOOT press resets that same timer
  so it doesn't immediately re-flip right after a deliberate manual
  switch. `drawPrimaryFace()` now respects `use24HourFormat` (12-hour
  conversion + a small AM/PM label) and `showSecondsSetting` (switches
  from `setTextSize(3)` "HH:MM" to `setTextSize(2)` "HH:MM:SS" — the
  128px-wide OLED can't fit seconds at the larger size). `printDate()`
  (new helper) renders whichever of the four `dateFormat` presets was
  selected. Verified with a real `arduino-cli compile
  --fqbn esp32:esp32:esp32s3 --warnings all` — succeeds with no new
  warnings or errors versus the pre-existing baseline (same four
  library-internal warnings noted elsewhere in this doc).
  - **Update**: `WatchSettingsPacket` grew an 8th byte,
    `ignoreBodyTempContactCheck`, later — see "Body temperature is gated
    on `fingerPresent`" above for what it does.

## On-device AI assistant (implemented, opt-in "wow" feature)

An explicitly marketing-flavored feature, framed as such to the user
in-app: a fully offline chatbot running **Gemma 4 E2B** entirely on the
phone, via Google's [flutter_gemma](https://pub.dev/packages/flutter_gemma)
(1.7.x) + its `flutter_gemma_litertlm` engine (LiteRT-LM, `.litertlm`
format). Deliberately **E2B, not E4B**: ~2.6GB vs ~3.65GB download, and
noticeably lower peak RAM — for a demo/"wow" feature rather than a
diagnostic tool, the smaller footprint matters more than the modest
quality gap between the two sizes. Apache-2.0 and publicly downloadable
(unlike Gemma3n/EmbeddingGemma on the same platform, no Hugging Face
token is required).

- **Opt-in, not automatic**: a new Settings → "AI Assistant" category
  (`lib/screens/settings/ai_assistant_screen.dart`) shows an explicit
  warning dialog (download size, "no data ever leaves this device",
  removable any time) before anything downloads — this app's established
  pattern for anything that costs the user meaningful storage/bandwidth
  (see the background-monitoring toggle). Defaults to **Wi-Fi only**
  (`AiChatSettingsStore.wifiOnlyDownload`, overridable), checked via
  `connectivity_plus` before the download starts — flutter_gemma itself
  has no such option, so `AiChatService.downloadModel()` enforces it
  before calling into the plugin.
- **`AiChatSettingsStore`** (`lib/storage/ai_chat_settings_store.dart`):
  the usual single-Hive-document pattern, holding only the user's
  opt-in flag and the Wi-Fi-only preference. Deliberately does NOT track
  whether the model file itself is on disk — `FlutterGemma
  .isModelInstalled(modelId)` already persists that, so duplicating it
  here would just be a second source of truth that can drift.
- **`AiChatService`** (`lib/ai_chat/ai_chat_service.dart`): owns the
  plugin lifecycle — registers the `LiteRtLmEngine` once at app startup
  (cheap, no download; safe to call unconditionally like every other
  `*Service.init()` in this app), downloads with a live progress
  callback (`installModel(...).fromNetwork(url, foreground: true)
  .withProgress(...).install()` — `foreground: true` runs the ~2.6GB
  transfer as an Android foreground service so it isn't killed by
  WorkManager's 9-minute background execution limit), lazily creates the
  model + chat session on first message, and streams the reply
  token-by-token (`chat.generateChatResponseAsync()`, filtered to
  `TextResponse`) into an in-memory transcript, persisted after every
  completed turn (see "Chat history" below). A short system instruction
  tells the model it is not a doctor and to defer specifics to the app's
  real vitals/emergency features. `maxTokens: 4096` (up from an initial
  2048) to leave real room for a PDF excerpt (see "Attachments" below)
  alongside the system prompt, conversation history, and reply.
- **CPU backend, not GPU — a real on-device crash, not a guess.** The
  model session was originally created with `preferredBackend:
  PreferredBackend.gpu`. On the first real test (a Snapdragon 8s Gen 4 /
  Adreno device), sending any message crashed the whole app with a native
  `SIGSEGV` inside `libLiteRtClGlAccelerator.so` during engine creation —
  a native crash, not a catchable Dart exception, so no graceful
  in-app fallback was possible once triggered. Root-caused from the real
  crash log (`adb`-pulled tombstone), not guessed: the backtrace showed
  the segfault inside the GPU/OpenCL accelerator's engine-creation path
  (`EngineAdvancedImpl::Create` → `LiteRtClGlAccelerator`). Fixed by
  switching to `PreferredBackend.cpu` — no vendor GPU-driver dependency,
  and E2B (2B params) is small enough that CPU-only inference is still
  reasonably fast for this "wow" feature.
- **`supportImage` has to be requested at the model level, not just the
  chat level — a second real crash, on the first real image.** Sending a
  photo threw `Stream error: INVALID_ARGUMENT: Vision executor should
  not be null, please TryLoadingVisionExecutor() first.` `createChat()`
  was already passed `supportImage: true`, which looked sufficient (and
  compiled/analyzed fine — this is a runtime engine-state check, not
  something static analysis catches) but only controls whether the
  Dart-side chat object *routes* image messages through; the actual
  native vision executor is loaded by `FlutterGemma.getActiveModel(...,
  supportImage: true)` at model-creation time. Fixed by passing
  `supportImage: true` there too, alongside `preferredBackend`/
  `maxTokens`.
- **Chat history — `AiChatHistoryStore`**
  (`lib/storage/ai_chat_history_store.dart`): each conversation is a
  document (key = session id, a timestamp) in a Hive box, one-document-
  per-session like `HistoryStore`'s time-series records rather than the
  single-document-per-box pattern used by `AiChatSettingsStore` — this is
  naturally a growing collection of independent records. Stores the
  title (auto-generated from the first message's shown text, or the
  attachment filename if that message was image/PDF-only), last-updated
  timestamp, and the full message list (images inline as base64 — chat
  sessions are short-lived and few, so this stays simpler than a separate
  file store). `AiChatScreen`'s History sheet lists sessions newest-first
  and can resume or delete one. **Resuming is lazy**: loading a session
  just repopulates the in-memory transcript for display; the actual
  model-context replay (`chat.addQueryChunk()` for every prior message)
  only happens right before the *next* message is sent in that
  conversation, so browsing old chats never pays real prefill cost.
  Excluded from data export/import (`BackupService`), same reasoning as
  `AiChatSettingsStore`: chat scratch, not tracked health data.
- **Attachments — images and PDFs.** `createChat(..., supportImage:
  true)` enables Gemma 4's native vision input (it's multimodal — text,
  image, and audio — per flutter_gemma's model support table, so this
  needed no different model or a second download). A message can carry
  `List<Uint8List> images`, sent via `Message.withImages(...)` and shown
  as an inline thumbnail in both the picker preview and the sent bubble.
  **PDF is handled differently** — Gemma 4 has no native document input,
  so `lib/ai_chat/pdf_text_extractor.dart` runs `syncfusion_flutter_pdf`'s
  `PdfTextExtractor` (pure-Dart, on-device, no network call — consistent
  with this feature's offline-first framing) over the picked file and
  caps the result at `pdfExtractLengthCap` (3000 characters) given the
  small token budget above. `AiChatMessage` carries both `text` (what's
  sent to/replayed into the model — for a PDF, the caption plus the
  extracted excerpt) and an optional `displayText` (what the bubble
  actually renders — just the caption), so the raw extracted dump never
  clutters the UI; an `attachmentLabel` chip shows the filename instead.
  Images use gallery-only picking (`image_picker`, no `ImageSource
  .camera`) — deliberately, to avoid a new `CAMERA` runtime permission
  and the onboarding/Settings-Permissions-screen sync that would require,
  the night before the demo; revisit if a camera-capture flow is wanted
  later. Both `image_picker` (Android 13+ Photo Picker, backported by the
  plugin) and `file_picker` (Storage Access Framework) need **no new
  Android manifest permission** for picking.
- **Floating chat bubble** (`lib/widgets/ai_chat_bubble.dart`): a
  WhatsApp-style draggable circular button, shown only once
  `AiChatSettingsStore.enabled && AiChatService.status == ready`. Per
  explicit user request, mounted **only inside `DashboardScreen`'s own
  `body` Stack**, not globally in `MaterialApp`'s `builder:` — pushing
  `AiChatScreen` via a plain `Navigator.of(context)` now that it's a
  regular descendant of the Navigator, rather than the shared
  `rootNavigatorKey` the original global-overlay placement needed. This
  means it's naturally covered whenever any other screen is pushed on
  top (same as any other widget below the active route), so it's only
  ever visible on the main screen — no separate route-tracking logic
  needed.
  - **Positioning bug — two attempts, real root cause on the second.**
    First report from real-device testing: "way down and can barely be
    touched." First fix guessed the position math was using
    `MediaQuery.of(context).size` (the full device screen) instead of
    the Scaffold `body`'s actual (smaller) area, and wrapped the button
    in a `LayoutBuilder` to get the real area size — this compiled and
    analyzed fine, but the real-device report afterward was worse: "top
    left instead of bottom right" and "disappears permanently on switch
    from main screen." The actual bug: `Positioned` only has any effect
    as a **direct** child of a `Stack`. That `LayoutBuilder` fix returned
    `Positioned(...)` from *inside* `LayoutBuilder`'s `builder` callback
    — but `LayoutBuilder` is itself a real `RenderObjectWidget`, so it
    sits as its own node between the `Positioned` and DashboardScreen's
    outer `Stack` in the actual render tree. `Stack` only inspects the
    parent data of its own *direct* render children; seeing a plain,
    non-positioned `LayoutBuilder` node there (not something flagged
    `StackParentData.isPositioned`), it fell back to its default
    top-left alignment and sized the whole subtree to its own intrinsic
    56x56 content — `_position`'s value had **no effect on render
    position at all**, matching the "top left instead of bottom right"
    report exactly. Fixed with the standard two-`Stack` idiom for this
    exact problem: `Positioned.fill` (a direct child of the outer
    `Stack`, correctly recognized) hands `LayoutBuilder` tight
    constraints equal to the real body area; inside that, an **inner**
    `Stack` + `Positioned` places the button freely, since that inner
    `Positioned` is now a direct child of *that* Stack. `_clamp` still
    re-derives against the actual current bounds every build, so a stale
    cached `_position` is self-correcting rather than getting stuck.
    Confirmed fixed via a real-device screenshot — bottom-right, exactly
    where placed.
  - **"Disappears permanently" — a real, separate bug, root-caused via
    live `adb logcat` (not guessed a third time).** An earlier version
    hid the button while `AiChatScreen` was on top using a manually
    toggled `ValueNotifier<bool> chatScreenOpen` on `AiChatService`,
    flipped `true` in `AiChatScreen.initState()` and back to `false` in
    its `dispose()`. Instrumented `AiChatBubble` with debug logging and
    watched a live device: opening the chat screen logged `chatOpen=
    true` as expected — but after using it and navigating back to the
    Dashboard, **no `dispose()` log ever appeared, and `chatOpen` never
    flipped back to `false`**, permanently hiding the button from that
    point on. Rather than chase why `dispose()` wasn't firing reliably,
    removed the whole mechanism: now that the bubble lives *inside*
    `DashboardScreen`'s own Stack (below the Navigator) rather than
    mounted globally above it, Flutter already doesn't paint anything in
    a covered route — `AiChatScreen` (or Settings, or Map, or anything
    else) being pushed on top automatically hides the bubble along with
    the rest of the Dashboard, no flag needed. The manually-toggled
    boolean was leftover complexity from the old global-overlay
    architecture; it had become both redundant and the actual bug.
  - **In-app only** — this is not a true system-wide overlay (no
    `SYSTEM_ALERT_WINDOW`), so it's only visible while ForeverFit itself
    is in the foreground, consistent with this project's existing
    preference for narrower, Play-sanctioned mechanisms over broad
    overlay permissions (see the full-screen-intent vs.
    `SYSTEM_ALERT_WINDOW` decision in "Background fall detection"
    above).
- **`AiChatScreen`** (`lib/screens/ai_chat_screen.dart`): a plain
  message-list + text field chat UI with a persistent "fully offline"
  banner — the strongest demo beat for this feature is toggling airplane
  mode on stage and still getting a response, a concrete proof of this
  app's offline-first thesis rather than a generic "look, a chatbot"
  moment. AppBar carries History (opens the session list) and New Chat
  actions; the input row carries an attach button (photo/PDF) alongside
  send.
  - **Edit and rerun** (`AiChatService.editAndResend()`), matching
    Claude's own chat UI: a pencil icon appears next to any of the
    user's own messages (not while a reply is streaming). Tapping it
    loads the message's caption back into the input field; sending
    discards that message and everything after it (the AI's old reply
    included) and generates a fresh turn — same "close the session,
    queue the kept prefix as a replay" mechanism `loadSession` already
    uses, so the model still has the right earlier context once the
    next message actually runs. Editing the very first message
    re-triggers the health-context injection above, same as any other
    fresh first turn.
    - **Only the prompt is ever editable, not the attachment.** A
      message with an image or PDF keeps that attachment across the
      edit — `AiChatMessage` gained an `attachedText` field (the raw
      PDF-extracted content, kept separate from `text`, which already
      has it merged in with the caption) purely so editing can rebuild
      `text` from a *new* caption plus the *same* content instead of
      losing the attachment. `AiChatScreen._startEditing()` reloads the
      original message's image bytes / PDF name+text into the same
      `_pendingImage`/`_pendingPdfName`/`_pendingPdfText` fields the
      normal attach flow uses, so the existing attachment-preview chip
      just works — except its delete (×) is hidden while editing
      (`onDeleted: null`), since removing the attachment was never part
      of what "edit" means here. The attach button itself stays
      disabled throughout editing for the same reason, so there's no
      path to swap it for a different file either.
  - **Voice input (dictation, not a live voice session)**: a mic button
    in the input row uses `speech_to_text` for on-device speech
    recognition — tap to start, live partial results fill the text
    field as you talk, tap again (or the recognizer's own "done"/
    "notListening" status) to stop. Deliberately not a continuous
    conversational voice mode: the transcript lands in the input field
    for the user to review/edit like anything typed, and they still tap
    send themselves.
  - **Read aloud + copy on replies**: every non-empty, non-error
    assistant message gets a speaker and copy icon below the bubble
    (Claude's own placement, not inside the colored bubble). Speaker
    reuses the existing `TtsService` (the same on-device
    `flutter_tts` wrapper the emergency-call workflow already speaks
    announcements with — no new TTS engine) and toggles play/stop;
    starting one stops whatever was already playing, so only one
    message ever speaks at a time, and the screen's `dispose()` stops
    playback too so leaving mid-sentence doesn't leave audio running.
    Copy uses `Clipboard.setData` with a brief confirmation snackbar.
  - **Camera capture, not just the gallery picker**: the attach sheet's
    photo option is now two — "Take a photo" (`ImageSource.camera`) and
    "Photo from gallery" (`ImageSource.gallery`, as before) — both via
    `image_picker`, same as the existing gallery path.
  - **New runtime permissions — `RECORD_AUDIO` and `CAMERA`.** Unlike
    the gallery-only picker (Android Photo Picker, needs no permission)
    and the SAF-based PDF picker, both voice input and camera capture
    are genuine new dangerous permissions — added to
    `domain/app_permissions.dart` (the single source of truth this
    project's standing rule requires updating first), with rationale
    text in `onboarding_screen.dart` and status rows in
    `permissions_screen.dart`, matching the pattern documented right in
    that source file. `AndroidManifest.xml` gained the two
    `<uses-permission>` entries, an optional (`required="false"`)
    `android.hardware.camera` `<uses-feature>` (a device without a
    camera shouldn't be blocked from installing the app), and a
    `<queries>` entry for `android.speech.RecognitionService` — required
    on Android 11+'s package-visibility rules for `speech_to_text` to
    even find the on-device recognizer. Verified by re-running the
    Gradle manifest-merge task directly, same standard this project
    already holds itself to for every prior manifest change.
- **Grounded in the user's own data — `buildHealthContext()`**
  (`lib/ai_chat/health_context_builder.dart`): the first message of a
  fresh conversation gets a compact "Context:" block silently prepended
  to what's actually sent to the model (never shown in the bubble —
  same `text`/`displayText` split used for PDF attachments) — live
  wearable vitals (with the personal baseline mean from
  `BaselineService`), a bounded vitals *trend* (see below), environment,
  body metrics, today's steps, and health-log highlights (blood
  pressure, glucose, sleep, medications, Medical ID). Deliberately a
  *pure read* of stores this app already has (`BleService`,
  `HistoryStore`, `MetricsStore`, `HealthLogStore`, `BaselineService`,
  `UserProfileStore`, `StepCounterService`) — same "reuse, don't
  re-derive" approach as `emergency_summary_builder.dart`. Injected once
  per conversation (not every message) to control token cost;
  `AiChatService` takes these seven dependencies via constructor
  injection like every other multi-store service in this app
  (`EmergencyWorkflowService`, `InsightWatcherService`), which meant
  moving its own provider registration in `main.dart` to *after*
  `BaselineService`/`StepCounterService` are registered, since
  `context.read()` inside a `create:` callback can only see providers
  already built earlier in the list.
  - **Vitals trend, added after a direct exchange with the model
    exposed the gap.** The initial version was a pure current-moment
    snapshot — asked "check my HR history," the model correctly
    answered it had no such access (a good sign: it wasn't hallucinating
    a capability it didn't have), which the user then asked to actually
    add. `_trend()` pulls `HistoryStore.heartRateHistory()`/
    `spo2History()`/`bodyTempHistory()` — each now filters its own
    metric's 0/no-reading samples back out itself (a stored record can
    have one signal zeroed while the other is real, e.g. body temp
    recorded with the developer contact-check override on but no finger
    contact — see "Body temperature is gated on `fingerPresent`" above),
    filters to `healthContextTrendWindow` (6 hours — a demo-session
    length, not "all history"), and reports one avg/range/count clause
    per metric. Still a bounded *summary*, not a dump: three short
    clauses added to the context block regardless of how many thousand
    raw samples back them, so the token budget stays predictable no
    matter how long the wearable's been connected.
    - **The line is now always emitted, even when every metric comes
      back empty.** The first cut only added the "Vitals history" line
      when there was at least one real trend clause — on a device with
      no recent wearable data, that meant the *entire* line vanished, so
      the context looked identical to before this feature existed, and
      the model (accurately, but unhelpfully) fell back to a generic "I
      don't have that view" answer instead of a grounded "no readings
      recorded" one. Fixed by always adding the line — an explicit
      "no wearable readings recorded in this app's database at all yet"
      when every metric is null, so an empty database and a populated
      one both get a real, honest answer instead of the model having to
      guess which case it's in from nothing at all.
- **Android build changes**: `flutter_gemma_litertlm`'s `.litertlm` FFI
  inference requires **API 30+** and ships **arm64-v8a-only** native
  libraries — `android/app/build.gradle.kts` now hardcodes `minSdk = 30`
  (up from Flutter's own default) and restricts `ndk.abiFilters` to
  `arm64-v8a`. This raises the app's minimum Android version for
  everyone, not just this feature — accepted as a reasonable trade for a
  hackathon demo target device running a recent Android version; revisit
  if a lower API floor becomes a real requirement. `INTERNET` and
  `FOREGROUND_SERVICE_DATA_SYNC` permissions were added explicitly (the
  latter for the foreground-service download); no new *runtime*
  permission was introduced, so `permissions_screen.dart` (which only
  tracks `permission_handler`-mediated runtime permissions) needed no
  change. **A second, real-crash-driven manifest fix**: the foreground
  download itself (via `background_downloader`, which `flutter_gemma`
  uses under `foreground: true`) crashed on first real device use with
  `IllegalArgumentException: foregroundServiceType ... is not a subset
  of ... 0x00000000` — WorkManager's own `SystemForegroundService` has no
  `foregroundServiceType` declared by default, and Android 14+ requires
  one that matches the `FOREGROUND_SERVICE_DATA_SYNC` permission actually
  used. Root-caused against `flutter_gemma`'s own example app manifest
  (which documents exactly this requirement) and fixed the same way:
  `AndroidManifest.xml` now declares `xmlns:tools` and overrides that
  service with `android:foregroundServiceType="dataSync"
  tools:node="merge"`, merging the attribute onto WorkManager's
  declaration instead of replacing it. Verified by re-running the Gradle
  manifest-merge task directly (`:app:processDebugMainManifest`) and
  confirming the merged manifest actually carries the attribute — the
  same "verify the actual output, not just the input" standard as the
  firmware's real `arduino-cli compile` elsewhere in this doc.
- **Verification limits**: `flutter analyze` and the full test suite
  pass with all dependencies resolved (this caught real API-surface
  mistakes against the actual installed `flutter_gemma`/
  `flutter_gemma_litertlm`/`image_picker`/`file_picker`/
  `syncfusion_flutter_pdf` packages, the same role a real compile plays
  for the firmware elsewhere in this doc), and the Android manifest merge
  was independently verified per the fix above. `flutter_gemma_litertlm`
  ships as a Dart native-assets/FFI "hook" package — its native build
  step only runs at `flutter build`/`flutter run`, which this project's
  standing practice leaves to the user rather than done here. Two real
  on-device crashes (the GPU segfault, the foreground-service manifest
  error) were found and fixed this way already — both from real crash
  logs the user pulled and shared, not simulated — so this feature has
  had genuine on-device exercise, but not a full pass of the newest
  surface (history/attachments) yet; test with real headroom before a
  live demo.

## Performance pass: 120Hz refresh rate + sensor over-sampling fix (implemented)

Two general "the app feels laggy" fixes, both unrelated to the on-device
AI assistant (confirmed by the user — the lag predates it) and found
from concrete evidence already sitting in this session rather than
guessed.

- **120Hz stuck at 60Hz — a real, currently-unresolved Flutter/Android
  limitation on some devices, not something app code can fully
  guarantee.** Android doesn't automatically render new frames at a
  display's highest supported refresh rate — Flutter's engine happily
  draws faster, but nothing requests a higher display mode without
  asking. First fix: `flutter_displaymode`'s
  `FlutterDisplayMode.setHighRefreshRate()`, called once at startup.
  That alone didn't switch the refresh rate on this project's own test
  phone (a Xiaomi POCO, HyperOS). Researched rather than guessed
  further: this is a live, currently-open issue
  (github.com/flutter/flutter/issues/160952) affecting several
  Xiaomi/POCO models by name (the Poco F5 among them) — some Android
  OEM skins run their own refresh-rate governor on top of the standard
  API this plugin wraps, and can silently keep an app at 60Hz
  regardless of what it requests, a behavior other, much larger Flutter
  apps hit the same wall on. Two follow-ups, both real but neither a
  guaranteed fix for every device: **`DisplayModeService`**
  (`lib/services/display_mode_service.dart`) re-requests the high
  refresh rate on every app *resume*, not just once at cold start
  (`WidgetsBindingObserver.didChangeAppLifecycleState`, the same
  "retry on resume" shape already used for BLE auto-connect), since
  some OEM skins reset the preferred mode across Activity lifecycle
  transitions; and it `debugPrint`s the actual active display mode
  after each request, so a real logcat capture can show mode-by-mode
  whether the request succeeded or the OS silently overrode it. If it's
  still capped after this, the one thing confirmed to work in other
  reports of this same issue is checking the device's own **Settings >
  Display > Refresh rate** — several HyperOS/MIUI builds only apply
  their own adaptive-rate heuristic (which doesn't always promote
  regular, non-allowlisted apps) while that's left on "Default"/"Auto",
  and switching it to a fixed 120Hz/"Custom" setting is device
  configuration, not something this app's code can reach into and set
  on the user's behalf.
  - **Real on-device evidence narrowed it further.** The device's own
    Settings > Display > "High refresh rate" screen showed ForeverFit
    listed under "Based on app settings" — i.e. HyperOS confirmed it's
    *deferring* to this app's own request, not silently overriding it
    with its own governor as first suspected. A pulled logcat backed
    that up: `FlutterDisplayMode.active` consistently reported the
    window's negotiated mode as `120Hz`, correctly, across multiple
    checks. So the Android *window* mode negotiation (the part
    `flutter_displaymode` controls) is genuinely succeeding — yet the
    on-screen refresh-rate counter never rose above 60, including
    during active scrolling. That points one level deeper: the
    **Flutter engine's own frame-pacing**, not the window/OS
    negotiation, isn't actually producing frames faster, regardless of
    what mode the window is capable of — a distinct, known-harder class
    of bug than a missing API call.
  - **Two more real, reversible experiments, since the standard fix
    alone wasn't enough.** (1) `DisplayModeService` now also
    re-requests the high refresh rate via
    `WidgetsBinding.instance.addPostFrameCallback` right after the
    first frame is drawn, not just before `runApp()` — on some devices
    the window's surface isn't fully established yet at the point
    `main()` first calls it. (2) Confirmed via this app's own logcat
    (captured earlier this session: `Using the Impeller rendering
    backend (Vulkan)`) that Impeller is the active renderer — Impeller
    and the older Skia backend have entirely separate frame-pacing/
    vsync implementations, and this exact "window mode says high
    refresh, observed frames stay at 60" symptom is reported elsewhere
    specifically on Impeller. `AndroidManifest.xml`'s `<activity>` now
    carries `io.flutter.embedding.android.EnableImpeller` set to
    `false`, forcing Skia, as a genuine experiment — **not a confirmed
    fix**, and worth reverting (delete that one `<meta-data>` block) if
    it doesn't help, rather than leaving a permanent workaround for a
    problem it didn't solve. A manifest-level flag needs a real
    reinstall to take effect, not a hot reload/restart.
- **Phone motion was over-sampled, likely the real cause of periodic
  jank/laggy scrolling.** `PhoneMotionService` reads the phone's own
  accelerometer + gyroscope via `sensors_plus` at a requested ~20Hz
  (`samplingPeriod: Duration(milliseconds: 50)`) and calls
  `notifyListeners()` from `_emitIfReady()` on *every* accelerometer OR
  gyroscope event once both streams have delivered at least one. The
  bug: `samplingPeriod` is only a *hint* to the OS, not a guarantee —
  and real evidence already captured earlier this session (via
  `ActivityClassifierService`'s own `windowSpanMs` debug log) showed a
  60-sample window spanning only ~400ms of wall-clock time, not the
  ~3000ms (60 samples @ 20Hz) both `FallDetectorService` and
  `ActivityClassifierService` are trained around — meaning this
  device's actual combined accel+gyro event rate was running well
  above 100Hz, not ~20Hz. Every one of those events fired a full
  `ChangeNotifier.notifyListeners()` dispatch on the **main UI
  isolate**, directly competing with frame rendering for CPU time —
  and, independently of the jank, was quietly shrinking both ML
  models' input windows to a fraction of the real-world time span they
  were actually trained on (a live-accuracy concern, not just a
  performance one). Fixed by throttling `_emitIfReady()` to only
  actually build a sample and call `notifyListeners()` once per
  `_samplingPeriod`, regardless of how fast the underlying OS delivers
  raw sensor events — the two TFLite `Timer.periodic` inference loops
  (`FallDetectorService` @ 500ms, `ActivityClassifierService` @ 1s)
  were untouched; they were always calling `Interpreter.run()`
  synchronously on the main isolate at the *intended* cadence, so
  fixing the sample-feed rate first, which had concrete evidence behind
  it, was the safer starting point for a safety-critical fall-detection
  path than restructuring where inference itself runs. If jank persists
  after this fix, moving those two `Interpreter.run()` calls onto a
  background isolate (the same isolate-hosted execution
  `fall_detection_task_handler.dart` already uses when the app is
  backgrounded) is the next thing to try — deliberately not done
  speculatively here without on-device confirmation the first fix
  wasn't enough.
- **`android/app/build.gradle.kts` restricted to `arm64-v8a` only** —
  already true (added earlier for `flutter_gemma_litertlm`'s
  arm64-v8a-only native libraries) and reconfirmed as a standing
  instruction during this pass: never widen `ndk.abiFilters` back to
  include other ABIs without being asked.

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
