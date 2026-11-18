"""Generate the project icon (magnifier with a quest '!') in every size the project needs.

Usage: python assets/make_icon.py   (run from the repository root)
Outputs:
  assets/logo-512.png                  CurseForge / GitHub logo
  WowheadForeverLink/icon.png          in-game icon (64x64, used by the .toc and buttons)
  companion/app.ico                    Windows icon for the companion .exe
"""
from PIL import Image, ImageDraw

S = 2048  # drawing canvas, downscaled for anti-aliasing

GOLD = (232, 179, 58, 255)
GOLD_DARK = (150, 100, 20, 255)
OUTLINE = (30, 18, 4, 255)
LENS = (18, 28, 50, 240)
YELLOW = (255, 209, 0, 255)
HANDLE = (95, 58, 26, 255)


def draw() -> Image.Image:
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Handle (drawn first, the lens ring covers its end)
    d.line([(1300, 1300), (1880, 1880)], fill=OUTLINE, width=300)
    d.line([(1300, 1300), (1860, 1860)], fill=HANDLE, width=220)
    d.line([(1300, 1300), (1420, 1420)], fill=GOLD_DARK, width=230)

    # Lens: outline, gold ring, dark glass
    cx, cy, r = 860, 860, 690
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=OUTLINE)
    r -= 34
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD)
    r -= 120
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=OUTLINE)
    r -= 24
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=LENS)

    # Quest '!' inside the lens
    d.rounded_rectangle([cx - 105, 400, cx + 105, 1030], radius=100, fill=OUTLINE)
    d.rounded_rectangle([cx - 75, 430, cx + 75, 1000], radius=75, fill=YELLOW)
    d.ellipse([cx - 115, 1085, cx + 115, 1315], fill=OUTLINE)
    d.ellipse([cx - 85, 1115, cx + 85, 1285], fill=YELLOW)

    # Glass highlight
    d.arc([cx - 520, cy - 520, cx + 520, cy + 520], start=200, end=250, fill=(255, 255, 255, 70), width=60)
    return img


def main() -> None:
    big = draw()
    big.resize((512, 512), Image.LANCZOS).save("assets/logo-512.png")
    big.resize((64, 64), Image.LANCZOS).save("WowheadForeverLink/icon.png")
    big.resize((256, 256), Image.LANCZOS).save(
        "companion/app.ico", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    )


if __name__ == "__main__":
    main()
