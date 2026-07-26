# Buat aset ikon & splash Android dari logo aplikasi (frontend/build/icon.png).
# Hasil ke mobile/assets/ lalu dipakai `npx capacitor-assets generate --android`.
from PIL import Image
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
SRC = os.path.join(REPO, "frontend", "build", "icon.png")   # logo Tuléh (sama dgn .exe)
OUT = os.path.join(HERE, "assets")
os.makedirs(OUT, exist_ok=True)
logo = Image.open(SRC).convert("RGBA")

def canvas(size, bg):
    return Image.new("RGBA", (size, size), bg if bg else (0, 0, 0, 0))

def center(base, target_w):
    w, h = logo.size
    s = target_w / max(w, h)
    lw, lh = int(w * s), int(h * s)
    rl = logo.resize((lw, lh), Image.LANCZOS)
    base.alpha_composite(rl, ((base.width - lw) // 2, (base.height - lh) // 2))
    return base

WHITE = (255, 255, 255, 255)
LIGHT = (243, 250, 248, 255)   # --bg terang
DARK = (14, 22, 38, 255)       # --bg gelap

center(canvas(1024, None), int(1024 * 0.60)).save(os.path.join(OUT, "icon-foreground.png"))
canvas(1024, WHITE).save(os.path.join(OUT, "icon-background.png"))
center(canvas(1024, WHITE), int(1024 * 0.76)).save(os.path.join(OUT, "icon-only.png"))
center(canvas(2732, LIGHT), 760).save(os.path.join(OUT, "splash.png"))
center(canvas(2732, DARK), 760).save(os.path.join(OUT, "splash-dark.png"))
print("OK icons →", OUT)
