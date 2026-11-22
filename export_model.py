"""Gör om CLIP-bildmodellen (samma som skapade index.db) till Core ML för iPhone."""
import numpy as np
import torch
import open_clip
import coremltools as ct
from PIL import Image

# Gör att attention kan översättas till Core ML.
try:
    torch.backends.mha.set_fastpath_enabled(False)
except Exception:
    pass

modell, _, preprocess = open_clip.create_model_and_transforms(
    "ViT-B-32", pretrained="laion2b_s34b_b79k")
modell.eval()

# Samma normalisering som open_clip använder vid indexeringen.
try:
    norm = preprocess.transforms[-1]
    mean = [float(x) for x in norm.mean]
    std = [float(x) for x in norm.std]
except Exception:
    mean = [0.48145466, 0.4578275, 0.40821073]
    std = [0.26862954, 0.26130258, 0.27577711]
print("mean:", mean, "std:", std)


class Embedder(torch.nn.Module):
    """Tar bild med pixelvärden 0-255 (RGB) och ger ett normaliserat fingeravtryck (512 tal)."""

    def __init__(self, visual):
        super().__init__()
        self.visual = visual
        self.register_buffer("mean", torch.tensor(mean).view(1, 3, 1, 1))
        self.register_buffer("std", torch.tensor(std).view(1, 3, 1, 1))

    def forward(self, x):
        x = (x / 255.0 - self.mean) / self.std
        f = self.visual(x)
        return f / f.norm(dim=-1, keepdim=True)


wrapper = Embedder(modell.visual).eval()
exempel = torch.rand(1, 3, 224, 224) * 255
with torch.no_grad():
    traced = torch.jit.trace(wrapper, exempel)

ml = ct.convert(
    traced,
    inputs=[ct.ImageType(name="bild", shape=tuple(exempel.shape),
                         color_layout=ct.colorlayout.RGB)],
    outputs=[ct.TensorType(name="embedding")],
    convert_to="mlprogram",
    minimum_deployment_target=ct.target.iOS16,
    compute_precision=ct.precision.FLOAT16,
)
ml.save("ProductEmbedder.mlpackage")
print("Sparade ProductEmbedder.mlpackage")

# Kontroll: ger Core ML samma svar som PyTorch? (fungerar bara på Mac)
try:
    bild = Image.fromarray((np.random.rand(224, 224, 3) * 255).astype("uint8"))
    ut = np.array(ml.predict({"bild": bild})["embedding"]).flatten()
    with torch.no_grad():
        ref = wrapper(torch.from_numpy(np.array(bild)).permute(2, 0, 1).unsqueeze(0).float())
    ref = ref.numpy().flatten()
    cos = float(np.dot(ut, ref) / (np.linalg.norm(ut) * np.linalg.norm(ref)))
    print("Likhet Core ML mot PyTorch:", round(cos, 4))
    if cos < 0.98:
        print("VARNING: Core ML-modellen avviker från originalet.")
except Exception as e:
    print("Kunde inte testa modellen här:", e)
