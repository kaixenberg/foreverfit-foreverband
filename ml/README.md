# Fall-detection model training pipeline

Trains the CNN used by the app's on-device fall detector. See
`ARCHITECTURE.md` at the repo root for the full design rationale; this
file covers how to actually run it.

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
above: **99% accuracy, 88% fall precision, 94% fall recall**.
`fall_detector_service.dart` uses a plain `cnnProb > 0.5` threshold
(matching the evaluation above) — no separate heuristic corroboration
step needed, since both channels are now properly trained inputs rather
than one being real and one being a rule-based stand-in.

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

## Retraining

Rerun the four scripts above after any change. If the dataset URL ever
moves, update `ZIP_FILENAME`/`ARTICLE_API` in `download_dataset.py` — the
Figshare article page is
https://figshare.com/articles/dataset/UMA_ADL_FALL_Dataset_zip/4214283.
