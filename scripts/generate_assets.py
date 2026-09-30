"""Generates the bundled chime (WAV). Stdlib only.

The app icon is a layered Icon Composer package (FocusTimer/Resources/AppIcon.icon)
whose layers were modelled in Figma alongside the carved numerals.

Run from the repo root:  python scripts/generate_assets.py
"""
import math
import struct
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "FocusTimer" / "Resources"


def chime(path: Path) -> None:
    """Two soft bell-like notes (E5 then A5) with gentle exponential decay."""
    rate, length = 44100, 2.6
    notes = [(0.00, 659.25), (0.22, 880.00)]
    frames = bytearray()
    for i in range(int(rate * length)):
        t = i / rate
        s = 0.0
        for start, f in notes:
            if t < start:
                continue
            u = t - start
            env = min(1.0, u / 0.012) * math.exp(-u / 0.75)
            s += env * (math.sin(2 * math.pi * f * u)
                        + 0.25 * math.sin(2 * math.pi * 2 * f * u)
                        + 0.06 * math.sin(2 * math.pi * 3 * f * u))
        fade = min(1.0, (length - t) / 0.15)
        frames += struct.pack("<h", int(max(-1, min(1, 0.32 * s * fade)) * 32767))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(bytes(frames))


if __name__ == "__main__":
    RES.mkdir(parents=True, exist_ok=True)
    chime(RES / "chime.wav")
    print("wrote chime.wav")
