# Buat aset ikon Android (adaptive foreground/background + legacy) dari wordmark
# Tuléh (logo-dashboard.png) dengan latar MINT #7AE2CF.
# CATATAN: splash.png / splash-dark.png TIDAK disentuh di sini — splash dikelola
# terpisah (dari logo-sharelink). Jalankan dari mobile/:  python gen-icons.py
from PIL import Image
import os

SRC = r"C:\Users\legio\OneDrive\Documents\CLIENT\POS_TAUFIQ\logo-dashboard.png"  # wordmark Tuléh
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
os.makedirs(OUT, exist_ok=True)
MINT = (122, 226, 207, 255)   # #7AE2CF (brand)

wm = Image.open(SRC).convert("RGBA")
wm = wm.crop(wm.getbbox())

def canvas(size, color):
    return Image.new("RGBA", (size, size), color if color else (0, 0, 0, 0))

def place(base, frac):
    out = base.copy()
    w, h = wm.size
    tw = int(base.width * frac); th = int(h * tw / w)
    out.alpha_composite(wm.resize((tw, th), Image.LANCZOS),
                        ((base.width - tw) // 2, (base.height - th) // 2))
    return out

# Adaptive: foreground (wordmark ~64% = dalam safe-zone lingkaran) + background mint
place(canvas(1024, None), 0.64).save(os.path.join(OUT, "icon-foreground.png"))
canvas(1024, MINT).save(os.path.join(OUT, "icon-background.png"))
# Legacy square: wordmark ~72% pada mint
place(canvas(1024, MINT), 0.72).save(os.path.join(OUT, "icon-only.png"))

print("OK ikon (wordmark mint) →", OUT)
for f in ("icon-foreground.png", "icon-background.png", "icon-only.png"):
    print(" ", f, Image.open(os.path.join(OUT, f)).size)
