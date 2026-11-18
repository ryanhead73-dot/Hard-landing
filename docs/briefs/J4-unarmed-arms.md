# J4 — Juno's arms when she has no gun (Astra)

## Problem (Jake's playtest, 2026-11-18)
When Juno has no gun (the opening, before she builds the rifle: `player.armed = false`, set in
`godot/scripts/opening.gd`), her arms sit in an odd position. Cause: every clip in
`blender/build_juno.py` is keyed with her hands IK'd onto the rifle grip (`HOLD`, `GRIP_R`/`GRIP_L`),
and `godot/scripts/juno_animator.gd` has no unarmed path, so she holds an invisible rifle.

## Goal
Unarmed, she moves like a person with empty hands: relaxed arms at her sides with a natural
counter-swing in walk and run, hands slightly open, the same body/legs as today. Armed play must not
change at all.

## What to build
1. In `build_juno.py`, add upper-body clips with no weapon IK (use `FREE`): `idle_free` (same length
   and breathing as `idle`; arms hang relaxed, slight elbow bend, a small look/fidget),
   `walk_free` and `run_free` (same 0.8 s cycle and phase as `walk`/`run`, so they layer over the same
   legs: arms swing opposite the legs, run with bent elbows ~80-90 deg and bigger swing),
   `crouch_free` (hands resting near the knees), `fall_free` (arms out for balance). Fingers relaxed,
   not curled round a grip. Keep every existing clip byte-identical where possible.
2. In `juno_animator.gd`, when `player.armed` is false, blend the arm/hand/finger bones (not legs,
   not hips) to the matching `*_free` clip, driven by the same speed/crouch/air parameters as the
   armed locomotion, with a short fade (~0.2 s) when `armed` changes. Actions (interact, install,
   stim, throw), hurt, roll and die keep working unarmed. Aim while unarmed: no shouldered-rifle
   pose (player can't fire unarmed; check what `player.gd` does with aim input when `armed` is false
   and keep the arms free).
3. Tests in `godot/tests/animation_test.gd` (add, never loosen): with `player.armed = false`, both
   hands are at least 0.25 m from the rifle grip points and below chest height while idle; walking
   unarmed swings the arms in opposition to the legs; setting `armed = true` puts both hands back on
   the rifle (existing grip-gap thresholds).

## Files
- May edit: `blender/build_juno.py` (new clips only, plus helpers), `blender/juno_rigged.blend`,
  `godot/assets/models/juno_rigged.glb` (+ its atlas png if it re-extracts), `godot/scripts/juno_animator.gd`,
  `godot/tests/animation_test.gd`, `README.md` (Juno bullet: clip list).
- Must not edit: the model geometry/materials in `build_juno.py`, weapons, creatures, `opening.gd`
  story logic, save code.

## Test
Build: `~/tools/bpyenv/bin/python blender/build_juno.py`, re-import
(`cd godot && timeout 600 godot --headless --path . --import`). Run one at a time with
`timeout 900 godot --headless --path godot res://tests/<name>.tscn`: animation_test, feel_test,
visuals_test, smoke_test. Paste the PASS/FAIL lines. Report the new clip names and lengths and what
is unverified. (Xvfb may not work in your sandbox; the overseer renders in Godot.)
