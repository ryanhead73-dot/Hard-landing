"""Hard Landing's adaptive score and ambience beds, synthesised, as stereo Ogg Vorbis loops.

    python3 tools/audio/make_music.py [name ...]     # needs numpy, scipy and ffmpeg

The score is three stems over one progression (D minor, 84 bpm, 32 bars) that start together
and loop in lockstep (scripts/music.gd crossfades them by mood):
  music_calm    pads, sub and a sparse bell motif: exploring the basin
  music_combat  drums, a driving bass ostinato, staccato strings and brass stabs
  music_finale  choir, a lead theme and timpani for the launch
Ambience beds are seamless stereo loops, one per zone (scripts/ambience.gd).
"""

import sys

import numpy as np

import dsp
from dsp import (RATE, adsr, bp, env, fm, formant, grains, hp, impulse, lp, metal_modes, modal, n, osc,
                 pan, peak, pink, place, reverb, sat, sweep, swept, t, white, wrap_loop, write_ogg, VOWELS)

BPM = 84.0
BEAT = 60.0 / BPM
BAR = BEAT * 4
BARS = 32
LENGTH = BAR * BARS
TAIL = 6.0


def hz(midi):
    return 440.0 * 2 ** ((midi - 69) / 12.0)


# Two bars per chord, eight bars per cycle, four cycles. Voicings as MIDI notes, root first.
CHORDS = [
    [38, 50, 57, 60, 64, 65],   # Dm9
    [34, 46, 53, 57, 62, 65],   # Bbmaj7
    [31, 43, 50, 53, 57, 58],   # Gm9
    [33, 45, 52, 55, 62, 64],   # A7sus4 (resolves to A7 in its second bar)
]
A7 = [33, 45, 52, 55, 61, 64]
SCALE = [62, 64, 65, 67, 69, 72, 74, 76, 77, 79, 81]  # D dorian-ish, for melodies


def chord_at(bar):
    c = CHORDS[(bar // 2) % 4]
    if c is CHORDS[3] and bar % 2 == 1:
        return A7
    return c


dsp.seed(7)
HALL = impulse(3.2, bright=5000, dark=1100, early=((0.021, 0.4), (0.037, 0.35), (0.053, 0.3)), predelay=0.02, stereo=True)
ROOMY = impulse(1.4, bright=6000, dark=1800, early=((0.013, 0.4), (0.029, 0.3)), predelay=0.01, stereo=True)


def bus(seconds):
    return np.zeros((n(seconds), 2))


def add(buf, start, sig, p=0.0, gain=1.0):
    s = sig if sig.ndim == 2 else pan(sig, p)
    i = int(start * RATE)
    m = min(len(s), len(buf) - i)
    if m > 0:
        buf[i:i + m] += s[:m] * gain


def finish(buf, wet, ir=HALL, peak_=0.8):
    x = reverb(buf, ir, wet)
    return wrap_loop(x, LENGTH)


# --- Instruments ---------------------------------------------------------------------------

def pad_note(f, seconds, bright=1.0):
    tones = [osc(f * (1 + c), seconds, "saw") for c in (-0.004, 0.0, 0.0045)]
    x = sum(tones) / 3.0
    x = lp(x, 900 * bright, 2)
    return x * adsr(seconds, 1.4, 1.0, 0.8, 1.8)


def bell(f, seconds=2.5, vel=1.0):
    d = seconds
    e = env(d, 0.002, d * 0.9)
    return fm(f, 3.5, 2.5, d, np.exp(-t(d) * 3.0)) * e * vel * 0.5 + osc(f * 2, d) * env(d, 0.002, d * 0.4) * 0.1 * vel


def pluck(f, seconds=0.5, cutoff=2500):
    x = osc(f, seconds, "saw") + 0.5 * osc(f * 1.005, seconds, "saw")
    return lp(x, cutoff) * env(seconds, 0.002, seconds * 0.8)


def kick():
    d = 0.5
    return osc(sweep(140, 42, 0.12, 0.5).tolist() + [42] * (n(d) - n(0.12)), d) * env(d, 0.001, 0.4) * 1.3 + \
        place(d, (0, lp(white(0.01), 4000) * 0.4))


def snare():
    d = 0.35
    body = osc(sweep(220, 170, 0.08).tolist() + [170] * (n(d) - n(0.08)), d) * env(d, 0.001, 0.12)
    noise = bp(white(d), 1500, 9000) * env(d, 0.001, 0.22)
    return body * 0.7 + noise * 0.8


def hat(open_=False):
    d = 0.3 if open_ else 0.06
    return hp(white(d), 7000) * env(d, 0.0005, d * 0.8) * 0.4


def tom(f):
    d = 0.6
    return osc(sweep(f * 1.4, f, 0.1).tolist() + [f] * (n(d) - n(0.1)), d) * env(d, 0.001, 0.45) + \
        lp(white(d), 900) * env(d, 0.001, 0.1) * 0.3


def taiko():
    d = 1.2
    return osc(sweep(90, 52, 0.2).tolist() + [52] * (n(d) - n(0.2)), d) * env(d, 0.002, 0.9) * 1.4 + \
        lp(white(d), 500) * env(d, 0.001, 0.25) * 0.6


def metal_hit():
    return place(1.5, (0, modal(1.5, metal_modes(310, 10, 2.8, 1.2)) * 0.5), (0, hp(white(0.05), 3000) * env(0.05, 0.0005, 0.04) * 0.3))


def cymbal_swell(seconds):
    x = hp(white(seconds), 5000) * (t(seconds) / seconds) ** 3
    return x * 0.5


def timpani(f):
    d = 1.6
    return (osc(f, d) + 0.4 * osc(f * 1.5, d) + 0.25 * osc(f * 2.0, d)) * env(d, 0.003, 1.3) + \
        lp(white(d), 700) * env(d, 0.001, 0.15) * 0.4


def choir_note(f, seconds, vowel="a"):
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t(seconds) + dsp.rng.uniform(0, 6))
    voices = sum(osc(f * vib * (1 + c), seconds, "saw") for c in (-0.006, -0.002, 0.003, 0.007)) / 4
    return formant(voices, VOWELS[vowel]) * adsr(seconds, 0.9, 0.6, 0.85, 1.5)


def lead_note(f, seconds):
    vib = 1 + 0.009 * np.sin(2 * np.pi * 5.5 * t(seconds)) * np.minimum(t(seconds) / 0.4, 1.0)
    x = osc(f * vib, seconds, "saw") * 0.6 + osc(f * vib * 2, seconds, "square") * 0.15
    return lp(x, 3200) * adsr(seconds, 0.04, 0.3, 0.75, 0.25)


def brass(f, seconds):
    x = sum(osc(f * (1 + c), seconds, "saw") for c in (-0.003, 0.003)) / 2
    x = swept(x, 300 + 2200 * env(seconds, 0.03, 0.5), "lowpass")
    return formant(x, VOWELS["o"]) * adsr(seconds, 0.02, 0.2, 0.6, 0.2)


# --- Stems ---------------------------------------------------------------------------------

def music_calm():
    dsp.seed(11)
    buf = bus(LENGTH + TAIL)
    for bar in range(0, BARS, 2):
        c = chord_at(bar)
        start = bar * BAR
        dur = 2 * BAR + 1.5
        bright = 0.8 + 0.4 * ((bar // 8) % 2)
        for k, m in enumerate(c[1:]):
            add(buf, start, pad_note(hz(m), dur, bright), p=-0.6 + 1.2 * k / 4, gain=0.22)
        add(buf, start, osc(hz(c[0]), dur) * adsr(dur, 0.8, 0.5, 0.9, 1.5), gain=0.35)
        if c is CHORDS[3]:
            # The resolution to A7 in the second bar.
            add(buf, start + BAR, pad_note(hz(61), BAR + 1.5, bright), p=0.3, gain=0.18)
    # Bell motif: sparse in the first pass, then answering phrases.
    motif = [(0, 74), (1.5, 77), (2.5, 76), (4, 72), (6, 69), (7, 74)]
    for cycle in range(4):
        density = [0.0, 0.6, 1.0, 0.5][cycle]
        for b in range(8):
            for beat, m in motif:
                if dsp.rng.uniform() < density * 0.55:
                    when = (cycle * 8 + b) * BAR + beat * BEAT * 0.5
                    note = m if b % 2 == 0 else SCALE[(SCALE.index(m) + 2) % len(SCALE)] if m in SCALE else m
                    add(buf, when, bell(hz(note), 2.6, dsp.rng.uniform(0.5, 1.0)), p=dsp.rng.uniform(-0.7, 0.7), gain=0.16)
    # Third pass: a soft pulse of chord tones in eighths.
    for bar in range(16, 24):
        c = chord_at(bar)
        for e8 in range(8):
            m = c[1 + (e8 * 2) % 5] + 12
            add(buf, bar * BAR + e8 * BEAT * 0.5, pluck(hz(m), 0.6, 1800), p=0.4 if e8 % 2 else -0.4, gain=0.05)
    breath = lp(pink(LENGTH + TAIL), 1200) * 0.03
    buf += np.stack([breath, np.roll(breath, 5000)], axis=1)
    return finish(buf, 0.5)


def music_combat():
    dsp.seed(12)
    buf = bus(LENGTH + TAIL)
    K, S, H = kick(), snare(), hat()
    for bar in range(BARS):
        s0 = bar * BAR
        c = chord_at(bar)
        for b in (0.0, 1.5, 2.0, 3.25 if bar % 2 else 2.75):
            add(buf, s0 + b * BEAT, K, gain=0.55)
        for b in (1.0, 3.0):
            add(buf, s0 + b * BEAT, S, p=0.05, gain=0.32)
        for s16 in range(16):
            acc = 1.0 if s16 % 4 == 2 else 0.5
            add(buf, s0 + s16 * BEAT / 4, H, p=0.35, gain=0.09 * acc)
        if bar % 4 == 0:
            add(buf, s0, taiko(), gain=0.5)
            add(buf, s0, metal_hit(), p=-0.4, gain=0.12)
        if bar % 8 == 7:
            for k, f in enumerate((180, 150, 120, 100, 85, 70)):
                add(buf, s0 + (2 + k * 0.33) * BEAT, tom(f), p=-0.5 + k * 0.2, gain=0.32)
        # Bass ostinato in sixteenths.
        pattern = [1, 0, 1, 1, 1, 0, 1, 0, 1, 1, 0, 1, 1, 0, 1, 1]
        root = c[0] + 12
        for s16, on in enumerate(pattern):
            if on:
                m = root + (7 if s16 in (6, 14) else 0)
                note = lp(osc(hz(m), 0.22, "saw") + 0.5 * osc(hz(m) * 0.5, 0.22, "square"), 700 + 500 * (s16 % 4 == 0)) * env(0.22, 0.003, 0.18)
                add(buf, s0 + s16 * BEAT / 4, note, gain=0.22)
        # Staccato strings in eighths: root and fifth, an octave up.
        for e8 in range(8):
            m = c[2] + 12 if e8 % 2 else c[1] + 12
            st = bp(sum(osc(hz(m) * (1 + d), 0.16, "saw") for d in (-0.004, 0.0, 0.004)), 200, 3500) * env(0.16, 0.004, 0.12)
            add(buf, s0 + e8 * BEAT / 2, st, p=-0.5 if e8 % 2 else 0.5, gain=0.08)
        # Brass stab where each chord lands.
        if bar % 2 == 0:
            for k, m in enumerate(c[1:4]):
                add(buf, s0, brass(hz(m), BEAT * 1.5), p=-0.3 + 0.3 * k, gain=0.1)
    return finish(buf, 0.22, ROOMY)


def music_finale():
    dsp.seed(13)
    buf = bus(LENGTH + TAIL)
    for bar in range(0, BARS, 2):
        c = chord_at(bar)
        dur = 2 * BAR + 1.0
        for k, m in enumerate(c[2:]):
            add(buf, bar * BAR, choir_note(hz(m + 12), dur, "a" if k % 2 else "o"), p=-0.5 + 0.33 * k, gain=0.12)
    # The theme: a rising phrase over each 8-bar cycle, climbing an octave on the last cycle.
    theme = [(0, 2, 74), (2, 1, 77), (3, 1, 76), (4, 3, 74), (7, 1, 72),
             (8, 2, 70), (10, 1, 74), (11, 1, 77), (12, 4, 79),
             (16, 2, 79), (18, 1, 81), (19, 1, 77), (20, 4, 74),
             (24, 2, 76), (26, 2, 73), (28, 4, 76)]
    for cycle in range(4):
        if cycle == 0:
            continue
        up = 12 if cycle == 3 else 0
        for beat, length, m in theme:
            when = (cycle * 8) * BAR + beat * BEAT
            add(buf, when, lead_note(hz(m + up - 12), length * BEAT + 0.2), p=0.1, gain=0.14)
            # A quarter-note echo.
            add(buf, when + BEAT * 0.75, lead_note(hz(m + up - 12), length * BEAT + 0.2), p=-0.5, gain=0.04)
    for bar in range(BARS):
        c = chord_at(bar)
        add(buf, bar * BAR, timpani(hz(c[0] + 12)), gain=0.35)
        if bar % 2 == 1:
            add(buf, bar * BAR + 2.5 * BEAT, timpani(hz(c[0] + 12)), gain=0.2)
            add(buf, bar * BAR + 3.0 * BEAT, timpani(hz(c[0] + 19)), gain=0.22)
        if bar % 8 == 6:
            add(buf, bar * BAR, cymbal_swell(2 * BAR), p=0.2, gain=0.25)
    return finish(buf, 0.4)


# --- Ambience ------------------------------------------------------------------------------

AMB = 40.0
XF = 3.0


def loop_bed(make):
    """Renders AMB + XF seconds and crossfades the overhang into the start."""
    x = make(AMB + XF)
    k, f = n(AMB), n(XF)
    out = np.array(x[:k])
    w = np.linspace(0, 1, f)[:, None]
    out[:f] = out[:f] * w + x[k:k + f] * (1 - w)
    return out


def gusts(seconds, rate=0.07, depth=0.6, phase=0.0):
    tt = t(seconds)
    g = sum(np.sin(2 * np.pi * rate * k * tt + phase + k) / k for k in (1, 2.3, 3.7))
    return 1.0 - depth + depth * (0.5 + 0.5 * g / 1.6)


def scatter(seconds, rate, make, spread=0.9):
    """Grains placed in stereo."""
    out = np.zeros((n(seconds), 2))
    pos = 0.0
    while True:
        pos += dsp.rng.exponential(1.0 / rate)
        if pos >= seconds:
            break
        add(out, pos, make(), p=dsp.rng.uniform(-spread, spread))
    return out


def wind_loop():
    dsp.seed(21)

    def make(d):
        chans = []
        for c in range(2):
            base = lp(pink(d), 380) * gusts(d, 0.06, 0.65, c * 1.3)
            whistle = peak(white(d), 820 + 90 * c, 35) * gusts(d, 0.09, 0.9, 2 + c) ** 3 * 0.25
            hiss = bp(white(d), 1500, 5000) * gusts(d, 0.11, 0.8, 4 + c) ** 2 * 0.05
            chans.append(base + whistle + hiss)
        return np.stack(chans, axis=1)
    return loop_bed(make)


def amb_springs_loop():
    dsp.seed(22)

    def make(d):
        bed = np.stack([hp(white(d), 2500) * gusts(d, 0.05, 0.5, c) * 0.06 for c in range(2)], axis=1)
        bubbles = scatter(d, 14, lambda: osc(sweep(dsp.rng.uniform(180, 500), dsp.rng.uniform(500, 1100), 0.05), 0.05) *
                          env(0.05, 0.003, 0.045) * dsp.rng.uniform(0.1, 0.5))
        bloops = scatter(d, 0.8, lambda: osc(sweep(dsp.rng.uniform(70, 120), dsp.rng.uniform(150, 260), 0.15), 0.15) *
                         env(0.15, 0.01, 0.13) * 0.6)
        lap = np.stack([lp(white(d), 500) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.31 * t(d) + c)) * 0.3 for c in range(2)], axis=1)
        return reverb(bed + bubbles + bloops + lap, ROOMY, 0.25)[:n(d)]
    return loop_bed(make)


def amb_loom_loop():
    dsp.seed(23)

    def make(d):
        tt = t(d)
        drone = sum(np.sin(2 * np.pi * f * tt + k) * a for k, (f, a) in enumerate(((36.7, 1.0), (55.1, 0.6), (73.6, 0.4), (110.2, 0.2))))
        drone *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.05 * tt)
        shimmer = np.zeros(n(d))
        for k in range(7):
            f = 880 * 2 ** (dsp.rng.integers(0, 12) / 12.0) * (1 + 0.003 * k)
            shimmer += np.sin(2 * np.pi * f * tt) * (0.5 + 0.5 * np.sin(2 * np.pi * dsp.rng.uniform(0.03, 0.12) * tt + k)) ** 4
        x = np.stack([drone * 0.5 + shimmer * 0.03, drone * 0.5 + np.roll(shimmer, 9000) * 0.03], axis=1)
        swells = scatter(d, 0.12, lambda: lp(white(4.0), 2000) * (t(4.0) / 4.0) ** 3 * 0.25)
        return reverb(x + swells, HALL, 0.4)[:n(d)]
    return loop_bed(make)


def amb_interior_loop():
    dsp.seed(24)

    def make(d):
        room = np.stack([lp(pink(d), 220) * 0.5 for _ in range(2)], axis=1)
        vent = pan((np.sin(2 * np.pi * 120 * t(d)) * 0.04 + bp(white(d), 400, 1500) * 0.03), 0.3)
        ticks = scatter(d, 0.9, lambda: modal(0.15, metal_modes(dsp.rng.uniform(1500, 4000), 4, 2.0, 0.08)) * dsp.rng.uniform(0.05, 0.25))
        creaks = scatter(d, 0.15, lambda: swept(white(1.2), sweep(dsp.rng.uniform(150, 300), dsp.rng.uniform(300, 600), 1.2), "bandpass") *
                         np.sin(np.pi * t(1.2) / 1.2) ** 2 * 0.25)
        drips = scatter(d, 0.25, lambda: osc(sweep(1400, 2600, 0.03), 0.03) * env(0.03, 0.001, 0.025) * 0.15, 0.5)
        return reverb(room + vent + ticks + creaks + drips, ROOMY, 0.35)[:n(d)]
    return loop_bed(make)


def amb_moss_loop():
    dsp.seed(25)

    def make(d):
        air = np.stack([lp(pink(d), 600) * gusts(d, 0.04, 0.4, c) * 0.25 for c in range(2)], axis=1)

        def chirp():
            k = dsp.rng.integers(3, 8)
            f = dsp.rng.uniform(3500, 6000)
            one = fm(f, 0.5, 1.5, 0.025) * env(0.025, 0.002, 0.022)
            return place(k * 0.06, *[(i * 0.06, one * (0.6 + 0.4 * (i % 2))) for i in range(k)]) * 0.08
        chirps = scatter(d, 1.2, chirp)
        drips = scatter(d, 0.6, lambda: osc(sweep(900, 1900, 0.04), 0.04) * env(0.04, 0.001, 0.035) * 0.18)
        calls = scatter(d, 0.06, lambda: formant(fm(sweep(160, 120, 1.4), 0.5, 1.2, 1.4), VOWELS["u"]) * adsr(1.4, 0.3, 0.3, 0.7, 0.6) * 0.15, 0.95)
        pops = scatter(d, 0.4, lambda: lp(white(0.02), 1500) * env(0.02, 0.001, 0.015) * 0.2)
        return reverb(air + chirps + drips + calls + pops, HALL, 0.35)[:n(d)]
    return loop_bed(make)


def amb_wreck_loop():
    dsp.seed(26)

    def make(d):
        wind = np.stack([lp(pink(d), 300) * gusts(d, 0.07, 0.6, c) * 0.4 for c in range(2)], axis=1)

        def groan():
            g = 3.0
            f0 = dsp.rng.uniform(70, 140)
            src = white(g)
            x = sum(peak(src, f0 * r * (1 + 0.04 * np.sin(2 * np.pi * 0.3 * t(g).mean())), 60) * a
                    for r, a in ((1.0, 1.0), (2.37, 0.5), (3.91, 0.3)))
            return x * np.sin(np.pi * t(g) / g) ** 2 * 0.8
        groans = scatter(d, 0.12, groan)
        clanks = scatter(d, 0.2, lambda: modal(1.2, metal_modes(dsp.rng.uniform(200, 600), 8, 2.6, 0.9)) * dsp.rng.uniform(0.04, 0.15))
        whistle = pan(peak(white(d), 1240, 40) * gusts(d, 0.1, 0.9, 1.0) ** 4 * 0.2, -0.4)
        return reverb(wind + groans + clanks + whistle, HALL, 0.35)[:n(d)]
    return loop_bed(make)



def rain_loop():
    """Steady rain on rock and water: a broad hiss, dense close patter, heavier drops and
    runnels, swelling in slow gusts."""
    dsp.seed(27)

    def make(d):
        chans = []
        for c in range(2):
            g = gusts(d, 0.05, 0.35, c * 0.9)
            hiss = bp(pink(d), 600, 9000) * g * 0.5
            body = lp(pink(d), 900) * g * 0.35
            chans.append(hiss + body)
        bed = np.stack(chans, axis=1)
        patter = scatter(d, 260, lambda: hp(white(0.004), 2500) * env(0.004, 0.0003, 0.003) * dsp.rng.uniform(0.05, 0.35))
        drops = scatter(d, 25, lambda: osc(sweep(dsp.rng.uniform(900, 1800), dsp.rng.uniform(1800, 3200), 0.02), 0.02) *
                        env(0.02, 0.001, 0.016) * dsp.rng.uniform(0.05, 0.25))
        return bed + patter + drops
    return loop_bed(make)


TRACKS = {
    "music_calm": (music_calm, 0.75), "music_combat": (music_combat, 0.85), "music_finale": (music_finale, 0.8),
    "wind_loop": (wind_loop, 0.6), "amb_springs_loop": (amb_springs_loop, 0.5), "amb_loom_loop": (amb_loom_loop, 0.55),
    "amb_interior_loop": (amb_interior_loop, 0.45), "amb_moss_loop": (amb_moss_loop, 0.5), "amb_wreck_loop": (amb_wreck_loop, 0.5),
    "rain_loop": (rain_loop, 0.5),
}


def main():
    for name in sys.argv[1:] or list(TRACKS):
        fn, level = TRACKS[name]
        x = fn()
        if name == "music_combat":
            # Drums are all peaks: glue them so the layer has weight when it comes in.
            x = sat(dsp.norm(x) * 1.0, 2.6)
        write_ogg(name, x, peak_=level)


if __name__ == "__main__":
    main()
