import os
import json
from typing import Callable, List, Tuple, Dict, Any

import numpy as np
from PIL import Image

# Optional imports — only used if that backend is selected
try:
    import coremltools as ct
except Exception:
    ct = None

try:
    import torch
    import open_clip
except Exception:
    torch = None
    open_clip = None


BASE_DIR = os.path.dirname(__file__)

DEFAULT_COREML_MODEL = os.path.join(
    BASE_DIR,
    "..",
    "DemoApp",
    "MLModels",
    "mobileclip_s0_image.mlpackage",
)

DEFAULT_OPENCLIP_MODEL = "MobileCLIP-S1"
DEFAULT_OPENCLIP_PRETRAINED = "datacompdr"


def _get_env(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value else default


def prepare_coreml_image(img: Image.Image, size: int = 256) -> Image.Image:
    """
    Prepare PIL image for CoreML MobileCLIP encoder.

    The CoreML model expects fixed-size image inputs. We resize to 256x256,
    which matches the pipeline assumptions used elsewhere.
    """
    if img.mode != "RGB":
        img = img.convert("RGB")
    return img.resize((size, size), Image.Resampling.BICUBIC)


def load_encoder() -> Tuple[Callable[[List[Image.Image]], np.ndarray], Dict[str, Any]]:
    """
    Returns:
      encode_pil_images: function(List[PIL.Image]) -> np.ndarray of shape (N, D)
      encoder_meta: dict with backend/model metadata

    Backends:
      - coreml   (default if model exists)
      - open_clip
    """
    backend = _get_env("SHOTCOACH_ENCODER_BACKEND", "auto").lower()

    if backend == "auto":
        if os.path.exists(DEFAULT_COREML_MODEL):
            backend = "coreml"
        else:
            backend = "open_clip"

    if backend == "coreml":
        return _load_coreml_encoder()

    if backend == "open_clip":
        return _load_openclip_encoder()

    raise ValueError(
        f"Unsupported SHOTCOACH_ENCODER_BACKEND='{backend}'. "
        f"Use 'coreml', 'open_clip', or unset it."
    )


def _load_coreml_encoder() -> Tuple[Callable[[List[Image.Image]], np.ndarray], Dict[str, Any]]:
    if ct is None:
        raise ImportError(
            "coremltools is not installed, but CoreML backend was requested."
        )

    model_path = _get_env("SHOTCOACH_COREML_MODEL_PATH", DEFAULT_COREML_MODEL)
    input_name = _get_env("SHOTCOACH_COREML_INPUT_NAME", "image")
    output_name = _get_env("SHOTCOACH_COREML_OUTPUT_NAME", "final_emb_1")
    image_size = int(_get_env("SHOTCOACH_COREML_IMAGE_SIZE", "256"))

    if not os.path.exists(model_path):
        raise FileNotFoundError(f"CoreML model not found: {model_path}")

    mlmodel = ct.models.MLModel(model_path)

    def encode_one(img: Image.Image) -> np.ndarray:
        img = prepare_coreml_image(img, size=image_size)
        result = mlmodel.predict({input_name: img})
        emb = result[output_name]
        return np.array(emb, dtype=np.float32).reshape(-1)

    def encode_pil_images(images: List[Image.Image]) -> np.ndarray:
        embs = [encode_one(img) for img in images]
        if not embs:
            return np.zeros((0, 0), dtype=np.float32)
        return np.stack(embs, axis=0).astype(np.float32)

    # Infer embedding dimension safely
    sample = Image.new("RGB", (image_size, image_size), color="black")
    emb = encode_one(sample)

    meta = {
        "backend": "coreml",
        "model_path": model_path,
        "input_name": input_name,
        "output_name": output_name,
        "image_size": image_size,
        "embedding_dim": int(emb.shape[0]),
    }

    return encode_pil_images, meta


def _load_openclip_encoder() -> Tuple[Callable[[List[Image.Image]], np.ndarray], Dict[str, Any]]:
    if torch is None or open_clip is None:
        raise ImportError(
            "torch/open_clip are not installed, but open_clip backend was requested."
        )

    model_name = _get_env("SHOTCOACH_OPENCLIP_MODEL", DEFAULT_OPENCLIP_MODEL)
    pretrained = _get_env("SHOTCOACH_OPENCLIP_PRETRAINED", DEFAULT_OPENCLIP_PRETRAINED)

    device = "mps" if torch.backends.mps.is_available() else "cpu"

    model, _, preprocess = open_clip.create_model_and_transforms(
        model_name,
        pretrained=pretrained,
    )
    model = model.to(device)
    model.eval()

    def encode_pil_images(images: List[Image.Image]) -> np.ndarray:
        if not images:
            return np.zeros((0, 0), dtype=np.float32)

        tensors = []
        for img in images:
            if img.mode != "RGB":
                img = img.convert("RGB")
            tensors.append(preprocess(img))

        batch = torch.stack(tensors).to(device)

        with torch.no_grad():
            emb = model.encode_image(batch)

        return emb.detach().cpu().float().numpy().astype(np.float32)

    # Infer embedding dimension safely
    dummy = Image.new("RGB", (256, 256), color="black")
    emb = encode_pil_images([dummy])

    meta = {
        "backend": "open_clip",
        "model_name": model_name,
        "pretrained": pretrained,
        "device": device,
        "embedding_dim": int(emb.shape[1]),
    }

    return encode_pil_images, meta


def save_embedding_metadata(path: str, meta: Dict[str, Any]) -> None:
    with open(path, "w") as f:
        json.dump(meta, f, indent=2)
