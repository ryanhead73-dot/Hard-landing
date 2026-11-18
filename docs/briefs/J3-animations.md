# J3 — Juno's animations, a quality pass (Astra; after J1 lands)

## Goal
Make her motion read as a real person in a heavy suit: weight, overlap and planted feet. Today
the clips are stiff (legs swing like pendulums, no foot roll, hands are fists, idle barely moves).

## What "done" looks like
- **Feet**: walk, run, crouch walk use planted-foot gaits with heel strike, roll and toe-off on
  the new `FootL/R` bones. `blender/creature_kit.py` has a `Gait` helper for planted feet; you
  may import it (do not edit it). Feet must not slide more than ~4 cm at the speeds the game plays
  each clip (WALK_CYCLE/RUN_CYCLE/CROUCH_CYCLE over CYCLE_TIME in `juno_animator.gd`). Keep the
  cycle distances the same, or change the constants and say so.
- **Body**: hips shift and rotate with the stride, counter-rotating chest, head stabilised,
  slight bob, the pack lags a little (PackMount), run leans forward (test needs Spine x < -4).
- **Hands**: fingers wrapped round the grip and foregrip in every gun-holding clip; open hand on
  reach/interact; curled round the stim and the throwable.
- **Idle**: breathing, weight shift from foot to foot, a look around, a small rifle adjust;
  4-6 s loop that does not pop.
- **Aim**: shouldered, cheek to the stock, elbow out, a settled stance.
- **Reload**: tilt the rifle, the left hand pulls the spent cell, goes to the belt, slaps a fresh
  one in, works the charging handle (keep the test's checks: hand leaves by > 0.2 m, rifle
  tilt > 0.25).
- **Jump / fall**: anticipation crouch on take-off, tuck, arms out for balance in the fall.
  Add a new `land` clip (0.35 s, knees absorb, recover) for the game to play on touchdown.
- **Roll**: shoulder roll with the rifle tucked, ends in a crouch-ready pose.
- **Hurt**: a sharper flinch with recovery. **Die**: knees buckle, falls to the side, settles.
- **Install / interact / stim / throw**: same timings, cleaner arcs, anticipation and follow-
  through.
- All clips loop cleanly where they loop (first and last keys equal), and no limb passes through
  the body or pack in any frame you render.

## Must keep
- Clip names and lengths of the 16 clips; `land` is new. Bone names. Two-hand IK onto the grip.
- `godot/tests/animation_test.gd` checks: legs swing > 25° range and in opposition, run Spine x
  < -4, crouch Leg x > 50 and knee bend > 80 and hips < 0.6, jump leg x > 10, aim weapon y > 1.45,
  throw wind-up hand y > 1.5 then z < -0.45, install hips < 0.75 and both hands z < -0.35, down
  hips < 0.4, stim left hand y < 1.0.

## Files
- May edit: `blender/build_juno.py` (actions only, plus any helper), the GLB and .blend,
  `godot/scripts/juno_animator.gd` (to play `land` on touchdown and constants),
  `godot/tests/animation_test.gd` (add checks for `land` and foot slide; never loosen existing
  checks).
- Must not edit: `blender/creature_kit.py`, creature files, weapons, save/mission code.

## How to build and test
- `~/tools/bpyenv/bin/python blender/build_juno.py`, re-import, then run `animation_test`,
  `feel_test`, `visuals_test`, `smoke_test` (timeout 900 each, at most two at once).
- Renders: `xvfb-run -a godot --path godot --rendering-driver opengl3 res://tests/rig_shots.tscn --
  /mnt/project-files/hard-landing-juno/j3 juno_rigged "walk:0:side,walk:0.25:side,walk:0.5:side,
  run:0:side,run:0.25:side,idle:0.5:front,aim:0.5:front,reload:0.3:front,reload:0.6:front,
  land:0.3:side,roll:0.5:side,die:1:front"`. Measure foot slide numerically (bone world positions
  sampled over a cycle in a small Godot or bpy script) and report the number.
- Report clip list with lengths, foot-slide numbers, test pass/fail lines, what is unverified.
