"""Turn raw iPhone screenshots into App Store Connect sized PNGs.

Usage (from "Nordic Sports iOS Companion"):
    python store/tools/make_screenshots.py <src_dir> <locale> [--size 1179x2556] [--blur x0,y0,x1,y1@file ...]

- Scales each PNG/JPG in <src_dir> (sorted by name) to the target width and pads/crops the
  height with the bottom-left pixel colour, so the result is exactly the target size.
- Output: store/screenshots/iphone-6.3/<locale>/NN_<stem>_<W>x<H>.png
- --blur takes fractions of the source image (0..1) and the source file name, e.g.
  --blur 0.76,0.90,0.975,0.95@20261022_184643000_iOS.png  (blurs the place name on the detail screen)

Accepted ASC sizes for the "iPhone with Dynamic Island (medium display)" slot (6.1"/6.3"):
1179x2556, 1206x2622 (portrait). 6.9" slot: 1290x2796 or 1320x2868.
"""
import argparse
import pathlib
from PIL import Image, ImageFilter

p = argparse.ArgumentParser()
p.add_argument("src")
p.add_argument("locale")
p.add_argument("--size", default="1179x2556")
p.add_argument("--blur", action="append", default=[])
a = p.parse_args()

W, H = map(int, a.size.split("x"))
root = pathlib.Path(__file__).resolve().parents[1]
out = root / "screenshots" / ("iphone-6.3" if W < 1250 else "iphone-6.9") / a.locale
out.mkdir(parents=True, exist_ok=True)

blurs = {}
for b in a.blur:
    box, name = b.split("@")
    blurs.setdefault(name, []).append([float(v) for v in box.split(",")])

files = sorted(f for f in pathlib.Path(a.src).iterdir() if f.suffix.lower() in (".png", ".jpg", ".jpeg"))
for i, f in enumerate(files, 1):
    im = Image.open(f).convert("RGB")
    for x0, y0, x1, y1 in blurs.get(f.name, []):
        box = (int(im.width * x0), int(im.height * y0), int(im.width * x1), int(im.height * y1))
        im.paste(im.crop(box).filter(ImageFilter.GaussianBlur(14)), box)
    h = round(im.height * W / im.width)
    im = im.resize((W, h), Image.LANCZOS)
    canvas = Image.new("RGB", (W, H), im.getpixel((5, min(h, H) - 5)))
    canvas.paste(im.crop((0, 0, W, min(h, H))), (0, 0))
    target = out / f"{i:02d}_{f.stem}_{W}x{H}.png"
    canvas.save(target)
    print(target)
