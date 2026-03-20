import os
import numpy as np
import torch
import coremltools as ct

from train_head_helpers import AestheticMLP

BASE = os.path.dirname(__file__)
MODEL_PT = os.path.join(BASE, "output", "aesthetic_head_v2.pt")
MODEL_PKG = os.path.join(BASE, "output", "aesthetic_head_v2.mlpackage")
EMBED_PATH = os.path.join(BASE, "output", "embeddings.npy")
MEAN_PATH = os.path.join(BASE, "output", "embed_mean.npy")
STD_PATH = os.path.join(BASE, "output", "embed_std.npy")


class ExportableAestheticModel(torch.nn.Module):
    def __init__(self, input_dim: int, mean: np.ndarray, std: np.ndarray):
        super().__init__()
        self.register_buffer("mean", torch.tensor(mean, dtype=torch.float32))
        self.register_buffer("std", torch.tensor(std, dtype=torch.float32))
        self.head = AestheticMLP(input_dim=input_dim)

    def forward(self, x):
        x = (x - self.mean) / self.std
        x = self.head(x)
        x = torch.clamp(x, 0.0, 100.0)
        return x


def main():
    if not os.path.exists(MODEL_PT):
        raise FileNotFoundError(f"Missing trained model: {MODEL_PT}")

    if not os.path.exists(EMBED_PATH):
        raise FileNotFoundError(f"Missing embeddings file: {EMBED_PATH}")

    if not os.path.exists(MEAN_PATH) or not os.path.exists(STD_PATH):
        raise FileNotFoundError(
            f"Missing normalization files: {MEAN_PATH} / {STD_PATH}"
        )

    input_dim = int(np.load(EMBED_PATH, mmap_mode="r").shape[1])
    mean = np.load(MEAN_PATH).astype(np.float32).reshape(1, input_dim)
    std = np.load(STD_PATH).astype(np.float32).reshape(1, input_dim)

    checkpoint = torch.load(MODEL_PT, map_location="cpu")

    model = ExportableAestheticModel(input_dim=input_dim, mean=mean, std=std)
    model.head.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    dummy_input = torch.zeros(1, input_dim, dtype=torch.float32)
    traced = torch.jit.trace(model, dummy_input)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="embedding", shape=(1, input_dim))],
        outputs=[ct.TensorType(name="score")],
        compute_units=ct.ComputeUnit.CPU_AND_NE,
        minimum_deployment_target=ct.target.iOS16,
    )

    mlmodel.save(MODEL_PKG)
    print(f"Saved: {MODEL_PKG}")

    dummy = {"embedding": np.zeros((1, input_dim), dtype=np.float32)}
    result = mlmodel.predict(dummy)
    score = result["score"]
    print(f"Dummy score: {float(np.array(score).reshape(-1)[0]):.4f}")

    size_mb = sum(
        os.path.getsize(os.path.join(dirpath, f))
        for dirpath, _, files in os.walk(MODEL_PKG)
        for f in files
    ) / 1e6
    print(f"Package size: {size_mb:.2f} MB")


if __name__ == "__main__":
    main()
