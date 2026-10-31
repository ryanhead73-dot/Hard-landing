# Hard Landing: autonomous build plan

This is the brief Claude works to while taking Hard Landing from vertical slice to a finished, exportable game without Jake in the loop. Jake delegated mechanics, story, visuals and animation decisions. Claude asks only when truly blocked.

## Starting point (main, 2026-10-31)

Vertical slice in Godot 4.7.2: third-person rifle combat, scuttler wildlife, relay station (aux power cell) and hauler wreck (coolant manifold) expeditions, fabricator with three upgrades, sound placeholders, pause/settings menu, generated greybox of Kestrel from `godot/data/kestrel_layout.json`, 48 headless smoke checks in CI.

## Rules for every milestone

1. Work on a branch, open a PR against `main`.
2. Add headless tests for every new feature (`godot/tests/`), and run the **full** suite locally with Godot 4.7.2 before pushing.
3. Do a code review pass of the diff for bugs (state that can get out of order, signals not disconnected, freed nodes, save/load round trips, softlocks). Fix what it finds, re-run the tests.
4. CI must be green. Then Claude merges its own PR (Jake asked for autonomy).
5. Record decisions and progress in project memory, and post a short update in the project thread.
6. Keep the game playable from start to finish after every merge. No milestone leaves a half-wired loop on `main`.

## Milestone 1: all seven repairs

Replace the hand-written two-stage flow with a data-driven repair campaign (`godot/scripts/campaign.gd` + `godot/data/repairs.json`), so each repair is: an expedition site, a component to recover (heavy, carried on the back, no sprint), an install point on Kestrel, a visible change and a benefit.

| # | Repair | Expedition site (world position) | Component | Benefit |
| --- | --- | --- | --- | --- |
| 1 | Aux power | Relay station (-60, 58) | Aux power cell | Lights, screens, fabricator online |
| 2 | Cooling | Hauler wreck in the hot springs (48, -58) | Coolant manifold | Heavy builds at the fabricator |
| 3 | Canopy | Survey skiff *Lark* on the basalt spires (-82, -28) | Canopy glazing panel | Cockpit sealed: scanner marks salvage crates and enemies on the HUD |
| 4 | Landing gear | Mining crawler in the quarry (14, 86) | Hydraulic strut pack | Ship levels, aft cargo ramp opens onto the armoury (scattergun) |
| 5 | Wing | Rescue dropship *Ferro-9* in the moss field (86, 28) | Wing-tip panel | Wing-mounted point-defence turret helps during ship attacks |
| 6 | Engine | Freighter *Long Patience* in the graveyard (-28, -90) | Drive coil | Engine bleed powers the top fabricator tier (arc lance) |
| 7 | Navigation | The Loom spire (-96, 12) | Pulse-timing nav core | Unlocks the departure sequence |

Each site gets its own layout, hazard or twist (spires: climbing route and falls; quarry: collapsing ledges and a dark tunnel; moss field: low visibility spore fog; graveyard: maze of hull plates with a heavy enemy guard; Loom: boss arena), salvage crates, a beacon of a distinct colour and an ambush when the component is taken. Repairs must be done in order; components found early say why they can't be taken yet.

Tests: each repair's full find > carry > install loop, ordering guards, the benefit each repair turns on, every site reachable and facing the ship.

## Milestone 2: mechanics

- **Weapons (3):** salvage rifle (existing), scattergun (close range, pellets, from the armoury after landing gear), arc lance (charged piercing beam, fabricated after engine). Switch with 1/2/3 and mouse wheel. Rifle has unlimited reserve; the others use limited reserve ammo, refilled from ammo drops and the ammo locker.
- **Inventory (Tab):** weapons and ammo, stims (heal, Q), scrap, upgrades built, logs found, current component.
- **Fabricator menu:** a proper list instead of a fixed order. Light upgrades: extended mag, suit plating I/II, heavy rounds, stim pouch, scattergun choke, arc capacitor, faster regen. Some gated by cooling/engine.
- **Enemies:** scuttler (melee, existing), spitter (keeps range, lobs telegraphed acid globs), ram (armoured front, charges in a straight line, weak behind), Warden (boss at the Loom). Spawn mixes per site get harder through the campaign.
- **Ship-attack events:** after canopy, landing gear and wing are fixed, returning home triggers a wave assault on Kestrel. The ship has hull integrity shown on the HUD; enemies go for the hull. Losing the hull ends the event, costs scrap and lets the player retry. Wing turret helps once repaired.
- **Save/load:** JSON in `user://save.json`. Autosave after every install and when resting at the bunk. Title screen offers Continue / New game.
- **Difficulty:** Story / Normal / Hard (damage taken and enemy count multipliers) in settings. Tune numbers with headless combat sims.

## Milestone 3: story

Decided by Claude (Jake delegated):

- **The planet** is catalogued HD-4471 b. Salvagers call it **the Kettle** for its steaming basalt wetlands. It has a reputation as a wreck-magnet, and it earns it: under the wetlands lies **the Loom**, an ancient lattice that throws gravitic pulses into orbit and drags drives down. Its teal light is the same glow in the moss and in the scuttlers, which graze on the heat of fresh wrecks. That's why they swarm crash sites, and why they come for Kestrel.
- **The player** is **Juno Vale**, Kestrel's owner-operator, a solo salvager who flew in to strip the abandoned relay station.
- **HOB**, Kestrel's ship mind, comes back with aux power. Dry, protective and a bit vain about the ship. HOB delivers objectives, banter and the departure countdown.
- **Ilse Marrow**, the relay station's last technician, studied the Loom. Her logs run through every site: she worked out that the pulses have a rhythm, and she left a nav core tuned to it at the spire before she vanished.
- **Captain Teodor Gant** of the coolant hauler *Brightwater*, **Pell Adair** who flew the survey skiff *Lark*, the quarry crew of the mining crawler, the rescue team of dropship *Ferro-9* (sent for Ilse and pulled down too), and the freighter *Long Patience*: each site holds 2-3 audio-style text logs that tell their part.
- **Missions:** each repair is one mission with an intro from HOB, logs at the site and an outro at install.
- **Finale:** with the nav core installed, HOB plots the gap between pulses. Juno starts the engine spool (90 s) while the swarm makes its last assault on Kestrel. Survive it, climb to the cockpit, and launch. A cockpit cinematic takes Kestrel up through the steam as the Loom pulses and misses. The ending card has Juno drop a warning buoy so nobody else falls, and leaves a hint that Ilse's last log was sent from orbit.

## Milestone 4: visuals

- Blender models built by script (`blender/*.py`, run with `bpy` 4.2 headless), exported as GLB into `godot/assets/`:
  - Kestrel exterior hull with real curvature, wings, nacelles, ramp; interior dressing (workshop bench, racks, pipes, lockers, cockpit console).
  - Each repair's damaged and repaired parts as modular `<id>_damaged` / `<id>_repaired` pieces in a mismatched salvage finish.
  - Player suit, rifle, scattergun, arc lance; scuttler, spitter, ram, Warden; components (cell, manifold, glazing, struts, wing panel, drive coil, nav core); crates, rocks, basalt columns, site wrecks.
- Materials: worn cream/off-white hull with oxide-orange bands, warm amber interior, dark metal; basalt #1b1d1f, wet slate #3c4448, glow moss #3fd1b5, steam #b7bfbd; no rust tones in the terrain.
- Lighting and VFX: day/dusk cycle, volumetric fog over pools, muzzle flash and impact VFX, acid splashes, spore fog, Loom pulse shockwave, engine glow.
- UI: restyled HUD (cream on dark, amber accents), compass, hull bar, inventory and fabricator panels, title screen with Kestrel at the crash site.

## Milestone 5: animation

Characters are rigid-part rigs built in Blender (separate limb meshes under a bone hierarchy), animated with Godot `AnimationPlayer` clips and a small state blend in code:

- Player: idle, walk, run, crouch, jump, aim pose, fire recoil, reload (per weapon), carry, install (kneel and fit), stim, hurt, down.
- Enemies: scuttler skitter/lunge/die, spitter rear-and-spit, ram charge/stagger, Warden phases.
- Ship: each repair animates in (panels slide, struts extend, mast rises, canopy seals), cargo ramp lowers, turret tracks.
- Cinematics: departure sequence (engine spool, lift-off, climb) and intro crash.

## Milestone 6: audio and build

- Regenerate placeholder sounds with more character, add new ones for every weapon, enemy, site and the finale; ambient loops per site; a short adaptive music layer (calm / combat / finale).
- Export presets for Linux and Windows; CI builds and uploads the export as an artifact; README with how to play.

## Where things stand

Progress: M1 merged in PR #6; M2 merged in PR #7; M3 merged in PR #8; M4 merged in PR #9; M5 merged in PR #10 (procedural animation in code rather than AnimationPlayer clips, since the rigs are rigid parts); M6 in the audio and build PR. M4 deferred: Kestrel's hull and the repair parts stay generated CSG (now panelled and textured) rather than Blender meshes, and there is no day/dusk cycle yet; revisit after M6. Progress is tracked in project memory and the project thread. Each milestone's PR links back to this plan.
