"""Hard Landing's sound effects, synthesised (no third-party audio in the repo).

    python3 tools/audio/make_sfx.py [name ...]     # needs numpy and scipy; writes godot/audio/

Each sound is layered the way a sound designer would build it from recordings: a transient, a
body, a tail, and the space it happens in (convolution with a generated impulse response).
Sounds that repeat a lot get variants, written as <id>__1.wav, <id>__2.wav...; the game picks
one at random. A recorded WAV with the same name replaces any of them.
"""

import sys

import numpy as np

import dsp
from dsp import (RATE, adsr, bp, brown, env, fm, formant, grains, hp, impulse, lp, metal_modes, modal, n, osc,
                 peak, pink, pitch, place, reverb, sat, sweep, t, trim, white, write_wav, VOWELS)

SOUNDS = {}


def sound(name, variants=1):
    def deco(fn):
        SOUNDS[name] = (fn, variants)
        return fn
    return deco


# Spaces, built once.
dsp.seed(100)
BASIN = impulse(1.9, bright=3500, dark=700, early=((0.11, 0.45), (0.23, 0.3), (0.41, 0.22), (0.66, 0.12)), predelay=0.01)
ROOM = impulse(0.55, bright=7000, dark=2500, early=((0.012, 0.6), (0.019, 0.5), (0.031, 0.4), (0.047, 0.3)))
CLOSE = impulse(0.25, bright=9000, dark=4000, early=((0.006, 0.5), (0.011, 0.4)))


def outdoor(x, wet=0.35):
    return trim(reverb(x, BASIN, wet))


def indoor(x, wet=0.25):
    return trim(reverb(x, ROOM, wet))


def click(seconds=0.012, lo=1500, hi=9000):
    return bp(white(seconds), lo, hi) * env(seconds, 0.0002, seconds)


def clack(base=1800, t60=0.12, seconds=0.25, weight=1.0):
    """A small mechanical part hitting another: a bright modal ring on a tick."""
    return place(seconds, (0, 0.6 * click(0.008, 2000, 10000)),
                 (0, weight * modal(seconds, metal_modes(base, 6, 2.2, t60))))


def thud(freq=70, seconds=0.25, drop=0.5):
    return osc(sweep(freq, freq * drop, seconds), seconds) * env(seconds, 0.001, seconds * 0.8)


# --- Weapons -------------------------------------------------------------------------------

@sound("rifle_shot", 3)
def rifle_shot(v):
    d = 0.5
    crack = bp(white(0.05), 1200, 9000) * env(0.05, 0.0002, 0.035)
    snap = hp(white(0.004), 4000) * 1.5
    body = (bp(white(0.14), 250, 1800) * env(0.14, 0.0005, 0.1)) * 0.9
    punch = thud(150 + 15 * v, 0.18, 0.35) * 1.1
    bolt = clack(2600 + 200 * v, 0.06, 0.12, 0.25)
    x = place(d, (0, snap), (0, crack), (0, body), (0, punch), (0.03, bolt))
    return outdoor(sat(x * 1.6, 2.5), 0.4)


@sound("scatter_shot", 2)
def scatter_shot(v):
    blast = place(0.6, (0, hp(white(0.006), 3000) * 2), (0, lp(white(0.4), 3200) * env(0.4, 0.0003, 0.25)),
                  (0, thud(95 - 6 * v, 0.45, 0.35) * 1.8), (0, bp(white(0.25), 120, 600) * env(0.25, 0.001, 0.2)))
    shot = outdoor(sat(blast * 1.8, 3.0), 0.5)
    pump_back = place(0.18, (0, clack(1400, 0.08, 0.15)), (0.02, bp(white(0.12), 600, 3500) * env(0.12, 0.01, 0.1) * 0.3))
    pump_fwd = clack(1100, 0.1, 0.2, 1.3)
    return place(1.3, (0, shot), (0.5, indoor(pump_back, 0.1) * 0.5), (0.68, indoor(pump_fwd, 0.1) * 0.6))


@sound("lance_shot", 2)
def lance_shot(v):
    d = 0.9
    whine = osc(sweep(900, 3400 + 300 * v, 0.18, 0.6), 0.18) * env(0.18, 0.15, 0.05) * 0.25
    discharge = grains(0.35, 260, lambda i: hp(white(0.004), 2500) * dsp.rng.uniform(0.3, 1.0))
    discharge *= env(0.35, 0.001, 0.3)
    hum = (osc(120, d, "saw") * 0.3 + osc(240, d) * 0.2) * env(d, 0.001, 0.45)
    boom = thud(70, 0.5, 0.5) * 1.4
    zap = fm(sweep(1800, 300, 0.25), 1.41, 6.0, 0.25) * env(0.25, 0.0005, 0.2) * 0.6
    x = place(1.0, (0, whine), (0.16, discharge), (0.16, hum), (0.16, boom), (0.16, zap))
    return outdoor(sat(x * 1.3, 2.0), 0.35)


@sound("turret_shot", 2)
def turret_shot(v):
    x = place(0.4, (0, hp(white(0.005), 3500) * 1.5), (0, bp(white(0.06), 1000, 7000) * env(0.06, 0.0002, 0.05)),
              (0, thud(180 + 20 * v, 0.14, 0.4)), (0.02, clack(3200, 0.05, 0.1, 0.3)))
    return outdoor(sat(x * 1.5, 2.2), 0.45)


@sound("rifle_reload")
def rifle_reload(v):
    mag_out = place(0.3, (0, clack(1500, 0.08, 0.2)), (0.04, bp(white(0.15), 500, 3000) * env(0.15, 0.01, 0.12) * 0.25))
    mag_in = place(0.35, (0, bp(white(0.06), 400, 2500) * env(0.06, 0.01, 0.05) * 0.3), (0.06, clack(1100, 0.12, 0.25, 1.4)),
                   (0.06, thud(140, 0.08, 0.6) * 0.5))
    bolt = place(0.4, (0, clack(2100, 0.06, 0.12)), (0.07, bp(white(0.08), 1500, 6000) * env(0.08, 0.005, 0.07) * 0.3),
                 (0.16, clack(1700, 0.1, 0.2, 1.2)))
    return indoor(place(1.5, (0.0, mag_out), (0.55, mag_in), (1.05, bolt)), 0.12)


@sound("rifle_empty")
def rifle_empty(v):
    return indoor(place(0.2, (0, clack(2400, 0.04, 0.1, 0.7)), (0, click(0.006))), 0.1)


@sound("weapon_switch")
def weapon_switch(v):
    cloth = bp(white(0.18), 300, 2500) * np.sin(np.pi * t(0.18) / 0.18) ** 2 * 0.25
    return indoor(place(0.45, (0, cloth), (0.12, clack(1300, 0.07, 0.15)), (0.24, clack(1900, 0.08, 0.15, 0.8))), 0.1)


# --- Hits, pickups and UI ------------------------------------------------------------------

@sound("hit_tick", 2)
def hit_tick(v):
    flesh = lp(white(0.07), 1400 + 300 * v) * env(0.07, 0.0005, 0.05)
    tick = osc(1700 + 150 * v, 0.04) * env(0.04, 0.0005, 0.03) * 0.35
    return place(0.1, (0, flesh), (0, tick))


@sound("kill_tick")
def kill_tick(v):
    crunch = grains(0.12, 300, lambda i: bp(white(0.006), 800, 5000) * dsp.rng.uniform(0.2, 1.0)) * env(0.12, 0.001, 0.1)
    tone = place(0.3, (0, osc(1320, 0.12) * env(0.12, 0.001, 0.1)), (0.07, osc(1980, 0.2) * env(0.2, 0.001, 0.18)))
    return place(0.3, (0, crunch * 0.8), (0, tone * 0.45))


@sound("scrap_pickup", 2)
def scrap_pickup(v):
    pieces = [modal(0.4, metal_modes(dsp.rng.uniform(1800, 3400), 5, 2.0, 0.25)) * dsp.rng.uniform(0.4, 1.0) for _ in range(4)]
    return indoor(place(0.6, *[(k * dsp.rng.uniform(0.03, 0.06), p) for k, p in enumerate(pieces)]), 0.15)


@sound("cell_pickup")
def cell_pickup(v):
    d = 1.2
    hum = (osc(sweep(80, 160, d), d) + 0.4 * osc(sweep(160, 320, d), d, "saw")) * env(d, 0.25, 0.8) * 0.4
    return indoor(place(d, (0, clack(900, 0.15, 0.3, 1.2)), (0.05, hum), (0.4, osc(1760, 0.6) * env(0.6, 0.01, 0.5) * 0.15)), 0.2)


@sound("manifold_pickup")
def manifold_pickup(v):
    ring = modal(1.4, [(430, 1.2, 1.0), (1170, 0.9, 0.6), (2290, 0.6, 0.35), (3410, 0.4, 0.2)])
    hiss = bp(white(0.5), 2500, 8000) * env(0.5, 0.01, 0.4) * 0.06
    return indoor(place(1.4, (0, thud(110, 0.15, 0.7) * 0.7), (0, ring * 0.6), (0.05, hiss)), 0.2)


@sound("power_up")
def power_up(v):
    d = 2.4
    relays = [(k * 0.12, clack(900 + k * 150, 0.1, 0.2, 0.8)) for k in range(3)]
    spool = osc(sweep(40, 120, d, 0.5), d, "saw") * env(d, 1.2, 1.2) * 0.35
    spool = lp(spool, 900)
    whine = osc(sweep(400, 1800, d, 0.7), d) * env(d, 1.4, 0.9) * 0.08
    hum = (osc(60, 1.5) + 0.5 * osc(120, 1.5) + 0.3 * osc(180, 1.5)) * env(1.5, 0.3, 1.2) * 0.3
    return indoor(place(3.5, *relays, (0.3, spool), (0.3, whine), (1.9, hum), (1.9, thud(55, 0.4, 0.8) * 0.8)), 0.3)


@sound("fabricate")
def fabricate(v):
    d = 1.6
    servo = osc(sweep(300, 520, d), d, "square") * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * t(d))) * 0.12
    servo = bp(servo, 200, 3000)
    weld = lp(grains(d, 120, lambda i: hp(white(0.01), 2500) * dsp.rng.uniform(0.1, 0.6)), 7000) * 0.22
    ding = modal(1.2, [(1568, 1.0, 1.0), (3920, 0.6, 0.3), (6272, 0.3, 0.1)]) * 0.4
    return indoor(place(2.8, (0, servo), (0.2, weld), (d, clack(1000, 0.1, 0.2)), (d + 0.15, ding)), 0.25)


@sound("repair_clunk")
def repair_clunk(v):
    heavy = place(0.8, (0, thud(65, 0.5, 0.6) * 1.5), (0, modal(0.8, metal_modes(220, 8, 2.6, 0.7)) * 0.9),
                  (0, bp(white(0.1), 200, 2000) * env(0.1, 0.001, 0.08)))
    ratchet = [(0.3 + k * 0.075, clack(2200 + (k % 2) * 300, 0.04, 0.08, 0.6)) for k in range(5)]
    return indoor(place(2.0, (0, heavy), *ratchet, (0.75, heavy * 1.2)), 0.3)


@sound("log_chime")
def log_chime(v):
    b1 = modal(1.6, [(880, 1.4, 1.0), (2200, 0.8, 0.3), (3520, 0.5, 0.15)])
    b2 = modal(1.6, [(1318.5, 1.4, 1.0), (3296, 0.8, 0.3)])
    return indoor(place(2.0, (0, b1), (0.16, b2 * 0.8)), 0.35)


@sound("ui_click")
def ui_click(v):
    return place(0.08, (0, click(0.01, 2000, 8000)), (0, osc(1500, 0.04) * env(0.04, 0.0005, 0.03) * 0.4))


@sound("beacon_ping")
def beacon_ping(v):
    ping = place(0.4, (0, osc(1900, 0.4) * env(0.4, 0.002, 0.35)), (0, 0.3 * osc(3800, 0.2) * env(0.2, 0.002, 0.15)))
    return outdoor(ping * 0.6, 0.6)


@sound("stim")
def stim(v):
    hiss = hp(white(0.25), 3000) * env(0.25, 0.005, 0.2) * 0.5
    beat = place(1.2, (0.3, thud(60, 0.15, 0.7)), (0.55, thud(55, 0.15, 0.7) * 0.7))
    glow = osc(sweep(500, 1100, 0.8), 0.8) * env(0.8, 0.2, 0.5) * 0.12
    return indoor(place(1.3, (0, clack(2600, 0.04, 0.08)), (0.03, hiss), (0, beat * 0.9), (0.25, glow)), 0.15)



@sound("charge_throw")
def charge_throw(v):
    """Thumb off the arming collar, a rising capacitor whine, then the air as it leaves the hand."""
    arm = clack(3200, 0.05, 0.1, 0.7)
    whine = osc(sweep(1400, 5200, 0.35, 0.5), 0.35) * env(0.35, 0.25, 0.08) * 0.12
    whoosh = bp(pink(0.3), 500, 2400) * adsr(0.3, 0.08, 0.05, 0.6, 0.15) * 0.6
    return indoor(place(0.55, (0, arm), (0.02, whine), (0.12, whoosh)), 0.12)


@sound("charge_bounce", 3)
def charge_bounce(v):
    """The charge's steel shell skipping on basalt."""
    return outdoor(place(0.18, (0, clack(2100 + 400 * v, 0.06, 0.15, 0.8)), (0, thud(160, 0.06, 0.6) * 0.3)), 0.2)


@sound("charge_blast", 2)
def charge_blast(v):
    """Discharge: a white crack, a lightning tear across the band, the pressure thump and a long
    electrical sizzle as the field collapses, all thrown out across the basin."""
    d = 2.4
    crack = hp(white(0.02), 1500) * env(0.02, 0.0005, 0.015) * 1.5
    tear = grains(0.5, 420, lambda i: hp(white(0.003), 1800) * dsp.rng.uniform(0.3, 1.0)) * env(0.5, 0.001, 0.4)
    zap = fm(sweep(2600 + 200 * v, 140, 0.4), 1.41, 7.0, 0.4) * env(0.4, 0.0005, 0.3) * 0.7
    thump = place(1.0, (0, thud(52, 1.0, 0.45) * 2.2), (0, lp(white(0.5), 380) * env(0.5, 0.001, 0.4)))
    sizzle = (grains(1.6, 90, lambda i: hp(white(0.004), 3000) * dsp.rng.uniform(0.05, 0.4))
              + bp(osc(95, 1.6, "saw"), 200, 3000) * 0.12) * env(1.6, 0.01, 1.3)
    debris = grains(1.2, 14, lambda i: lp(white(0.04), dsp.rng.uniform(800, 3000)) * env(0.04, 0.001, 0.03) * dsp.rng.uniform(0.1, 0.4))
    x = place(d, (0, crack), (0, tear), (0, zap), (0.005, sat(thump, 2.2)), (0.12, sizzle), (0.25, debris))
    return outdoor(x, 0.5)


# --- Juno ----------------------------------------------------------------------------------

@sound("footstep_0", 4)
def footstep_gravel(v):
    """Boot on wet basalt grit: heel, then a crunch of small stones."""
    heel = lp(white(0.03), 700) * env(0.03, 0.001, 0.025) * 0.8
    crunch = grains(0.11, 450, lambda i: bp(white(n(0.003) / RATE), 900, 6000) * dsp.rng.uniform(0.05, 0.6))
    crunch *= env(0.11, 0.004, 0.1)
    x = place(0.2, (0, heel), (0.008, crunch), (0.06, lp(white(0.03), 500) * env(0.03, 0.002, 0.025) * 0.4))
    return trim(reverb(pitch(x, 1.0 + 0.05 * (v - 1.5)), CLOSE, 0.08))


@sound("footstep_1", 4)
def footstep_gravel_b(v):
    return footstep_gravel(v + 4) * 0.9


@sound("step_metal", 4)
def step_metal(v):
    """Boot on Kestrel's deck plates: a dull thump with a short plate ring."""
    thump = place(0.06, (0, lp(white(0.04), 500) * env(0.04, 0.001, 0.035)), (0, thud(90, 0.06, 0.6) * 0.5))
    ring = modal(0.3, metal_modes(310 + 25 * v, 7, 2.4, 0.18)) * 0.18
    rattle = clack(2600 + 200 * v, 0.03, 0.06, 0.12)
    return indoor(place(0.35, (0, thump), (0, ring), (0.01, rattle)), 0.2)


@sound("splash_0", 3)
def splash(v):
    slap = bp(white(0.06), 250, 1600) * env(0.06, 0.002, 0.05)
    drops = grains(0.25, 40, lambda i: osc(sweep(dsp.rng.uniform(900, 2000), dsp.rng.uniform(1800, 3200), 0.02), 0.02) *
                   env(0.02, 0.001, 0.018) * dsp.rng.uniform(0.1, 0.4))
    trickle = hp(white(0.3), 1800) * env(0.3, 0.02, 0.25) * 0.2
    return trim(reverb(place(0.4, (0, slap), (0.02, drops), (0.03, trickle)), CLOSE, 0.1))


@sound("splash_1", 3)
def splash_b(v):
    return splash(v + 3)


@sound("roll_whoosh", 2)
def roll_whoosh(v):
    d = 0.42
    air = dsp.swept(white(d), sweep(300, 1600 + 200 * v, d, 0.6), "lowpass") * np.sin(np.pi * t(d) / d) ** 1.5
    cloth = bp(white(d), 1500, 5000) * np.sin(np.pi * t(d) / d) ** 4 * 0.15
    gear = place(d, (0.08, clack(1800, 0.04, 0.08, 0.3)), (0.31, clack(1500, 0.05, 0.1, 0.4)), (0.33, lp(white(0.04), 600) * env(0.04, 0.001, 0.03)))
    return place(0.5, (0, air * 0.8), (0, cloth), (0, gear))


@sound("player_hurt", 2)
def player_hurt(v):
    impact = place(0.3, (0, lp(white(0.06), 900) * env(0.06, 0.0005, 0.05)), (0, thud(85, 0.2, 0.6)),
                   (0.005, modal(0.3, metal_modes(700 + 100 * v, 6, 2.0, 0.15)) * 0.25))
    alarm = place(0.5, (0.1, osc(1250, 0.07, "square") * env(0.07, 0.002, 0.07) * 0.08),
                  (0.2, osc(1250, 0.07, "square") * env(0.07, 0.002, 0.07) * 0.08))
    return indoor(place(0.6, (0, impact), (0, alarm)), 0.1)



@sound("thunder", 2)
def thunder(v):
    """A crack overhead, then the long rolling rumble off the basin walls."""
    d = 6.0
    crack = place(d, (0.0, hp(white(0.15), 600) * env(0.15, 0.002, 0.12) * (0.7 if v else 1.0)))
    roll = lp(brown(d), 160 + 40 * v) * adsr(d, 0.25, 0.4, 0.7, 3.5)
    rumble = grains(d * 0.7, 6, lambda i: lp(brown(0.6), dsp.rng.uniform(80, 220)) * env(0.6, 0.05, 0.5) * dsp.rng.uniform(0.3, 1.0))
    x = place(d + 0.5, (0, crack), (0.05, roll * 1.5), (0.3, rumble))
    return reverb(sat(x * 1.4, 1.5), BASIN, 0.5)


# --- Wildlife ------------------------------------------------------------------------------

def chitter(seconds, rate=40, base=2600, spread=900):
    """A train of chitin clicks."""
    return grains(seconds, rate, lambda i: modal(0.03, [(base + dsp.rng.uniform(-spread, spread), 0.02, 1.0),
                                                        (base * 1.9, 0.015, 0.4)], 0.0002), jitter=0.3)


def creature(seconds, f0, f1, vowel="a", rough=0.3, ratio=1.0, index=2.0, vib=6.0):
    """A creature call: an FM voice gliding from f0 to f1 through a vowel, with grit."""
    f = sweep(f0, f1, seconds) * (1.0 + 0.02 * np.sin(2 * np.pi * vib * t(seconds)))
    voice = fm(f, ratio, index, seconds) + 0.5 * osc(f, seconds, "saw")
    grit = bp(white(seconds), 300, 4000) * rough
    return formant(voice + grit, VOWELS[vowel])


@sound("scuttler_alert", 2)
def scuttler_alert(v):
    d = 0.6
    squeal = creature(d, 1600 + 200 * v, 2400, "i", 0.4, 1.5, 3.0, 22) * env(d, 0.02, 0.45) * 0.5
    return outdoor(place(0.8, (0, chitter(0.5, 55) * 0.6), (0.05, squeal)), 0.3)


@sound("scuttler_lunge", 2)
def scuttler_lunge(v):
    d = 0.35
    hiss = bp(white(d), 2000, 7000) * env(d, 0.01, 0.3) * 0.6
    snap = clack(3200 + 300 * v, 0.03, 0.06, 1.2)
    return outdoor(place(0.45, (0, hiss), (0.25, snap)), 0.25)


@sound("scuttler_hurt", 2)
def scuttler_hurt(v):
    d = 0.22
    return outdoor(creature(d, 2200 + 300 * v, 1500, "e", 0.6, 2.0, 4.0) * env(d, 0.005, 0.18) * 0.7 +
                   place(d, (0, chitter(0.1, 90))), 0.2)


@sound("scuttler_death", 2)
def scuttler_death(v):
    d = 0.8
    crunch = grains(0.25, 220, lambda i: bp(white(0.006), 600, 5000) * dsp.rng.uniform(0.2, 1.0)) * env(0.25, 0.001, 0.22)
    squeal = creature(d, 2000 + 200 * v, 500, "e", 0.5, 1.5, 3.0, 30) * env(d, 0.01, 0.6) * 0.5
    wet = lp(white(0.2), 800) * env(0.2, 0.01, 0.15) * 0.5
    legs = chitter(0.5, 25, 2000) * np.linspace(1, 0, n(0.5)) * 0.5
    return outdoor(place(1.0, (0, crunch), (0, squeal), (0.05, wet), (0.2, legs)), 0.3)


@sound("spitter_charge", 2)
def spitter_charge(v):
    d = 0.9
    bubbles = grains(d, 30 + 20 * np.linspace(0, 1, 1)[0], lambda i: osc(sweep(dsp.rng.uniform(150, 400), dsp.rng.uniform(500, 900), 0.04), 0.04) *
                     env(0.04, 0.002, 0.035) * dsp.rng.uniform(0.3, 1.0))
    throat = creature(d, 140 + 20 * v, 260, "o", 0.5, 0.5, 1.5, 4) * env(d, 0.4, 0.4) * 0.6
    return outdoor(place(1.0, (0, bubbles * np.linspace(0.3, 1.0, n(d)) * 0.7), (0, throat)), 0.25)


@sound("spitter_spit", 2)
def spitter_spit(v):
    d = 0.4
    burst = bp(white(d), 900, 5000) * env(d, 0.003, 0.25)
    pop = osc(sweep(500 + 60 * v, 140, 0.12), 0.12) * env(0.12, 0.002, 0.1) * 0.8
    goo = grains(0.3, 60, lambda i: lp(white(0.01), 1500) * dsp.rng.uniform(0.1, 0.5))
    return outdoor(place(0.5, (0, burst * 0.7), (0, pop), (0.05, goo)), 0.25)


@sound("spitter_death")
def spitter_death(v):
    d = 1.1
    gurgle = creature(d, 300, 90, "o", 0.6, 0.5, 2.0, 14) * env(d, 0.01, 0.9) * 0.7
    deflate = lp(white(d), 900) * env(d, 0.05, 0.9) * (0.5 + 0.5 * np.sin(2 * np.pi * 17 * t(d))) * 0.5
    return outdoor(place(1.3, (0, gurgle), (0, deflate)), 0.3)


@sound("ram_paw", 2)
def ram_paw(v):
    stomp = place(0.5, (0, thud(48 + 4 * v, 0.4, 0.7) * 1.4), (0, lp(white(0.15), 300) * env(0.15, 0.001, 0.12)))
    gravel = grains(0.25, 300, lambda i: bp(white(0.004), 700, 4000) * dsp.rng.uniform(0.05, 0.4)) * env(0.25, 0.005, 0.2)
    snort = bp(white(0.3), 300, 1800) * env(0.3, 0.05, 0.2) * 0.4
    return outdoor(place(0.7, (0, stomp), (0.01, gravel), (0.25, snort)), 0.3)


@sound("ram_charge")
def ram_charge(v):
    d = 1.4
    bellow = creature(d, 85, 120, "a", 0.5, 0.5, 2.5, 5) * env(d, 0.08, 1.1)
    sub = osc(sweep(42, 55, d), d) * env(d, 0.1, 1.1) * 0.6
    return outdoor(place(1.6, (0, sat(bellow * 1.5, 2.0)), (0, sub)), 0.4)


@sound("ram_stun")
def ram_stun(v):
    d = 1.2
    crack = place(0.6, (0, thud(60, 0.5, 0.5) * 1.5), (0, lp(white(0.3), 1200) * env(0.3, 0.0005, 0.25)))
    ring = osc(sweep(2300, 2000, d), d) * env(d, 0.002, 1.0) * 0.12 * (0.7 + 0.3 * np.sin(2 * np.pi * 7 * t(d)))
    groan = creature(0.7, 110, 70, "o", 0.4, 0.5, 1.5) * env(0.7, 0.05, 0.6) * 0.5
    return outdoor(place(1.5, (0, crack), (0.05, ring), (0.2, groan)), 0.35)


@sound("ram_death")
def ram_death(v):
    d = 1.8
    groan = creature(d, 100, 45, "o", 0.5, 0.5, 2.0, 3) * env(d, 0.05, 1.6)
    fall = place(1.0, (0, thud(45, 0.6, 0.6) * 1.5), (0, lp(white(0.4), 400) * env(0.4, 0.002, 0.35)))
    return outdoor(place(2.4, (0, groan), (0.9, fall)), 0.4)



def big_splash(seconds=0.9, size=1.0):
    """Something heavy breaking the surface: a low slap, a sheet of water, then falling drops."""
    slap = place(seconds, (0, lp(white(0.12), 600) * env(0.12, 0.002, 0.1) * 1.2), (0, thud(70, 0.2, 0.5) * 0.8))
    sheet = bp(white(0.5), 400, 3500) * adsr(0.5, 0.01, 0.1, 0.5, 0.3) * 0.5
    drops = grains(seconds, 60 * size, lambda i: osc(sweep(dsp.rng.uniform(700, 1800), dsp.rng.uniform(1600, 3000), 0.025), 0.025) *
                   env(0.025, 0.001, 0.02) * dsp.rng.uniform(0.1, 0.5))
    drops *= env(seconds, 0.15, seconds * 0.8)
    return place(seconds, (0, slap), (0.01, sheet), (0.05, drops))


@sound("lurker_emerge", 2)
def lurker_emerge(v):
    d = 1.6
    roar = creature(1.0, 120 + 10 * v, 70, "o", 0.6, 0.5, 3.0, 4) * env(1.0, 0.06, 0.8)
    gurgle = grains(0.8, 30, lambda i: (lambda f: bp(white(0.03), f, f * 2.5))(dsp.rng.uniform(200, 700)) * env(0.03, 0.002, 0.025) * dsp.rng.uniform(0.2, 0.7))
    x = place(d, (0, big_splash(1.2)), (0.12, sat(roar * 1.4, 2.0)), (0.1, gurgle * 0.6))
    return outdoor(x, 0.4)


@sound("lurker_hiss", 2)
def lurker_hiss(v):
    d = 0.6
    hiss = bp(white(d), 1800, 7000) * adsr(d, 0.12, 0.1, 0.8, 0.2) * 0.5
    rattle = grains(d, 35, lambda i: modal(0.03, [(900 + dsp.rng.uniform(-200, 200), 0.02, 1.0)], 0.0003)) * 0.4
    throat = creature(d, 180 + 15 * v, 160, "e", 0.6, 0.5, 1.5, 9) * 0.25 * adsr(d, 0.1, 0.1, 0.7, 0.2)
    return outdoor(place(0.7, (0, hiss), (0, rattle), (0, throat)), 0.25)


@sound("lurker_bite", 2)
def lurker_bite(v):
    snap = place(0.5, (0, clack(900 + 120 * v, 0.07, 0.15, 1.2)), (0, thud(110, 0.15, 0.6)),
                 (0.002, hp(white(0.02), 2000) * env(0.02, 0.0005, 0.015) * 0.8))
    lunge = bp(pink(0.3), 200, 1200) * adsr(0.3, 0.02, 0.05, 0.5, 0.2) * 0.4
    return outdoor(place(0.6, (0, lunge), (0.12, snap)), 0.25)


@sound("lurker_hurt", 2)
def lurker_hurt(v):
    d = 0.4
    return outdoor(creature(d, 260 + 30 * v, 180, "a", 0.5, 0.7, 2.5, 11) * env(d, 0.01, 0.3), 0.25)


@sound("lurker_death")
def lurker_death(v):
    d = 1.8
    wail = creature(d, 200, 60, "o", 0.5, 0.5, 2.2, 5) * env(d, 0.05, 1.4)
    bubbles = grains(1.4, 25, lambda i: osc(sweep(dsp.rng.uniform(200, 400), dsp.rng.uniform(500, 900), 0.03), 0.03) * env(0.03, 0.002, 0.025) * 0.4)
    return outdoor(place(2.0, (0, wail), (0.6, bubbles), (0.5, thud(60, 0.4, 0.5))), 0.4)


@sound("lurker_dive")
def lurker_dive(v):
    return outdoor(place(1.0, (0, big_splash(0.9, 0.7) * 0.8)), 0.3)


@sound("warden_roar")
def warden_roar(v):
    d = 2.6
    low = creature(d, 70, 55, "a", 0.6, 0.5, 3.0, 4) * adsr(d, 0.35, 0.5, 0.8, 1.2)
    mid = creature(d, 220, 160, "o", 0.8, 1.0, 4.0, 7) * adsr(d, 0.3, 0.6, 0.6, 1.0) * 0.6
    screech = creature(d, 900, 650, "e", 0.6, 1.5, 3.0, 11) * adsr(d, 0.5, 0.6, 0.4, 0.9) * 0.25
    sub = osc(sweep(32, 26, d), d) * adsr(d, 0.4, 0.5, 0.8, 1.0) * 0.7
    x = sat((low + mid + screech) * 1.4, 2.5) + sub
    return outdoor(x, 0.55)


@sound("warden_slam")
def warden_slam(v):
    d = 2.2
    boom = place(d, (0, thud(45, 1.2, 0.5) * 2.0), (0, lp(white(0.8), 500) * env(0.8, 0.001, 0.7)))
    debris = grains(1.4, 18, lambda i: lp(white(0.05), dsp.rng.uniform(600, 2500)) * env(0.05, 0.001, 0.04) * dsp.rng.uniform(0.1, 0.6))
    return outdoor(place(2.6, (0, sat(boom, 2.0)), (0.1, debris)), 0.5)


# --- World ---------------------------------------------------------------------------------

@sound("steam_hiss", 2)
def steam_hiss(v):
    d = 1.0
    hiss = bp(white(d), 2000, 9000) * (t(d) / d) ** 2 * np.minimum((d - t(d)) / 0.05, 1.0)
    gurgle = grains(d, 25, lambda i: osc(dsp.rng.uniform(200, 500), 0.03) * env(0.03, 0.002, 0.025) * 0.3) * (t(d) / d)
    return outdoor(hiss * 0.6 + gurgle, 0.2)


@sound("steam_burst", 2)
def steam_burst(v):
    d = 1.8
    roar = bp(white(d), 300, 6000) * np.minimum(t(d) / 0.02, 1.0) * np.exp(-t(d) * 1.4)
    rumble = lp(white(d), 180) * env(d, 0.01, 1.2) * 1.5
    spatter = grains(d, 60, lambda i: hp(white(0.006), 2500) * dsp.rng.uniform(0.05, 0.4)) * np.exp(-t(d) * 1.5)
    return outdoor(roar + rumble + spatter, 0.35)


@sound("rock_impact", 2)
def rock_impact(v):
    d = 1.6
    hit = place(d, (0, thud(60 + 10 * v, 0.6, 0.5) * 1.6), (0, lp(white(0.5), 900) * env(0.5, 0.0005, 0.4)))
    rubble = grains(1.2, 40, lambda i: bp(white(0.03), 400, 3000) * env(0.03, 0.001, 0.025) * dsp.rng.uniform(0.05, 0.6))
    rubble *= np.exp(-t(1.2) * 2.5)
    return outdoor(place(d, (0, sat(hit, 2.0)), (0.03, rubble)), 0.45)


@sound("arc_zap", 2)
def arc_zap(v):
    d = 0.7
    crackle = grains(d, 200, lambda i: hp(white(0.003), 2000) * dsp.rng.uniform(0.2, 1.0))
    buzz = bp(osc(100 + 20 * v, d, "saw"), 200, 4000) * 0.4
    x = (crackle + buzz) * env(d, 0.001, 0.6) * (0.6 + 0.4 * (dsp.rng.uniform(0, 1, n(d)) > 0.3))
    return outdoor(x, 0.25)


@sound("spore_burst")
def spore_burst(v):
    pop = place(0.2, (0, thud(180, 0.12, 0.5)), (0, lp(white(0.08), 1200) * env(0.08, 0.001, 0.06)))
    spray = bp(white(1.4), 500, 4000) * env(1.4, 0.03, 1.1) * 0.5
    sparkle = grains(1.2, 30, lambda i: osc(dsp.rng.uniform(3000, 6000), 0.03) * env(0.03, 0.001, 0.025) * 0.15)
    return outdoor(place(1.6, (0, pop), (0.02, spray), (0.1, sparkle)), 0.35)


@sound("loom_hum")
def loom_hum(v):
    d = 1.6
    f = sweep(40, 85, d)
    x = (osc(f, d) + 0.5 * osc(f * 2.01, d) + 0.25 * fm(f * 3, 0.5, 2.0, d)) * (t(d) / d) ** 2 * np.minimum((d - t(d)) / 0.05, 1.0)
    return outdoor(x, 0.4)


@sound("acid_splash", 2)
def acid_splash(v):
    d = 1.0
    splat = bp(white(0.1), 300, 2000) * env(0.1, 0.001, 0.08)
    sizzle = hp(white(d), 3000) * env(d, 0.02, 0.8) * (0.6 + 0.4 * dsp.rng.uniform(0, 1, n(d))) * 0.4
    bubbles = grains(d, 30, lambda i: osc(dsp.rng.uniform(800, 1600), 0.02) * env(0.02, 0.001, 0.015) * 0.2)
    return outdoor(place(1.1, (0, splat), (0.02, sizzle), (0.05, bubbles)), 0.25)


@sound("siege_horn")
def siege_horn(v):
    d = 3.2
    f = 82.4 * (1.0 + 0.004 * np.sin(2 * np.pi * 4.5 * t(d)))
    voice = sum(osc(f * k * (1 + 0.002 * k), d, "saw") / k for k in (1, 2, 3))
    horn = formant(voice, VOWELS["o"]) * adsr(d, 0.5, 0.4, 0.8, 1.3)
    return outdoor(sat(horn * 2.0, 1.8), 0.6)


@sound("crash_impact")
def crash_impact(v):
    d = 4.0
    boom = place(d, (0, thud(38, 2.0, 0.5) * 2.5), (0, lp(white(1.5), 700) * env(1.5, 0.001, 1.3) * 1.2))
    screech = modal(2.5, metal_modes(180, 12, 3.0, 1.8)) * 0.4 + bp(white(2.5), 1500, 5000) * env(2.5, 0.05, 1.8) * 0.3
    debris = grains(3.0, 25, lambda i: modal(0.3, metal_modes(dsp.rng.uniform(600, 2500), 4, 2.0, 0.2)) * dsp.rng.uniform(0.05, 0.5))
    debris *= np.exp(-t(3.0) * 1.0)
    return outdoor(place(d, (0, sat(boom, 2.5)), (0.08, screech), (0.2, debris)), 0.5)


@sound("launch_roar")
def launch_roar(v):
    d = 6.0
    rise = np.minimum(t(d) / 3.0, 1.0) ** 2
    roar = lp(pink(d), 2000) * rise * 1.2
    jet = bp(white(d), 1500, 7000) * rise * 0.4
    sub = osc(sweep(30, 45, d), d) * rise
    crackle = grains(d, 80, lambda i: lp(white(0.01), 3000) * dsp.rng.uniform(0.1, 0.8)) * rise * 0.5
    x = (roar + jet + sub + crackle) * np.minimum((d - t(d)) / 2.0, 1.0)
    return outdoor(sat(x, 1.8), 0.4)


# --- Loops (mono, played in 3D) -------------------------------------------------------------

def _seamless(x, seconds, xfade=0.5):
    k = n(seconds)
    f = n(xfade)
    out = np.array(x[:k])
    w = np.linspace(0, 1, f)
    out[:f] = out[:f] * w + x[k:k + f] * (1 - w)
    return out


@sound("ship_hum_loop")
def ship_hum_loop(v):
    d = 6.0
    tt = t(d + 0.5)
    hum = sum(a * np.sin(2 * np.pi * f * tt) for f, a in ((60, 1.0), (120, 0.5), (180, 0.25), (240, 0.12)))
    hum *= 0.85 + 0.15 * np.sin(2 * np.pi * tt / 3.0)
    air = lp(pink(d + 0.5), 900) * 0.25
    fan = bp(white(d + 0.5), 600, 2000) * (0.8 + 0.2 * np.sin(2 * np.pi * 23 * tt)) * 0.08
    return _seamless(hum * 0.5 + air + fan, d)


@sound("spool_loop")
def spool_loop(v):
    d = 4.0
    tt = t(d + 0.5)
    whine = np.sin(2 * np.pi * 440 * tt) * 0.5 + np.sin(2 * np.pi * 880 * tt) * 0.25 + np.sin(2 * np.pi * 1320.5 * tt) * 0.12
    whine *= 0.85 + 0.15 * np.sin(2 * np.pi * 4 * tt)
    turb = bp(white(d + 0.5), 400, 3000) * 0.35
    rumble = lp(white(d + 0.5), 120) * 0.6
    return _seamless(whine + turb + rumble, d)


# Peak levels, so the mix keeps the balance the game's volume settings were tuned against.
@sound("hit_crit", 2)
def hit_crit(v):
    """A weak-spot hit: a wet crack under a bright two-note ping, sharper than hit_tick."""
    crack = bp(white(0.09), 900 + 200 * v, 4200) * env(0.09, 0.0005, 0.07)
    ping = place(0.22, (0, osc(2350 + 120 * v, 0.08) * env(0.08, 0.0005, 0.07)),
                 (0.035, osc(3140 + 160 * v, 0.16) * env(0.16, 0.0005, 0.14)))
    return place(0.22, (0, crack * 0.8), (0, ping * 0.4))


@sound("skimmer_screech", 2)
def skimmer_screech(v):
    """A thin rising scream as it hangs before the dive."""
    d = 0.7
    cry = creature(d, 1300 + 150 * v, 2900, "i", 0.25, 2.0, 3.5, 28) * adsr(d, 0.04, 0.1, 0.8, 0.3) * 0.55
    rasp = bp(white(d), 2500, 8000) * adsr(d, 0.05, 0.1, 0.5, 0.3) * 0.2
    return outdoor(place(0.8, (0, cry), (0, rasp)), 0.4)


@sound("skimmer_dive", 2)
def skimmer_dive(v):
    """Air tearing past folded wings."""
    d = 0.9
    shape = np.sin(np.pi * t(d) / d) ** 2
    air = dsp.swept(white(d), sweep(500, 3200 + 300 * v, d, 0.5), "lowpass") * shape
    flutter = bp(white(d), 900, 3000) * shape * (0.5 + 0.5 * np.sin(2 * np.pi * 38 * t(d))) * 0.25
    return outdoor(place(1.0, (0, air * 0.8), (0, flutter)), 0.25)


@sound("skimmer_rake", 2)
def skimmer_rake(v):
    """Talons scraping across the suit."""
    d = 0.3
    scrape = grains(d, 70, lambda i: bp(white(0.008), 2500, 7000) * dsp.rng.uniform(0.3, 1.0)) * env(d, 0.005, 0.25)
    tick = clack(2600 + 200 * v, 0.03, 0.06, 0.8)
    return place(0.35, (0, scrape * 0.7), (0.02, tick * 0.6))


@sound("skimmer_flap", 3)
def skimmer_flap(v):
    """One heavy wingbeat: a soft thump of membrane."""
    d = 0.22
    thump = lp(white(d), 400 + 60 * v) * env(d, 0.01, 0.16)
    snap = bp(white(0.05), 700, 2200) * env(0.05, 0.002, 0.04) * 0.3
    return outdoor(place(0.25, (0, thump), (0.02, snap)), 0.2)


@sound("skimmer_hurt", 2)
def skimmer_hurt(v):
    d = 0.3
    return outdoor(creature(d, 1900 + 200 * v, 1200, "e", 0.4, 1.5, 3.0, 20) * env(d, 0.01, 0.25) * 0.6, 0.3)


@sound("skimmer_death")
def skimmer_death(v):
    d = 1.1
    wail = creature(d, 2100, 500, "i", 0.4, 1.5, 2.8, 14) * env(d, 0.02, 0.9) * 0.6
    flutter = grains(0.6, 26, lambda i: lp(white(0.03), 600) * env(0.03, 0.002, 0.025)) * 0.5
    return outdoor(place(1.2, (0, wail), (0.1, flutter)), 0.35)


@sound("signal_ping")
def signal_ping(v):
    """The visor's search ping: a short, soft two-tone blip."""
    blip = place(0.16, (0, osc(1480, 0.05) * env(0.05, 0.002, 0.045)), (0.05, osc(1980, 0.07) * env(0.07, 0.002, 0.06) * 0.7))
    return blip * 0.6


@sound("hull_groan")
def hull_groan(v):
    """A stranded hull shifting on rock: a low bending moan, a grinding scrape, a jolt."""
    d = 2.8
    moan = modal(d, metal_modes(62, 10, 2.2, 2.4)) * 0.7
    bend = osc(sweep(95, 60, d), d) * env(d, 0.4, 2.2) * 0.35
    scrape = bp(white(1.6), 300, 1800) * env(1.6, 0.15, 1.2) * 0.45
    jolt = thud(48, 0.8, 0.6) * 1.6
    return outdoor(place(d, (0, moan), (0, bend), (0.6, scrape), (1.7, sat(jolt, 2.0))), 0.5)


PEAKS = {
    "hit_tick": 0.5, "hit_crit": 0.55, "kill_tick": 0.6, "scrap_pickup": 0.5, "beacon_ping": 0.4, "footstep_0": 0.5, "footstep_1": 0.5,
    "step_metal": 0.5, "steam_hiss": 0.5, "arc_zap": 0.7, "spore_burst": 0.7, "turret_shot": 0.6, "weapon_switch": 0.6,
    "stim": 0.6, "acid_splash": 0.7, "spitter_charge": 0.6, "spitter_spit": 0.7, "ram_paw": 0.8, "ram_charge": 0.85,
    "ram_stun": 0.9, "warden_roar": 0.9, "siege_horn": 0.7, "crash_impact": 0.95, "repair_clunk": 0.85, "log_chime": 0.5,
    "ui_click": 0.5, "warden_slam": 0.95, "spitter_death": 0.7, "ram_death": 0.85, "launch_roar": 0.9, "splash_0": 0.5,
    "splash_1": 0.5, "roll_whoosh": 0.45, "lance_shot": 0.8, "scuttler_lunge": 0.7, "loom_hum": 0.8,
    "ship_hum_loop": 0.5, "spool_loop": 0.5, "player_hurt": 0.8, "rifle_empty": 0.7,
    "lurker_hurt": 0.7, "lurker_hiss": 0.7, "lurker_dive": 0.7,
    "thunder": 0.9,
    "charge_throw": 0.55, "charge_bounce": 0.5, "charge_blast": 0.95,
    "signal_ping": 0.4, "skimmer_flap": 0.45, "skimmer_rake": 0.7, "skimmer_hurt": 0.65, "skimmer_screech": 0.75,
    "hull_groan": 0.9,
}

# Sounds whose output should loop (a 'smpl' chunk in the WAV).
LOOPS = {"ship_hum_loop", "spool_loop"}


def main():
    names = sys.argv[1:] or list(SOUNDS)
    for k, name in enumerate(SOUNDS):
        if name not in names:
            continue
        fn, variants = SOUNDS[name]
        for v in range(variants):
            dsp.seed(1000 + k * 17 + v)
            x = fn(v)
            out = name if v == 0 else "%s__%d" % (name, v)
            write_wav(out, x, peak_=PEAKS.get(name, 0.89), loop=name in LOOPS)


if __name__ == "__main__":
    main()
