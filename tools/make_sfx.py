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

    # --- Milestone 2: weapons, wildlife, sieges -------------------------------------------
    d = 0.7
    blast = lowpass(noise(d), 2400) * env(d, 0.0005, 9)
    boom = sine(lambda tt: 70 - 35 * tt / d, d) * env(d, 0.001, 10)
    pump = place(0.2, (0.0, click(0.05, 1200)), (0.1, click(0.06, 900)))
    write("scatter_shot", place(1.0, (0.0, 0.5 * highpass(noise(0.1), 3000) * env(0.1, 0.0005, 60)), (0.0, blast + 1.4 * boom), (0.45, pump)))
    d = 0.9
    charge = sine(lambda tt: 300 + 2400 * np.minimum(tt / 0.25, 1.0) ** 2, d) * env(d, 0.001, 4)
    crackle = bandpass(noise(d), 1500, 6000) * env(d, 0.001, 7)
    write("lance_shot", 0.5 * charge + crackle + 0.8 * sine(lambda tt: 55 - 20 * tt / d, d) * env(d, 0.001, 6), peak=0.8)
    write("weapon_switch", place(0.35, (0.0, click(0.04, 1800)), (0.16, click(0.05, 1100))), peak=0.6)
    d = 0.6
    write("stim", place(0.8, (0.0, highpass(noise(0.12), 2500) * env(0.12, 0.002, 25)), (0.12, sine(lambda tt: 500 + 500 * tt / d, d) * env(d, 0.02, 5) * 0.4)), peak=0.6)
    d = 0.5
    write("acid_splash", bandpass(noise(d), 600, 3500) * env(d, 0.001, 9) * (0.6 + 0.4 * np.sin(2 * np.pi * 37 * t(d))), peak=0.7)
    d = 0.8
    gurgle = lowpass(noise(d), 900) * (0.5 + 0.5 * np.sin(2 * np.pi * 14 * t(d))) * np.minimum(t(d) / d, 1.0)
    write("spitter_charge", gurgle, peak=0.6)
    d = 0.35
    write("spitter_spit", place(d, (0.0, bandpass(noise(d), 1200, 4000) * env(d, 0.002, 14)), (0.0, sine(lambda tt: 400 - 250 * tt / d, d) * env(d, 0.002, 18) * 0.5)), peak=0.7)
    d = 0.4
    write("ram_paw", lowpass(noise(d), 300) * env(d, 0.001, 12) + 0.7 * sine(55, d) * env(d, 0.001, 14), peak=0.8)
    d = 1.4
    bellow = (sine(lambda tt: 80 + 30 * np.sin(tt * 9), d) + 0.6 * sine(lambda tt: 160 + 60 * np.sin(tt * 9), d)) * np.minimum(t(d) / 0.2, 1.0) * np.minimum((d - t(d)) / 0.4, 1.0)
    write("ram_charge", bellow + 0.3 * lowpass(noise(d), 500) * np.minimum(t(d) / 0.2, 1.0), peak=0.85)
    d = 0.9
    write("ram_stun", place(d, (0.0, lowpass(noise(0.4), 700) * env(0.4, 0.0005, 9)), (0.0, sine(lambda tt: 120 - 70 * tt / d, d) * env(d, 0.001, 5)), (0.15, sine(2300, 0.5) * env(0.5, 0.001, 9) * 0.25)), peak=0.9)
    d = 2.4
    roar = sum(a * sine(lambda tt, f=f: f * (1 + 0.04 * np.sin(tt * 23)) * (1 - 0.3 * tt / d), d) for a, f in ((1.0, 48), (0.7, 73), (0.5, 97), (0.3, 151)))
    roar *= np.minimum(t(d) / 0.35, 1.0) * np.minimum((d - t(d)) / 0.8, 1.0)
    write("warden_roar", roar + 0.4 * bandpass(noise(d), 200, 1200) * np.minimum(t(d) / 0.35, 1.0) * np.exp(-t(d)), peak=0.9)
    d = 2.2
    horn = (sine(196, d) + 0.6 * sine(392, d) + 0.35 * sine(588, d)) * np.minimum(t(d) / 0.15, 1.0) * np.minimum((d - t(d)) / 0.5, 1.0)
    horn *= 0.75 + 0.25 * np.sign(np.sin(2 * np.pi * 2.0 * t(d)))
    write("siege_horn", horn, peak=0.7)

    milestone6()
    refinement()


# --- Milestone 6: music, ambience and the remaining sounds ---------------------------------

BPM = 96
BEAT = 60.0 / BPM
BAR = 4 * BEAT
LOOP = 8 * BAR  # 20 s: every music stem has this length, so the layers stay locked together.
# Two bars each: D minor, B flat, F, C.
CHORDS = [(146.83, 174.61, 220.0), (116.54, 146.83, 174.61), (174.61, 220.0, 261.63), (130.81, 164.81, 196.0)]


def wrap(total, *parts):
    """Like place(), but a tail that runs past the end wraps to the start, so the buffer loops."""
    out = np.zeros(int(RATE * total))
    n = len(out)
    for start, sig in parts:
        i = int(RATE * start) % n
        k = 0
        while k < len(sig):
            m = min(len(sig) - k, n - i)
            out[i:i + m] += sig[k:k + m]
            k += m
            i = 0
    return out


def seamless(x, fade):
    """Crossfades the extra `fade` seconds at the end into the start, for noisy loops."""
    f = int(RATE * fade)
    out = x[:-f].copy()
    ramp = np.linspace(0.0, 1.0, f)
    out[:f] = out[:f] * ramp + x[-f:] * (1.0 - ramp)
    return out


def tone(freq, seconds, harmonics=((1, 1.0),), detune=0.0):
    out = np.zeros(int(RATE * seconds))
    for h, a in harmonics:
        out += a * sine(freq * h * (1 + detune), seconds)
    return out


def pad(freq, seconds):
    sw = ((1, 1.0), (2, 0.35), (3, 0.15), (4, 0.06))
    x = tone(freq, seconds, sw, 0.003) + tone(freq, seconds, sw, -0.003)
    tt = t(seconds)
    return x * np.minimum(tt / 1.2, 1.0) * np.minimum(np.maximum(seconds - tt, 0.0) / 1.5, 1.0)


def bell(freq, seconds=2.0, decay=2.5):
    return (sine(freq, seconds) + 0.4 * sine(freq * 2.76, seconds) + 0.15 * sine(freq * 5.4, seconds)) * env(seconds, 0.003, decay)


def pluck(freq, seconds=0.4, decay=9.0):
    return tone(freq, seconds, ((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15), (5, 0.08))) * env(seconds, 0.002, decay)


def kick(seconds=0.45):
    return sine(lambda tt: 45 + 90 * np.exp(-tt * 30), seconds) * env(seconds, 0.001, 9)


def hat(seconds=0.08):
    return highpass(noise(seconds), 6000) * env(seconds, 0.0005, 60)


def snare(seconds=0.3):
    return bandpass(noise(seconds), 900, 5000) * env(seconds, 0.001, 18) + 0.4 * sine(185, seconds) * env(seconds, 0.001, 25)


def tom(freq, seconds=0.5):
    return sine(lambda tt: freq * (1 + 0.5 * np.exp(-tt * 20)), seconds) * env(seconds, 0.001, 7)


def milestone6():
    # Music: three stems at the same tempo and length. Calm always plays; combat and finale
    # fade in over it (scripts/music.gd).
    parts = []
    for i, chord in enumerate(CHORDS):
        start = i * 2 * BAR
        for f in chord:
            parts.append((start, 0.5 * pad(f / 2, 2 * BAR + 1.6)))
        parts.append((start, 0.6 * pad(chord[0] / 4, 2 * BAR + 1.6)))
        # A sparse bell figure, two beats apart, an octave up.
        for j, k in enumerate((0, 2, 1, 2)):
            parts.append((start + j * 2 * BEAT, 0.22 * bell(chord[k] * 4, 2.6)))
    breath = seamless(lowpass(noise(LOOP + 1.0), 500), 1.0)
    write("music_calm", wrap(LOOP, *parts) + 0.12 * breath * (0.6 + 0.4 * np.sin(2 * np.pi * t(LOOP) / LOOP * 4)), peak=0.55, loop=True)

    parts = []
    for i, chord in enumerate(CHORDS):
        for b in range(16):  # eighth notes over two bars
            at = i * 2 * BAR + b * BEAT / 2
            root = chord[0] / 2 if b % 8 != 6 else chord[2] / 2
            parts.append((at, 0.5 * pluck(root, 0.35, 12)))
        for bar in range(2):
            base = i * 2 * BAR + bar * BAR
            parts += [(base, kick()), (base + 2 * BEAT, kick()), (base + 3.5 * BEAT, 0.7 * kick())]
            parts += [(base + BEAT, 0.6 * snare()), (base + 3 * BEAT, 0.6 * snare())]
            parts += [(base + (h + 0.5) * BEAT, 0.25 * hat()) for h in range(4)]
    write("music_combat", wrap(LOOP, *parts), peak=0.6, loop=True)

    parts = []
    for i, chord in enumerate(CHORDS):
        tones = [chord[0] * 2, chord[1] * 2, chord[2] * 2, chord[0] * 4]
        for b in range(32):  # sixteenths
            at = i * 2 * BAR + b * BEAT / 4
            parts.append((at, 0.22 * pluck(tones[[0, 1, 2, 3, 2, 1][b % 6]], 0.25, 14)))
        brass = sum(pad(f, 2 * BAR + 1.0) for f in chord)
        parts.append((i * 2 * BAR, 0.35 * lowpass(brass, 1400)))
        for beat in range(8):
            parts.append((i * 2 * BAR + beat * BEAT, 0.8 * kick()))
        fill = i * 2 * BAR + 7 * BEAT
        parts += [(fill + k * BEAT / 4, 0.5 * tom(f)) for k, f in enumerate((180, 150, 120, 95))]
    write("music_finale", wrap(LOOP, *parts), peak=0.6, loop=True)

    # Ambience loops, 8 s.
    d = 8.0
    pops = []
    for k in range(40):
        f = rng.uniform(180, 700)
        pops.append((rng.uniform(0, d), 0.3 * sine(lambda tt, f=f: f * (1 + 2.5 * tt), 0.06) * env(0.06, 0.002, 60)))
    rumble = seamless(lowpass(noise(d + 1.0), 250), 1.0)
    write("amb_springs_loop", wrap(d, *pops) + 0.5 * rumble, peak=0.5, loop=True)
    tt = t(d)
    drone = (sine(36, d) + 0.6 * sine(54, d)) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.5 * tt))
    shimmer = (sine(1800, d) + 0.7 * sine(2403, d)) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.25 * tt)) * 0.08
    write("amb_loom_loop", drone + shimmer, peak=0.55, loop=True)
    room = seamless(lowpass(lowpass(noise(d + 1.0), 180), 180), 1.0)
    creaks = [(at, 0.25 * (sine(lambda tt: 310 - 60 * tt, 0.7) + 0.5 * bandpass(noise(0.7), 600, 2000)) * env(0.7, 0.05, 4)) for at in (2.3, 6.1)]
    write("amb_interior_loop", 2.0 * room + wrap(d, *creaks), peak=0.45, loop=True)

    # The engine spool: a whine that the game pitches up as the spool fills (periods divide 2 s).
    d = 2.0
    whine = sine(220, d) + 0.5 * sine(330, d) + 0.3 * sine(440, d) + 0.2 * sine(1320, d)
    write("spool_loop", whine * (0.85 + 0.15 * np.sin(2 * np.pi * 4 * t(d))) + 0.4 * seamless(bandpass(noise(d + 0.5), 400, 2500), 0.5), peak=0.5, loop=True)

    # One-shots.
    d = 3.2
    boom = lowpass(noise(d), 260) * env(d, 0.002, 1.6) + 1.2 * sine(lambda tt: 50 - 25 * tt / d, d) * env(d, 0.002, 2.0)
    screech = bandpass(noise(d), 1500, 4500) * env(d, 0.01, 2.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 13 * t(d)))
    debris = [(0.3 + k * 0.17 + rng.uniform(0, 0.1), 0.4 * click(0.05, 1500)) for k in range(12)]
    write("crash_impact", place(d, (0.0, boom), (0.05, 0.5 * screech), *debris), peak=0.95)
    d = 1.0
    clunk = lambda: lowpass(noise(0.18), 700) * env(0.18, 0.001, 22) + 0.6 * sine(110, 0.18) * env(0.18, 0.001, 25)
    ratchet = [(0.25 + k * 0.06, 0.35 * click(0.025, 2500)) for k in range(6)]
    write("repair_clunk", place(d, (0.0, clunk()), (0.65, 1.2 * clunk()), *ratchet), peak=0.85)
    write("log_chime", place(1.4, (0.0, bell(880, 1.2, 4)), (0.18, bell(1318.5, 1.2, 4))), peak=0.5)
    write("ui_click", click(0.05, 2000) + 0.4 * sine(1400, 0.05) * env(0.05, 0.001, 70), peak=0.5)
    d = 1.6
    write("warden_slam", lowpass(noise(d), 300) * env(d, 0.001, 3) + 1.4 * sine(lambda tt: 60 - 30 * tt / d, d) * env(d, 0.001, 3.5) + 0.3 * place(d, *[(0.1 + k * 0.11, click(0.05, 900)) for k in range(5)]), peak=0.95)
    d = 0.9
    write("spitter_death", lowpass(noise(d), 800) * (0.5 + 0.5 * np.sin(2 * np.pi * 18 * t(d))) * env(d, 0.01, 4) + 0.5 * sine(lambda tt: 300 - 220 * tt / d, d) * env(d, 0.01, 4), peak=0.7)
    d = 1.6
    write("ram_death", (sine(lambda tt: 90 - 50 * tt / d, d) + 0.5 * sine(lambda tt: 180 - 100 * tt / d, d)) * np.minimum(t(d) / 0.1, 1.0) * np.exp(-t(d) * 2.2) + 0.3 * lowpass(noise(d), 400) * env(d, 0.01, 3), peak=0.85)
    d = 6.0
    tt = t(d)
    rise = np.minimum(tt / 1.5, 1.0)
    roar = lowpass(noise(d), 400) * rise * np.minimum((d - tt) / 2.0, 1.0)
    jet = sine(lambda x: 180 + 500 * (x / d) ** 1.5, d) * 0.3 * rise * np.minimum((d - tt) / 2.0, 1.0)
    write("launch_roar", roar + jet + 0.6 * sine(40, d) * rise * np.minimum((d - tt) / 2.0, 1.0), peak=0.9)



# --- Refinement: game feel -----------------------------------------------------------------

def refinement():
    global rng
    rng = np.random.default_rng(31)
    # A boot in shallow water: a wet slap, then a short trickle of droplets.
    for i, cutoff in enumerate((900, 1300)):
        slap = bandpass(noise(0.06), 300, cutoff) * env(0.06, 0.002, 50)
        drops = sum(sine(rng.uniform(900, 1800), 0.05) * env(0.05, 0.001, 70) * 0.25 for _ in range(1))
        trickle = highpass(noise(0.2), 2000) * env(0.2, 0.01, 18) * 0.25
        write(f"splash_{i}", place(0.25, (0.0, slap), (0.03, drops), (0.04, trickle)), peak=0.5)
    # Dodge roll: a cloth-and-gear whoosh.
    d = 0.35
    sweep = bandpass(noise(d), 200, 1400) * np.sin(np.pi * t(d) / d) ** 2
    write("roll_whoosh", sweep, peak=0.45)


if __name__ == "__main__":
    main()
