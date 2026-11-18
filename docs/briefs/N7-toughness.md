# N7 — Fewer, tougher, readable creatures: numbers pass (Sol, medium effort)

Plan: "Hard Landing: next phase plan", Pillar 2. Phase A. Behaviour changes (territory, director,
stalker) come later in N5/N6/N9; this task is numbers, wind-ups and weak points only.

## Goal
Each creature is about 2.5x as tough and hits harder, but shows clearly when it will attack and
where to shoot.

## What "done" looks like
- One table, `godot/scripts/creature_stats.gd` (`class_name CreatureStats`, a const dictionary by
  creature id), holding health, damage values and the weak-point multiplier. Each creature's
  `_ready` reads from it instead of hard-coded numbers. First pass:

  | creature | health (was) | damage (was) |
  | --- | --- | --- |
  | scuttler | 150 (60) | bite 30 (14) |
  | spitter | 110 (45) | glob 24 (14) |
  | ram | 420 (170) | charge 45 (30) |
  | lurker | 360 (150) | bite 34 (24) |
  | skimmer | 100 (40) | dive 22 (12), knockdown 24 (16) |
  | pinweaver | 170 (70) | snap 12 (8) |
  | veilwing | 75 (30) | swoop 22 (14) |
  | ridge diver | 150 (60) | erupt 30 (22) |
  | chord singer | 340 (140) | unchanged |
  | fuse thief, drifter, cantor, patience guardian, Warden | unchanged | unchanged |

  Elites: `ELITE_MIN_HEALTH` 280 -> 600; `ELITE_HEALTH` multiplier stays.
- Weak points: hits inside `weak_radius` deal 2.5x (today `CRIT_MULT` 1.75). Scuttler and spitter
  get a weak point if they have none (scuttler: the head/mandible joint; spitter: the throat sac).
- Wind-ups: every melee/charge attack has a visible and audible tell of at least 0.45 s (scuttler
  rears up and hisses, ram paws and lowers its head, spitter's sac swells). Reuse existing
  animation clips/poses and `Sfx`; no new Blender work. The attack can't land during the tell.
- Stagger window: after a ram charge misses or a scuttler's bite, 0.8 s where it takes +50% damage
  (show it with the existing hit flash colour tinted amber).
- `ROAM_MAX_ALIVE` in `wildlife.gd` 7 -> 3 and `ROAM_INTERVAL` (50, 90) -> (110, 170) as a stopgap
  until N5's director replaces packs. Siege waves (`ship_siege.gd`) halve their counts.
- Mission defend/elite stages: keep them winnable. If a stage's spawn count makes it unwinnable
  with the new health, halve that stage's count in its own data (list each change).

## Files
- May edit: creature scripts, `enemy.gd`, new `creature_stats.gd`, `wildlife.gd` (two constants),
  `ship_siege.gd` (counts), mission spawn counts in site scripts (counts only), tests.
- Must not edit: `player.gd`, `weapon.gd`, `game.gd`, save code, Blender files, `campaign.gd`.

## Tests
Add `creature_stats` checks to `encounters_test`: every listed creature's health and damage come
from the table; weak-point hits deal 2.5x; an attack cannot land during its tell; the stagger
window multiplier. Update existing tests that hard-code old health (explain each); never delete.
Run `encounters_test`, `feel_test`, `missions_test`, `loom_test`, `patience_test`, `crown_test`,
`finale_test`, `smoke_test` (timeout 400 each, at most two at once). Report results and the
number of rifle body shots / weak-point shots to kill each creature.
