# J5c — Foregrip hold: lower the right elbow, fix jump/land/roll support hand (Astra, medium)

## Review of J5b (overseer, 2026-11-18)
Accepted: the support glove now sits on the foregrip/pump for all three guns, muzzle pitch 19-23 deg
down, yaw under 12 deg, all five suites pass. Two problems remain.

1. **Right elbow flares up and out ("chicken wing").** In the in-game portrait and a rear-side view the
   right upper arm is roughly horizontal, elbow at shoulder height, and the stock sits up by her chin.
   Cause: `LOW_READY` was raised to y = 1.405 and the right-arm pole for forward holds is
   `frame @ (1, -.3, 1.7)` (mostly sideways/back, barely down).
2. **Codex review P2 (verified):** the new `GRIP_L` also applies to the `HOLD_W` poses used by armed
   jump, land and roll. Those poses don't bring the left shoulder forward, so IK clamps short and the
   left glove misses the grip by up to 19.7 cm (3.9 cm before J5b). The grip sweep doesn't cover them.

## Fix
1. Right arm in every forward hold (idle, walk, run, crouch, crouch_walk, fall, aim): elbow hangs down
   and slightly out, clearly below the shoulder (upper arm about 30-50 deg from vertical when not
   aiming). Point the right pole mostly down (e.g. chest-frame down with a little out/back), and lower
   `LOW_READY` (stock against the front of the right shoulder/upper chest, not up by the helmet) as
   far as the foregrip still allows. Keep muzzle pitch 15-25 deg down and yaw within 15 deg.
   `AIM_W` may keep a slightly higher elbow (shouldered), but not above the shoulder.
2. Make armed jump, land and roll reach the new foregrip: retune their weapon/shoulder poses (or switch
   them to the forward-hold frame) so the left glove stays within the existing L < 0.08 m threshold
   wherever the hand is meant to be on the gun. Add jump, land and roll to the grip sweep in
   `animation_test.gd` (sample the parts of roll where both hands should be on the gun; if a part of
   the roll is deliberately one-handed, exclude only that window and say so).
3. New check: while idle, walk and run (armed, each gun), the right elbow (ForeArmR head / UpperArmR
   tail) stays at least 0.12 m below the right shoulder joint; and while aiming, not above it.
4. Keep everything else from J5/J5b: GRIP_L point and markers, palm-to-surface checks, reload taking the
   left hand off, J4 unarmed clips byte-identical, all existing checks unchanged or stricter.

## Files
- May edit: `blender/build_juno.py` (hold constants, poles, armed clips), the Juno GLB and .blend,
  `godot/scripts/juno_animator.gd` (only if needed), `godot/tests/animation_test.gd`.
- Must not edit: weapon geometry or markers, Juno's mesh/materials, creatures, save code.

## Test
Rebuild Juno, re-import, run animation_test, feel_test, visuals_test, smoke_test and mechanics_test
one at a time (`timeout 900`). Report: right elbow drop below shoulder (idle/walk/run/aim), max grip
gaps for jump/land/roll per gun, idle muzzle pitch and yaw, and what is unverified.
