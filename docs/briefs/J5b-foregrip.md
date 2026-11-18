# J5b — Rejected J5: the support hand is on the wrong part of the gun (Astra, medium)

J5 kept the gloves on the GripR/GripL markers through every loop, but in game the support hand still
reads as clenched near her chest, as in Jake's screenshot. Root cause: `GRIP_L = (0, -0.06, -0.12)`
dates from the old 0.42 m box rifle. On the rebuilt guns (about 0.95 m long, muzzle at z = -0.48,
pistol grip at z = +0.17) that point is just in front of the magazine well, 29 cm from the right hand,
so both hands bunch at the back half and the whole front of the gun hangs unsupported.

## Fix
1. Move the support-hand point forward onto a real foregrip, shared by all three guns (the clips are
   baked once for every weapon): about z = -0.27 (between -0.24 and -0.30), on the underside of the
   handguard, with the glove wrapped round it, palm up and fingers over the side.
   - Rifle: the handguard/shroud underside at that z (add a short vertical or angled foregrip if
     there is no surface to hold).
   - Scattergun: the pump (`Pump` empty is at z = -0.25); the hand goes on the pump.
   - Arc lance: add a foregrip at that point on the frame below the coils, without hiding the coils.
   Update `GRIP_L` in `blender/build_juno.py`, the `GripL` empties in `blender/build_weapons.py`, the
   grip constants in `godot/tests/animation_test.gd`, and anything else that reads them.
2. Re-solve every armed clip (idle, walk, run, crouch, crouch_walk, fall, aim, and the start/end of
   reload) against the new point. Keep the low-ready angle from J5 (muzzle 15-25 deg down) and keep
   the rifle pointing forward along her facing, not yawed across her body (add a check: muzzle yaw
   within 15 deg of her forward while idle and walking). Arm must not pass through the torso,
   magazine or pack.
3. Add a check that the left glove centre is within 4 cm of the weapon's mesh surface (a short
   raycast or nearest-point test against the equipped gun) while idle, for each of the three guns.
4. Keep J4 unarmed clips and all existing checks. Reload must still take the left hand off for the
   cell swap.

## Files
- May edit: `blender/build_juno.py` (hold constants, armed clips), `blender/build_weapons.py` (GripL
  empties, foregrip geometry only), the four GLBs and .blend, `godot/scripts/juno_animator.gd`,
  `godot/tests/animation_test.gd`.
- Must not edit: model geometry/materials of Juno, creatures, save code.

## Test
Rebuild Juno and the weapons, re-import, run animation_test, feel_test, visuals_test, smoke_test and
mechanics_test one at a time (`timeout 900`). Report new GRIP_L, grip gaps, idle muzzle pitch and yaw,
glove-to-surface distances per gun, and what is unverified.
