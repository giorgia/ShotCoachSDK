import os
import json
import numpy as np
import torch
from sklearn.model_selection import train_test_split
from torch.utils.data import DataLoader, TensorDataset

from train_head_helpers import AestheticMLP

BASE = os.path.dirname(__file__)
EMBED_PATH = os.path.join(BASE, "output", "embeddings.npy")
SCORE_PATH = os.path.join(BASE, "output", "scores.npy")
MODEL_OUT = os.path.join(BASE, "output", "aesthetic_head_v2.pt")
STATS_OUT = os.path.join(BASE, "output", "train_stats.json")
MEAN_OUT = os.path.join(BASE, "output", "embed_mean.npy")
STD_OUT = os.path.join(BASE, "output", "embed_std.npy")

EPOCHS = int(os.getenv("SHOTCOACH_EPOCHS", "20"))
BATCH_SIZE = int(os.getenv("SHOTCOACH_TRAIN_BATCH_SIZE", "512"))
LR = float(os.getenv("SHOTCOACH_LR", "0.001"))
PATIENCE = int(os.getenv("SHOTCOACH_PATIENCE", "3"))
MIN_DELTA = float(os.getenv("SHOTCOACH_MIN_DELTA", "0.1"))


def save_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)


def main():
    print("Loading embeddings and scores...")
    X_np = np.load(EMBED_PATH).astype(np.float32)
    y_np = np.load(SCORE_PATH).astype(np.float32)

    if X_np.ndim != 2:
        raise RuntimeError(f"Expected embeddings to have shape (N, D), got {X_np.shape}")
    if y_np.ndim != 1:
        raise RuntimeError(f"Expected scores to have shape (N,), got {y_np.shape}")
    if X_np.shape[0] != y_np.shape[0]:
        raise RuntimeError(f"Embedding/sample mismatch: X={X_np.shape}, y={y_np.shape}")

    input_dim = X_np.shape[1]
    print(f"Dataset: {X_np.shape[0]} samples")
    print(f"Embedding dim: {input_dim}")

    score_buckets = (y_np // 10).astype(int).clip(0, 9)
    X_train, X_val, y_train, y_val = train_test_split(
        X_np,
        y_np,
        test_size=0.1,
        stratify=score_buckets,
        random_state=42,
    )

    mean = X_train.mean(axis=0, keepdims=True)
    std = X_train.std(axis=0, keepdims=True) + 1e-6

    X_train = (X_train - mean) / std
    X_val = (X_val - mean) / std

    np.save(MEAN_OUT, mean.astype(np.float32))
    np.save(STD_OUT, std.astype(np.float32))

    train_loader = DataLoader(
        TensorDataset(
            torch.tensor(X_train, dtype=torch.float32),
            torch.tensor(y_train, dtype=torch.float32).unsqueeze(1),
        ),
        batch_size=BATCH_SIZE,
        shuffle=True,
    )

    val_loader = DataLoader(
        TensorDataset(
            torch.tensor(X_val, dtype=torch.float32),
            torch.tensor(y_val, dtype=torch.float32).unsqueeze(1),
        ),
        batch_size=BATCH_SIZE,
        shuffle=False,
    )

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"Training on: {device}")

    model = AestheticMLP(input_dim=input_dim).to(device)
    criterion = torch.nn.HuberLoss(delta=5.0)
    optimizer = torch.optim.Adam(model.parameters(), lr=LR)

    best_val_mae = float("inf")
    patience_left = PATIENCE
    history = []

    for epoch in range(1, EPOCHS + 1):
        model.train()
        train_loss = 0.0
        train_count = 0

        for xb, yb in train_loader:
            xb, yb = xb.to(device), yb.to(device)

            optimizer.zero_grad()
            pred = torch.clamp(model(xb), 0.0, 100.0)
            loss = criterion(pred, yb)
            loss.backward()
            optimizer.step()

            train_loss += loss.item() * len(xb)
            train_count += len(xb)

        train_loss /= max(train_count, 1)

        model.eval()
        val_mae = 0.0
        val_count = 0

        with torch.no_grad():
            for xb, yb in val_loader:
                xb, yb = xb.to(device), yb.to(device)
                pred = torch.clamp(model(xb), 0.0, 100.0)
                val_mae += torch.abs(pred - yb).sum().item()
                val_count += len(xb)

        val_mae /= max(val_count, 1)

        print(
            f"Epoch {epoch:2d}/{EPOCHS}  "
            f"train_loss={train_loss:.4f}  val_mae={val_mae:.4f}"
        )

        history.append({
            "epoch": epoch,
            "train_loss": float(train_loss),
            "val_mae": float(val_mae),
        })

        if val_mae < best_val_mae - MIN_DELTA:
            best_val_mae = val_mae
            patience_left = PATIENCE
            torch.save(
                {
                    "model_state_dict": model.state_dict(),
                    "input_dim": input_dim,
                },
                MODEL_OUT,
            )
            print(f"           ↳ New best val_mae={best_val_mae:.4f} (saved)")
        else:
            patience_left -= 1
            if patience_left == 0:
                print(f"Early stopping at epoch {epoch}.")
                break

    save_json(
        STATS_OUT,
        {
            "best_val_mae": float(best_val_mae),
            "input_dim": int(input_dim),
            "epochs_ran": len(history),
            "history": history,
        },
    )

    print(f"\nBest val MAE: {best_val_mae:.4f} / 100")
    print(f"Saved model: {MODEL_OUT}")
    print(f"Saved stats: {STATS_OUT}")
    print(f"Saved normalization: {MEAN_OUT}, {STD_OUT}")


if __name__ == "__main__":
    main()
