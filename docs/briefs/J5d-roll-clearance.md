# J5d — Keep the gun above the floor during the armed roll (Astra, medium)

## Review of J5c (overseer + Codex review, 2026-11-18)
Accepted: right elbow now 29-30 cm below the shoulder in idle/walk/run/aim, both gloves on the gun
through jump, land and roll, muzzle pitch/yaw unchanged, all five suites pass.

One regression (Codex review P2, verified by sampling): the roll tuck now uses `LOW_READY`
(`blender/build_juno.py` ~1191), and with the rifle on `WeaponMount` the stock sinks about 35 cm below
flat ground around 40% of the roll (about 22 cm before J5c). The grip sweep doesn't catch it because
the hands follow the weapon underground.

## Fix
1. Give the roll its own tuck pose: rifle held tight across the chest/belly during the inverted part,
   so no part of any of the three equipped guns goes below the floor on flat ground (target: deepest
   point at or above 0.0 m; at worst 5 cm below). Keep both gloves on the grips (existing thresholds).
2. Add a test in `animation_test.gd`: sample the roll at 60 Hz with each gun equipped on flat ground and
   check the lowest point of the gun's mesh AABB (or its Muzzle/stock ends) in world space stays above
   floor - 0.05 m. Report the deepest value per gun.
3. Keep every J4/J5/J5b/J5c check and number unchanged or better; touch no other clip.

## Files
- May edit: `blender/build_juno.py` (roll clip and its hold pose only), the Juno GLB and .blend,
  `godot/tests/animation_test.gd`.
- Must not edit: anything else.

## Test
Rebuild Juno, re-import, run animation_test, feel_test, visuals_test, smoke_test and mechanics_test
one at a time (`timeout 900`). Report deepest gun point during the roll per gun, roll grip gaps, and
what is unverified.
