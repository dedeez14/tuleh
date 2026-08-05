# Buat aset ikon Android (adaptive foreground/background + legacy) dari ikon
# notepad Tuléh (2.png). Latar Android = PUTIH (adaptive icon Android tak bisa
# benar-benar transparan — latar transparan tampil HITAM di banyak launcher).
# Ikon .exe desktop (frontend/build/icon.png) dibuat TERPISAH dengan latar
# transparan. Splash TIDAK disentuh (dikelola dari logo-sharelink).
# Jalankan dari mobile/:  python gen-icons.py
from PIL import Image
import os

SRC = r"C:\Users\legio\OneDrive\Documents\CLIENT\POS_TAUFIQ\2.png"  # notepad transparan
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "assets")
os.makedirs(OUT, exist_ok=True)
WHITE = (255, 255, 255, 255)

wm = Image.open(SRC).convert("RGBA")
wm = wm.crop(wm.getbbox())

def canvas(size, color):
    return Image.new("RGBA", (size, size), color if color else (0, 0, 0, 0))

def place(base, frac):
    out = base.copy()
    w, h = wm.size
    s = int(base.width * frac)
    if w >= h: tw, th = s, int(h * s / w)
    else:      th, tw = s, int(w * s / h)
    out.alpha_composite(wm.resize((tw, th), Image.LANCZOS),
                        ((base.width - tw) // 2, (base.height - th) // 2))
    return out

# Adaptive: foreground (ikon ~66% = dalam safe-zone) transparan + background PUTIH
place(canvas(1024, None), 0.66).save(os.path.join(OUT, "icon-foreground.png"))
canvas(1024, WHITE).save(os.path.join(OUT, "icon-background.png"))
# Legacy square: ikon ~82% pada PUTIH
place(canvas(1024, WHITE), 0.82).save(os.path.join(OUT, "icon-only.png"))

print("OK ikon Android (notepad, latar putih) di", OUT)
