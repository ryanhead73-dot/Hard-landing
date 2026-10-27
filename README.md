# Hard Landing: Kestrel blockout

A walkable greybox of Kestrel at the basalt-wetlands crash site, built to the deck plan (Rev A).
It's for checking scale, routes through the ship, camera clearance and how damaged and repaired parts read. It isn't final art.

## Open it

- **Godot 4.7.2:** Import `godot/project.godot`, then press F5. The ship and terrain also show in the editor.
- **Blender 4.2+:** Open `blender/kestrel_blockout.blend`, or rebuild it with
  `blender --background --python blender/kestrel_blockout.py`.
  This also re-exports `godot/assets/kestrel_blockout.glb`.

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look (click to capture the mouse, Esc to release) |
| Shift / Space / C | Sprint / jump / crouch (crawlways need crouch) |
| E | Interact (install aux power in the aux bay, beside the side door) |
| F | Flashlight |
| N | Toggle day / dusk |
| 1-7 | Dev toggle for each repair: aux power, cooling, canopy, landing gear, wing, engine, navigation |
| R | Respawn outside the side door |

The top-right readout shows the camera boom length. It says SQUEEZED whenever a wall pushes the camera in, which shows you where spaces are too tight.

## What each repair changes

| # | Repair | Damaged | Repaired |
| --- | --- | --- | --- |
| 1 | Aux power | Dead generator, red emergency lights | Amber lights, live screens, glowing core |
| 2 | Cooling | Broken pipe run, open floor hatch | Continuous salvaged pipes with brackets, hatch closed |
| 3 | Canopy | Cracked, taped glass, one pane missing | Clear glass, new mullions |
| 4 | Landing gear | Crushed struts, ship rolled 4° and nose down 3° | Struts down, ship rises and levels over 3 seconds |
| 5 | Wing | Port tip torn off and lying on the ground | Salvaged tip panel with a reinforced joint |
| 6 | Engine | Port nacelle crushed, debris trail | Replacement nacelle in a mismatched bare-metal finish |
| 7 | Navigation | Mast lying flat on the spine | Mast, dish and nav lights |

Replacement parts use a mismatched grey-green salvage finish on purpose, so the repairs stay readable as patches.

## How it's built

- `godot/data/kestrel_layout.json` holds the single source of truth: room sizes, openings, stairs, fixtures and repair mount points, all in deck-plan metres. Godot and Blender both read it, so changing a room there changes both.
- `godot/scripts/kestrel.gd` generates the hull and walls as one CSG solid, plus fixtures, lights and the seven repairables.
- `godot/scripts/repairable.gd` is the damaged/repaired pattern. Each repair is a node at its mount point with a damaged child and a repaired child, and only one of them is visible and collidable. It also accepts the `<id>_damaged` / `<id>_repaired` names that Blender exports, so real modelled parts can drop in later.
- `godot/scripts/crash_site.gd` builds the basin: ridges, basalt columns, steaming pools, glowing moss, a plough berm and the crash furrow with debris. It uses a fixed seed, so the site looks the same every time.
- `blender/kestrel_blockout.py` builds the same layout in Blender: a single boolean shell (`Shell-col`), floors, fixtures, the exterior, and one mount empty per repair with placeholder volumes for both states. Model the real parts inside those empties.
- `godot/tests/smoke_test.tscn` walks the route headless and checks it, including the side door, workshop, stairs, cockpit, crawlway, installing aux power and levelling the ship. Run it with `godot --headless --path godot res://tests/smoke_test.tscn`.

## Known gaps

- Combat, enemies and the component pickup aren't in yet. Aux power installs from the aux bay without needing a recovered part.
- The interior ambient darkening uses a reflection probe, which works in Forward+ only. The Compatibility renderer will look brighter inside.
