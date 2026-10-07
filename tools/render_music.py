"""Render the Ball Connect background music to assets/music/calm_loop.ogg.

Own synthesis, no samples: slow detuned pads, a soft sine bass and a sparse
bell melody on the D major pentatonic scale, through a long convolution
reverb. 64 BPM, no drums, every note has a soft attack (at least 25 ms).

Seamless loop: every note is rendered into a buffer longer than the loop and
the part past the loop end is added back onto the start (circular wrap), and
the reverb is a circular convolution over the loop length. The file is
therefore exactly periodic: the sample after the last one is the first one.

Output: 44.1 kHz mono Ogg Vorbis (libvorbis via ffmpeg). Mono and a moderate
VBR quality keep the file under the repo's 1 MB per-file pre-commit cap.
Deterministic: every random choice has a fixed seed.

Usage:
    python3 tools/render_music.py [--out assets/music/calm_loop.ogg] [--wav x.wav]
"""

from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf
from scipy import signal

SR = 44100
BPM = 64.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
BARS = 32  # 32 bars at 64 BPM = 120.0 s
LOOP_S = BARS * BAR
N = int(round(LOOP_S * SR))
TAIL_S = 12.0  # longest note release that wraps back onto the start
PEAK_DBFS = -3.0
VORBIS_Q = "4"  # libvorbis VBR quality (mono 44.1 kHz)

# MIDI note numbers. Key: D major, melody on D major pentatonic.
PENTA = [62, 64, 66, 69, 71, 74, 76, 78, 81]  # D4 E4 F#4 A4 B4 D5 E5 F#5 A5
# Two bars per chord: Dmaj9, Bm7(add11), Gmaj7, A6sus2.
CHORDS = [
    (38, [50, 57, 61, 64, 66]),
    (35, [47, 54, 57, 62, 64]),
    (31, [43, 50, 54, 59, 62]),
    (33, [45, 52, 57, 59, 64]),
]


def hz(midi: float) -> float:
    return 440.0 * 2.0 ** ((midi - 69.0) / 12.0)


def tt(dur: float) -> np.ndarray:
    return np.arange(int(dur * SR)) / SR


def lp(x: np.ndarray, f: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, f, btype="lowpass", fs=SR, output="sos"), x)


def hp(x: np.ndarray, f: float, order: int = 2) -> np.ndarray:
    return signal.sosfilt(signal.butter(order, f, btype="highpass", fs=SR, output="sos"), x)


def place(buf: np.ndarray, x: np.ndarray, start_s: float) -> None:
    """Add x into buf at start_s; buf is longer than the loop by TAIL_S."""
    i = int(round(start_s * SR))
    seg = x[: max(0, len(buf) - i)]
    buf[i : i + len(seg)] += seg


def wrap(buf: np.ndarray) -> np.ndarray:
    """Fold everything past the loop end back onto the start."""
    out = buf[:N].copy()
    rest = buf[N:]
    while len(rest):
        k = min(len(rest), N)
        out[:k] += rest[:k]
        rest = rest[k:]
    return out


def ad_env(dur: float, attack: float, release: float) -> np.ndarray:
    """Raised-cosine attack, flat hold, raised-cosine release to exact zero."""
    t = tt(dur)
    a = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / attack, 0.0, 1.0))
    r = 0.5 - 0.5 * np.cos(np.pi * np.clip((dur - t) / release, 0.0, 1.0))
    return a * r


def pad_voice(midi: int, dur: float, rng: np.random.Generator) -> np.ndarray:
    """Three detuned sine/triangle-ish partials, slow attack and release."""
    t = tt(dur)
    f = hz(midi)
    x = np.zeros_like(t)
    for cents in (-7.0, 0.0, 6.0):
        fc = f * 2.0 ** (cents / 1200.0)
        ph = rng.uniform(0, 2 * np.pi)
        # Soft triangle: odd harmonics at 1/n^2, only the first three.
        x += np.sin(2 * np.pi * fc * t + ph)
        x += np.sin(2 * np.pi * 3 * fc * t + 3 * ph) / 9.0 * 0.6
        x += np.sin(2 * np.pi * 5 * fc * t + 5 * ph) / 25.0 * 0.4
    return x / 3.0 * ad_env(dur, 2.6, 3.2)


def bass(midi: int, dur: float) -> np.ndarray:
    t = tt(dur)
    f = hz(midi)
    x = np.sin(2 * np.pi * f * t) + 0.18 * np.sin(2 * np.pi * 2 * f * t)
    return x * ad_env(dur, 1.8, 2.8)


def bell(midi: int, rng: np.random.Generator) -> np.ndarray:
    """Soft glassy bell: sine partials, 30 ms attack, long exponential decay."""
    dur = 5.0
    t = tt(dur)
    f = hz(midi)
    x = np.zeros_like(t)
    for ratio, amp, tau in ((1.0, 1.0, 1.9), (2.0, 0.22, 0.9), (3.0, 0.07, 0.5), (4.01, 0.03, 0.3)):
        x += amp * np.sin(2 * np.pi * f * ratio * t + rng.uniform(0, 2 * np.pi)) * np.exp(-t / tau)
    att = 0.5 - 0.5 * np.cos(np.pi * np.clip(t / 0.03, 0.0, 1.0))
    end = 0.5 - 0.5 * np.cos(np.pi * np.clip((dur - t) / 1.0, 0.0, 1.0))
    return lp(x * att * end, 3500.0)


def melody(rng: np.random.Generator) -> list[tuple[float, int, float]]:
    """(start_s, midi, gain) per bell note. Sparse first pass, fuller later."""
    notes: list[tuple[float, int, float]] = []
    idx = 4
    density = [0.0, 0.3, 0.45, 0.3]  # per 8-bar section; section 0 = pads only
    for bar in range(BARS):
        section = bar // 8
        for beat in range(4):
            if rng.random() >= density[section]:
                continue
            # Gentle random walk on the pentatonic scale, mostly steps.
            idx = int(np.clip(idx + rng.choice([-2, -1, -1, 0, 1, 1, 2]), 0, len(PENTA) - 1))
            start = bar * BAR + beat * BEAT
            gain = 0.55 + 0.25 * rng.random()
            notes.append((start, PENTA[idx], gain))
    return notes


def reverb_ir(rt: float, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    t = tt(rt * 1.2)
    ir = rng.standard_normal(len(t)) * np.exp(-6.9 * t / rt)
    ir = lp(ir, 4500.0)
    ir[: int(0.02 * SR)] *= np.linspace(0.0, 1.0, int(0.02 * SR))  # 20 ms pre-delay fade
    return ir / np.sqrt(np.sum(ir**2))


def circular_convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    h = np.zeros(len(x))
    h[: len(ir)] = ir
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n=len(x))


def render() -> np.ndarray:
    rng = np.random.default_rng(20261006)
    buf_len = N + int(TAIL_S * SR)
    pads = np.zeros(buf_len)
    low = np.zeros(buf_len)
    bells = np.zeros(buf_len)

    chord_len = 2 * BAR
    for k in range(BARS // 2):
        root, voicing = CHORDS[k % len(CHORDS)]
        start = k * chord_len
        dur = chord_len + 3.2  # overlap into the next chord's attack
        for m in voicing:
            place(pads, pad_voice(m, dur, rng), start)
        place(low, bass(root, dur), start)

    for start, m, g in melody(rng):
        place(bells, bell(m, rng) * g, start)

    pads = wrap(pads)
    low = wrap(low)
    bells = wrap(bells)

    # Slow periodic swell (exactly 4 cycles per loop) so the pad breathes.
    t = np.arange(N) / SR
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * 4.0 * t / LOOP_S)
    pads = lp(np.concatenate([pads, pads]), 2400.0)[N:] * swell  # filter with warm-up, stays periodic

    dry = 0.30 * pads + 0.32 * low + 0.20 * bells
    wet = circular_convolve(0.30 * pads + 0.28 * bells, reverb_ir(4.0, 7))
    mix = dry + 0.55 * wet
    mix = hp(np.concatenate([mix, mix]), 35.0)[N:]  # remove DC, periodic
    mix -= np.mean(mix)
    return mix / np.max(np.abs(mix)) * 10 ** (PEAK_DBFS / 20.0)


def encode(x: np.ndarray, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as d:
        wav = Path(d) / "loop.wav"
        sf.write(wav, x.astype(np.float32), SR, subtype="FLOAT")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-c:a", "libvorbis",
             "-q:a", VORBIS_Q, "-ac", "1", str(out)],
            check=True,
        )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/music/calm_loop.ogg")
    ap.add_argument("--wav", default="", help="also write the raw float WAV here")
    args = ap.parse_args()
    x = render()
    if args.wav:
        sf.write(args.wav, x.astype(np.float32), SR, subtype="FLOAT")
    encode(x, Path(args.out))
    rms = 20 * np.log10(np.sqrt(np.mean(x**2)))
    print(f"rendered {len(x) / SR:.2f} s, peak {20 * np.log10(np.max(np.abs(x))):.2f} dBFS, rms {rms:.2f} dBFS")
    print(f"seam: first {x[0]:+.5f} last {x[-1]:+.5f} step {abs(x[0] - x[-1]):.5f}, "
          f"median step {np.median(np.abs(np.diff(x))):.5f}, max step {np.max(np.abs(np.diff(x))):.5f}")


if __name__ == "__main__":
    main()
