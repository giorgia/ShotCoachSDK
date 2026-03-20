# Aesthetic Model V2 — ML Pipeline Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Train a general-purpose CoreML aesthetic scoring model (`aesthetic_head_v2.mlpackage`) using the AVA dataset and MobileCLIP S0 embeddings, to replace `home_head_s0` across all four ShotCoach categories.

**Architecture:** Parse AVA dataset → compute MobileCLIP S0 embeddings once (checkpointed) → train a small MLP head (512→256→1) → export head to CoreML. The CoreML encoder (`mobileclip_s0_image.mlpackage`) already exists in DemoApp and is unchanged.

**Tech Stack:** Python 3.9, PyTorch 2.8 (MPS), open-clip-torch, coremltools 9.0, numpy, scikit-learn, Pillow

**Spec:** `docs/superpowers/specs/2026-03-17-aesthetic-model-v2.md`

---

## File Structure

```
ml/
├── requirements.txt              ← Python dependencies
├── 01_parse_ava.py               ← Parse AVA.txt → scores.csv
├── 02_compute_embeddings.py      ← Images → embeddings.npy + scores.npy
├── 03_train_head.py              ← Train MLP, save aesthetic_head_v2.pt
├── 04_export_coreml.py           ← Convert .pt → aesthetic_head_v2.mlpackage
└── test_pipeline.py              ← Smoke tests for each stage

data/                             ← created by user, not committed
├── images/                       ← AVA images from Kaggle
└── AVA.txt                       ← AVA ratings file from Kaggle

output/                           ← created by scripts, not committed
├── scores.csv                    ← image_id, normalised_score
├── embeddings.npy                ← shape (N, 512)
├── scores.npy                    ← shape (N,)
├── checkpoint.npy                ← resume state for embedding step
└── aesthetic_head_v2.pt          ← trained PyTorch model
```

> **Note:** `data/` and `output/` are never committed to git — they contain large binary files.

---

## Chunk 1: Environment + Project Scaffold

### Task 1: Create ml/ directory and requirements.txt

**Files:**
- Create: `ml/requirements.txt`
- Create: `.gitignore` additions

- [ ] **Step 1: Create the ml/ directory and requirements file**

```bash
mkdir -p /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml
```

Create `ml/requirements.txt` with this exact content:

```
open-clip-torch==2.26.1
scikit-learn==1.4.2
tqdm==4.66.2
```

(PyTorch, coremltools, numpy, and Pillow are already installed.)

- [ ] **Step 2: Install dependencies**

```bash
pip3 install --user -r /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/requirements.txt
```

Expected: packages install without errors. `open_clip` and `sklearn` are now available.

- [ ] **Step 3: Verify installation**

```bash
python3 -c "import open_clip; import sklearn; import tqdm; print('OK')"
```

Expected output: `OK`

- [ ] **Step 4: Add data/ and output/ to .gitignore**

Add these lines to the bottom of `/Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/.gitignore` (create it if it doesn't exist):

```
# ML pipeline — large files, not committed
ml/data/
ml/output/
```

- [ ] **Step 5: Create output directory**

```bash
mkdir -p /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/data
mkdir -p /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/output
```

- [ ] **Step 6: Commit**

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK
git add ml/requirements.txt .gitignore
git commit -m "chore: add ML pipeline scaffold and requirements"
```

---

### Task 2: Download AVA dataset

**Files:** none (downloaded to `ml/data/`, not committed)

- [ ] **Step 1: Download from Kaggle**

1. Go to https://www.kaggle.com/datasets/nicolasmartinelli/aesthetics-image-analysis
2. Click **Download** (requires free Kaggle account)
3. Save the zip to `ml/data/`
4. Extract it:

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/data
unzip aesthetics-image-analysis.zip
```

Expected result: `ml/data/images/` folder with ~255k JPG files, and `ml/data/AVA.txt`.

- [ ] **Step 2: Verify the download**

```bash
python3 -c "
import os
img_count = len(os.listdir('/Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/data/images'))
print(f'Images: {img_count}')
with open('/Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/data/AVA.txt') as f:
    lines = f.readlines()
print(f'AVA rows: {len(lines)}')
"
```

Expected: `Images: ~255000`, `AVA rows: ~255000`

---

## Chunk 2: AVA Parsing

### Task 3: Parse AVA.txt and compute normalised scores

**Files:**
- Create: `ml/01_parse_ava.py`
- Create: `ml/test_pipeline.py` (first test)

- [ ] **Step 1: Write the test first**

Create `ml/test_pipeline.py`:

```python
import numpy as np
import sys
import os
sys.path.insert(0, os.path.dirname(__file__))

# ── Test 1: score normalisation ───────────────────────────────────────────────

def test_normalise_score():
    """AVA scores 1–10 should map to 0–100."""
    from parse_ava_helpers import normalise_score
    assert normalise_score(1.0) == 0.0,   f"Expected 0.0, got {normalise_score(1.0)}"
    assert normalise_score(10.0) == 100.0, f"Expected 100.0, got {normalise_score(10.0)}"
    assert abs(normalise_score(5.5) - 50.0) < 0.01, f"Expected ~50.0, got {normalise_score(5.5)}"
    print("✅ test_normalise_score passed")

if __name__ == "__main__":
    test_normalise_score()
    print("\nAll tests passed.")
```

- [ ] **Step 2: Run the test — expect failure**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/test_pipeline.py
```

Expected: `ModuleNotFoundError: No module named 'parse_ava_helpers'`

- [ ] **Step 3: Create the helper module**

Create `ml/parse_ava_helpers.py`:

```python
def normalise_score(avg: float) -> float:
    """Map AVA average score [1, 10] to [0, 100]."""
    return (avg - 1.0) / 9.0 * 100.0
```

- [ ] **Step 4: Run the test — expect pass**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/test_pipeline.py
```

Expected: `✅ test_normalise_score passed` / `All tests passed.`

- [ ] **Step 5: Create 01_parse_ava.py**

Create `ml/01_parse_ava.py`:

```python
"""
Parse AVA.txt and produce scores.csv.

AVA.txt format (space-separated):
  col 0:  "1" (literal)
  col 1:  image_id
  col 2:  semantic_tag_1
  col 3–12: vote counts for scores 1–10
  col 13: semantic_tag_2
  col 14: challenge_id

We compute: avg_score = sum(score * votes) / sum(votes) for scores 1–10
Then normalise to [0, 100].
"""

import csv
import os
from parse_ava_helpers import normalise_score

AVA_TXT   = os.path.join(os.path.dirname(__file__), "data", "AVA.txt")
IMAGE_DIR = os.path.join(os.path.dirname(__file__), "data", "images")
OUTPUT    = os.path.join(os.path.dirname(__file__), "output", "scores.csv")


def parse_ava():
    rows = []
    missing = 0

    with open(AVA_TXT) as f:
        for line in f:
            parts = line.strip().split()
            image_id = parts[1]
            votes = [int(parts[i]) for i in range(3, 13)]   # scores 1–10
            total = sum(votes)
            if total == 0:
                continue
            avg = sum((i + 1) * v for i, v in enumerate(votes)) / total
            score = normalise_score(avg)

            img_path = os.path.join(IMAGE_DIR, f"{image_id}.jpg")
            if not os.path.exists(img_path):
                missing += 1
                continue

            rows.append({"image_id": image_id, "score": round(score, 4)})

    print(f"Parsed {len(rows)} images ({missing} missing from disk, skipped)")

    os.makedirs(os.path.dirname(OUTPUT), exist_ok=True)
    with open(OUTPUT, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["image_id", "score"])
        writer.writeheader()
        writer.writerows(rows)

    print(f"Saved: {OUTPUT}")
    return rows


if __name__ == "__main__":
    rows = parse_ava()
    scores = [r["score"] for r in rows]
    print(f"Score range: {min(scores):.1f} – {max(scores):.1f}")
    print(f"Mean score:  {sum(scores)/len(scores):.1f}")
```

- [ ] **Step 6: Run the parser**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/01_parse_ava.py
```

Expected output (approximate):
```
Parsed ~250000 images (N missing from disk, skipped)
Saved: .../output/scores.csv
Score range: 0.0 – 100.0
Mean score:  ~50.0
```

- [ ] **Step 7: Commit**

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK
git add ml/01_parse_ava.py ml/parse_ava_helpers.py ml/test_pipeline.py
git commit -m "feat(ml): add AVA parser and score normalisation"
```

---

## Chunk 3: Embedding Computation

### Task 4: Compute MobileCLIP S0 embeddings for all images

**Files:**
- Create: `ml/02_compute_embeddings.py`

This script is the slow step (~2–3hrs). It saves a checkpoint every 1000 images so you can safely pause (Ctrl+C) and resume.

- [ ] **Step 1: Add embedding test to test_pipeline.py**

Append to `ml/test_pipeline.py`:

```python
# ── Test 2: MobileCLIP embedding shape ───────────────────────────────────────

def test_embedding_shape():
    """MobileCLIP S0 should produce 512-D embeddings."""
    import torch
    import open_clip
    from PIL import Image
    import numpy as np

    model, _, preprocess = open_clip.create_model_and_transforms(
        'MobileCLIP-S0', pretrained='datacomp_s12ft_s12m_b4k'
    )
    model.eval()

    # Create a dummy 256x256 image
    dummy_image = Image.fromarray(np.zeros((256, 256, 3), dtype=np.uint8))
    tensor = preprocess(dummy_image).unsqueeze(0)  # shape: (1, 3, 256, 256)

    with torch.no_grad():
        embedding = model.encode_image(tensor)

    assert embedding.shape == (1, 512), f"Expected (1, 512), got {embedding.shape}"
    print("✅ test_embedding_shape passed")


if __name__ == "__main__":
    test_normalise_score()
    test_embedding_shape()
    print("\nAll tests passed.")
```

- [ ] **Step 2: Run the test (downloads MobileCLIP weights ~100MB first time)**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/test_pipeline.py
```

Expected (first run downloads model weights):
```
✅ test_normalise_score passed
✅ test_embedding_shape passed

All tests passed.
```

- [ ] **Step 3: Create 02_compute_embeddings.py**

Create `ml/02_compute_embeddings.py`:

```python
"""
Compute MobileCLIP S0 embeddings for all images in scores.csv.

Saves:
  output/embeddings.npy  — shape (N, 512), float32
  output/scores.npy      — shape (N,),    float32
  output/checkpoint.npy  — last completed index (for resume)

Run once. Takes ~2–3 hours on M1.
Resume safely after Ctrl+C — script picks up from checkpoint.
"""

import os
import csv
import numpy as np
import torch
import open_clip
from PIL import Image
from tqdm import tqdm

SCORES_CSV    = os.path.join(os.path.dirname(__file__), "output", "scores.csv")
IMAGE_DIR     = os.path.join(os.path.dirname(__file__), "data", "images")
EMBED_OUT     = os.path.join(os.path.dirname(__file__), "output", "embeddings.npy")
SCORES_OUT    = os.path.join(os.path.dirname(__file__), "output", "scores.npy")
CHECKPOINT    = os.path.join(os.path.dirname(__file__), "output", "checkpoint.npy")
SAVE_EVERY    = 1000


def load_rows():
    with open(SCORES_CSV) as f:
        return list(csv.DictReader(f))


def main():
    rows = load_rows()
    n = len(rows)
    print(f"Total images: {n}")

    # Load model — uses MPS (M1 GPU) if available, else CPU
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"Using device: {device}")
    model, _, preprocess = open_clip.create_model_and_transforms(
        'MobileCLIP-S0', pretrained='datacomp_s12ft_s12m_b4k'
    )
    model = model.to(device)
    model.eval()

    # Resume from checkpoint if it exists
    start = 0
    if os.path.exists(CHECKPOINT):
        start = int(np.load(CHECKPOINT)) + 1
        embeddings = np.load(EMBED_OUT).tolist()
        scores     = np.load(SCORES_OUT).tolist()
        print(f"Resuming from image {start}")
    else:
        embeddings = []
        scores     = []

    with torch.no_grad():
        for i in tqdm(range(start, n), initial=start, total=n):
            row = rows[i]
            img_path = os.path.join(IMAGE_DIR, f"{row['image_id']}.jpg")

            try:
                img = Image.open(img_path).convert("RGB")
                tensor = preprocess(img).unsqueeze(0).to(device)
                emb = model.encode_image(tensor).squeeze(0).cpu().float().numpy()
                embeddings.append(emb)
                scores.append(float(row["score"]))
            except Exception as e:
                print(f"Skipping {row['image_id']}: {e}")
                continue

            # Save checkpoint every SAVE_EVERY images
            if (i + 1) % SAVE_EVERY == 0:
                np.save(EMBED_OUT,  np.array(embeddings, dtype=np.float32))
                np.save(SCORES_OUT, np.array(scores,     dtype=np.float32))
                np.save(CHECKPOINT, np.array(i))

    # Final save
    np.save(EMBED_OUT,  np.array(embeddings, dtype=np.float32))
    np.save(SCORES_OUT, np.array(scores,     dtype=np.float32))
    if os.path.exists(CHECKPOINT):
        os.remove(CHECKPOINT)   # done — remove checkpoint

    print(f"\nDone. Embeddings shape: {np.load(EMBED_OUT).shape}")
    print(f"Scores shape:     {np.load(SCORES_OUT).shape}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the embedding script**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/02_compute_embeddings.py
```

Expected: a progress bar counting up to ~255k. Let it run. You can safely stop with **Ctrl+C** and re-run to resume.

Final expected output:
```
Done. Embeddings shape: (250000, 512)
Scores shape:     (250000,)
```

- [ ] **Step 5: Commit scripts (not data)**

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK
git add ml/02_compute_embeddings.py ml/test_pipeline.py
git commit -m "feat(ml): add MobileCLIP embedding computation with checkpointing"
```

---

## Chunk 4: MLP Training

### Task 5: Train the MLP head

**Files:**
- Create: `ml/03_train_head.py`

- [ ] **Step 1: Add training smoke test to test_pipeline.py**

Append to `ml/test_pipeline.py`:

```python
# ── Test 3: MLP forward pass shape ───────────────────────────────────────────

def test_mlp_forward():
    """MLP should accept (B, 512) and output (B, 1) in [0, 100]."""
    import torch
    import sys, os
    sys.path.insert(0, os.path.dirname(__file__))
    from train_head_helpers import AestheticMLP

    model = AestheticMLP()
    dummy = torch.zeros(4, 512)   # batch of 4 embeddings
    out = model(dummy)
    assert out.shape == (4, 1), f"Expected (4, 1), got {out.shape}"
    assert (out >= 0).all() and (out <= 100).all(), "Output out of [0, 100] range"
    print("✅ test_mlp_forward passed")


if __name__ == "__main__":
    test_normalise_score()
    test_embedding_shape()
    test_mlp_forward()
    print("\nAll tests passed.")
```

- [ ] **Step 2: Create train_head_helpers.py**

Create `ml/train_head_helpers.py`:

```python
import torch


class AestheticMLP(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.fc1     = torch.nn.Linear(512, 256)
        self.relu    = torch.nn.ReLU()
        self.dropout = torch.nn.Dropout(0.2)
        self.fc2     = torch.nn.Linear(256, 1)

    def forward(self, x):
        x = self.fc1(x)
        x = self.relu(x)
        x = self.dropout(x)
        x = self.fc2(x)
        return torch.sigmoid(x) * 100
```

- [ ] **Step 3: Run the test**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/test_pipeline.py
```

Expected: all three tests pass.

- [ ] **Step 4: Create 03_train_head.py**

Create `ml/03_train_head.py`:

```python
"""
Train the MLP head on precomputed embeddings.

Input:  output/embeddings.npy, output/scores.npy
Output: output/aesthetic_head_v2.pt

Run AFTER 02_compute_embeddings.py completes.
Training takes ~5 minutes on M1.
"""

import os
import numpy as np
import torch
from torch.utils.data import DataLoader, TensorDataset
from sklearn.model_selection import train_test_split
from train_head_helpers import AestheticMLP

EMBED_PATH = os.path.join(os.path.dirname(__file__), "output", "embeddings.npy")
SCORE_PATH = os.path.join(os.path.dirname(__file__), "output", "scores.npy")
MODEL_OUT  = os.path.join(os.path.dirname(__file__), "output", "aesthetic_head_v2.pt")

EPOCHS        = 20
BATCH_SIZE    = 512
LR            = 0.001
PATIENCE      = 3       # early stopping: stop if val MAE doesn't improve
MIN_DELTA     = 0.1     # minimum improvement to count as progress


def main():
    # Load data
    print("Loading embeddings and scores...")
    X_np = np.load(EMBED_PATH)
    y_np = np.load(SCORE_PATH)
    print(f"Dataset: {X_np.shape[0]} samples")

    # 90/10 stratified split — bins scores into 10-point buckets so train and val
    # have the same distribution of low/medium/high scores.
    score_buckets = (y_np // 10).astype(int).clip(0, 9)
    X_train, X_val, y_train, y_val = train_test_split(
        X_np, y_np, test_size=0.1, stratify=score_buckets, random_state=42
    )
    n_train, n_val = len(X_train), len(X_val)

    train_loader = DataLoader(
        TensorDataset(torch.tensor(X_train, dtype=torch.float32),
                      torch.tensor(y_train, dtype=torch.float32).unsqueeze(1)),
        batch_size=BATCH_SIZE, shuffle=True,
    )
    val_loader = DataLoader(
        TensorDataset(torch.tensor(X_val, dtype=torch.float32),
                      torch.tensor(y_val, dtype=torch.float32).unsqueeze(1)),
        batch_size=BATCH_SIZE,
    )

    # Model, loss, optimiser
    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"Training on: {device}")
    model     = AestheticMLP().to(device)
    criterion = torch.nn.MSELoss()
    optimiser = torch.optim.Adam(model.parameters(), lr=LR)

    best_val_mae  = float("inf")
    patience_left = PATIENCE

    for epoch in range(1, EPOCHS + 1):
        # ── Training ──
        model.train()
        train_loss = 0.0
        for xb, yb in train_loader:
            xb, yb = xb.to(device), yb.to(device)
            optimiser.zero_grad()
            pred = model(xb)
            loss = criterion(pred, yb)
            loss.backward()
            optimiser.step()
            train_loss += loss.item() * len(xb)
        train_loss /= n_train

        # ── Validation ──
        model.eval()
        val_mae = 0.0
        with torch.no_grad():
            for xb, yb in val_loader:
                xb, yb = xb.to(device), yb.to(device)
                pred = model(xb)
                val_mae += torch.abs(pred - yb).sum().item()
        val_mae /= n_val

        print(f"Epoch {epoch:2d}/{EPOCHS}  "
              f"train_loss={train_loss:.2f}  val_mae={val_mae:.2f}")

        # ── Early stopping ──
        if val_mae < best_val_mae - MIN_DELTA:
            best_val_mae = val_mae
            patience_left = PATIENCE
            torch.save(model.state_dict(), MODEL_OUT)
            print(f"           ↳ New best val_mae={best_val_mae:.2f}  (saved)")
        else:
            patience_left -= 1
            if patience_left == 0:
                print(f"Early stopping at epoch {epoch}.")
                break

    print(f"\nBest val MAE: {best_val_mae:.2f} / 100")
    print(f"Saved: {MODEL_OUT}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 5: Run training**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/03_train_head.py
```

Expected output (approximate):
```
Loading embeddings and scores...
Dataset: 250000 samples
Training on: mps
Epoch  1/20  train_loss=450.00  val_mae=18.00
           ↳ New best val_mae=18.00  (saved)
Epoch  2/20  train_loss=380.00  val_mae=15.50
           ↳ New best val_mae=15.50  (saved)
...
```

A healthy final `val_mae` is **below 12.0** (meaning predictions are on average within 12 points out of 100). If `val_mae` stays above 20 after 5 epochs, stop and check that `embeddings.npy` has the right shape (should be N × 512).

- [ ] **Step 6: Commit**

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK
git add ml/03_train_head.py ml/train_head_helpers.py ml/test_pipeline.py
git commit -m "feat(ml): add MLP training with early stopping"
```

---

## Chunk 5: CoreML Export + Verification

### Task 6: Export trained model to CoreML

**Files:**
- Create: `ml/04_export_coreml.py`

- [ ] **Step 1: Add export test to test_pipeline.py**

Append to `ml/test_pipeline.py`:

```python
# ── Test 4: CoreML export produces valid package ──────────────────────────────

def test_coreml_export():
    """Exported .mlpackage should load and produce a float output in [0, 100]."""
    import coremltools as ct
    import numpy as np
    import os

    pkg_path = os.path.join(os.path.dirname(__file__),
                            "output", "aesthetic_head_v2.mlpackage")
    if not os.path.exists(pkg_path):
        print("⚠️  test_coreml_export skipped — run 04_export_coreml.py first")
        return

    mlmodel = ct.models.MLModel(pkg_path)
    dummy = {"embedding": np.zeros((1, 512), dtype=np.float32)}
    result = mlmodel.predict(dummy)

    assert "score" in result, f"Expected output key 'score', got: {list(result.keys())}"
    score = result["score"]
    assert 0.0 <= float(score) <= 100.0, f"Score out of range: {score}"
    print(f"✅ test_coreml_export passed (dummy score: {float(score):.2f})")


if __name__ == "__main__":
    test_normalise_score()
    test_embedding_shape()
    test_mlp_forward()
    test_coreml_export()
    print("\nAll tests passed.")
```

- [ ] **Step 2: Create 04_export_coreml.py**

Create `ml/04_export_coreml.py`:

```python
"""
Convert aesthetic_head_v2.pt → aesthetic_head_v2.mlpackage

Input:  output/aesthetic_head_v2.pt
Output: output/aesthetic_head_v2.mlpackage

Run AFTER 03_train_head.py completes.
"""

import os
import torch
import coremltools as ct
import numpy as np
from train_head_helpers import AestheticMLP

MODEL_PT  = os.path.join(os.path.dirname(__file__), "output", "aesthetic_head_v2.pt")
MODEL_PKG = os.path.join(os.path.dirname(__file__), "output", "aesthetic_head_v2.mlpackage")


def main():
    # Load trained weights
    model = AestheticMLP()
    model.load_state_dict(torch.load(MODEL_PT, map_location="cpu"))
    model.eval()   # IMPORTANT: disables Dropout for inference

    # Trace the model with a dummy input
    # torch.jit.trace records the computation graph for a specific input shape
    dummy_input = torch.zeros(1, 512)
    traced = torch.jit.trace(model, dummy_input)

    # Convert to CoreML
    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="embedding", shape=(1, 512))],
        outputs=[ct.TensorType(name="score")],
        compute_units=ct.ComputeUnit.CPU_AND_NE,   # uses Neural Engine on device
        minimum_deployment_target=ct.target.iOS16,
    )

    # Save
    mlmodel.save(MODEL_PKG)
    print(f"Saved: {MODEL_PKG}")

    # Quick sanity check: run a dummy prediction
    dummy = {"embedding": np.zeros((1, 512), dtype=np.float32)}
    result = mlmodel.predict(dummy)
    score = list(result.values())[0]
    print(f"Dummy score (all-zero embedding): {float(score):.2f} / 100")
    print("Expected: a value in [0, 100]. Exact value doesn't matter for zeros.")

    # Size check
    import shutil
    size_mb = sum(
        os.path.getsize(os.path.join(dirpath, f))
        for dirpath, _, files in os.walk(MODEL_PKG)
        for f in files
    ) / 1e6
    print(f"Package size: {size_mb:.1f} MB  (expected: < 2 MB)")


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Run the export**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/04_export_coreml.py
```

Expected output:
```
Saved: .../output/aesthetic_head_v2.mlpackage
Dummy score (all-zero embedding): XX.XX / 100
Package size: ~0.5 MB  (expected: < 2 MB)
```

If package size > 2MB, the wrong model was exported (check that you're exporting only the MLP head, not the full CLIP encoder).

- [ ] **Step 4: Run the full test suite**

```bash
python3 /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/test_pipeline.py
```

Expected: all four tests pass.

- [ ] **Step 5: Copy the model to DemoApp**

```bash
cp -r /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/ml/output/aesthetic_head_v2.mlpackage \
      /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/DemoApp/MLModels/
```

- [ ] **Step 6: Commit**

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK
git add ml/04_export_coreml.py ml/test_pipeline.py
git add DemoApp/MLModels/aesthetic_head_v2.mlpackage
git commit -m "feat(ml): add CoreML export script and trained aesthetic_head_v2"
```

- [ ] **Step 7: Update README model reference**

In `README.md`, update the CoreML pipeline section to reference `aesthetic_head_v2` instead of `home_head_s0`:

```
├── mobileclip_s0_image  (CLIP encoder → 512-D embedding)  ─┐
│                                                             ├── raw score (70%)
├── aesthetic_head_v2    (embedding → sigmoid [0, 100])     ─┘
```

- [ ] **Step 8: Final commit and tag**

```bash
cd /Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK
git add README.md
git commit -m "docs: update README to reference aesthetic_head_v2"
git push
git tag v1.1.0
git push origin v1.1.0
```

> **Note:** The SDK integration (updating `HomeListingAestheticModel.swift` to load `aesthetic_head_v2` instead of `home_head_s0`, and wiring it to all four categories) is a separate sub-project spec.
