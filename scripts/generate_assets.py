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


def chime_samples(length=2.6, decay=0.75, amp=0.32):
    """The chime's two soft bell notes (E5 then A5) as floats; `chime()` keeps the original 2.6 s take."""
    notes = [(0.00, 659.25), (0.22, 880.00)]
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        s = 0.0
        for start, f in notes:
            if t < start:
                continue
            u = t - start
            env = min(1.0, u / 0.012) * math.exp(-u / decay)
            s += env * (math.sin(2 * math.pi * f * u)
                        + 0.25 * math.sin(2 * math.pi * 2 * f * u)
                        + 0.06 * math.sin(2 * math.pi * 3 * f * u))
        out.append(amp * s * min(1.0, (length - t) / 0.15))
    return out


def bell(freq, length, decay):
    """A struck bell: inharmonic partials, the high ones dying first."""
    partials = [(1.0, 1.0, 1.0), (2.76, 0.35, 0.5), (5.40, 0.12, 0.3), (0.5, 0.25, 1.4)]
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        att = min(1.0, t / 0.004)
        s = sum(a * math.exp(-t / (decay * d)) * math.sin(2 * math.pi * freq * m * t) for m, a, d in partials)
        out.append(att * s * min(1.0, (length - t) / 0.12))
    return out


def knock(freq, length, seed):
    """A wood block: a fast-dying hollow tone plus a tick of noise."""
    rng = random.Random(seed)
    out, low = [], 0.0
    for i in range(int(RATE * length)):
        t = i / RATE
        low += 0.5 * (rng.uniform(-1, 1) - low)
        tone = math.sin(2 * math.pi * freq * t) + 0.4 * math.sin(2 * math.pi * 2.3 * freq * t)
        out.append(math.exp(-t / 0.035) * tone + 0.3 * math.exp(-t / 0.004) * low)
    return out


def pad(freqs, length):
    """A soft detuned chord with slow attack and release."""
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        env = min(1.0, t / 0.3) * min(1.0, (length - t) / 0.6)
        s = sum(math.sin(2 * math.pi * f * t) + math.sin(2 * math.pi * f * 1.004 * t) for f in freqs)
        out.append(env * s)
    return out


def square(freq, length):
    """A softened square wave (first three odd harmonics) for 8-bit sounds."""
    out = []
    for i in range(int(RATE * length)):
        t = i / RATE
        p = 2 * math.pi * freq * t
        env = min(1.0, t / 0.003) * min(1.0, (length - t) / 0.03)
        out.append(env * (math.sin(p) + math.sin(3 * p) / 3 + math.sin(5 * p) / 5))
    return out


def loudness(samples, window=0.3):
    """RMS of the loudest 300 ms, so short and long sounds compare by how they hit."""
    n = int(RATE * window)
    sq = [v * v for v in samples]
    best = acc = sum(sq[:n])
    for i in range(n, len(sq)):
        acc += sq[i] - sq[i - n]
        best = max(best, acc)
    return math.sqrt(best / min(n, len(sq)))


def normalised(samples, target):
    gain = target / max(loudness(samples), 1e-9)
    peak = max(abs(v) for v in samples) * gain
    if peak > 0.95:  # never clip; quieter than target is better than distorted
        gain *= 0.95 / peak
    return [v * gain for v in samples]


PACK = ["chime", "bell", "beep", "blip", "wood", "softpad", "arcade"]


def sound_pack(folder: Path) -> None:
    """Pickable alert sounds (pack_<name>.wav), 0.3-1.5 s, levelled to the chime. Names match SoundBoard.builtIns."""
    folder.mkdir(parents=True, exist_ok=True)
    target = loudness(chime_samples())
    sounds = {
        "chime": chime_samples(1.5, 0.42),
        "bell": bell(784.0, 1.5, 0.45),
        "beep": blip(880, 0.12) + silence(0.07) + blip(880, 0.12) + silence(0.07) + blip(880, 0.16),
        "blip": blip(523, 0.08) + blip(659, 0.08) + blip(784, 0.08) + blip(1047, 0.14),
        "wood": knock(900, 0.18, 7) + knock(1200, 0.28, 8),
        "softpad": pad([261.63, 329.63, 392.0, 523.25], 1.4),
        "arcade": square(988, 0.08) + square(1319, 0.32),
    }
    assert list(sounds) == PACK
    for name, samples in sounds.items():
        length = len(samples) / RATE
        assert 0.3 <= length <= 1.5, (name, length)
        write_wav(folder / f"pack_{name}.wav", normalised(samples, target))


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
    # A white terminal prompt ">_" on solid black (same artwork as the website logo).
    S = 1024
    black = (0, 0, 0)
    white = (255, 255, 255)

    def cov(d):  # signed distance -> coverage, ~1.5px antialiasing
        return max(0.0, min(1.0, 0.5 - d / 1.5))

    def seg(px, py, ax, ay, bx, by, r):
        vx, vy, wx, wy = bx - ax, by - ay, px - ax, py - ay
        h = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy)))
        return math.hypot(wx - vx * h, wy - vy * h) - r

    def mix(a, b, k):
        return tuple(a[i] + (b[i] - a[i]) * k for i in range(3))

    r = 0.0425 * S  # round-capped strokes, 8.5% of the icon wide
    p = lambda fx, fy: (fx * S, fy * S)
    (ax, ay), (bx, by), (cx, cy) = p(0.27, 0.33), p(0.45, 0.50), p(0.27, 0.67)
    (ux, uy), (vx, vy) = p(0.55, 0.67), p(0.74, 0.67)

    def pixel(x, y):
        chevron = min(seg(x, y, ax, ay, bx, by, r), seg(x, y, bx, by, cx, cy, r))
        underscore = seg(x, y, ux, uy, vx, vy, r)
        c = mix(black, white, cov(min(chevron, underscore)))
        return tuple(int(round(v)) for v in c)

    png(path, S, pixel)


if __name__ == "__main__":
    RES.mkdir(parents=True, exist_ok=True)
    chime(RES / "chime.wav")
    ui_sounds(RES / "Sounds")
    sound_pack(RES / "Sounds")
    # App icons (all styles) come from scripts/generate_icons.py.
    print("wrote chime.wav, Sounds/*.wav (incl. pack_*.wav) and icon-1024.png")
