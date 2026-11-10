"""HOB's lines -> raw TTS takes, one WAV per fixed line, named by the md5 of its text (12 hex).

Needs: pip install kokoro-onnx soundfile, and kokoro-v1.0.onnx + voices-v1.0.bin from
https://github.com/thewh1teagle/kokoro-onnx/releases (model-files-v1.0) in the working directory.
Then run tools/audio/make_hob_voice.py on the output folder. Re-run after changing HOB's lines;
existing takes are kept.
"""
import re, os, sys, glob, hashlib, json, soundfile as sf
from kokoro_onnx import Kokoro
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "godot", "scripts")
OUT = sys.argv[1] if len(sys.argv) > 1 else "voice_raw"
os.makedirs(OUT, exist_ok=True)
pat = re.compile(r'(?:\bHOB|"HOB"|Story\.HOB), "((?:[^"\\]|\\.)*)"')
lines = {}
for f in glob.glob(SRC + "/**/*.gd", recursive=True):
    for m in pat.finditer(open(f).read()):
        text = m.group(1).replace('\\"', '"')
        if "%" in text:
            continue
        lines[hashlib.md5(text.encode()).hexdigest()[:12]] = text
print(len(lines))
json.dump(lines, open(OUT + "/lines.json", "w"), indent=1)
k = Kokoro("kokoro-v1.0.onnx", "voices-v1.0.bin")
for h, text in lines.items():
    p = f"{OUT}/{h}.wav"
    if os.path.exists(p):
        continue
    # HOB is said as a name, not spelled out.
    s, sr = k.create(text.replace("HOB", "Hob"), voice="bm_george", speed=1.08, lang="en-gb")
    sf.write(p, s, sr)
print("done")
