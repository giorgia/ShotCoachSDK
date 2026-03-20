# ShotCoach Aesthetic Model V2 — Patched LAION Pipeline

This package fixes the `MobileCLIP-S0 not found` issue by supporting **two encoder backends**:

1. **`open_clip` backend** — easiest local setup, uses `MobileCLIP-S1`
2. **`coreml` backend** — uses your existing local `mobileclip_s0_image.mlpackage` for embedding generation

## Which backend should you use?

### Use `open_clip` if:
- you want the fastest path to test the pipeline
- you are okay changing the app encoder later to match the trained head

### Use `coreml` if:
- you want the trained head to match your existing app encoder
- your app already ships `mobileclip_s0_image.mlpackage`
- correctness matters more than speed

## Important compatibility rule

The MLP head must be trained on embeddings from the **same encoder** used at inference time.

So:
- `open_clip` + `MobileCLIP-S1` head **only works with S1 embeddings**
- `coreml` + `mobileclip_s0_image.mlpackage` head **only works with S0 embeddings**

---

## Folder layout

Copy `ml/` into your repo so you have:

```text
ShotCoachSDK/
├── ml/
│   ├── data/
│   │   └── image_cache/
│   ├── output/
│   ├── 00_README_STEP_BY_STEP.md
│   ├── 01_load_laion.py
│   ├── 02_download_images.py
│   ├── 03_compute_embeddings.py
│   ├── 04_train_head.py
│   ├── 05_export_coreml.py
│   ├── encoder_utils.py
│   ├── train_head_helpers.py
│   └── test_pipeline.py
```

---

## Step 1 — Install dependencies

From your repo root:

```bash
pip3 install --user -r ml/requirements.txt
```

If you plan to use the `coreml` backend, make sure `coremltools` is already installed.

---

## Step 2 — Create folders

```bash
mkdir -p ml/data/image_cache
mkdir -p ml/output
```

---

## Step 3 — Pick your encoder backend

### Option A — open_clip backend (easier)

This uses `MobileCLIP-S1` because your installed `open_clip` does not expose `MobileCLIP-S0`.

Run:

```bash
export SHOTCOACH_ENCODER_BACKEND=open_clip
```

### Option B — CoreML backend (recommended for final production)

This uses your local CoreML encoder package.

Run:

```bash
export SHOTCOACH_ENCODER_BACKEND=coreml
export SHOTCOACH_COREML_ENCODER_PATH="/Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/DemoApp/MLModels/mobileclip_s0_image.mlpackage"
```

Adjust the path if your encoder lives elsewhere.

---

## Step 4 — Run smoke tests

```bash
python3 ml/test_pipeline.py
```

Expected:
- normalization test passes
- MLP shape test passes
- encoder probe passes or is skipped with a helpful message

---

## Step 5 — Load LAION metadata

Default sample count is 30k. You can change it with an env var.

```bash
export SHOTCOACH_MAX_SAMPLES=30000
python3 ml/01_load_laion.py
```

This creates:

- `ml/output/manifest.csv`

---

## Step 6 — Download images to cache

```bash
python3 ml/02_download_images.py
```

This downloads images into:

- `ml/data/image_cache/`

You can rerun it safely.

---

## Step 7 — Compute embeddings

### For `open_clip` backend:

```bash
export SHOTCOACH_ENCODER_BACKEND=open_clip
python3 ml/03_compute_embeddings.py
```

### For `coreml` backend:

```bash
export SHOTCOACH_ENCODER_BACKEND=coreml
export SHOTCOACH_COREML_ENCODER_PATH="/Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/DemoApp/MLModels/mobileclip_s0_image.mlpackage"
python3 ml/03_compute_embeddings.py
```

This creates:
- `ml/output/embeddings.npy`
- `ml/output/scores.npy`
- `ml/output/embedding_metadata.json`

---

## Step 8 — Train the head

```bash
python3 ml/04_train_head.py
```

This creates:
- `ml/output/aesthetic_head_v2.pt`
- `ml/output/embed_mean.npy`
- `ml/output/embed_std.npy`
- `ml/output/train_metadata.json`

---

## Step 9 — Export the head to CoreML

```bash
python3 ml/05_export_coreml.py
```

This creates:
- `ml/output/aesthetic_head_v2.mlpackage`

---

## Step 10 — Copy to app

```bash
cp -r ml/output/aesthetic_head_v2.mlpackage DemoApp/MLModels/
```

---

## Suggested first run

Use a small sample first:

```bash
export SHOTCOACH_MAX_SAMPLES=5000
python3 ml/01_load_laion.py
python3 ml/02_download_images.py
python3 ml/03_compute_embeddings.py
python3 ml/04_train_head.py
python3 ml/05_export_coreml.py
```

Once stable, increase to:

```bash
export SHOTCOACH_MAX_SAMPLES=30000
```

Then later:

```bash
export SHOTCOACH_MAX_SAMPLES=100000
```

---

## Common errors

### 1. `Model config for MobileCLIP-S0 not found`
Use:
```bash
export SHOTCOACH_ENCODER_BACKEND=open_clip
```
This switches to `MobileCLIP-S1`.

### 2. CoreML encoder path not found
Check:
```bash
ls "/Users/giorgiamarenda/Projects/ShotCoach/ShotCoachSDK/DemoApp/MLModels/mobileclip_s0_image.mlpackage"
```

### 3. `coremltools` predict fails on macOS
Use Python 3.9/3.10 on macOS and verify:
```bash
python3 -c "import coremltools as ct; print(ct.__version__)"
```

### 4. MPS out of memory
Lower batch size:
```bash
export SHOTCOACH_BATCH_SIZE=32
```

---

## Notes

- This package makes embedding dimension dynamic.
- The exported head includes normalization inside the model, so inference matches training.
- The CoreML export is only the **head**, not the full image encoder.
