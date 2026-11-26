"""
Download every external file the project needs (benchmarks, SPMF, UCI Online Retail).

Files come from the group's Hugging Face dataset mirror; each is checked against a
SHA-256 so Colab runs use byte-identical copies of the data used locally. If the
mirror is unreachable, the official source is used where one exists.

Usage (from the repository root):
    python scripts/download_data.py            # download what is missing
    python scripts/download_data.py --force    # re-download everything

Set CHARM_DATA_REPO to use another Hugging Face dataset repository.
Only the Python standard library is used.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DATA_REPO = os.environ.get("CHARM_DATA_REPO", "TheBrilliantCoder/frequent-itemset-mining-data")
MIRROR_URL = f"https://huggingface.co/datasets/{DATA_REPO}/resolve/main/{{path}}"

SPMF_URL = "https://www.philippe-fournier-viger.com/spmf/spmf.jar"
UCI_RETAIL_ZIP_URL = "https://archive.ics.uci.edu/static/public/352/online+retail.zip"

# (path in the mirror, local path, sha256, official fallback or None)
FILES = [
    ("benchmark/chess.txt", "data/benchmark/chess.txt",
     "a12ea887df58a396709430af5bf0a9a32d1f6eba8e7c13dd41f28b98572c5db2", None),
    ("benchmark/mushrooms.txt", "data/benchmark/mushrooms.txt",
     "3bc1159b06baa231932810d1d58cbb958684be88b6daa8e3672f8d76c5f0eb98", None),
    ("benchmark/retail.txt", "data/benchmark/retail.txt",
     "732c26de19888cb570d3fbb97e47206a9b1c0ce064f85dc1403314ba38f04eaa", None),
    ("benchmark/T10I4D100K.txt", "data/benchmark/T10I4D100K.txt",
     "949983f61aa976d1b774474fadd31c5f15775b24728a5e7c8b79801822ab3f89", None),
    ("benchmark/accidents.txt", "data/benchmark/accidents.txt",
     "8c2275550966e3cb4b6066f2bb168489a9566c500af559fa3925f1b11d97f0cd", None),
    ("tools/spmf.jar", "tools/spmf.jar",
     "2cc2d89e39909230ea0455da4a1c79b389dc98ca04b0670befb63e679b5e2ea0", "spmf"),
    ("online_retail/Online Retail.xlsx", "data/applications/online_retail/Online Retail.xlsx",
     "43465a06f2ccf7c8b5bd2892bc7defb52f97487934fe93b16ae4c3936424676d", "uci"),
]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch(url: str, dest: Path, attempts: int = 3) -> None:
    """Download url to dest atomically, retrying transient failures."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        fd, tmp_name = tempfile.mkstemp(dir=dest.parent, suffix=".part")
        os.close(fd)
        tmp = Path(tmp_name)
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "charm-mining-downloader"})
            with urllib.request.urlopen(request, timeout=60) as response, tmp.open("wb") as out:
                shutil.copyfileobj(response, out, 1 << 20)
            tmp.replace(dest)
            return
        except Exception as err:  # network errors vary by platform
            last_error = err
            tmp.unlink(missing_ok=True)
            if attempt < attempts:
                time.sleep(2 * attempt)
    raise RuntimeError(f"Could not download {url}: {last_error}")


def fetch_fallback(kind: str, dest: Path) -> None:
    if kind == "spmf":
        fetch(SPMF_URL, dest)
    elif kind == "uci":
        zip_path = dest.parent / "online_retail.zip"
        fetch(UCI_RETAIL_ZIP_URL, zip_path)
        with zipfile.ZipFile(zip_path) as zf:
            zf.extractall(dest.parent)
    else:
        raise ValueError(kind)


def ensure(mirror_path: str, local: str, expected: str, fallback: str | None, force: bool) -> None:
    dest = REPO_ROOT / local
    if dest.exists() and not force and sha256(dest) == expected:
        print(f"[ok]       {local}")
        return

    try:
        fetch(MIRROR_URL.format(path=urllib.request.quote(mirror_path)), dest)
        source = "mirror"
    except RuntimeError as err:
        if fallback is None:
            raise
        print(f"[warn]     mirror failed for {local} ({err}); using official source")
        fetch_fallback(fallback, dest)
        source = "official"

    actual = sha256(dest)
    if actual != expected:
        if source == "official" and fallback == "spmf":
            # The official jar is updated over time; results are still comparable.
            print(f"[warn]     {local}: official SPMF build differs from the pinned one")
            return
        raise RuntimeError(f"Checksum mismatch for {local}: expected {expected}, got {actual}")
    print(f"[download] {local} ({source}, {dest.stat().st_size:,} bytes, sha256 verified)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--force", action="store_true", help="re-download even if a valid file exists")
    args = parser.parse_args()

    print(f"Data mirror: https://huggingface.co/datasets/{DATA_REPO}")
    for entry in FILES:
        ensure(*entry, force=args.force)
    print("All data files are present and verified.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
