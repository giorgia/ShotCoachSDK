# Aesthetic Model V2 — Decisions Log

This document records all deviations and design decisions made from the original AVA-based pipeline plan to the final working LAION + CoreML pipeline.

## Overview

**Original Plan**
- Dataset: AVA (Kaggle)
- Encoder: MobileCLIP S0 via `open_clip`
- Pipeline: parse → embed → train → export

**Final Implementation**
- Dataset: LAION aesthetic (Hugging Face)
- Encoder: existing CoreML `mobileclip_s0_image.mlpackage`
- Pipeline: load → download → embed → train → export

## Dataset Decisions

### 1. Switched from AVA → LAION
- **Reason:** AVA dataset links unavailable / unreliable
- **Replacement:** `laion/laion2B-en-aesthetic`
- **Impact:** removed dependency on `AVA.txt` and vote parsing

### 2. Replaced AVA parsing with manifest generation
- `01_parse_ava.py` → `01_load_laion.py`
- Outputs `manifest.csv` with:
  - `id`
  - `url`
  - `score`

### 3. Score source changed
- AVA: computed from vote distribution
- LAION: direct `aesthetic` field (0–10)
- Normalized to:
  `score = aesthetic * 10  → [0, 100]`

### 4. Fixed URL encoding issues
- LAION URLs contain HTML entities (`&amp;`)
- **Fix:** unescape URLs before download

## Data Pipeline Changes

### 5. Added explicit image download stage
New step:
`02_download_images.py`

- Downloads images locally to:
  `ml/data/image_cache/`

### 6. Separated download from embedding
- **Before:** embed directly from URLs
- **After:** embed only from cached images

**Why:**
- reproducibility
- faster retries
- avoids network bottlenecks

## Encoder Decisions

### 7. Abandoned `open_clip` MobileCLIP-S0
- Model not available in installed version
- Caused runtime failure

### 8. Switched to CoreML encoder (critical decision)
Used:
`DemoApp/MLModels/mobileclip_s0_image.mlpackage`

**Why:**
- guarantees identical embeddings to production app
- avoids mismatch between training and inference

### 9. Introduced encoder abstraction
Created:
`encoder_utils.py`

Provides:
- `load_encoder()`
- backend selection (CoreML vs fallback)

### 10. CoreML requires fixed image size
- Error:
  `Image size not in allowed set`

**Fix:**
- resize images before prediction

### 11. Standardized embedding output shape
- CoreML sometimes returns `(512,)`
- **Fix:**
  `emb = emb.reshape(-1)`

### 12. Fixed batching bug
- Incorrect:
  `(10636288,)`
- Correct:
  `(20774, 512)`

**Fix:**
`np.stack(embeddings, axis=0)`

## Model & Training Decisions

### 13. Parameterized input dimension
- Original: fixed `512`
- Final:
  `AestheticMLP(input_dim)`

### 14. Removed sigmoid from model
- Original:
  `sigmoid(x) * 100`
- Final:
  - raw output
  - clamp externally

### 15. Added embedding normalization
Saved:
- `embed_mean.npy`
- `embed_std.npy`

Used:
`X = (X - mean) / std`

### 16. Switched loss function
- Original: MSE
- Final: Huber

`torch.nn.HuberLoss(delta=5.0)`

**Why:**
- more robust to noisy labels

### 17. Improved checkpoint format
Saved:
```python
{
  "model_state_dict": ...,
  "input_dim": ...
}
```

### 18. Added training stats
New file:
`train_stats.json`

Contains:
- best val MAE
- training history
- epochs run

## Export Decisions

### 19. Export includes normalization
CoreML model now performs:

`embedding → normalize → MLP head → clamp [0, 100]`

### 20. Export script updated
Final file:
`05_export_coreml.py`

## Testing Changes

### 21. Removed AVA dependency
- `parse_ava_helpers.py` no longer required

### 22. Encoder test uses real backend
- Tests actual CoreML encoder instead of mock/open_clip

### 23. Dynamic input dimension in tests
- Reads dimension from `embeddings.npy`

## Final Pipeline

`01_load_laion.py → manifest.csv → 02_download_images.py → image_cache/ → 03_compute_embeddings.py → embeddings.npy + scores.npy → 04_train_head.py → aesthetic_head_v2.pt + normalization → 05_export_coreml.py → aesthetic_head_v2.mlpackage`

## Key Outcomes

- Fully working pipeline (end-to-end)
- Uses production encoder (CoreML)
- No external dataset dependencies at runtime
- Deterministic + resumable
- Lightweight CoreML head (<2MB)
- Verified via test suite

## Most Important Decisions (TL;DR)

1. **AVA → LAION switch** (unblocked pipeline)
2. **Use CoreML encoder instead of open_clip** (correctness)
3. **Cache images locally** (stability + speed)
4. **Add normalization + include it in export** (model quality)
5. **Fix embedding shape + batching bugs** (critical correctness)
