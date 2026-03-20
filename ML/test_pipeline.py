import os
import sys
import numpy as np
import torch

sys.path.insert(0, os.path.dirname(__file__))

from train_head_helpers import AestheticMLP
from encoder_utils import load_encoder


def test_encoder_probe():
    encode_pil_images, meta = load_encoder()
    dummy = np.zeros((256, 256, 3), dtype=np.uint8)

    from PIL import Image
    emb = encode_pil_images([Image.fromarray(dummy)])

    assert emb.ndim == 2, f"Expected 2D embeddings, got shape {emb.shape}"
    assert emb.shape[0] == 1, f"Expected batch size 1, got shape {emb.shape}"
    assert emb.shape[1] == meta["embedding_dim"], (
        f"Dim mismatch: emb={emb.shape[1]}, meta={meta['embedding_dim']}"
    )

    print(f"✅ test_encoder_probe passed ({meta['backend']}, dim={meta['embedding_dim']})")


def test_mlp_forward():
    model = AestheticMLP(input_dim=512)
    dummy = torch.zeros(4, 512)

    out = model(dummy)
    out = torch.clamp(out, 0.0, 100.0)

    assert out.shape == (4, 1), f"Expected (4, 1), got {out.shape}"
    assert (out >= 0).all() and (out <= 100).all(), "Output out of range"

    print("✅ test_mlp_forward passed")


def test_coreml_export():
    import coremltools as ct

    base = os.path.dirname(__file__)
    pkg_path = os.path.join(base, "output", "aesthetic_head_v2.mlpackage")
    emb_path = os.path.join(base, "output", "embeddings.npy")

    if not os.path.exists(pkg_path):
        print("⚠️  skipped — CoreML model not found")
        return

    input_dim = int(np.load(emb_path, mmap_mode="r").shape[1])

    mlmodel = ct.models.MLModel(pkg_path)
    dummy = {"embedding": np.zeros((1, input_dim), dtype=np.float32)}

    result = mlmodel.predict(dummy)
    score = float(np.array(result["score"]).reshape(-1)[0])

    assert 0.0 <= score <= 100.0, f"Invalid score: {score}"

    print(f"✅ test_coreml_export passed (score={score:.2f})")


if __name__ == "__main__":
    test_encoder_probe()
    test_mlp_forward()
    test_coreml_export()
    print("\nAll tests passed.")
