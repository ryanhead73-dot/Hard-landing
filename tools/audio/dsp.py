"""Small DSP kit for Hard Landing's generated audio (numpy + scipy).

Everything the game hears is synthesised from these pieces: noise and oscillators, filters
(fixed and swept), envelopes, modal (struck-object) synthesis, formant filters for creature
voices, saturation, and convolution reverb with generated impulse responses. Signals are
float64 arrays at RATE; stereo signals have shape (n, 2).
"""

import os
import struct
import subprocess
import tempfile

import numpy as np
import scipy.signal as ss

RATE = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "godot", "audio")

rng = np.random.default_rng(1)


def seed(s):
    global rng
    rng = np.random.default_rng(s)


def n(seconds):
    return max(1, int(round(RATE * seconds)))


def t(seconds):
    return np.arange(n(seconds)) / RATE


# --- Sources -------------------------------------------------------------------------------

def white(seconds):
    return rng.standard_normal(n(seconds))


def pink(seconds):
    b = [0.049922035, -0.095993537, 0.050612699, -0.004408786]
    a = [1.0, -2.494956002, 2.017265875, -0.522189400]
    return ss.lfilter(b, a, white(seconds)) * 3.5


def brown(seconds):
    x = np.cumsum(white(seconds))
    x = hp(x, 15)
    return x / (np.max(np.abs(x)) or 1.0)


def osc(freq, seconds, shape="sine", phase=None):
    """An oscillator; freq is a number or an array of per-sample frequencies."""
    k = n(seconds)
    f = np.full(k, float(freq)) if np.isscalar(freq) else np.asarray(freq, dtype=float)[:k]
    ph = np.cumsum(f) / RATE + (rng.uniform(0, 1) if phase is None else phase)
    if shape == "sine":
        return np.sin(2 * np.pi * ph)
    if shape == "saw":
        # Additive-ish saw: a naive saw tamed by a lowpass well under Nyquist.
        return lp(2.0 * (ph % 1.0) - 1.0, min(16000, RATE * 0.4))
    if shape == "square":
        return lp(np.sign(np.sin(2 * np.pi * ph)), min(14000, RATE * 0.4))
    if shape == "tri":
        return 2.0 * np.abs(2.0 * (ph % 1.0) - 1.0) - 1.0
    raise ValueError(shape)


def sweep(f0, f1, seconds, curve=1.0):
    """Per-sample frequency gliding from f0 to f1 (exponential when both are positive)."""
    x = (t(seconds) / seconds) ** curve
    if f0 > 0 and f1 > 0:
        return f0 * (f1 / f0) ** x
    return f0 + (f1 - f0) * x


def fm(carrier, ratio, index, seconds, index_env=None):
    """Two-operator FM; carrier may be an array. index_env scales the index over time."""
    k = n(seconds)
    c = np.full(k, float(carrier)) if np.isscalar(carrier) else np.asarray(carrier, dtype=float)[:k]
    mod = np.sin(2 * np.pi * np.cumsum(c * ratio) / RATE)
    idx = index * (index_env if index_env is not None else 1.0)
    return np.sin(2 * np.pi * np.cumsum(c) / RATE + idx * mod)


def modal(seconds, modes, strike=0.0005):
    """Struck-object synthesis: modes are (freq, t60, amp). A short noise strike excites them."""
    tt = t(seconds)
    out = np.zeros_like(tt)
    for f, t60, a in modes:
        if f >= RATE * 0.45:
            continue
        out += a * np.sin(2 * np.pi * f * tt + rng.uniform(0, 2 * np.pi)) * np.exp(-6.91 * tt / t60)
    att = np.minimum(tt / strike, 1.0)
    return out * att


def metal_modes(base, count=8, spread=2.7, t60=0.6, jitter=0.04):
    """Inharmonic plate-ish modes above `base`."""
    modes = []
    for k in range(count):
        f = base * (1.0 + spread * k ** 1.35 / 3.0) * (1.0 + rng.uniform(-jitter, jitter))
        modes.append((f, t60 * (1.0 - 0.6 * k / count), 1.0 / (1.0 + 0.6 * k)))
    return modes


def grains(seconds, rate_hz, make, jitter=1.0):
    """Scatters short sounds: make(i) returns a grain; rate_hz grains per second on average."""
    out = np.zeros(n(seconds))
    pos = 0.0
    i = 0
    while True:
        pos += rng.exponential(1.0 / rate_hz) if jitter else 1.0 / rate_hz
        k = int(pos * RATE)
        if k >= len(out):
            break
        g = make(i)
        m = min(len(g), len(out) - k)
        out[k:k + m] += g[:m]
        i += 1
    return out


# --- Filters -------------------------------------------------------------------------------

def _sos(kind, f, order):
    f = np.clip(f, 10.0, RATE * 0.49)
    return ss.butter(order, f, kind, fs=RATE, output="sos")


def lp(x, f, order=2):
    return ss.sosfilt(_sos("lowpass", f, order), x, axis=0)


def hp(x, f, order=2):
    return ss.sosfilt(_sos("highpass", f, order), x, axis=0)


def bp(x, lo, hi, order=2):
    return ss.sosfilt(_sos("bandpass", [lo, hi], order), x, axis=0)


def peak(x, f, q):
    b, a = ss.iirpeak(min(f, RATE * 0.49), q, fs=RATE)
    return ss.lfilter(b, a, x, axis=0)


def formant(x, formants):
    """Vowel-ish colour: formants are (freq, q, gain) resonances summed in parallel."""
    return sum(g * peak(x, f, q) for f, q, g in formants)


VOWELS = {
    "a": [(730, 8, 1.0), (1090, 10, 0.5), (2440, 14, 0.25)],
    "o": [(570, 8, 1.0), (840, 10, 0.45), (2410, 14, 0.15)],
    "u": [(300, 7, 1.0), (870, 10, 0.3), (2240, 14, 0.1)],
    "e": [(530, 8, 1.0), (1840, 12, 0.45), (2480, 14, 0.25)],
    "i": [(270, 7, 0.8), (2290, 12, 0.5), (3010, 14, 0.3)],
}


def swept(x, f_curve, kind="lowpass", block=256, order=2):
    """A filter whose cutoff follows f_curve (per sample), processed in blocks."""
    x = np.asarray(x, dtype=float)
    out = np.zeros_like(x)
    zi = None
    for s in range(0, len(x), block):
        f = float(np.clip(f_curve[min(s, len(f_curve) - 1)], 20.0, RATE * 0.3))
        wn = [f / 1.4, f * 1.4] if kind == "bandpass" else f
        sos = ss.butter(order, wn, kind, fs=RATE, output="sos")
        if zi is None:
            zi = np.zeros((sos.shape[0], 2))
        out[s:s + block], zi = ss.sosfilt(sos, x[s:s + block], zi=zi)
    return out


# --- Envelopes and shaping -----------------------------------------------------------------

def env(seconds, attack=0.002, decay=0.2, hold=0.0):
    """Attack, optional hold, then exponential decay; decay is the time to fall 60 dB."""
    tt = t(seconds)
    a = np.minimum(tt / max(attack, 1e-5), 1.0)
    d = np.exp(-6.91 * np.maximum(tt - attack - hold, 0.0) / decay)
    return a * d


def adsr(seconds, a, d, s, r):
    """Attack, decay to sustain level s, release over the last r seconds."""
    tt = t(seconds)
    e = np.where(tt < a, tt / max(a, 1e-5),
                 np.where(tt < a + d, 1.0 - (1.0 - s) * (tt - a) / max(d, 1e-5), s))
    return e * np.clip((seconds - tt) / max(r, 1e-5), 0.0, 1.0)


def fade(x, fin=0.002, fout=0.01):
    x = np.array(x, dtype=float)
    a, b = n(fin), n(fout)
    x[:a] *= np.linspace(0, 1, a)[:, None] if x.ndim == 2 else np.linspace(0, 1, a)
    x[-b:] *= np.linspace(1, 0, b)[:, None] if x.ndim == 2 else np.linspace(1, 0, b)
    return x


def sat(x, drive=2.0):
    return np.tanh(drive * x) / np.tanh(drive)


def norm(x, peak_=1.0):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak_


def place(total, *parts):
    """Mixes (start_seconds, signal) pairs into one buffer (mono or stereo by the first part)."""
    stereo = any(np.ndim(p[1]) == 2 for p in parts)
    out = np.zeros((n(total), 2)) if stereo else np.zeros(n(total))
    for start, sig in parts:
        sig = np.asarray(sig)
        if stereo and sig.ndim == 1:
            sig = np.stack([sig, sig], axis=1)
        i = int(RATE * start)
        m = min(len(sig), len(out) - i)
        if m > 0:
            out[i:i + m] += sig[:m]
    return out


def pitch(x, ratio):
    """Resamples by ratio (2.0 = an octave up, shorter)."""
    k = int(len(x) / ratio)
    return np.interp(np.arange(k) * ratio, np.arange(len(x)), x)


def pan(x, p):
    """Mono to stereo, p from -1 (left) to 1 (right), constant power."""
    a = (p + 1.0) * np.pi / 4.0
    return np.stack([x * np.cos(a), x * np.sin(a)], axis=1)


# --- Space ---------------------------------------------------------------------------------

def impulse(t60, length=None, bright=6000, dark=1200, early=(), predelay=0.0, stereo=False, density=1.0):
    """A generated room/outdoor response: decaying noise that darkens as it fades, with
    optional early reflections (delay, gain)."""
    length = length or t60 * 1.1
    tt = t(length)

    def one():
        x = white(length) * (rng.uniform(0, 1, len(tt)) < density) if density < 1 else white(length)
        d = np.exp(-6.91 * tt / t60)
        b = lp(x, bright) * d
        k = lp(x, dark) * d
        mixw = np.clip(tt / t60, 0, 1)
        r = b * (1 - mixw) + k * mixw
        r = place(length + predelay, (predelay, r))
        for dl, g in early:
            i = int((dl + predelay) * RATE)
            if i < len(r):
                r[i] += g * 30.0 * (1.0 + 0.2 * rng.standard_normal())
        return r / np.sqrt(np.sum(r ** 2) + 1e-9)

    return np.stack([one(), one()], axis=1) if stereo else one()


def reverb(x, ir, wet=0.3, dry=1.0):
    """Convolves with an impulse response; output is as long as input plus the tail."""
    if ir.ndim == 2:
        xs = x if x.ndim == 2 else np.stack([x, x], axis=1)
        w = np.stack([ss.fftconvolve(xs[:, c], ir[:, c]) for c in range(2)], axis=1)
    else:
        xs = x
        w = ss.fftconvolve(x, ir)
    d = np.zeros_like(w)
    d[:len(xs)] = xs
    return dry * d + wet * w * (np.max(np.abs(x)) / (np.max(np.abs(w)) or 1.0))


def trim(x, threshold_db=-60.0, keep=0.05):
    """Drops the silent tail."""
    a = np.abs(x).max(axis=1) if x.ndim == 2 else np.abs(x)
    m = a.max() or 1.0
    idx = np.where(a > m * 10 ** (threshold_db / 20.0))[0]
    end = min(len(x), (idx[-1] if len(idx) else len(x) - 1) + n(keep))
    return fade(x[:end], 0.0005, min(0.05, end / RATE * 0.2))


def wrap_loop(x, length):
    """Folds everything after `length` seconds back onto the start, so a loop's tails carry
    over the seam."""
    k = n(length)
    out = np.array(x[:k], dtype=float)
    rest = x[k:]
    while len(rest):
        m = min(len(rest), k)
        out[:m] += rest[:m]
        rest = rest[m:]
    return out


# --- Output --------------------------------------------------------------------------------

def _pcm(x, peak_):
    x = np.asarray(x, dtype=np.float64)
    m = np.max(np.abs(x)) or 1.0
    return np.clip(x / m * peak_, -1, 1)


def write_wav(name, x, peak_=0.89, loop=False):
    """16-bit WAV (mono or stereo). Loops get a 'smpl' chunk, which Godot reads as loop points."""
    x = _pcm(x, peak_)
    ch = 2 if x.ndim == 2 else 1
    pcm = (x * 32767).astype("<i2").tobytes()
    chunks = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, ch, RATE, RATE * 2 * ch, 2 * ch, 16)
    if loop:
        frames = len(x)
        smpl = struct.pack("<9I", 0, 0, 1_000_000_000 // RATE, 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, frames - 1, 0, 0)
        chunks += struct.pack("<4sI", b"smpl", len(smpl)) + smpl
    chunks += struct.pack("<4sI", b"data", len(pcm)) + pcm
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f"{name}.wav"), "wb") as fh:
        fh.write(struct.pack("<4sI4s", b"RIFF", 4 + len(chunks), b"WAVE") + chunks)
    _drop(name, keep=".wav")
    print("wrote", name, "%.2fs" % (len(x) / RATE))


def write_ogg(name, x, peak_=0.89, quality=5):
    """Ogg Vorbis via ffmpeg, for long stereo loops (music and ambience). The game sets them
    looping when it loads them."""
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "x.wav")
        x = _pcm(x, peak_)
        ch = 2 if x.ndim == 2 else 1
        pcm = (x * 32767).astype("<i2").tobytes()
        hdr = struct.pack("<4sIHHIIHH", b"fmt ", 16, 1, ch, RATE, RATE * 2 * ch, 2 * ch, 16)
        hdr += struct.pack("<4sI", b"data", len(pcm))
        with open(wav, "wb") as fh:
            fh.write(struct.pack("<4sI4s", b"RIFF", 4 + len(hdr) + len(pcm), b"WAVE") + hdr + pcm)
        dst = os.path.join(OUT, f"{name}.ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", str(quality), dst], check=True)
    _drop(name, keep=".ogg")
    print("wrote", name, "%.2fs (ogg)" % (len(x) / RATE))


def _drop(name, keep):
    """Removes the other format's file for this sound, so only one of them ships."""
    for ext in (".wav", ".ogg"):
        if ext != keep:
            p = os.path.join(OUT, name + ext)
            if os.path.exists(p):
                os.remove(p)
