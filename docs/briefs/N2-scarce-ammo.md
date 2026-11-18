# N2 — Scarce ammo (Sol, medium effort)

Plan: "Hard Landing: next phase plan", Pillar 1. Phase A. Runs after N1 is merged.

## Goal
Every rifle shot is a choice. The rifle loses its unlimited reserve; rounds come from salvage,
creatures and the fabricator.

## What "done" looks like
- `weapon.gd` SPECS: rifle `reserve_max` 96 (was -1). Mag stays 24. Other weapons unchanged.
- New game: rifle starts with a full mag and 0 reserve when the opening builds it; the survey pod's
  "spare mag" find gives 12 reserve. A save without an opening (skipped/older) keeps whatever it has.
- `AMMO_BUNDLE` in `main.gd` gains `"rifle": 12`. Crates (`_search_crate`) give rifle rounds with
  55% chance (other limited weapons keep their current chance). Drift caches give 24.
- Creatures drop rifle rounds through `scrap_pickup.gd`'s ammo kind: scuttler/spitter 25% chance
  of 4-6, ram and elites always 10-12. Put chances in one table.
- Fabricator: a repeatable build "Rifle rounds" (12 rounds for 8 scrap), always available, listed
  next to stims and charges in `fabricator_menu.gd`.
- `main._resupply`: no longer refills ammo. It patches the suit (health) and tops each weapon's
  reserve up to a floor (rifle 24, scattergun 6, arc lance 2) only if it is below that. Update its
  message text to say so.
- `player.revive(refill := true)`: same floor rule instead of a full refill.
- HUD: reserve shown as a number for the rifle (no ∞). Reserve text goes orange at 12 or less.
- The benchmark scene (`benchmark.gd`) keeps calling `weapon.refill()`; `refill()` itself still
  fills to max (used by tests and the armoury's first scattergun grant).

## Files
- May edit: `weapon.gd`, `main.gd` (resupply, crate rewards, AMMO_BUNDLE), `player.gd` (revive),
  `scrap_pickup.gd`, `enemy.gd` (drop table only), `fabricator_menu.gd`, `game.gd` (ammo helpers,
  build costs), `hud.gd` (reserve text), `opening.gd` (rifle build and spare mag only), tests.
- Must not edit: save format (no version bump needed: ammo is already saved), `campaign.gd`,
  `mission_runner.gd`, creature behaviour.

## Tests
Add checks to `mechanics_test` (or a new `ammo_test`): rifle reserve is finite and capped at 96;
reload stops at 0 reserve; resupply/revive floor rule; fabricator rounds build costs 8 scrap and
adds 12; crate and creature drops can give rifle rounds (seed `randf` or call the table directly).
Update any existing check that assumed an unlimited rifle; never delete one, explain each change.
Run `mechanics_test`, `rewards_test`, `opening_test`, `slice_test`, `encounters_test`,
`missions_test`, `smoke_test` (timeout 400 each, at most two at once). Report results.
