# J2 — Juno's three weapons, rebuilt (Astra)

## Goal
The rifle, scattergun and arc lance are a few boxes each (see
`/mnt/project-files/hard-landing-juno/before_weapons_sheet.jpg`). Rebuild them as believable
salvage-built sci-fi guns that read clearly at third-person distance and each have a distinct
silhouette, in a new script `blender/build_weapons.py` (move the three functions out of
`blender/build_models.py`, and leave a one-line pointer there).

- **Salvage rifle** (the default gun, built by Juno in the opening): a compact bullpup-ish
  carbine made from ship parts. Ribbed receiver, a heat-sinked barrel shroud with vent slots,
  a boxy power-cell magazine with a small charge window, a folding wire stock, a rail with a
  scavenged optic, wrapped grip tape, an oxide orange panel with a stencilled number.
- **Scattergun**: heavy and short. Thick double barrel or one fat bore with a flared muzzle
  brake, a pump grip (keep the `Pump` pivot so the game can slide it), a side shell carrier
  with 4-5 shells, a chunky stock pad, a hazard-striped panel.
- **Arc lance**: the alien-tech-adjacent weapon. Ivory shell with gunmetal frame, three
  exposed coil rings that glow teal-blue (emissive) along an open emitter spine, twin prongs at
  the tip, a glowing cell at the back, cable runs between cell and coils.

Shared style: gunmetal, worn ivory, oxide orange accents, edge wear and AO baked into vertex
colour (same approach as `blender/creature_kit.py`), bevels on every hard edge. 3-4 materials
per gun, 2,500-5,000 triangles each.

## Must keep
- GLB names `rifle.glb`, `scattergun.glb`, `arc_lance.glb`, root names `Rifle`, `Scattergun`,
  `ArcLance`, a `Muzzle` empty at the bore tip, the scattergun's `Pump` empty.
- Where the hands go: Juno's IK puts her right hand at `GRIP_R = (0, -0.12, 0.17)` and left at
  `GRIP_L = (0, -0.06, -0.12)` in the weapon's frame (`blender/build_juno.py`). The pistol grip
  and foregrip must sit at those points (within 2 cm) on all three guns. Add empties `GripR` and
  `GripL` at those points in each GLB for later use.
- Overall length within 15% of today's (rifle ~0.95 m, scattergun ~0.9 m, lance ~1.0 m).
- `godot/scripts/weapon.gd` lines the model's `Muzzle` up with the shared muzzle point; check
  tracers still leave the barrel.

## Files
- May edit: `blender/build_weapons.py` (new), `blender/build_models.py` (remove the three
  functions, pointer comment), the three GLBs, `godot/tests/rig_shots.gd` only if needed,
  `README.md`, `ASSETS.md` if anything new is sourced.
- Must not edit: `blender/build_juno.py` and Juno's GLB (J1/J3), creature files, gameplay
  numbers in `weapon.gd`.

## How to build and test
- `~/tools/bpyenv/bin/python blender/build_weapons.py`, then re-import
  (`cd godot && timeout 600 godot --headless --path . --import`).
- Tests (wrap in `timeout 900`, at most two at once): `visuals_test`, `mechanics_test`,
  `feel_test`, `animation_test` (`godot --headless --path godot res://tests/<name>.tscn`).
- Renders: `xvfb-run -a godot --path godot --rendering-driver opengl3 res://tests/rig_shots.tscn --
  /mnt/project-files/hard-landing-juno/j2 <rifle|scattergun|arc_lance>` for each gun. Look at
  them and fix anything that reads as a plain box.
- Report triangles and materials per gun, grip/muzzle positions measured from the GLB, test
  pass/fail lines, and anything unverified.
