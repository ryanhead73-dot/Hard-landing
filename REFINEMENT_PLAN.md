# Hard Landing: refinement plan

Jake playtested the finished build (2026-10-31): everything works, but the core loop is dull, because each repair is a short walk to fetch one part, and the world still reads as a greybox. Jake asked Claude to take control and push the game toward a near-AAA experience, especially visuals and theming, checking in only at major milestones.

Same rules as AUTONOMOUS_PLAN.md: a branch and PR per milestone, headless tests for every feature, the full suite run locally before pushing, a review pass, green CI, then Claude merges. The game stays playable start to finish after every merge.

## M7: missions, not fetch quests

Every repair becomes a mission of three to five stages, driven by data in `Campaign` and run by a `MissionRunner`. Stage types:

- **reach**: get to a place (a vantage point, the bottom of a climb).
- **activate**: work a set of objective devices (breakers, valves, winches, floodlights, transponders, resonators). Some need E held for a few seconds, which is interrupted if you are hit or walk off.
- **defend**: stay near a machine while it works (a cradle releasing the cell, a crane lowering struts). Waves arrive from set points; progress pauses while you are away from it.
- **elite**: kill a named elite (bigger, tougher, glowing variant with its own health bar).
- **pulse**: activate devices only in the quiet gap between Loom pulses.
- **take**: take the component, which then springs the ambush and the walk home.

| Repair | Mission |
| --- | --- |
| Aux power | Reach the relay. Its backup generator is tripped: throw three breakers round the compound. The cell sits in a charging cradle that needs 40 s to release it: hold the station while scuttlers pour in. Take the cell. |
| Cooling | The hold is scalded by vents: close three valves round the springs, each one quiets part of the pool. The manifold is clamped: cut two clamps (hold E). A spitter matriarch nests on the wreck: kill her. Take the manifold. |
| Canopy | Climb to the skiff. Lark is sliding off the brink: lock both winch anchors (hold E) before the glazing can come free. Take it; spitters close in on the descent. |
| Landing gear | The quarry tunnel is pitch dark: restart three floodlights. Power the crawler's console, then defend while its crane lowers the strut pack, with rams charging up the ramp. Take the struts. |
| Wing | Spore fog: triangulate the dropship from three rescue transponders. Cut the wing-tip panel free at three points (hold E). A bull ram guards the wreck: kill it. Take the panel. |
| Engine | The Long Patience's engine room is sealed: find the chief engineer's keycard in the hull maze. Kill the yard's guardian (an elite ram). Unlock the coil and defend while it cools. Take it. |
| Navigation | Tune three resonators round the spire, each only between pulses. Take the core. The Warden rises. |

Tests: a new `missions_test` plays every mission stage by stage, plus save/load in the middle of a mission. Older suites skip missions (`MissionRunner.bypass`).

## M8: the world looks like the Kettle

- Terrain: a real displaced mesh for the basin (ridges, gullies, raised basalt shelves) with a terrain shader: triplanar basalt, wet slate in the low ground, teal moss in creases, puddles that reflect the sky.
- Basalt columns as clustered hexagonal prisms with bevels and broken tops; boulders with displaced, faceted surfaces; ridges as cliff meshes, not boxes. All built in Blender by script.
- Water: a shader for the pools (depth tint, fresnel, ripples, soft steam).
- Ground cover: moss tufts and reeds scattered with MultiMesh.
- Sky: a sky shader with layered clouds, haze and sun glow that follows the day/dusk cycle.

## M9: Kestrel, Juno and the sites, modelled

- Kestrel's exterior hull as a Blender mesh with real curvature (fuselage, cockpit glazing, wings, nacelles, cargo ramp), cream with oxide-orange bands and wear. The CSG stays as invisible collision.
- Repair parts as modelled damaged/repaired pieces.
- Juno remodelled: rounded suit, helmet with a glowing visor, backpack.
- The site wrecks and the relay station dressed with modelled parts.

## M10: lighting, post and game feel

- Lighting: SDFGI/SSIL tuned for the basin, volumetric fog in hollows, glow and colour grading per time of day, light shafts at dusk.
- Feel: camera shake and recoil kick, hit stop on kills, enemy hit flashes and knockback, a dodge roll, sprint FOV, footstep splashes in pools, objective markers on the HUD, mission stage banners.

## Where things stand

- M7 (missions): MissionRunner + MissionDevice, all seven missions, elites, missions_test. Merged in PR #13.
- M8 (world), merged in PR #14: terrain mesh + height-map collider with hills, rim and pool hollows (flat at the ship, sites and the paths between); terrain, rock, water and sky shaders; Blender basalt clusters, boulders, crags, moss and reeds (`blender/build_world.py`).
- M9 + M10 merged in PR #15. M9 (models): Kestrel's modelled skin (`blender/build_kestrel.py`: roof fairings, keel, nose, cockpit bezel, fins, nacelles), Juno and the wildlife rebuilt from smooth volumes, chamfered edges on every box part of the ship and sites (`bevel.gd`).
- M10 (lighting and feel): soft four-split sun shadows, SSIL, a basin haze with sun shafts, per-room interior probes, a Performance/Quality setting; dodge roll, camera shake and recoil kick, hit stop, sprint FOV, pool splashes, damage-direction arcs, landing thump, screen-shake setting. `feel_test`.
- Site dressing: `blender/build_props.py` prop kit (shipping container, jersey barriers, generator, pipe run, torn hull shards). `ExpeditionSite._prop()` fits a prop to a collision box; `_build_debris()` scatters shards round every site clear of objectives; stone columns are flat-shaded hexagonal prisms (`Bevel.flat`).
- Kestrel detail (PR #16): modelled landing gear (intact and snapped), airfoil-tapered wing panels, navigation mast and dish (standing and torn down).
- Interior and wrecks: live console readouts (`shaders/screen.gdshader`), cooling pipe flanges; `blender/build_sites.py` models the quarry's mining crawler, the freighter graveyard's hull ribs (two broken), fallen hull plates and engine section, the coolant hauler and its torn-off nose, the relay hut with its lattice mast, and the moss forest's giant fungus and crashed Ferro-9 dropship, all in their site's coordinates over box colliders (`ExpeditionSite._collider()`). Quarry faces are packed columnar basalt (`_basalt_block()`). visuals_test checks the colliders line up with the modelled walls.
