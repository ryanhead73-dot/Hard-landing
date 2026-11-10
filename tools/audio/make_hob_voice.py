"""HOB's voice: turns the neural-TTS takes (tools/tts, see docs) into the ship computer.

Reads <raw>/<hash>.wav (24 kHz mono, one per HOB line, named by the md5 of the line's text, first
12 hex digits) and writes godot/audio/voice/hob/<hash>.ogg. Voice.gd finds a line's take by the
same hash. The treatment: band-limited like an intercom, a short metallic comb, a light ring
modulation for the machine in it, and a touch of drive.

    python tools/audio/make_hob_voice.py /path/to/raw
"""
import os, sys, glob
import numpy as np
from scipy.signal import resample_poly
from scipy.io import wavfile
sys.path.insert(0, os.path.dirname(__file__))
import dsp


def robot(x, sr):
    x = resample_poly(x, dsp.RATE, sr) if sr != dsp.RATE else x
    x = dsp.hp(x, 140.0)
    d = int(0.0065 * dsp.RATE)
    comb = np.concatenate([np.zeros(d), x[:-d]])
    y = x + 0.38 * comb
    t = np.arange(len(y)) / dsp.RATE
    y = 0.8 * y + 0.2 * y * np.sin(2 * np.pi * 85.0 * t)
    y = dsp.bp(y, 220.0, 7200.0)
    y = dsp.sat(y * 1.4, 1.6)
    # A breath of room at the end so the cut isn't abrupt.
    return dsp.fade(np.concatenate([y, np.zeros(int(0.12 * dsp.RATE))]), 0.004, 0.08)


def main(raw):
    os.makedirs(os.path.join(dsp.OUT, "voice", "hob"), exist_ok=True)
    n = 0
    for f in sorted(glob.glob(os.path.join(raw, "*.wav"))):
        sr, x = wavfile.read(f)
        x = x.astype(np.float64) / (32768.0 if x.dtype == np.int16 else 1.0)
        if x.ndim > 1:
            x = x.mean(axis=1)
        name = os.path.splitext(os.path.basename(f))[0]
        dsp.write_ogg("voice/hob/" + name, robot(x, sr), 0.7, 4)
        n += 1
    print(n, "lines")


if __name__ == "__main__":
    main(sys.argv[1])
