# N3 — The opening: finding your footing (Sol, high effort)

Plan: "Hard Landing: next phase plan", Pillar 1. Phase A, last task: runs after N1 (suit power),
N2 (scarce ammo) and N7 (tougher creatures) are merged, and builds on them.

## Goal
The first hour is a scarcity and orientation problem, not a guided path. Juno navigates by the
land, decides how to stretch her power and rounds, and the first real fight feels desperate.
The story beats in `opening.gd` (APPROACH .. YARD) and their voice lines stay.

## What "done" looks like
1. **No objective markers until the scanner is back.** Until `canopy` is repaired, `main._waypoint()`
   still computes the goal, but the HUD shows no in-world diamond and no distance
   (`hud.set_waypoint`). Instead:
   - The compass strip shows the goal's bearing as a small tick only once the goal has been
     **sighted**: Juno has had the target's site beacon / landmark within 140 m with a clear ray
     from the camera (one raycast every 0.5 s), or the goal is inside Kestrel. Store sighted site
     ids in `Game.flags["sighted"]` (array) so it saves.
   - Within 20 m of a mission device or the component, the existing close-range prompt/marker
     still shows (the suit's short-range sense), so nothing is unfindable up close.
   - In the opening, the reflector beads are the guide; the relay mast gets a slow red aviation
     light visible from Kestrel's door so the first goal is always in view.
   - Settings: a new option "Objective markers: Always / After the scanner" (default After the
     scanner) in the existing gameplay settings, saved like other settings. Always restores
     today's behaviour.
   - The map panel (M) keeps working; sites appear on it once sighted.
2. **Power is the opening's problem.** With N1's numbers Juno wakes at 60 power. Put three
   alternative power fixes on the route, any one of which is enough to reach the relay with margin:
   the survey pod's scanner battery (exists; +40 from N1), a drift-cache cell visible off the trail
   near the cable bridge, and the hull solar trickle at Kestrel (N1). Juno comments once when power
   first drops below 40 ("Suit's draining. Need a cell, or daylight on the hull.").
3. **Kestrel is shelter.** First squall (weather) after the rifle is built: HOB is dark, so Juno
   says she should get under the hull. Inside the hull the squall is safe; outside during it,
   creature sight is not reduced for this first one (they hunt in it). Bunk use during the opening
   waits out the squall and saves. Use the existing `weather.gd` API; don't change its defaults for
   the rest of the game.
4. **The first fight is desperate.** The yard scuttler (now 150 HP from N7) attacks with only the
   rifle's 24-round mag and the 12 spare rounds (N2). Make sure it is winnable: the stagger window
   and weak point from N7 must be learnable here. Add one Juno line hinting at the weak point when
   the scuttler rears ("Under the jaw. Wait for it to rear."). If the player dies here, the
   checkpoint respawn returns them to the yard gate with at least 24 rounds.
5. Keep the opening's length about 20-30 minutes for a first-time player.

## Files
- May edit: `opening.gd`, `story.gd`, `hud.gd` (marker visibility, compass tick), `main.gd`
  (`_waypoint` consumer and sighting tick only), `map_panel.gd` (sighted filter), `relay_station.gd`
  (aviation light only), settings code where the existing gameplay options live, tests.
- Must not edit: `campaign.gd`, `mission_runner.gd`, creature stats, save version (use flags),
  Blender files.

## Tests
Extend `opening_test` (or add `footing_test`): before canopy no in-world marker is shown and the
compass tick appears only after sighting; with the setting on Always the marker shows; sighted
ids survive save/load; each power fix works; squall shelter beat triggers once; the yard fight
respawn gives at least 24 rounds. Update `navigation_test`/`slice_test` checks that assume the
marker is always visible (set the option to Always in those suites rather than loosening checks).
Run `opening_test`, `navigation_test`, `slice_test`, `story_test`, `saves_test`, `smoke_test`
(timeout 400 each, at most two at once). Report results and anything untested.
