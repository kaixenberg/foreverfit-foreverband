"""Build training windows for the activity classifier from the MotionSense
dataset (Malekzadeh et al., MIT licensed — see ml/README.md for how it was
verified before use: real GitHub repo, MIT LICENSE file, raw accel/gyro
CSVs directly downloadable, units confirmed by inspecting actual value
ranges, not just docs).

Source layout (data/raw_activity/, gitignored, fetched by
download_activity_dataset.py):
    accel/B_Accelerometer_data/{activity}_{trial}/sub_{subject}.csv  (x,y,z)
    gyro/C_Gyroscope_data/{activity}_{trial}/sub_{subject}.csv       (x,y,z)
24 subjects, 6 raw activities (dws/ups/sit/std/wlk/jog) at 50Hz, iPhone in
front trouser pocket.

Channel order in the output (must match the Flutter-side inference tensor
exactly — see app/health_companion/lib/ml/activity_classifier_service.dart):
    [phone_ax, phone_ay, phone_az, phone_gx, phone_gy, phone_gz]
Same convention as the fall detector: raw (gravity-included) accelerometer,
in m/s^2 and rad/s — matching what sensors_plus reports on the phone.

Units, confirmed by inspecting actual value ranges (not just Apple's docs):
  - accel (folder B, CMAccelerometer): values up to ~3.3 in magnitude while
    walking — consistent with G's (would be ~30+ if already m/s^2), so
    converted the same way UMAFall's accel was (x * 9.80665).
  - gyro (folder C, CMGyroscope): values up to ~6.3 while walking —
    consistent with rad/s (would be ~350+ if degrees/s), so used as-is,
    no conversion needed.

Label mapping: MotionSense's 6 raw activities are collapsed to the 3
classes the app actually acts on (see ARCHITECTURE.md's activity-gating
use case — "elevated HR while running is normal, elevated HR while
sitting still isn't"):
    still   = sit, std
    walking = wlk, dws, ups   (stairs kept with walking, not split out —
                                same broad "upright locomotion" gesture
                                signature; a finer stairs-vs-level split
                                isn't needed for HR-threshold gating)
    running = jog
"""

import re
from pathlib import Path

import numpy as np
import pandas as pd

RAW_DIR = Path(__file__).parent / "data" / "raw_activity"
ACCEL_DIR = RAW_DIR / "accel" / "B_Accelerometer_data"
GYRO_DIR = RAW_DIR / "gyro" / "C_Gyroscope_data"
OUT_DIR = Path(__file__).parent / "data" / "processed"

G_TO_MS2 = 9.80665
SRC_RATE_HZ = 50.0

RATE_HZ = 20.0  # matches PhoneMotionService's sampling rate
WINDOW_SEC = 3.0
WINDOW_LEN = int(WINDOW_SEC * RATE_HZ)  # 60
STRIDE = WINDOW_LEN // 2  # 30, 50% overlap

LABEL_MAP = {
    "sit": "still",
    "std": "still",
    "wlk": "walking",
    "dws": "walking",
    "ups": "walking",
    "jog": "running",
}
CLASSES = ["still", "walking", "running"]
CLASS_TO_IDX = {c: i for i, c in enumerate(CLASSES)}

TRIAL_DIR_RE = re.compile(r"^(dws|ups|sit|std|wlk|jog)_(\d+)$")


def resample_to_grid(t_src: np.ndarray, values: np.ndarray, t_grid: np.ndarray) -> np.ndarray:
    out = np.empty((len(t_grid), values.shape[1]), dtype=np.float64)
    for i in range(values.shape[1]):
        out[:, i] = np.interp(t_grid, t_src, values[:, i])
    return out


def process_trial(accel_path: Path, gyro_path: Path, activity: str, subject_id: int):
    accel_df = pd.read_csv(accel_path)
    gyro_df = pd.read_csv(gyro_path)

    accel = accel_df[["x", "y", "z"]].to_numpy()
    gyro = gyro_df[["x", "y", "z"]].to_numpy()

    t_accel = np.arange(len(accel)) * (1000.0 / SRC_RATE_HZ)
    t_gyro = np.arange(len(gyro)) * (1000.0 / SRC_RATE_HZ)

    t_end = min(t_accel[-1], t_gyro[-1])
    if t_end < WINDOW_SEC * 1000:
        return None

    n_samples = int(t_end / 1000.0 * RATE_HZ)
    t_grid = np.arange(n_samples) * (1000.0 / RATE_HZ)

    a = resample_to_grid(t_accel, accel, t_grid) * G_TO_MS2
    g = resample_to_grid(t_gyro, gyro, t_grid)  # already rad/s

    fused = np.concatenate([a, g], axis=1)  # (n_samples, 6)

    label_idx = CLASS_TO_IDX[LABEL_MAP[activity]]
    windows = []
    for start in range(0, n_samples - WINDOW_LEN + 1, STRIDE):
        windows.append(fused[start : start + WINDOW_LEN])

    if not windows:
        return None
    return subject_id, label_idx, np.stack(windows)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    trial_dirs = sorted(d for d in ACCEL_DIR.iterdir() if d.is_dir())
    print(f"Found {len(trial_dirs)} trial directories in {ACCEL_DIR}")

    all_windows, all_labels, all_subjects = [], [], []
    skipped = 0
    n_trials = 0

    for accel_trial_dir in trial_dirs:
        m = TRIAL_DIR_RE.match(accel_trial_dir.name)
        if not m:
            continue
        activity = m.group(1)
        gyro_trial_dir = GYRO_DIR / accel_trial_dir.name
        if not gyro_trial_dir.is_dir():
            continue

        for accel_path in sorted(accel_trial_dir.glob("sub_*.csv")):
            subject_id = int(accel_path.stem.split("_")[1])
            gyro_path = gyro_trial_dir / accel_path.name
            if not gyro_path.exists():
                skipped += 1
                continue

            n_trials += 1
            result = process_trial(accel_path, gyro_path, activity, subject_id)
            if result is None:
                skipped += 1
                continue
            subj, label_idx, windows = result
            all_windows.append(windows)
            all_labels.append(np.full(len(windows), label_idx, dtype=np.int64))
            all_subjects.extend([subj] * len(windows))

    X = np.concatenate(all_windows, axis=0).astype(np.float32)
    y = np.concatenate(all_labels, axis=0).astype(np.int64)
    subjects = np.array(all_subjects, dtype=np.int64)

    print(f"Processed {n_trials - skipped}/{n_trials} trial files ({skipped} skipped)")
    print(f"Windows: {X.shape}")
    for i, cls in enumerate(CLASSES):
        print(f"  {cls}: {(y == i).sum()} ({(y == i).mean() * 100:.1f}%)")
    print(f"Subjects present: {sorted(set(subjects.tolist()))}")

    out_path = OUT_DIR / "activity_windows.npz"
    np.savez(out_path, X=X, y=y, subjects=subjects)
    print(f"Saved to {out_path}")


if __name__ == "__main__":
    main()
