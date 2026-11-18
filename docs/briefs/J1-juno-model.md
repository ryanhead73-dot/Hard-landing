# J1 — Juno's model, a big quality jump (Astra)

## Goal
Juno, the player character, still reads as a toy: capsule limbs, ball hands, a round helmet and
flat colours (see `/mnt/project-files/hard-landing-juno/before_juno_sheet.jpg`). Rebuild her look
in `blender/build_juno.py` so she reads as a believable salvage-crew survivor in a worn
hard-shell EVA suit, at third-person camera distance (2.5-5 m), in the game's style: worn ivory
armour, oxide orange accents, slate-teal suit fabric, gunmetal hardware, warm amber visor, one
small teal status lamp.

## What "done" looks like
- Proportions: an athletic adult woman in a bulky suit, ~1.78 m to the top of the helmet (keep the
  current joint heights within 3 cm so clips and the camera still fit). Narrower waist than chest
  and hips, shoulders that read under the pauldrons, slight taper to wrists and ankles.
- Under-suit: smooth, continuous, no visible capsule seams. Add soft fabric detail (quilted panels
  on the abdomen and inner thighs, ribbed joints at knees/elbows, seams) as geometry or as baked
  vertex colour/AO, not as floating pieces.
- Hard armour, each piece bevelled with readable panel lines and chipped-paint wear baked in:
  chest plate with a recessed centre and an oxide stripe, segmented abdominal guard, back plate,
  pauldrons, upper-arm and forearm bracers, thigh plates, knee and elbow cops, shin guards.
- Helmet: a faceted shell (not a sphere) with a recessed, curved amber visor (emissive rim only,
  glass reads glossy), a chin/jaw guard, a brow ridge, side ear pods with a small antenna, a
  shoulder-mounted lamp on the right, and a neck seal ring.
- Hands: gloves with four fingers and a thumb (simple 2-3 segment shapes are fine), knuckle
  guards. Add bones `HandL/HandR` (child of the forearm) and, per hand, `FingersL/R` (one bone
  for the four fingers) and `ThumbL/R`, so animation can curl them around a grip.
- Feet: boots with a chunky sole, tread, ankle guard and toe cap. Add bones `FootL/FootR` (child
  of the shin) so the clips can roll the feet.
- Kit: a harness (two chest straps to the belt), a utility belt with 3-4 pouches, a tool on the
  left hip, a thigh holster or pouch on the right, the life-support pack rebuilt with more
  detail (frame, two tanks with bands and valves, a vent grille, a coiled hose to the helmet,
  the teal status lamp, a rolled blanket or tool roll strapped under it), a couple of cloth or
  tape patches for character.
- Materials: at most 6 materials. Colour comes from vertex colours baked with AO and edge wear
  (see how `blender/creature_kit.py` bakes paint and AO into sRGB vertex colours and the game
  turns them on via `CreatureLook`), or from a small atlas; roughness and metallic must differ
  per material (fabric matte, plates satin, metal more metallic, visor glossy).
- Budget: 18,000-30,000 triangles total for Juno (GTX 1660, 1080p60 Medium). One skinned mesh
  for the body is preferred; rigidly bound armour may stay separate meshes if under 12 draw calls
  total.

## Must keep (the game depends on these)
- Bone names `Hips Spine Chest Neck Head PackMount ArmL ForearmL ArmR ForearmR LegL ShinL LegR
  ShinR WeaponMount` and their parent chain. New bones are additive only.
- All 16 clip names and their lengths: idle walk run crouch crouch_walk jump fall aim reload hurt
  roll interact install stim throw die (`godot/scripts/juno_animator.gd` ACTIONS, LOOPS,
  WALK_CYCLE/RUN_CYCLE/CROUCH_CYCLE/CYCLE_TIME). Re-key them onto the new mesh; animation
  quality itself is J3, so do not rework the motion here beyond what new bones need.
- The two-hand IK onto `GRIP_R`/`GRIP_L`, so the hands stay on the rifle (`HAND = 0.35` m elbow to
  glove centre in the animator; update the constant if the glove centre moves, and say so).
- Mesh node name `JunoMesh` and `Skeleton3D` (checked by `visuals_test`).
- `blender/build_people.py` builds the survivors on Juno's bone names: run it after your change and
  make sure the five `person_*.glb` still build and look right (they may keep their own looks).

## Files
- May edit: `blender/build_juno.py`, `blender/build_people.py` (only if needed to keep it
  building), `godot/assets/models/juno_rigged.glb`, `godot/assets/models/person_*.glb`,
  `blender/juno_rigged.blend`, `godot/scripts/juno_animator.gd` (constants only),
  `godot/tests/rig_shots.gd` (to attach the rifle in shots), `README.md` (the Juno bullet).
- Must not edit: `blender/creature_kit.py`, `blender/build_creatures.py`, any creature GLB,
  `blender/build_models.py` weapon functions (J2 owns weapons), save/campaign/mission scripts.
  Do not delete or weaken tests.

## How to build and test
- Build: `~/tools/bpyenv/bin/python blender/build_juno.py` (bpy 4.2, headless), then
  `~/tools/bpyenv/bin/python blender/build_people.py`.
- Re-import: `cd godot && timeout 600 godot --headless --path . --import`.
- Tests (all must pass; wrap each in `timeout 900`):
  `godot --headless --path godot res://tests/animation_test.tscn`,
  `res://tests/visuals_test.tscn`, `res://tests/feel_test.tscn`, `res://tests/smoke_test.tscn`.
  Run at most two at once.
- Renders: `xvfb-run -a godot --path godot --rendering-driver opengl3 res://tests/rig_shots.tscn --
  /mnt/project-files/hard-landing-juno/j1 juno_rigged` (rest pose, four sides) and
  `... juno_rigged "idle:0.3:front,run:0.25:side,aim:0.5:front,reload:0.5:front"`.
  Look at the renders yourself and fix anything that clips, floats or reads as a primitive.
- Report: triangle count, material count, draw calls, bone list, clip list with lengths, test
  results (paste the pass/fail lines), what you could not verify.
