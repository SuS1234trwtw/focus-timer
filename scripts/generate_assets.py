"""Generates the bundled chime and UI sounds (WAV) and the 1024px app icon (PNG). Stdlib only.

Run from the repo root:  python scripts/generate_assets.py
"""
import math
import random
import struct
import wave
import zlib
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


RATE = 44100


def write_wav(path: Path, samples) -> None:
    frames = bytearray()
    for v in samples:
        frames += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


def click(length=0.014, amp=0.22, seed=1, tone=2400.0):
    """A soft mechanical key click: a filtered noise burst with a faint body tone."""
    rng = random.Random(seed)
    out, low = [], 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        env = math.exp(-t / (length / 5))
        low += 0.35 * (rng.uniform(-1, 1) - low)
        out.append(amp * env * (0.7 * low + 0.3 * math.sin(2 * math.pi * tone * t)))
    return out


def blip(freq, length, amp=0.22, glide_to=None):
    """A short rounded terminal beep, optionally gliding in pitch."""
    out, phase = [], 0.0
    n = int(RATE * length)
    for i in range(n):
        t = i / RATE
        f = freq if glide_to is None else freq + (glide_to - freq) * (i / n)
        phase += 2 * math.pi * f / RATE
        env = min(1.0, t / 0.004) * min(1.0, (length - t) / 0.025)
        out.append(amp * env * (math.sin(phase) + 0.12 * math.sin(3 * phase)))
    return out


def ding(freqs, length, amp=0.2):
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        env = min(1.0, t / 0.005) * math.exp(-t / (length / 3.5))
        out.append(amp * env * sum(math.sin(2 * math.pi * f * t) for f in freqs) / len(freqs))
    return out


def silence(length):
    return [0.0] * int(RATE * length)


def ui_sounds(folder: Path) -> None:
    """Short feedback sounds; names match FeedbackEvent in the app."""
    folder.mkdir(parents=True, exist_ok=True)
    sounds = {
        "tick": click(0.014, 0.20, seed=1),
        "minute": click(0.014, 0.28, seed=2) + silence(0.055) + click(0.018, 0.30, seed=3, tone=1800),
        "start": blip(660, 0.06) + blip(990, 0.09),
        "pause": blip(990, 0.06) + blip(660, 0.09),
        "reset": blip(880, 0.045) + blip(660, 0.045) + blip(440, 0.07),
        "switch": blip(523, 0.07, 0.18) + blip(784, 0.11, 0.18),
        "tap": click(0.008, 0.16, seed=4, tone=3200),
        "task_add": blip(700, 0.07, 0.2, glide_to=1100),
        "task_done": ding([1318.5, 1760.0], 0.32),
        "task_undo": blip(660, 0.06, 0.16, glide_to=520),
        "task_delete": blip(220, 0.09, 0.3, glide_to=120) + click(0.01, 0.12, seed=5, tone=600),
        "task_focus": blip(740, 0.045, 0.18) + blip(988, 0.06, 0.18),
    }
    for name, samples in sounds.items():
        write_wav(folder / f"{name}.wav", samples)


def png(path: Path, size: int, pixel) -> None:
    rows = bytearray()
    for y in range(size):
        rows.append(0)
        for x in range(size):
            rows += bytes(pixel(x + 0.5, y + 0.5))
    def chunk(kind, data):
        c = kind + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n"
    data += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    data += chunk(b"IDAT", zlib.compress(bytes(rows), 9))
    data += chunk(b"IEND", b"")
    path.write_bytes(data)


def icon(path: Path) -> None:
    S = 1024
    bg = (0x1A, 0x16, 0x14)
    orange = (0xF5, 0xA0, 0x5A)
    green = (0x8F, 0xD6, 0x94)
    dark = (0x1A, 0x16, 0x14)

    def cov(d):  # signed distance -> coverage, ~1.5px antialiasing
        return max(0.0, min(1.0, 0.5 - d / 1.5))

    def seg(px, py, ax, ay, bx, by, r):
        vx, vy, wx, wy = bx - ax, by - ay, px - ax, py - ay
        h = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
        return math.hypot(wx - vx * h, wy - vy * h) - r

    def mix(a, b, k):
        return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))

    cx, cy, R = 512, 560, 330

    def pixel(x, y):
        c = bg
        # soft orange glow behind the tomato
        glow = max(0.0, 1 - math.hypot(x - cx, y - cy) / 620) ** 2 * 0.18
        c = mix(c, orange, glow)
        # tomato body
        c = mix(c, orange, cov(math.hypot(x - cx, y - cy) - R))
        # leaf: two capsules
        leaf = min(seg(x, y, 512, 250, 420, 200, 34), seg(x, y, 512, 250, 604, 200, 34),
                   seg(x, y, 512, 250, 512, 170, 22))
        c = mix(c, green, cov(leaf))
        # terminal prompt ">_" cut into the tomato
        chevron = min(seg(x, y, 380, 470, 470, 560, 30), seg(x, y, 470, 560, 380, 650, 30))
        underscore = seg(x, y, 530, 650, 650, 650, 30)
        c = mix(c, dark, cov(min(chevron, underscore)))
        return tuple(int(round(v)) for v in c)

    png(path, S, pixel)


if __name__ == "__main__":
    RES.mkdir(parents=True, exist_ok=True)
    chime(RES / "chime.wav")
    ui_sounds(RES / "Sounds")
    icon(ROOT / "FocusTimer" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "icon-1024.png")
    print("wrote chime.wav, Sounds/*.wav and icon-1024.png")
