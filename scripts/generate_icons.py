"""Draws the `>_` app icon once per terminal style (same artwork as generate_assets.icon()).

AppIcon is mono (the default); the others are alternate icons the app switches to.
Run from the repo root:  python scripts/generate_icons.py   (needs Pillow)
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "FocusTimer" / "Resources" / "Assets.xcassets"

# icon set name: (glyph, background)
STYLES = {
    "AppIcon": ("#F5F5F2", "#050505"),
    "AppIcon-cozy": ("#F5A05A", "#1A1614"),
    "AppIcon-powershell": ("#F9F1A5", "#012456"),
    "AppIcon-cmd": ("#3B78FF", "#0C0C0C"),
    "AppIcon-ubuntu": ("#E95420", "#300A24"),
}

S, SS = 1024, 4  # output size, supersampling for antialiasing


def draw(glyph: str, background: str) -> Image.Image:
    n = S * SS
    img = Image.new("RGB", (n, n), background)
    d = ImageDraw.Draw(img)
    r = 0.0425 * n  # round-capped strokes, 8.5% of the icon wide
    p = lambda fx, fy: (fx * n, fy * n)
    for a, b in [(p(0.27, 0.33), p(0.45, 0.50)), (p(0.45, 0.50), p(0.27, 0.67)), (p(0.55, 0.67), p(0.74, 0.67))]:
        d.line([a, b], fill=glyph, width=round(2 * r))
        for x, y in (a, b):
            d.ellipse([x - r, y - r, x + r, y + r], fill=glyph)
    return img.resize((S, S), Image.LANCZOS)


def main() -> None:
    for name, (glyph, background) in STYLES.items():
        folder = ASSETS / f"{name}.appiconset"
        folder.mkdir(parents=True, exist_ok=True)
        draw(glyph, background).save(folder / "icon-1024.png")
        contents = {
            "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
            "info": {"author": "xcode", "version": 1},
        }
        (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", newline="\n")
        print(f"wrote {name}.appiconset")


if __name__ == "__main__":
    main()
