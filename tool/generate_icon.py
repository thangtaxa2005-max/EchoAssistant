"""Generate Echo launcher icons. Run once when the visual identity changes."""

from pathlib import Path
from math import sin, pi
from PIL import Image, ImageDraw


ROOT = Path(__file__).absolute().parents[1]
SIZE = 1024
image = Image.new("RGB", (SIZE, SIZE), "#E5F3F0")
draw = ImageDraw.Draw(image)

# Four calm sound waves, matching the mint and teal app palette.
for center_y, amplitude, phase in [
    (325, 26, 0.0),
    (450, 44, 0.45),
    (575, 38, 0.9),
    (700, 20, 1.35),
]:
    points = [
        (x, center_y + amplitude * sin((x - 195) / 630 * 2.2 * pi + phase))
        for x in range(195, 827, 3)
    ]
    for x, y in points:
        draw.ellipse((x - 24, y - 24, x + 24, y + 24), fill="#087F79")

sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
for density, pixels in sizes.items():
    icon = image.resize((pixels, pixels), Image.Resampling.LANCZOS)
    for base in (ROOT / "tool" / "icons", ROOT / "android" / "app" / "src" / "main" / "res"):
        target = base / f"mipmap-{density}" / "ic_launcher.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        icon.save(target)

image.resize((512, 512), Image.Resampling.LANCZOS).save(ROOT / "tool" / "echo_icon.png")
