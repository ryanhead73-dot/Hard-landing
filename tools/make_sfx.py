"""Generate the slice's placeholder sound effects as 16-bit mono WAVs.

    python3 tools/make_sfx.py            # writes godot/audio/*.wav

Everything is synthesised (noise, sines, simple filters) so the repo has no third-party audio.
Replace any file with a recorded sound of the same name and the game picks it up.
"""

import os
import struct

import numpy as np

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "audio")
rng = np.random.default_rng(7)


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def noise(seconds):
    return rng.uniform(-1.0, 1.0, int(RATE * seconds))


def lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, low, high):
    return lowpass(highpass(x, low), high)


def sine(freq, seconds, phase=0.0):
    tt = t(seconds)
    if callable(freq):
        return np.sin(2.0 * np.pi * np.cumsum(freq(tt)) / RATE + phase)
    return np.sin(2.0 * np.pi * freq * tt + phase)


def env(seconds, attack=0.002, decay=10.0):
    tt = t(seconds)
    return np.minimum(tt / attack, 1.0) * np.exp(-tt * decay)


def place(total, *parts):
    """Mixes (start_seconds, signal) pairs into one buffer."""
    out = np.zeros(int(RATE * total))
    for start, sig in parts:
        i = int(RATE * start)
        n = min(len(sig), len(out) - i)
        out[i:i + n] += sig[:n]
    return out


def write(name, x, peak=0.9, loop=False):
    """Writes a 16-bit mono WAV. Loops get a 'smpl' chunk, which Godot's importer reads as loop points."""
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    pcm = (x / m * peak * 32767).astype("<i2").tobytes()
    chunks = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, 1, RATE, RATE * 2, 2, 16)
    if loop:
        frames = len(pcm) // 2
        smpl = struct.pack("<9I", 0, 0, 1_000_000_000 // RATE, 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        chunks += struct.pack("<4sI", b"smpl", len(smpl)) + smpl
    chunks += struct.pack("<4sI", b"data", len(pcm)) + pcm
    with open(os.path.join(OUT, f"{name}.wav"), "wb") as fh:
        fh.write(struct.pack("<4sI4s", b"RIFF", 4 + len(chunks), b"WAVE") + chunks)
    print(f"{name}.wav  {len(pcm) / 2 / RATE:.2f}s{'  (loop)' if loop else ''}")


def click(seconds=0.03, cutoff=3000):
    return highpass(noise(seconds), cutoff) * env(seconds, 0.0005, 120)


def main():
    os.makedirs(OUT, exist_ok=True)

    d = 0.4
    crack = highpass(noise(d), 2500) * env(d, 0.0005, 60)
    body = lowpass(noise(d), 1800) * env(d, 0.001, 14)
    thump = sine(lambda tt: 90 - 50 * tt / d, d) * env(d, 0.001, 22)
    write("rifle_shot", 0.6 * crack + body + 1.2 * thump)

    slide = bandpass(noise(0.25), 800, 3000) * env(0.25, 0.05, 8)
    write("rifle_reload", place(1.5, (0.0, click()), (0.08, click(0.04, 1500)), (0.55, slide), (1.25, click(0.05, 1200)), (1.3, click())))
    write("rifle_empty", click(0.05, 2000))

    write("hit_tick", sine(1600, 0.04) * env(0.04, 0.001, 70), peak=0.5)
    write("kill_tick", place(0.15, (0.0, sine(1400, 0.05) * env(0.05, 0.001, 60)), (0.06, sine(2100, 0.08) * env(0.08, 0.001, 40))), peak=0.6)

    d = 0.55
    chitter = bandpass(noise(d), 1800, 4500) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 28 * t(d)))) * env(d, 0.01, 5)
    write("scuttler_alert", chitter)
    d = 0.45
    hiss = highpass(noise(d), 3000) * np.minimum(t(d) / d, 1.0) ** 2 * (1 - np.exp(-(d - t(d)) * 40))
    write("scuttler_lunge", hiss, peak=0.7)
    write("scuttler_hurt", lowpass(noise(0.14), 1400) * env(0.14, 0.001, 30))
    d = 0.7
    squeal = sine(lambda tt: 900 - 700 * tt / d, d) * env(d, 0.005, 5) * 0.4
    crunch = lowpass(noise(0.3), 1000) * env(0.3, 0.001, 14)
    write("scuttler_death", place(d, (0.0, crunch), (0.0, squeal)))

    d = 0.3
    write("player_hurt", sine(lambda tt: 110 - 60 * tt / d, d) * env(d, 0.002, 14) + 0.4 * lowpass(noise(d), 600) * env(d, 0.002, 20))
    blip = np.concatenate([sine(880, 0.05), sine(1320, 0.07)])
    write("scrap_pickup", blip * env(len(blip) / RATE, 0.002, 18), peak=0.5)

    d = 1.2
    hum = (sine(110, d) + 0.5 * sine(220, d) + 0.25 * sine(330, d)) * np.minimum(t(d) / 0.3, 1.0) * np.exp(-t(d) * 1.5)
    write("cell_pickup", place(d, (0.0, click(0.06, 800)), (0.02, hum)))

    d = 2.6
    sweep = lambda tt: 50 + 170 * (tt / d) ** 1.5
    power = (sine(sweep, d) + 0.5 * sine(lambda tt: 2 * sweep(tt), d) + 0.2 * sine(lambda tt: 3 * sweep(tt), d))
    power *= np.minimum(t(d) / 0.4, 1.0) * np.minimum((d - t(d)) / 0.6, 1.0)
    clunk = lowpass(noise(0.2), 500) * env(0.2, 0.001, 18)
    write("power_up", place(d + 0.3, (0.0, clunk * 1.5), (0.1, power), (d - 0.2, clunk * 2.0)))

    d = 1.4
    saw = 2 * ((200 * t(d)) % 1.0) - 1
    whir = lowpass(saw, 1200) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t(d))) * np.minimum(t(d) / 0.1, 1.0) * np.minimum((d - t(d)) / 0.2, 1.0)
    ding = (sine(1320, 0.8) + 0.4 * sine(2640, 0.8)) * env(0.8, 0.002, 5)
    write("fabricate", place(d + 0.8, (0.0, whir * 0.7), (d, ding)))

    write("beacon_ping", sine(1900, 0.18) * env(0.18, 0.003, 18), peak=0.4)
    for i, cutoff in enumerate((500, 700)):
        write(f"footstep_{i}", lowpass(noise(0.09), cutoff) * env(0.09, 0.002, 45), peak=0.5)

    # Loops: length is a whole number of cycles for every tone so they repeat without a click.
    d = 8.0
    wind = lowpass(lowpass(noise(d), 300), 300)
    gust = 0.6 + 0.4 * np.sin(2 * np.pi * t(d) / d) ** 2
    fade = int(RATE * 0.5)
    wind = wind * gust
    wind[:fade] = wind[:fade] * np.linspace(0, 1, fade) + wind[-fade:] * np.linspace(1, 0, fade)
    write("wind_loop", wind[: len(wind) - fade], peak=0.6, loop=True)
    d = 4.0
    ship = sine(55, d) + 0.6 * sine(110, d) + 0.15 * sine(165, d) + 0.1 * sine(440, d) * (0.5 + 0.5 * sine(0.5, d))
    write("ship_hum_loop", ship, peak=0.5, loop=True)

    # Added after the loops so earlier sounds keep the same random noise.
    d = 0.9
    write("steam_hiss", highpass(noise(d), 2500) * (t(d) / d) ** 2 * np.minimum((d - t(d)) / 0.05, 1.0), peak=0.5)
    d = 1.4
    roar = bandpass(noise(d), 300, 4000) * np.minimum(t(d) / 0.03, 1.0) * np.exp(-t(d) * 1.6)
    write("steam_burst", roar + 0.5 * lowpass(noise(d), 200) * env(d, 0.005, 4))
    d = 1.0
    ring = (sine(430, d) + 0.7 * sine(1170, d) + 0.4 * sine(2290, d)) * env(d, 0.001, 6)
    write("manifold_pickup", place(d, (0.0, lowpass(noise(0.15), 900) * env(0.15, 0.001, 20)), (0.0, ring * 0.6)))

    # Milestone 1: the five new sites and Kestrel's turret.
    d = 1.0
    write("rock_impact", lowpass(noise(d), 400) * env(d, 0.001, 6) + 0.6 * sine(lambda tt: 70 - 30 * tt / d, d) * env(d, 0.001, 8))
    d = 0.6
    buzz = (np.sign(np.sin(2 * np.pi * 120 * t(d))) * 0.4 + highpass(noise(d), 3000)) * env(d, 0.001, 5)
    write("arc_zap", buzz, peak=0.7)
    d = 1.2
    write("spore_burst", place(d, (0.0, lowpass(noise(0.1), 700) * env(0.1, 0.001, 30)), (0.02, bandpass(noise(1.1), 400, 2500) * env(1.1, 0.02, 3))), peak=0.7)
    d = 1.4
    write("loom_hum", (sine(lambda tt: 40 + 40 * tt / d, d) + 0.5 * sine(lambda tt: 120 + 120 * tt / d, d)) * np.minimum(t(d) / d, 1.0) ** 2 * np.minimum((d - t(d)) / 0.05, 1.0), peak=0.8)
    d = 0.2
    write("turret_shot", 0.5 * highpass(noise(d), 2000) * env(d, 0.0005, 50) + sine(lambda tt: 160 - 80 * tt / d, d) * env(d, 0.001, 25), peak=0.6)


if __name__ == "__main__":
    main()
