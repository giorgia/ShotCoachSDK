import os
import csv
import html
from datasets import load_dataset

OUT_DIR = os.path.join(os.path.dirname(__file__), "output")
MANIFEST = os.path.join(OUT_DIR, "manifest.csv")

DATASET_NAME = os.getenv("SHOTCOACH_DATASET_NAME", "laion/laion2B-en-aesthetic")
DATASET_SPLIT = os.getenv("SHOTCOACH_DATASET_SPLIT", "train")
MAX_SAMPLES = int(os.getenv("SHOTCOACH_MAX_SAMPLES", "30000"))
HF_TOKEN = os.getenv("HF_TOKEN")


def pick_first(row, candidates):
    for key in candidates:
        if key in row and row[key] is not None:
            return row[key]
    return None


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    print(f"Loading dataset: {DATASET_NAME} [{DATASET_SPLIT}]")
    ds = load_dataset(
        DATASET_NAME,
        split=DATASET_SPLIT,
        token=HF_TOKEN if HF_TOKEN else None,
    )

    print("Dataset columns:", ds.column_names)

    if len(ds) == 0:
        raise RuntimeError("Dataset loaded but is empty")

    sample_count = min(MAX_SAMPLES, len(ds))
    ds = ds.shuffle(seed=42).select(range(sample_count))

    first = ds[0]
    print("First row keys:", list(first.keys()))
    print("First row sample:", first)

    kept = 0

    with open(MANIFEST, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "url", "score"])
        writer.writeheader()

        for i, row in enumerate(ds):
            url = pick_first(row, [
                "URL", "url", "image_url", "jpg", "image"
            ])

            score = pick_first(row, [
                "aesthetic",      # <-- this is the real one
                "AESTHETIC_SCORE",
                "aesthetic_score",
                "score",
                "rating",
                "aes"
            ])

            if isinstance(url, dict):
                url = url.get("url") or url.get("path")

            if isinstance(url, str):
                url = html.unescape(url).strip()

            try:
                if score is not None:
                    score = float(score)
            except Exception:
                score = None

            if not url or score is None:
                continue

            # dataset score is 0–10, convert to 0–100
            if score <= 10.0:
                score *= 10.0

            writer.writerow({
                "id": f"{i:07d}",
                "url": url,
                "score": round(score, 4),
            })
            kept += 1

    print(f"Saved manifest: {MANIFEST}")
    print(f"Rows kept: {kept}")


if __name__ == "__main__":
    main()
