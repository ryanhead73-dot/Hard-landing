# Hard Landing

Third-person sci-fi shooter in Godot 4.7.2. You crash-land on a hostile planet aboard Kestrel, a salvage ship, and restore her one recovered component at a time.

This repo holds the **vertical slice**: one weapon, one enemy, one location, one component and one visible repair, all running in a greybox of Kestrel at the basalt-wetlands crash site.

![Relay station approach and aiming at a scuttler](docs/station_approach.png)

## The slice loop

1. **Start at Kestrel.** She's dead without power. Red emergency lights are on and the fabricator is offline.
2. **Head out.** Follow the blinking red beacon (about 60 m) to the abandoned relay station. A waypoint marker shows the distance.
3. **Fight.** Basalt scuttlers hide as rocks around the site. They rush you when they see you or hear a pack-mate get shot, and they crouch and glow before every bite. They drop scrap, and orange salvage crates hold more.
4. **Recover the aux power cell** from the building. It rides on your back and slows you down, so you can't sprint. Taking it draws an ambush on the way home.
5. **Install it in the aux bay**, just inside Kestrel's side door. The interior switches from red emergency light to warm amber, the screens wake up, and the fabricator comes online.
6. **Spend scrap at the fabricator** on three upgrades: extended magazine (30), suit plating (40) and heavy rounds (45).

If you go down, you're hauled back to Kestrel with full health and keep what you carry.

## Open it

- **Godot 4.7.2:** Import `godot/project.godot`, then press F5. The ship and terrain also show in the editor.
- **Blender 4.2+:** Open `blender/kestrel_blockout.blend`, or rebuild it with
  `blender --background --python blender/kestrel_blockout.py`.
  This also re-exports `godot/assets/kestrel_blockout.glb`.

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look (click to capture the mouse, Esc to release) |
| Right mouse / left mouse / R | Aim / fire / reload |
| Shift / Space / C | Sprint / jump / crouch (crawlways need crouch) |
| E | Interact: take the cell, search crates, install, fabricate |
| F | Flashlight |
| F1 | Dev panel |

With the dev panel open: 1-7 toggle each repair, N toggles day and dusk, K gives 50 scrap, T jumps to the station and H jumps home. The panel also shows the camera boom length and says SQUEEZED when a wall pushes the camera in.

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
- `godot/scripts/game.gd` (autoload `Game`) holds the session state: scrap, what you carry, upgrades, the objective and shared physics layers.
- `godot/scripts/player.gd` and `weapon.gd` handle third-person movement and over-the-shoulder aim. The rifle is hitscan from the camera, so shots land on the crosshair, with tracers drawn from the muzzle. It has a 24-round magazine.
- `godot/scripts/scuttler.gd` is the enemy: idle, chase, wind-up, lunge and recover states. Alerts spread through the pack, and it has a leash range.
- `godot/scripts/relay_station.gd` builds the expedition site: the building, cover, cell cradle, salvage crates, mast beacon and spawn points.
- `godot/scripts/hud.gd` draws the objective, waypoint, crosshair and hit markers, ammo, suit health, scrap, prompts and damage flash.
- `godot/scripts/crash_site.gd` builds the basin: ridges, basalt columns, steaming pools, glowing moss, a plough berm and the crash furrow with debris. It uses a fixed seed, so the site looks the same every time.
- `blender/kestrel_blockout.py` builds the same layout in Blender: a single boolean shell (`Shell-col`), floors, fixtures, the exterior, and one mount empty per repair with placeholder volumes for both states. Model the real parts inside those empties.
- `godot/tests/smoke_test.tscn` plays the slice headless with 23 checks: ship routes, killing a scuttler, scrap pickup, taking a bite, the cell loop, crate search, fabricator, death and respawn, and the repair states. Run it with `godot --headless --path godot res://tests/smoke_test.tscn`. GitHub Actions runs it on every pull request.

## Known gaps

- Enemies steer directly with simple wall sidestepping and have no navmesh. That's fine in the open basin, but they can get stuck inside buildings.
- There's no audio yet, and the reserve ammo is unlimited.
- The interior ambient darkening uses a reflection probe, which works in Forward+ only. The Compatibility renderer will look brighter inside.
