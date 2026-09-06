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

## Roadmap (not yet implemented)

### 1. On-device CNNs for anomaly detection

Two small 1D-CNNs, trained offline in Python on public datasets, exported to
TensorFlow Lite, bundled as Flutter assets, and run via `tflite_flutter`:

- **Fall detection** (binary). Input: a sliding window of the 6 motion
  channels (~40–60 samples, 2–3s @ 20Hz), normalized per-channel. Training
  data: **SisFall** or **MobiFall** (labeled accelerometer fall/ADL traces).
  Output: fall probability → triggers the SOS flow below if it crosses a
  threshold and the user doesn't cancel within a short countdown.
- **Vitals / heat-stress anomaly** (multi-class). Input: a sliding window
  (e.g. last 2–5 minutes) of HR, SpO2, body temp, ambient temp, humidity.
  Training data: **WESAD** (wearable stress/affect, has physiological
  signals under thermal/physical stress) as a starting point, plus
  heat-index-labeled synthetic augmentation since WESAD alone won't cover
  heat-stress specifically. Output classes: normal / possible heat stress /
  possible dehydration / possible respiratory or cardiac concern.

Both models are small enough (a few conv1d layers + global pooling + dense)
to run in a few ms on a modern phone CPU via TFLite, well within an
offline-first, no-cloud-dependency constraint.

### 2. Disaster-specific heuristics (rule-based first, per team decision)

Given the time budget, disaster classification starts as **explicit
formulas**, not learned models — they're well-established, explainable, and
need no training data:

- **Heat-wave risk**: standard heat-index formula from `ambientTempC` +
  `humidity` (BME280), thresholded per IMD heat-wave guidance.
- **Cyclone/storm risk**: BME280 pressure **drop-rate** over a rolling
  window (a fast, sustained fall in hPa/hour is a classic pre-storm signal),
  combined with phone GPS to check proximity to known coastal/cyclone-prone
  regions.
- **Flood risk**: sustained high humidity + rainfall/AQI data when online,
  combined with a bundled static flood-plain layer (see maps, below) when
  offline.
- These heuristics can be replaced or augmented by a learned model later
  once labeled disaster-event sensor data is available — not a hackathon-
  timeline task.

### 3. Offline maps

`flutter_map` + `flutter_map_tile_caching` for pre-downloaded/cached raster
tiles of the demo region, overlaid with a **bundled GeoJSON hazard layer**
(flood-prone zones, heat-vulnerable areas) shipped as an app asset so the
map and hazard context work with zero connectivity. Live disaster-agency
data feeds (e.g. IMD, CWC) are an optional enhancement only when online.

### 4. SOS / emergency assistance

Since "network is icing on the cake," SOS must work over the cellular
network without data connectivity:
- `url_launcher` with `sms:` and `tel:` URIs to reach emergency contacts
  (stored locally, never synced) with the user's GPS coordinates —
  SMS/calls don't need mobile data.
- A fall or vitals-anomaly detection (from the CNNs above) triggers a
  cancellable countdown before auto-sending the SOS, so a false positive
  doesn't spam contacts.
- An online webhook/push notification path can be added later as a
  supplementary channel, never a dependency.

## Repo layout

```
sih26-health-companion/
├── firmware/health_companion/   # Arduino IDE sketch (ESP32-S3, Arduino Core 3.3.11)
│   └── health_companion.ino
└── app/health_companion/        # Flutter app
    └── lib/
        ├── main.dart
        ├── ble/{protocol.dart, ble_service.dart}
        ├── models/sensor_reading.dart
        ├── storage/history_store.dart
        ├── screens/{scan_connect_screen.dart, dashboard_screen.dart}
        └── widgets/metric_card.dart
```
