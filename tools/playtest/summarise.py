#!/usr/bin/env python3
"""Merges Hard Landing playtest session logs into one Markdown summary.

Each tester's game writes session_<date>.json to its playtests folder (see docs/PLAYTEST.md).
Collect them in one folder, renamed after the tester if you like (ana.json, ben.json), then:

    python3 tools/playtest/summarise.py <folder or files...> > playtest_summary.md

Standard library only.
"""
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def mmss(seconds):
    s = int(seconds)
    return f"{s // 60}:{s % 60:02d}"


def load(args):
    paths = []
    for a in args:
        p = Path(a)
        paths += sorted(p.glob("*.json")) if p.is_dir() else [p]
    sessions = []
    for p in paths:
        try:
            sessions.append((p.stem, json.loads(p.read_text(encoding="utf-8"))))
        except (OSError, ValueError) as e:
            print(f"Skipping {p}: {e}", file=sys.stderr)
    return sessions


def summarise(sessions):
    out = [f"# Playtest summary ({len(sessions)} sessions)", ""]
    out += ["| Tester | Played | Repairs | Deaths | Flags | Preset | Avg fps | Low fps |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for name, r in sessions:
        out.append(f"| {name} | {mmss(r['play_seconds'])} | {r['repairs_done']} | {r['deaths']} | {r['flags']} "
                   f"| {r['preset']} | {r['fps_avg']:.0f} | {r['fps_low']:.0f} |")

    # Objectives, in the order they first appear.
    times = defaultdict(list)
    order = []
    for _, r in sessions:
        for e in r["events"]:
            if e["kind"] == "objective_done":
                obj = e.get("objective", e["text"])
                if obj not in order:
                    order.append(obj)
                times[obj].append(e["seconds"])
    out += ["", "## Time per objective", "",
            "| Objective | Reached by | Median | Fastest | Slowest |", "| --- | --- | --- | --- | --- |"]
    for obj in order:
        t = times[obj]
        out.append(f"| {obj} | {len(t)}/{len(sessions)} | {mmss(statistics.median(t))} | {mmss(min(t))} | {mmss(max(t))} |")

    areas = defaultdict(lambda: {"seconds": 0.0, "damage": 0.0, "deaths": 0})
    for _, r in sessions:
        for n, a in r["areas"].items():
            for k in ("seconds", "damage", "deaths"):
                areas[n][k] += a[k]
    out += ["", "## Areas (all sessions)", "", "| Area | Time | Damage taken | Deaths |", "| --- | --- | --- | --- |"]
    for n, a in sorted(areas.items(), key=lambda kv: -kv[1]["seconds"]):
        out.append(f"| {n} | {mmss(a['seconds'])} | {a['damage']:.0f} | {a['deaths']} |")

    out += ["", "## Flags, deaths and stuck points", ""]
    any_moment = False
    for name, r in sessions:
        objective = ""
        for e in r["events"]:
            if e["kind"] == "objective":
                objective = e["text"]
            elif e["kind"] in ("flag", "death", "long_objective"):
                any_moment = True
                label = {"flag": "Flag", "death": "Death", "long_objective": "Stuck?"}[e["kind"]]
                where = e.get("area", "")
                pos = e.get("pos")
                at = f" at ({pos[0]:.0f}, {pos[2]:.0f})" if pos else ""
                out.append(f"- **{name} {mmss(e['t'])} {label}** in {where}{at}. {e['text']}. Objective: {objective}")
    if not any_moment:
        out.append("None.")
    return "\n".join(out) + "\n"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    sessions = load(sys.argv[1:])
    if not sessions:
        print("No session files found.", file=sys.stderr)
        return 1
    sys.stdout.write(summarise(sessions))
    return 0


if __name__ == "__main__":
    sys.exit(main())
