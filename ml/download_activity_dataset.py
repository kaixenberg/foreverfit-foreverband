"""Download the MotionSense dataset (phone accel + gyro during 6 activities).

Source: Malekzadeh et al., "MotionSense Dataset for Human Activity and
Attribute Recognition", MIT licensed, via the public GitHub repo (no auth
needed): https://github.com/mmalekzadeh/motion-sense

Only the raw single-sensor folders are fetched (B_Accelerometer_data.zip,
C_Gyroscope_data.zip) — the combined DeviceMotion folder (A) is ~74MB and
not needed since accel/gyro are read from B and C directly.

Idempotent: skips download/extraction if the CSVs are already present.
"""

import io
import zipfile
from pathlib import Path

import requests

BASE_URL = "https://raw.githubusercontent.com/mmalekzadeh/motion-sense/master/data"
FILES = {
    "B_Accelerometer_data.zip": "accel",
    "C_Gyroscope_data.zip": "gyro",
}

RAW_DIR = Path(__file__).parent / "data" / "raw_activity"


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    for filename, subdir in FILES.items():
        out_dir = RAW_DIR / subdir
        if out_dir.exists() and any(out_dir.rglob("*.csv")):
            print(f"Found existing CSVs in {out_dir}, skipping {filename}.")
            continue

        url = f"{BASE_URL}/{filename}"
        print(f"Downloading {url} ...")
        resp = requests.get(url, timeout=300)
        resp.raise_for_status()

        print(f"Extracting to {out_dir} ...")
        with zipfile.ZipFile(io.BytesIO(resp.content)) as zf:
            zf.extractall(out_dir)

    print("Done.")


if __name__ == "__main__":
    main()
