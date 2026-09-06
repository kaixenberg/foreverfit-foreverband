"""Parse UMAFall trial CSVs into fixed-length, unit-corrected, labeled windows.

Channel order in the output (must match the Flutter-side inference tensor
exactly — see app/health_companion/lib/ml/fall_detector_service.dart):
    [wrist_ax, wrist_ay, wrist_az, wrist_gx, wrist_gy, wrist_gz,
     phone_ax, phone_ay, phone_az]

Unit conversions (verified against actual data, not just docs — see
ARCHITECTURE.md and the plan for how these were found):
  - accel: dataset is in G -> multiplied by 9.80665 to get m/s^2
  - gyro:  dataset is in deg/s -> multiplied by pi/180 to get rad/s
This matches what Adafruit_MPU6050 (firmware) and sensors_plus (phone) both
report natively, so no unit conversion is needed at inference time.

Each UMAFall CSV is one short (~15s) discrete trial of a single labeled
movement (filename encodes subject/label/activity/trial) — not a long
continuous log — so every window extracted from a trial inherits that
trial's whole-file label.
"""

import re
from pathlib import Path

import numpy as np
import pandas as pd

RAW_DIR = Path(__file__).parent / "data" / "raw"
OUT_DIR = Path(__file__).parent / "data" / "processed"

G_TO_MS2 = 9.80665
DEG_TO_RAD = np.pi / 180.0

RATE_HZ = 20.0
WINDOW_SEC = 3.0
WINDOW_LEN = int(WINDOW_SEC * RATE_HZ)  # 60
STRIDE = WINDOW_LEN // 2  # 30, i.e. 50% overlap

WRIST_ID = 3
PHONE_ID = 0
TYPE_ACCEL = 0
TYPE_GYRO = 1

COLUMNS = ["timestamp_ms", "sample_no", "x", "y", "z", "sensor_type", "sensor_id"]

FILENAME_RE = re.compile(
    r"UMAFall_Subject_(\d+)_(ADL|Fall)_(.+)_(\d+)_\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.csv"
)


def parse_trial(path: Path) -> pd.DataFrame | None:
    rows = []
    with open(path, "r", errors="replace") as f:
        for line in f:
            if not line or not line[0].isdigit():
                continue  # skip '%' comment lines and blanks
            parts = line.strip().rstrip(";").split(";")
            if len(parts) < 7:
                continue
            try:
                rows.append([float(p) for p in parts[:7]])
            except ValueError:
                continue
    if not rows:
        return None
    return pd.DataFrame(rows, columns=COLUMNS)


def extract_channel(df: pd.DataFrame, sensor_id: int, sensor_type: int):
    sub = df[(df.sensor_id == sensor_id) & (df.sensor_type == sensor_type)]
    sub = sub.sort_values("timestamp_ms")
    return sub["timestamp_ms"].to_numpy(), sub[["x", "y", "z"]].to_numpy()


def resample_to_grid(t_src: np.ndarray, values: np.ndarray, t_grid: np.ndarray) -> np.ndarray:
    out = np.empty((len(t_grid), values.shape[1]), dtype=np.float64)
    for i in range(values.shape[1]):
        out[:, i] = np.interp(t_grid, t_src, values[:, i])
    return out


def process_trial(path: Path):
    m = FILENAME_RE.match(path.name)
    if not m:
        return None
    subject_id = int(m.group(1))
    is_fall_trial = m.group(2) == "Fall"

    df = parse_trial(path)
    if df is None:
        return None

    t_wrist_a, wrist_accel = extract_channel(df, WRIST_ID, TYPE_ACCEL)
    t_wrist_g, wrist_gyro = extract_channel(df, WRIST_ID, TYPE_GYRO)
    t_phone_a, phone_accel = extract_channel(df, PHONE_ID, TYPE_ACCEL)

    if len(t_wrist_a) < 5 or len(t_wrist_g) < 5 or len(t_phone_a) < 5:
        return None  # a required channel is missing/corrupt for this trial

    t_start = max(t_wrist_a[0], t_wrist_g[0], t_phone_a[0])
    t_end = min(t_wrist_a[-1], t_wrist_g[-1], t_phone_a[-1])
    if t_end - t_start < WINDOW_SEC * 1000:
        return None  # too short once trimmed to the overlapping time range

    n_samples = int((t_end - t_start) / 1000.0 * RATE_HZ)
    t_grid = t_start + np.arange(n_samples) * (1000.0 / RATE_HZ)

    wa = resample_to_grid(t_wrist_a, wrist_accel, t_grid) * G_TO_MS2
    wg = resample_to_grid(t_wrist_g, wrist_gyro, t_grid) * DEG_TO_RAD
    pa = resample_to_grid(t_phone_a, phone_accel, t_grid) * G_TO_MS2

    fused = np.concatenate([wa, wg, pa], axis=1)  # (n_samples, 9)

    # Each trial is ~15s but the actual tumble/impact only takes 1-2s — the
    # rest is quiescent. Labeling the WHOLE trial "Fall" teaches the model
    # that stillness itself means "Fall" (confirmed empirically on the
    # phone-only variant of this pipeline: 65% of whole-trial-labeled Fall
    # windows had peak accel under ~1.2g, indistinguishable from ADL — see
    # ml/README.md). Only windows that actually CONTAIN the impact are
    # labeled Fall; the rest of a Fall trial's windows are ADL, since
    # they're genuinely quiescent too.
    if is_fall_trial:
        accel_mag = np.linalg.norm(wa, axis=1)
        peak_idx = int(np.argmax(accel_mag))
    else:
        peak_idx = None

    windows = []
    labels = []
    for start in range(0, n_samples - WINDOW_LEN + 1, STRIDE):
        windows.append(fused[start : start + WINDOW_LEN])
        contains_impact = (
            is_fall_trial and start <= peak_idx < start + WINDOW_LEN
        )
        labels.append(1 if contains_impact else 0)

    if not windows:
        return None
    return subject_id, np.array(labels, dtype=np.int64), np.stack(windows)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    files = sorted(RAW_DIR.glob("UMAFall_*.csv"))
    print(f"Found {len(files)} trial files in {RAW_DIR}")

    all_windows, all_labels, all_subjects = [], [], []
    skipped = 0
    for path in files:
        result = process_trial(path)
        if result is None:
            skipped += 1
            continue
        subject_id, labels, windows = result
        all_windows.append(windows)
        all_labels.append(labels)
        all_subjects.extend([subject_id] * len(windows))

    if not all_windows:
        raise SystemExit("No usable trials found — check ml/data/raw/ contents.")

    X = np.concatenate(all_windows, axis=0).astype(np.float32)
    y = np.concatenate(all_labels, axis=0).astype(np.int64)
    subjects = np.array(all_subjects, dtype=np.int64)

    print(f"Processed {len(files) - skipped}/{len(files)} trials ({skipped} skipped)")
    print(f"Windows: {X.shape}, fall-positive: {y.sum()} ({y.mean() * 100:.1f}%)")
    print(f"Subjects present: {sorted(set(subjects.tolist()))}")

    out_path = OUT_DIR / "windows.npz"
    np.savez(out_path, X=X, y=y, subjects=subjects)
    print(f"Saved to {out_path}")


if __name__ == "__main__":
    main()
