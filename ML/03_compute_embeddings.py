import os
import csv
import numpy as np
from PIL import Image, ImageFile

from encoder_utils import load_encoder, save_embedding_metadata

ImageFile.LOAD_TRUNCATED_IMAGES = True

BASE = os.path.dirname(__file__)
MANIFEST = os.path.join(BASE, "output", "manifest.csv")
CACHE_DIR = os.path.join(BASE, "data", "image_cache")
FINAL_EMB = os.path.join(BASE, "output", "embeddings.npy")
FINAL_SCORES = os.path.join(BASE, "output", "scores.npy")
META_OUT = os.path.join(BASE, "output", "embedding_metadata.json")

BATCH_SIZE = int(os.getenv("SHOTCOACH_EMBED_BATCH_SIZE", "64"))


def load_rows():
    with open(MANIFEST) as f:
        rows = list(csv.DictReader(f))
    rows = [
        r for r in rows
        if os.path.exists(os.path.join(CACHE_DIR, f"{r['id']}.jpg"))
    ]
    return rows


def load_images(batch_rows):
    images = []
    scores = []

    for row in batch_rows:
        path = os.path.join(CACHE_DIR, f"{row['id']}.jpg")
        try:
            img = Image.open(path).convert("RGB")
            images.append(img)
            scores.append(float(row["score"]))
        except Exception as e:
            print(f"Skipping {path}: {e}")

    return images, scores


def main():
    rows = load_rows()
    print(f"Cached images found: {len(rows)}")

    encode_pil_images, encoder_meta = load_encoder()
    print(f"Encoder: {encoder_meta}")

    all_emb = []
    all_scores = []
    processed_images = 0

    for start in range(0, len(rows), BATCH_SIZE):
        batch_rows = rows[start:start + BATCH_SIZE]
        imgs, scores = load_images(batch_rows)

        if not imgs:
            continue

        emb = encode_pil_images(imgs).astype(np.float32)

        # Safety check: force (N, D)
        if emb.ndim == 1:
            emb = emb.reshape(1, -1)

        if emb.shape[0] != len(scores):
            raise RuntimeError(
                f"Embedding batch/image count mismatch: emb.shape={emb.shape}, "
                f"len(scores)={len(scores)}"
            )

        all_emb.append(emb)
        all_scores.append(np.array(scores, dtype=np.float32))

        processed_images += emb.shape[0]
        if processed_images % 1024 < emb.shape[0]:
            print(f"Processed {processed_images} images")

    if not all_emb:
        raise RuntimeError("No embeddings were produced.")

    X = np.concatenate(all_emb, axis=0).astype(np.float32)
    y = np.concatenate(all_scores, axis=0).astype(np.float32)

    np.save(FINAL_EMB, X)
    np.save(FINAL_SCORES, y)
    save_embedding_metadata(META_OUT, encoder_meta)

    print("Done")
    print("Embeddings:", X.shape)
    print("Scores:", y.shape)
    print(f"Saved metadata: {META_OUT}")


if __name__ == "__main__":
    main()
