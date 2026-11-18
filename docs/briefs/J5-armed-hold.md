# J5 — Juno's armed hold: support hand on the foregrip, believable low-ready (Astra)

## Playtest report from Jake (2026-11-18)
Screenshot: `/mnt/project-files/hard-landing-juno/playtest/juno_gun_arm.png`. Standing with the rifle in
game, the support (left) hand is clenched against her chest instead of on the foregrip, and the rifle
hangs low, angled steeply down and off to her left side, away from the body. The overseer's Godot
render of the `idle` clip shows the same thing. The existing test only checks the grip gap at one
instant, and measures the hand as forearm + `HAND` constant rather than the real glove, so it misses
this.

## Fix
1. Armed hold: in every armed loop (idle, walk, run, crouch, crouch_walk, fall) and over the WHOLE
   loop, the left hand stays on the foregrip (GripL) and the right on the pistol grip (GripR). Remove
   any idle "rifle adjust" that takes the left hand off; a small weight shift of the rifle is fine.
2. Carry angle: a believable low-ready. The rifle sits close in front of her torso, stock near the
   right hip/belly, muzzle forward and down about 15-25 deg, pointing roughly at the ground 2-3 m
   ahead, not across to her left side. Tune `HOLD` / `HOLD_W` (and `AIM_W` only if needed; aim already
   looks right).
3. Measure hands for real: in `juno_animator.gd` make `hand(side)` use the Hand bone (HandL/R, glove
   centre). In `animation_test.gd` sample the grip gap over a full cycle of idle, walk and run (max
   over ~1 s each), measured against the GripR/GripL markers of the gun actually equipped (rifle, then
   scattergun, then arc lance). Thresholds: R < 0.06 m, L < 0.08 m. Add a check on the rest carry
   angle (muzzle pitched down between 10 and 30 deg while idle). Never loosen existing checks.
4. Reload, throw, stim and install keep their current left-hand behaviour. The J4 unarmed clips and
   their tests keep passing.
5. Add a `juno_unarmed` portrait to `godot/tests/screenshots.gd` (same spot as `juno`, with
   `player.armed = false`) so both poses can be rendered for review.

## Files
- May edit: `blender/build_juno.py` (hold poses and armed clips only), the GLB/.blend (+ atlas png if
  re-extracted), `godot/scripts/juno_animator.gd`, `godot/tests/animation_test.gd`,
  `godot/tests/screenshots.gd`.
- Must not edit: model geometry/materials, weapons, creatures, save code.

## Test
Build with `~/tools/bpyenv/bin/python blender/build_juno.py`, re-import
(`cd godot && timeout 600 godot --headless --path . --import`), then run animation_test, feel_test,
visuals_test and smoke_test one at a time (`timeout 900`). Report max grip gaps per clip and weapon,
the idle muzzle pitch, and what is unverified.
