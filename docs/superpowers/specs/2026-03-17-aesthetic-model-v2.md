# Aesthetic Model V2 — ML Pipeline Spec

**Date:** 2026-03-17
**Status:** Approved

---

## Goal

Train a general-purpose aesthetic scoring model (`aesthetic_head_v2.mlpackage`) that works across all four built-in ShotCoach categories, replacing the category-specific `home_head_s0` (trained on a poor dataset). The model reuses the existing `mobileclip_s0_image` CLIP encoder already bundled in DemoApp.

---

## Context

- `home_head_s0` was trained on a low-quality dataset and is homeListing-only
- `productPhoto`, `carListing`, `foodPhoto` have no local aesthetic model at all
- Goal: one general model, all categories, better quality
- User has no ML background — every step must be explicit

## Architecture

```
AVA dataset (Kaggle, ~255k images)
        ↓
Embedding computation (one-time, ~2-3hrs on M1)
        ↓
embeddings.npy (255k × 512) + scores.npy (255k,)
        ↓
MLP head training (~minutes)
        ↓
aesthetic_head_v2.mlpackage
        ↓
replaces home_head_s0 in DemoApp + ListingCoach
works for all 4 categories
```

---

## Section 1 — Data

**Source:** AVA (Aesthetic Visual Analysis) dataset from Kaggle (`aesthetics-image-analysis`)

**Download steps:**
1. Create a free account at https://kaggle.com
2. Search for "aesthetics-image-analysis" and download (~1.2GB zip)
3. Extract: `unzip aesthetics-image-analysis.zip` → creates an `images/` folder and `AVA.txt`

**Contents:**
- ~255k JPG images
- `AVA.txt` — ratings distribution per image (columns 3–12 = vote counts for scores 1–10)

**Score normalisation:**
```
avg_score = weighted mean of votes (scores 1–10)
normalised = (avg_score - 1) / 9 * 100   → [0, 100]
```

**Split:** 90% train / 10% validation, stratified by score bucket (i.e. train and validation have the same distribution of low/medium/high scores — prevents the model from seeing only easy examples during training).

---

## Section 2 — Embedding Computation

One-time script. Processes all 255k images through `mobileclip_s0_image`, saves results to disk.

**Per image:**
1. Resize to 256×256
2. Run through `mobileclip_s0_image`
3. Extract 512-dimensional embedding
4. Save alongside normalised AVA score

**Output files:**
- `embeddings.npy` — shape (255000, 512)
- `scores.npy` — shape (255000,)

**Checkpointing:** saves progress every 1000 images so the script can be paused and resumed safely on M1.

**Runtime:** ~2–3 hours on M1 (one-time cost).

---

## Section 3 — MLP Head

**Architecture:**
```
Input:  512 floats (MobileCLIP embedding)
        ↓
Linear (512 → 256)
        ↓
ReLU
        ↓
Dropout (p=0.2)
        ↓
Linear (256 → 1)
        ↓
Sigmoid × 100
Output: 1 float in [0, 100]
```

**PyTorch class:**
```python
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

**Training config:**
- Loss: MSE (mean squared error)
- Optimiser: Adam, lr=0.001
- Epochs: max 20, early stopping patience=3 (stop if validation MAE doesn't drop by more than 0.1 for 3 consecutive epochs)
- Batch size: 512

**Important:** Call `model.eval()` before export to disable Dropout (which only runs during training). Forgetting this makes the model behave randomly at inference time.

**Output:** `aesthetic_head_v2.pt` (PyTorch checkpoint)

---

## Section 4 — CoreML Export

Export the trained MLP head to CoreML using `coremltools`:

```python
model.eval()
traced = torch.jit.trace(model, torch.zeros(1, 512))
mlmodel = coremltools.convert(
    traced,
    inputs=[coremltools.TensorType(name="embedding", shape=(1, 512))],
    outputs=[coremltools.TensorType(name="score")],
    compute_units=coremltools.ComputeUnit.CPU_AND_NE,
)
mlmodel.save("aesthetic_head_v2.mlpackage")
```

**Model properties:**
- Input feature name: `"embedding"` — 512 floats (from `mobileclip_s0_image`)
- Output feature name: `"score"` — 1 float in [0, 100]
- Size: ~500KB (tiny — just the MLP weights)

**Important — feature name:** The existing `home_head_s0` model used output name `"var_5"`. The v2 model must export with output name `"score"` explicitly (set in the `coremltools.convert` call above). The updated `HomeListingAestheticModel.swift` will read `"score"` directly instead of falling back to `"var_5"`.

---

## SDK Integration (out of scope for this pipeline, separate sub-project)

Once `aesthetic_head_v2.mlpackage` is produced:
- Replace `home_head_s0.mlpackage` in `DemoApp/MLModels/`
- Update `DemoApp/HomeListingAestheticModel.swift` to load `aesthetic_head_v2` instead of `home_head_s0`
- Apply to all 4 categories (not just homeListing)
- Update README references

---

## Environment

| Tool | Version | Status |
|---|---|---|
| Python | 3.9.6 | ✅ installed |
| PyTorch | 2.8.0 | ✅ installed, MPS enabled |
| coremltools | 9.0 | ✅ installed |
| numpy | 2.0.2 | ✅ installed |
| Pillow | 11.3.0 | ✅ installed |
| open-clip-torch | — | ❌ needs pip3 install |
| scikit-learn | — | ❌ needs pip3 install |

**Missing installs:**
```bash
pip3 install --user open-clip-torch scikit-learn
```

---

## What Is NOT In This Spec

- The iOS app (separate sub-project, depends on this model)
- SDK changes to wire the new model in (separate sub-project)
- Fine-tuning on product-specific images (future v3 if general model underperforms)
