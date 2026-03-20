import csv
import os
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests

BASE = os.path.dirname(__file__)
MANIFEST = os.path.join(BASE, "output", "manifest.csv")
CACHE_DIR = os.path.join(BASE, "data", "image_cache")

TIMEOUT = int(os.environ.get("SHOTCOACH_DOWNLOAD_TIMEOUT", "10"))
MAX_WORKERS = int(os.environ.get("SHOTCOACH_DOWNLOAD_WORKERS", "32"))
RETRIES = int(os.environ.get("SHOTCOACH_DOWNLOAD_RETRIES", "2"))

def path_for_id(image_id: str) -> str:
    return os.path.join(CACHE_DIR, f"{image_id}.jpg")

def download_one(row):
    image_id = row["id"]
    url = row["url"]
    out_path = path_for_id(image_id)

    if os.path.exists(out_path) and os.path.getsize(out_path) > 0:
        return ("cached", image_id)

    for attempt in range(RETRIES + 1):
        try:
            r = requests.get(
                url,
                timeout=TIMEOUT,
                stream=True,
                headers={"User-Agent": "ShotCoach-AestheticTrainer/1.0"},
            )
            r.raise_for_status()

            content_type = r.headers.get("Content-Type", "")
            if "image" not in content_type.lower():
                return ("non_image", image_id)

            tmp_path = out_path + ".tmp"
            with open(tmp_path, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)

            if os.path.getsize(tmp_path) == 0:
                os.remove(tmp_path)
                return ("empty", image_id)

            os.replace(tmp_path, out_path)
            return ("downloaded", image_id)
        except Exception:
            if attempt == RETRIES:
                return ("failed", image_id)
            time.sleep(0.5 * (attempt + 1))

def main():
    os.makedirs(CACHE_DIR, exist_ok=True)

    with open(MANIFEST) as f:
        rows = list(csv.DictReader(f))

    counts = {"downloaded": 0, "cached": 0, "failed": 0, "non_image": 0, "empty": 0}

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as ex:
        futures = [ex.submit(download_one, row) for row in rows]
        for i, fut in enumerate(as_completed(futures), 1):
            status, _ = fut.result()
            counts[status] = counts.get(status, 0) + 1
            if i % 1000 == 0:
                print(f"{i} / {len(rows)}  {counts}")

    print("Done:", counts)

if __name__ == "__main__":
    main()
