# Hard Landing

Third-person sci-fi shooter in Godot 4.7.2. You crash-land on a hostile planet aboard Kestrel, a salvage ship, and restore her one recovered component at a time.

The whole repair campaign is playable: seven expeditions, each recovering one component for a visible repair with a benefit, ending with lift-off. The build plan for the rest of the game is in [AUTONOMOUS_PLAN.md](AUTONOMOUS_PLAN.md).

![Relay station approach and aiming at a scuttler](docs/station_approach.png)

## The campaign

Each repair is one expedition. Follow the site's beacon (only the site you need flashes bright, and only it pings), then work through the site's mission before the component comes free: throw breakers, close valves, lock winches, restart floodlights, triangulate transponders, find a keycard, hold a machine while waves come in, or kill a named elite. Some objectives need E held for a few seconds and break if you're hit; at the Loom they only work between pulses. Banners mark each stage and the HUD shows the next objective. Then carry the component home on your back (no sprinting) and install it. Taking a component stirs up an ambush. Components found out of order say what Kestrel needs first.

| # | Repair | Mission |
| --- | --- | --- |
| 1 | Aux power | Throw three breakers round the relay, then hold the station while the cradle releases the cell |
| 2 | Cooling | Close three valves to quiet the vents, cut two clamps, kill the spitter matriarch |
| 3 | Canopy | Climb to the skiff, lock both winch anchors before the glazing comes free |
| 4 | Landing gear | Restart three floodlights in the dark bay, then defend the crawler's crane as it lowers the struts |
| 5 | Wing | Find three rescue transponders in the spore fog, kill the bull ram, cut the panel free |
| 6 | Engine | Find the chief engineer's keycard, kill the yard guardian, hold the engine room while the coil unlocks |
| 7 | Navigation | Tune three resonators between the Loom's pulses |


| # | Repair | Site | Beacon | Twist | Benefit |
| --- | --- | --- | --- | --- | --- |
| 1 | Aux power | Relay station | Red | Ambush on the way home | Lights, screens, fabricator online |
| 2 | Cooling | Hauler wreck in the hot springs | Blue-white strobe | Steam vents burst on a cycle | Heavy fabricator builds |
| 3 | Canopy | Survey skiff *Lark* on the basalt spires | Yellow | Climb three platforms of columns | Scanner marks crates and wildlife on the HUD |
| 4 | Landing gear | Mining crawler in the quarry | Violet | Dark maintenance bay, rockfalls | Ship levels, cargo ramp opens, armoury locker resupplies |
| 5 | Wing | Dropship *Ferro-9* in the moss field | Green | Spore fog, spore pods burst when approached or shot | Point-defence turret on the wing root |
| 6 | Engine | Freighter *Long Patience* graveyard | White | Maze of hull plates, live arc conduits | Top fabricator tier (rapid cycler, reinforced plating) |
| 7 | Navigation | The Loom spire | Teal | The spire sends out rings of force: jump them | Pilot's seat starts the engine spool: hold the hull for 90 s, then launch |

Scuttlers at each site stay asleep until you get near. If you go down, you're hauled back to Kestrel with full health and keep what you carry.

## Play it

Every push to `main` and every pull request builds the game. Open the latest run of the **Smoke test** workflow under the repository's Actions tab and download **HardLanding-windows** (run `HardLanding.exe`) or **HardLanding-linux** (run `HardLanding.x86_64`). Each is a single file with the game packed inside. Saves and settings go to Godot's user folder (`%APPDATA%\Godot\app_userdata\Hard Landing` on Windows, `~/.local/share/godot/app_userdata/Hard Landing` on Linux).

To build it yourself, install the Godot 4.7.2 export templates (Editor > Manage Export Templates), then use Project > Export, or run:

```
godot --headless --path godot --export-release "Linux" ../build/linux/HardLanding.x86_64
godot --headless --path godot --export-release "Windows" ../build/windows/HardLanding.exe
```

A new game opens with Kestrel's crash (E, Space or Esc skips it).

## Open it

- **Godot 4.7.2:** Import `godot/project.godot`, then press F5. The ship and terrain also show in the editor.
- **Blender 4.2+:** Open `blender/kestrel_blockout.blend`, or rebuild it with
  `blender --background --python blender/kestrel_blockout.py`.
  This also re-exports `godot/assets/kestrel_blockout.glb`.

## Controls

| Key | Action |
| --- | --- |
| WASD / mouse | Move / look (click to capture the mouse) |
| Esc | Pause menu: mouse sensitivity, invert Y, volume, music volume, difficulty, screen shake, graphics (Performance / Quality); save and quit to title |
| Right mouse / left mouse / R | Aim / fire / reload |
| 1 / 2 / 3, mouse wheel | Rifle / scattergun / arc lance (the ones you own) |
| Q | Use a stim (heals 55; carry 3, or 5 with the stim pouch) |
| G | Throw an arc charge: bounces, then discharges after 1.6 s or on hitting a creature. 5.5 m blast that ignores armour plates and shoves survivors; it stings you up close. Carry 3. |
| M | Survey map: the basin in relief, Kestrel, every site (mended, next, to come), drift caches you've spotted, lurker pools you've found, your heading and where you're bound |
| Tab or I | Inventory: weapons, ammo, stims, arc charges, upgrades, components |
| L | Logs: read the newest data slate, or the list of all of them |
| Shift / Space / C | Sprint / jump / crouch (crawlways need crouch) |
| V or Alt | Dodge roll: you can't be hurt in the first third of it |
| E | Interact: take components, search crates, install, fabricate, rest in the bunk (saves) |
| F | Flashlight |
| F1 | Dev panel |

The basin drifts from day into a long amber dusk and back over a 20 minute cycle, and the moss glows brighter as the light goes. With the dev panel open: 1-7 toggle each repair (the campaign follows), N jumps between day and dusk (and stops the cycle), K gives 50 scrap, T jumps to the current site's component and H jumps home. The panel also shows the camera boom length and says SQUEEZED when a wall pushes the camera in.

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

## Story

Juno Vale's salvage ship *Kestrel* is down on HD-4471 b, "the Kettle", pulled out of the sky like every ship before her. HOB, Kestrel's ship mind, comes back with aux power and talks Juno through each repair. Across the seven sites, 22 logs (in salvage crates and with each component) tell the story of the people the Kettle caught: relay technician Ilse Marrow, Captain Gant of the *Brightwater*, survey pilot Pell Adair, the quarry crew, the *Ferro-9* rescue team, and the sixty-year-old wreck of the *Long Patience*. Ilse worked out that the Loom under the basin pulses on a beat, and she built the nav core that lets a ship fly in the gap.

**The finale.** With the nav core in, the pilot's seat starts a 90-second engine spool, and every animal in the basin comes for the hull. A breach dumps the spool and you can try again. Once the spool is full, get back to the seat and launch: the Loom's pulse rolls underneath and misses, and the ending card follows.

## Combat, gear and saving

- **Weapons.** The rifle has unlimited reserve. The scattergun is in the armoury locker once the landing gear is fixed: 8 pellets that fall off past 8 m, 6 shells and 36 in reserve. The arc lance is fabricated after the engine repair: 4 charges that pierce up to four targets. Crates and kills drop ammo for what you carry.
- **Fabricator.** Upgrades unlock with repairs: extended mag, stim pouch, plating I and II, heavy rounds, regen servo, rapid cycler, scattergun choke, arc capacitor, the arc lance itself, stims at 15 scrap each and arc charges at 20. Creatures sometimes drop stims and charges.
- **Wildlife.** Scuttlers hunt as a pack: only a couple close in to bite at once (one on Story, three on Hard) while the rest circle out of reach, facing you, waiting their turn; spitters keep 8 to 16 m away and lob acid that leaves a burning puddle; rams paw, then charge, and their head plate soaks 75% of damage from the front, so flank them or bait them into rock to stun them (double damage). The Warden guards the nav core: armoured until it opens up after an attack, and it calls the pack at two-thirds and one-third health. Mire lurkers lie in the bigger pools with only their eye stalks showing: almost immune under the water, they burst out at anything that comes close, gape (a shot into the open mouth does 1.5x) and bite hard, then dive home to heal when hurt or outrun. The cockpit scanner shows where they wait. Skimmers join the packs once three repairs are in: gliders that wheel overhead, hang in the air with their belly sac flaring, then dive to rake you with their talons and climb away to go round again. A solid hit or a crit while one hangs or dives knocks it out of the air, and on the ground it takes 1.5x.
- **Weak spots.** Every creature's glow marks where it is soft: the scuttler's spine ridge, the spitter's acid sac, the skimmer's belly sac, the ram's hump vents and the lurker's eye stalks (once it has surfaced). Shots that land there do 1.75x and ignore armour, with an amber hit marker and a sharper tick. Blasts never crit.
- **Drift caches.** Eight caches of cargo flung from ships the Loom pulled down lie out between the paths, half-buried, each with an amber locator beam you can see from far off. Prise one open for scrap, ammo, charges and stims; four hold logs. Three sit on scuttler nests that boil up around you when the lid comes off. The scanner shows the ones still shut, and the save remembers which are open.
- **Weather.** Every few minutes a squall rolls over the rim: low cloud, rain, wet glossy rock, rippling pools, lightning and thunder. In the murk wildlife sees 40% less far, so a storm is a chance to slip past a pack. Inside Kestrel the rain is a muffled drum.
- **The open basin.** Roaming packs cross your path between the ship and the sites, more often and tougher as Kestrel comes back to life: scuttlers at first, spitters after two repairs, rams after four. Never near the ship, during a siege or at the launch.
- **Sieges.** After the canopy, landing gear and wing repairs, wildlife comes for Kestrel the next time you are home: waves aimed at the hull, with a hull bar. Hold it for scrap and a stim. If the hull breaks you lose a quarter of your scrap and they come back later. You can't launch while they're on the hull.
- **Difficulty.** Story, Normal or Hard, on the title screen or in the pause menu: changes damage taken and wildlife health, and Hard adds more wildlife.
- **Saving.** Resting in the bunk saves, and so do installing a repair and quitting to the title. Continue on the title screen loads `user://save.json`.

## How it's built

- `godot/data/kestrel_layout.json` holds the single source of truth: room sizes, openings, stairs, fixtures and repair mount points, all in deck-plan metres. Godot and Blender both read it, so changing a room there changes both.
- `godot/scripts/kestrel.gd` generates the hull and walls as one CSG solid, plus fixtures, lights and the seven repairables.
- `godot/scripts/repairable.gd` is the damaged/repaired pattern. Each repair is a node at its mount point with a damaged child and a repaired child, and only one of them is visible and collidable. It also accepts the `<id>_damaged` / `<id>_repaired` names that Blender exports, so real modelled parts can drop in later.
- `godot/scripts/game.gd` (autoload `Game`) holds the session state: scrap, what you carry, upgrades, repair states, the objective and shared physics layers.
- `godot/scripts/campaign.gd` is the repair campaign as data: each repair's site, component, objective text and install prompts. The current repair is always the first one Kestrel still has damaged, so dev toggles drive the campaign too.
- `godot/scripts/expedition_site.gd` is the base for every site: component, crates, resident pack, ambush points, beacon and save state. Each site script (`relay_station.gd`, `hauler_wreck.gd`, `spire_skiff.gd`, `quarry_crawler.gd`, `moss_dropship.gd`, `freighter_graveyard.gd`, `loom_spire.gd`) fills in its layout.
- `godot/scripts/timed_hazard.gd` is the quiet / warning / active cycle shared by `rockfall.gd`, `arc_gap.gd` and `spore_pod.gd`. `loom_pulse.gd` is the expanding ring at the spire. `point_defense.gd` is the wing turret.
- `godot/scripts/player.gd` and `weapon.gd` handle third-person movement and over-the-shoulder aim. The rifle is hitscan from the camera, so shots land on the crosshair, with tracers drawn from the muzzle. It has a 24-round magazine.
- `godot/scripts/enemy.gd` is the shared wildlife base: health, damage scaling by hit direction, weak-spot crits (`weak_joint` / `weak_offset` / `weak_radius`), pack alerts, leash range, ray-feeler steering and drops. `scuttler.gd`, `spitter.gd` (with `acid_glob.gd` / `acid_puddle.gd`), `ram.gd`, `lurker.gd`, `skimmer.gd` and `warden.gd` extend it. `wildlife.gd` places the lurkers and drift caches (`basin_cache.gd`) and sends the roaming packs; `weather.gd` runs the storms; `arc_charge.gd` is the thrown charge.
- `godot/scripts/ship_siege.gd` runs the attacks on Kestrel; `hull_point.gd` marks the places wildlife can hit the hull.
- `godot/scripts/story.gd` is the story as data: opening lines, HOB's lines for each repair and siege, the finale, the ending and every log with where it's found. `voice.gd` plays lines as subtitles in a queue (alarms interrupt). `log_panel.gd` is the log reader. `finale.gd` runs the engine spool and the launch cinematic hands off from `main.gd`.
- `godot/scripts/ui_panel.gd` is the pausing panel base for `fabricator_menu.gd` and `inventory_panel.gd`. `title.gd` (`scenes/title.tscn`) is the main scene.
- `godot/scripts/sfx.gd` (autoload `Sfx`) plays one-shots and loops from `godot/audio/<id>.wav`. Every sound is synthesised by `tools/audio/` (numpy, scipy and ffmpeg): `make_sfx.py` builds the effects as layered WAVs with generated-room reverb and random variants (`<id>__1.wav`...), `make_music.py` the three adaptive score stems and the ambience beds as looping Ogg Vorbis. Drop a recorded file with the same name into `godot/audio/` to replace one. Loop points for WAV loops live in the file; Oggs always loop. Enclosed spaces (Kestrel's rooms, the wreck interiors) send to an Interior reverb bus via `AudioZones`, and Juno's footsteps change on metal decks. Flat loops belong to a scene (`Sfx.loop_flat(id, owner)`), so they stop when it does.
- `godot/scripts/music.gd` is the adaptive score: three stems (`music_calm`, `music_combat`, `music_finale`) at the same tempo and length start together and loop in lockstep, and the mood (calm, combat when wildlife is hunting nearby or during a siege, finale during the spool) only changes their volumes. `ambience.gd` crossfades the background by where you are: wind outdoors, hot springs at the hauler wreck, the Loom's hum at the spire, room tone inside Kestrel. Music and ambience have their own audio buses, and the pause menu has a music volume.
- `godot/scripts/pause_menu.gd` is the Esc menu. Settings are saved to `user://settings.cfg`.
- `godot/scripts/steam_vent.gd` is the vent hazard: quiet, then a hiss and glowing crust as warning, then a burst that damages the player and scuttlers inside it.
- `godot/scripts/hud.gd` draws the compass strip (with the waypoint marker), objective, waypoint, crosshair and hit markers, ammo, suit health, scrap, prompts and damage flash.
- `godot/scripts/crash_site.gd` builds the basin: a generated terrain mesh with a height-map collider (flat at the ship, the sites and the paths between them), steaming pools, basalt clusters, boulders and crags, moss and reeds, a plough berm and the crash furrow. It uses a fixed seed, so the site looks the same every time. `godot/shaders/` holds the terrain (wet, moss and cliff masks), rock, water and sky shaders; `world_props.gd` places and scatters the rock and ground-cover models from `blender/build_world.py`.
- `godot/scripts/mission_runner.gd` (`main.missions`) runs each site's mission (the `mission` array a site fills in `_mission()`): reach, activate, pulse, defend and elite stages, then the take. `mission_device.gd` is the breaker, valve, winch, floodlight and other objective props. Progress saves in `Game.mission_stage` / `Game.mission_done`.
- Feel lives in `player.gd`: the dodge roll, camera shake (trauma), recoil kick, hit stop on kills, sprint FOV, landing thump and footstep splashes in pools; `hud.gd` draws red arcs toward whatever hit you.
- `blender/build_props.py` builds the sites' prop kit (container, barriers, generator, pipes, hull shards). `ExpeditionSite._prop()` fits a prop over a collision box and `_build_debris()` scatters hull shards round each site.
- `blender/build_sites.py` builds the big set pieces in their site's own coordinates: the quarry crawler, the graveyard's ribs, hull plates and engine section, the coolant hauler, the relay hut and mast, and the moss forest's fungus and dropship. The site scripts spawn them at the site origin and add box colliders under them (`ExpeditionSite._collider()`).
- `godot/scripts/bevel.gd` gives every box part of Kestrel and the sites chamfered edges that catch the light.
- `blender/build_kestrel.py` builds Kestrel's modelled skin over the CSG: arched roof fairings, keel, nose cone, cockpit bezel, fins and nacelles, fitted to the deck plan (`godot/assets/kestrel/`).
- `blender/build_models.py` builds every character, weapon, component and the salvage crate as rigid-part rigs (named pivots such as `Hips`, `ArmL`, `LegL1`, `Muzzle` with meshes under them) and exports them to `godot/assets/models/<name>.glb`. Run it with Blender (`blender -b -P blender/build_models.py`) or headless `bpy` 4.2 (`python blender/build_models.py [-- juno warden]` to rebuild only some). `godot/scripts/rig.gd` loads them, finds joints and gives an instance its own copy of a material (so one creature's glow can pulse alone). A missing GLB falls back to an empty node.
- Animation is procedural, posing the rigs' joints in code. `rig_pose.gd` sets joint rotations on top of each rest pose. `juno_animator.gd` (`player.anim`) blends walk and run cycles, crouch, jump, aim pitch, recoil, reload, carrying, flinches and going down, and plays one-shot actions (`install`, `interact`, `stim`, `throw`). The weapon rides on her `Chest` joint. `creature_animator.gd` (`enemy.anim`) walks six legs in a tripod gait and four in diagonal pairs, poses each creature's states from `anim_state()` (jaws, the spitter's neck and sac, the ram's head, the Warden's arms and opening carapace), plays `attack` / `slam` / `hurt` one-shots and curls the legs on death. Installing a part springs it into place with sparks (`Repairable.play_repair`), the wing turret sweeps while idle, and a new game opens with the crash intro (`main.play_intro`, skipped with E, Space or Esc).
- `godot/scripts/surfaces.gd` generates the hull panelling, basalt and grime textures at startup (greyscale albedo plus normal map, applied triplanar, so CSG needs no UVs). `vfx.gd` builds the particles: death puffs, acid splashes, the muzzle star, Kestrel's engine exhaust and the moss motes around the player.
- `blender/kestrel_blockout.py` builds the same layout in Blender: a single boolean shell (`Shell-col`), floors, fixtures, the exterior, and one mount empty per repair with placeholder volumes for both states. Model the real parts inside those empties.
- `godot/tests/` holds the headless tests. `smoke_test.tscn` plays the slice (audio, pause, ship routes, combat, the first two repair loops, fabricator, vents, death and respawn). `campaign_test.tscn` checks every site's layout and routes, every hazard, each repair loop in order with its benefit, and the launch. `mechanics_test.tscn` covers weapons, ammo, stims, arc charges, the fabricator and inventory, every enemy, sieges, difficulty, balance numbers, save/load and the title screen. `story_test.tscn` checks the story data, where logs are found and that they save, when HOB and Juno speak, and the whole finale through to the ending card. `audio_test.tscn` checks every sound and loop, the music stems, buses, adaptive music, ambience zones, the spool whine and story sounds. `animation_test.tscn` checks Juno's poses and actions, every creature's gait and state poses, the repair spring, the turret sweep and the crash intro. `missions_test.tscn` plays every mission stage, including holds, interrupts, defends, elites and a save in the middle of a mission. `encounters_test.tscn` covers the lurker's ambush, bite, dive and heal and the roaming packs. `feel_test.tscn` checks the roll, shake, recoil, sprint FOV, splashes, damage arcs and the graphics setting. `visuals_test.tscn` checks every model and its joints, that the player, weapons, wildlife, components and crates use them, hit flashes, particles, surfaces, the engine exhaust and the compass. Run one with `godot --headless --path godot res://tests/smoke_test.tscn`; GitHub Actions runs every `*_test.tscn` on each pull request. `screenshots.tscn` renders review shots (see the script header).

## Known gaps

- Enemies steer with ray feelers rather than a navmesh. They get round walls and wreckage, but a deep dead end can still trap one.
- Sounds and music are synthesised (see `tools/audio/`); a recorded file with the same name replaces any of them.
- The interior ambient darkening uses one reflection probe per room, which works in Forward+ only. The Compatibility renderer will look brighter inside.
