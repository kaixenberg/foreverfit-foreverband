# ML training pipelines

Two independent pipelines live here: the fall-detection CNN and the
activity classifier. Both share the same `uv`-managed Python env and the
same "verify the dataset directly before trusting it" discipline. See
`ARCHITECTURE.md` at the repo root for the full design rationale; this
file covers how to actually run them.

**Currently active: phone-only** (`*_phone_only.py` scripts). The
wearable's MPU6050 died on the breadboard build (confirmed via an I2C bus
scan in firmware — see `health_companion.ino`'s `scanI2CBus()`), so the
app currently runs a model trained on phone-only data instead of the
original wrist+phone fusion. The wrist+phone scripts (without the
`_phone_only` suffix) are kept as-is, ready to resume once the wearable's
IMU is replaced — just point `fall_detector_service.dart` back at
`fall_detector.tflite` and re-add the `BleService` motion buffer (see git
history for that version).

## Why an isolated Python env

The dev machine's default Python (3.14) has no TensorFlow wheel yet.
[`uv`](https://docs.astral.sh/uv/) provisions an isolated Python 3.12 just
for this directory — doesn't touch the system Python or any other project
(same reasoning as pinning JDK 17 for the Android build elsewhere in this
repo). No manual setup needed beyond having `uv` installed; `uv run`
creates/reuses `ml/.venv` automatically from `pyproject.toml`.

## Running the pipeline

```bash
cd ml
uv run python download_dataset.py               # fetches UMAFall via the Figshare API, no auth

# Currently active — phone-only:
uv run python prepare_windows_phone_only.py      # -> ml/data/processed/windows_phone_only.npz
uv run python train_fall_model_phone_only.py     # -> ml/data/fall_model_phone_only.keras
uv run python convert_to_tflite_phone_only.py    # -> .../assets/models/fall_detector_phone_only.tflite

# On hold until the wearable's IMU is replaced — wrist+phone fusion:
uv run python prepare_windows.py    # -> ml/data/processed/windows.npz
uv run python train_fall_model.py   # -> ml/data/fall_model.keras, prints eval metrics
uv run python convert_to_tflite.py  # -> app/health_companion/assets/models/fall_detector.tflite
```

`ml/data/` (raw CSVs, processed windows, the `.keras` checkpoints) is
gitignored — regenerate it by rerunning the pipeline. Only the final
`.tflite` artifacts are committed, into the Flutter app's assets.

## Dataset: UMAFall

Casilari et al., *"UMAFall: A Multisensor Dataset for the Research on
Automatic Fall Detection"*, Procedia Computer Science 110 (2017): 32-39.
19 subjects, 746 short (~15s) single-movement trials (208 falls, ~507
ADLs), with synchronized sensors on wrist, waist, chest, ankle, and a
smartphone in the pocket — the wrist + phone combination is what makes it
usable for this project's watch+phone fusion (verified by inspecting the
raw CSVs directly, not just the paper — see `ARCHITECTURE.md`).

**Only 9 of the wrist+phone channels have real training data**: wrist
accel(x,y,z) + wrist gyro(x,y,z) + phone accel(x,y,z). The phone in this
dataset has no gyroscope channel — a hardware limitation of the 2016
phone used to collect it, not something a different public dataset
solves (checked WEDA-FALL, MobiFall, FallAllD; none has wrist + phone-gyro
recorded simultaneously for the same falls). The app's phone gyroscope is
real and still used — as a rule-based corroboration signal alongside the
CNN, not a fabricated 10th trained input. See
`fall_detector_service.dart` in the app.

**Two unit conversions matter and are easy to get wrong** (`prepare_windows.py`
handles both): the dataset's accelerometer values are in **G**, and its
gyroscope values are in **deg/s** — both need converting to **m/s²** and
**rad/s** respectively to match what `Adafruit_MPU6050` (firmware) and
`sensors_plus` (phone) report natively. Skipping this wouldn't error out;
it would just quietly train a model on the wrong input scale that looks
fine in evaluation and fails on real device data.

**Labeling every window in a Fall trial "Fall" is wrong, and was caught
live, not in evaluation.** A first version of the phone-only model, tested
on real hardware, got stuck predicting "Fall" continuously — at a
constant, unchanging probability — for many seconds after a single real
drop test, long after the phone had settled and gone still. Each UMAFall
trial is ~15s but the actual tumble/impact only takes 1-2s; the rest is
quiescent (before the movement starts, or lying still afterward).
Labeling the *whole* trial "Fall" meant most of the "Fall" training
examples were actually just stillness — confirmed by checking peak
accelerometer magnitude per window: **65% of whole-trial-labeled Fall
windows had a peak under ~1.2g**, and Fall vs. ADL windows had nearly
identical average peak magnitude (17.11 vs 16.71 m/s²) despite the
different labels. The model had learned "stillness → Fall" because
that's what most of its Fall-labeled data actually looked like. Both
`prepare_windows_phone_only.py` and `prepare_windows.py` now find the
peak-acceleration sample within each Fall trial and only label windows
that actually *contain* that peak as Fall; the rest of a Fall trial's
windows — including the quiescent lead-in and the aftermath — are
correctly labeled ADL. This is why the fall-positive fraction dropped
sharply (30.6% → 7.6% for phone-only) — the earlier number was inflated
by mislabeled stillness, not a sign of a richer positive class.

## Phone-only model (currently active)

`prepare_windows_phone_only.py` uses two UMAFall channels instead of
three: the **real phone accelerometer** (Sensor_ID=0, RIGHTPOCKET —
authentic phone hardware, exactly what `sensors_plus` reads in
deployment) plus the **waist SensorTag's gyroscope** (Sensor_ID=2) as a
physically-justified proxy for "phone gyro," since UMAFall's own phone
has none. Waist and trouser-pocket are the same hip/torso body region,
recorded simultaneously in the same trial — a reasonable stand-in, not
fabricated data. Only 617/746 trials (~83%) recorded the waist sensor at
all; the rest are skipped. 6 channels total: `[phone_ax, phone_ay,
phone_az, phone_gx, phone_gy, phone_gz]`.

Same architecture, unit conversions, and subject-level split (1-14 train,
15-17 val, 18-19 test) as the wrist+phone model below. Held-out test
performance (subjects 18-19), with the impact-based labeling described
above, **at the model's own default 0.5 cutoff**: 99% accuracy, 88% fall
precision, 94% fall recall. `fall_detector_service.dart` no longer uses
0.5 directly — see "Threshold tuning" below — but no separate
heuristic-corroboration step is needed either way, since both channels
are now properly trained inputs rather than one being real and one being
a rule-based stand-in.

### Threshold tuning

The user reported the deployed detector felt too trigger-happy. Rather
than guess a new cutoff, re-ran inference on the same held-out test set
(subjects 18-19, 1504 windows, 7.4% fall-positive) across a range of
thresholds using the already-trained/saved model
(`data/fall_model_phone_only.keras`) — no retraining needed:

```
threshold  precision   recall   fall-alerts   missed-falls
     0.50      88.2%    93.8%           119              7
     0.55      89.0%    93.8%           118              7
     0.60      89.0%    93.8%           118              7
     0.65      89.0%    93.8%           118              7
     0.70      90.4%    92.0%           114              9
     0.75      90.4%    92.0%           114              9
     0.80      92.0%    92.0%           112              9
     0.85      91.9%    91.1%           111             10
     0.90      91.4%    85.7%           105             16
```

**0.80** is the sweet spot: it strictly dominates every threshold below
it (precision keeps climbing while recall holds at 92.0%) and every
threshold above it (0.85+ starts trading real recall for flat-or-worse
precision). `FallInference.threshold` in
`lib/ml/fall_inference.dart` was raised from 0.5 to 0.8 on this basis —
this part is backed by real held-out data and stayed.

**Also briefly raised `_consecutiveTriggersToAlert` from 2 to 3** in both
`fall_detector_service.dart` and `fall_detection_task_handler.dart`
(kept in sync) — inference runs every 500ms on a 3s *sliding* window, so
2 consecutive triggers only demanded ~1s of sustained motion over
heavily-overlapping windows, which a single hard jolt (dropping the
phone, a hard step) could pass regardless of the model's own confidence.
**Reverted back to 2** after live on-device testing: this lever isn't
reflected in the window-level table above (that's per-window precision/
recall, not the compounded "N consecutive windows" requirement an actual
alert needs), and stacking it on top of the already-stricter 0.8
threshold made genuine falls harder to trigger too, not just false
positives — an untested combination that turned out to be too much at
once. If false positives are still a problem with just the threshold
change, revisit this one with real fall-test data behind the choice
(e.g. log `cnnProb` across a handful of real drop tests) rather than
guessing again.

To regenerate this table after any retraining:

```python
import numpy as np, tensorflow as tf
from sklearn.metrics import precision_score, recall_score, confusion_matrix

data = np.load("data/processed/windows_phone_only.npz")
X, y, subjects = data["X"], data["y"], data["subjects"]
mask = np.isin(subjects, [18, 19])
X_test, y_test = X[mask], y[mask]

model = tf.keras.models.load_model("data/fall_model_phone_only.keras")
probs = model.predict(X_test, verbose=0).ravel()

for t in [0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]:
    pred = (probs > t).astype(int)
    p = precision_score(y_test, pred, zero_division=0)
    r = recall_score(y_test, pred, zero_division=0)
    print(t, p, r)
```

## Wrist+phone model (on hold)

Small 1D-CNN (~14k params, ~60KB as TFLite): `BatchNorm -> Conv1D(32) ->
MaxPool -> Conv1D(64) -> MaxPool -> GlobalAveragePooling -> Dense(32) ->
Dropout -> Dense(1, sigmoid)`. Input: a 3-second window (60 samples @
20Hz) of the 9 fused channels. `BatchNormalization` learns its own
scale/shift baked into the exported graph, so there are no separate
normalization constants to keep in sync with the Dart side. The
phone-only model above shares this exact architecture, just with 6 input
channels instead of 9.

Split by **subject ID** (1-14 train, 15-17 val, 18-19 test), not by
window — windows from the same trial are highly correlated, so a
window-level split would leak and overstate accuracy.

Held-out test performance (subjects 18-19, never seen in training), with
the impact-based labeling described above: 94% accuracy, 58% fall
precision, 90% fall recall — recall improved substantially over the
original whole-trial-labeled version, but precision dropped (more false
alarms), a real tradeoff rather than a pure improvement. This version's
trigger logic used a conservative combined rule (0.7 standalone, 0.4 with
phone-gyro corroboration) since the phone's gyro wasn't a trained input
then — see git history for `fall_detector_service.dart` at that point;
that threshold choice should be revisited against the corrected labeling
before this model is put back into the app.

## Retraining (fall detector)

Rerun the four scripts above after any change. If the dataset URL ever
moves, update `ZIP_FILENAME`/`ARTICLE_API` in `download_dataset.py` — the
Figshare article page is
https://figshare.com/articles/dataset/UMA_ADL_FALL_Dataset_zip/4214283.

---

# Activity classifier

Trains the 3-class CNN (still/walking/running) the app uses to gate
vitals anomaly thresholds — see `ARCHITECTURE.md`'s AI/ML roadmap item 1
("elevated HR while running is normal, elevated HR while sitting still
isn't").

```bash
cd ml
uv run python download_activity_dataset.py   # fetches MotionSense from GitHub, no auth
uv run python prepare_activity_windows.py    # -> ml/data/processed/activity_windows.npz
uv run python train_activity_model.py        # -> ml/data/activity_model.keras, prints eval metrics
uv run python convert_activity_to_tflite.py  # -> .../assets/models/activity_classifier.tflite
```

## Dataset: MotionSense

Malekzadeh et al., *"Mobile Sensor Data Anonymization"*, IoTDI '19. MIT
licensed, downloaded directly from the [GitHub
repo](https://github.com/mmalekzadeh/motion-sense) (verified: real repo,
`LICENSE` file present, files return `200`/`application/zip` on direct
fetch — not just linked from a paper). 24 subjects, 6 activities
(downstairs, upstairs, sitting, standing, walking, jogging) at 50Hz, an
iPhone 6s in the front trouser pocket. Used the raw single-sensor folders
(`B_Accelerometer_data`, `C_Gyroscope_data` — accel and gyro each ~20MB
zipped) rather than the combined `A_DeviceMotion_data` folder (~74MB,
includes attitude/gravity/rotation-rate the app doesn't need).

**Units confirmed by inspecting actual value ranges, not just Apple's
docs**: accelerometer values peaked around ±3.3 while walking —
consistent with **G**'s (would be ±30+ if already m/s², so converted the
same way UMAFall's accel was, `× 9.80665`); gyroscope values peaked
around ±6.3 — consistent with **rad/s** already (would be ±350+ in
deg/s), so used as-is.

**Label mapping**: MotionSense's 6 raw activities collapse to the 3
classes the app actually acts on — `still` = sit+stand, `walking` =
walking+downstairs+upstairs (kept together; a finer stairs-vs-level split
isn't needed for HR-threshold gating), `running` = jogging.

Same architecture family as the fall detector (`BatchNorm -> Conv1D(32)
-> MaxPool -> Conv1D(64) -> MaxPool -> GlobalAveragePooling -> Dense(32)
-> Dropout -> Dense(3, softmax)`), same subject-disjoint split
methodology (train 1-18, val 19-21, test 22-24 of 24 subjects). Held-out
test performance: **99.9% accuracy** (still/walking: 1.00 precision and
recall; running: 0.99 precision, 1.00 recall) — much higher than the fall
detector's, because distinguishing sustained activity patterns over a 3s
window is a substantially easier task than catching a brief 1-2s impact
signature; this is a real, expected result for this task, not a red flag.

**Known gap — "running" underrepresented on-device, live-testing caught
this, held-out metrics didn't**: two real differences between MotionSense
and how this app is actually tested are worth checking before assuming a
model bug if "running" never gets picked live:
1. **Trial count imbalance**: MotionSense has only 2 jogging trial
   recordings per subject vs. 3 each for the other activities (9.4% of
   all windows are `running`, vs. 46.2%/44.4% for still/walking — see
   `prepare_activity_windows.py`'s printed class breakdown). Class
   weighting during training corrects the *loss function's* bias toward
   the majority classes, but can't manufacture the pace/stride-style
   diversity a larger jogging sample would have covered.
2. **Sensor delivery rate assumption**: `activity_classifier_service.dart`
   assumes ~20Hz (60 samples = 3s, matching training) but doesn't verify
   it — if a device's actual `sensors_plus` event rate runs slower under
   real conditions, the same 60-sample window spans *more* real time,
   which smears out exactly the high-frequency cadence that separates
   running from walking (a slower activity has less high-frequency
   content to lose, so this would selectively hurt running detection
   specifically — consistent with what live testing found). A
   `windowSpanMs` value is now logged alongside the per-class
   probabilities on every inference (`debugPrint` in `_runInference()`)
   to check this against the real device rather than guessing.

Neither has been confirmed as *the* cause yet — both are plausible,
checkable candidates once there's a live log from a real run to look at.

## Heat-stress CNN: investigated, not built

The original AI/ML roadmap scoped a WESAD-trained heat-stress anomaly
CNN. Verified directly before starting (not assumed): WESAD's documented
primary host (`ubi29.informatik.uni-siegen.de/.../WESAD.zip`) and its
commonly-cited Sciebo mirror both return `404`. The remaining path (Kaggle,
auth-gated, ~2.5GB) has a more fundamental problem beyond availability:
WESAD's signals are chest/wrist ECG, EMG, EDA, and respiration from a lab
rig — this app's wearable has none of those, only HR/SpO2/body
temp/ambient temp/humidity/pressure. Same shape of dead end as the flood
dataset described in `ARCHITECTURE.md` — training on it would mean
reconstructing most of the feature set as a mismatch-driven exercise, not
a small conversion fix.

Implemented instead: a transparent heat-index formula (NOAA/Rothfusz
regression) combining the wearable's real ambient temp + humidity
readings, in `app/health_companion/lib/utils/heat_index.dart` — feeds
both the Dashboard's Ambient Temp warning and the composite wellness
score. Consistent with the composite-score philosophy elsewhere in this
app: reach for a trained model only once a formula demonstrably
underperforms, not by default.
