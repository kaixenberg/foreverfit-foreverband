"""Download the UMAFall dataset (wrist + phone-pocket fall/ADL trials).

Source: Casilari et al., "UMAFall: A Multisensor Dataset for the Research
on Automatic Fall Detection", via the Figshare API (no auth needed).
https://api.figshare.com/v2/articles/4214283

Idempotent: skips download/extraction if the CSVs are already present.
"""

import io
import sys
import zipfile
from pathlib import Path

import requests

ARTICLE_API = "https://api.figshare.com/v2/articles/4214283"
# "UMAFall_Dataset_corrected_version.zip" — prefer the corrected version
# over the original release.
ZIP_FILENAME = "UMAFall_Dataset_corrected_version.zip"

RAW_DIR = Path(__file__).parent / "data" / "raw"


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)

    existing = list(RAW_DIR.glob("UMAFall_*.csv"))
    if existing:
        print(f"Found {len(existing)} existing CSVs in {RAW_DIR}, skipping download.")
        return

    print(f"Fetching article metadata from {ARTICLE_API} ...")
    resp = requests.get(ARTICLE_API, timeout=30)
    resp.raise_for_status()
    files = resp.json()["files"]

    match = next((f for f in files if f["name"] == ZIP_FILENAME), None)
    if match is None:
        names = [f["name"] for f in files]
        sys.exit(f"Could not find {ZIP_FILENAME!r} among Figshare files: {names}")

    print(f"Downloading {match['name']} ({match['size'] / 1e6:.1f} MB) ...")
    data_resp = requests.get(match["download_url"], timeout=300)
    data_resp.raise_for_status()

    print("Extracting CSVs ...")
    with zipfile.ZipFile(io.BytesIO(data_resp.content)) as zf:
        csv_names = [n for n in zf.namelist() if n.lower().endswith(".csv")]
        zf.extractall(RAW_DIR, members=csv_names)

    print(f"Done: {len(csv_names)} CSV files in {RAW_DIR}")


if __name__ == "__main__":
    main()
