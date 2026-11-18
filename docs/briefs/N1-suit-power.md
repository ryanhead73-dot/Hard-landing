# N1 — Suit power, the one survival meter (Sol, high effort)

Plan: "Hard Landing: next phase plan", Pillar 1 (approved by Jake 2026-11-18). Phase A, first task.

## Goal
Juno's suit runs on a battery. Health no longer refills for free: regeneration spends power.
Kestrel cannot recharge the suit until aux power is restored, so the first expedition is a real
risk. One meter only (no oxygen, food or water).

## What "done" looks like
- `Game.suit_power: float` 0..`Game.SUIT_POWER_MAX` (100). New game starts at 60 (the crash
  drained it). Signal `Game.suit_power_changed(power, max)`.
- Constants in one place (a `SUIT` dictionary or consts in `game.gd`), so balance is one edit:
  - Base drain outdoors 0.08/s (about 21 min from full). No drain inside Kestrel's hull
    (`Kestrel.is_inside`) or during cutscenes/menus/the finale.
  - Sprinting adds 0.25/s.
  - Health regeneration costs 0.5 power per HP healed. With no power, health does not regenerate.
    `regen_servo` makes regen cost 0.3 per HP (keep its faster/sooner effect too).
  - Story difficulty halves all drain; Hard multiplies by 1.25 (use `Game.difficulty`).
- At 0 power: no regen, no sprint, the suit scanner's marks are off (`main.scanner_marks()` returns
  only what the cockpit scanner gives, if repaired), a slow dim vignette on the HUD. No health
  drain, no death from power.
- Recharge:
  - Inside Kestrel's hull once `aux_power` is repaired: +6/s to full.
  - Before aux power, standing within 12 m of Kestrel in daylight (`main.daylight` > 0.5): +0.5/s,
    but only up to 50 (the hull's solar skin). Juno says one line the first time (add to
    `story.gd`).
  - Power cells: a new pickup kind in `scrap_pickup.gd` (`"power"`, +35). Crates found by
    `main._search_crate` give one with 35% chance. Drift caches (`wildlife.gd`) always give one.
  - The opening's survey-pod "scanner battery" reward also gives +40 power.
  - The Kestrel resupply (`main._resupply`) refills power to full when aux power is on.
- HUD: a POWER bar directly under the SUIT bar, same style (`hud.set_power(power, max)`), cream
  above 25%, orange (`UiStyle.ORANGE`) at or below 25%, a short pulse when it hits 0. Text
  `POWER 42%`.
- Voice: one Juno line at 25% and one at 0% (once each per drop, re-armed after recharging above
  50%). Keep it in Juno's voice; HOB is dark before aux power.
- Save: `suit_power` saved in `Game.session_state()` and restored in `apply_session()`. Bump
  `SaveMigrations.CURRENT` to 3 with a `_to_3` step that sets `suit_power` to 100 for older saves.
  Add a fixture `godot/tests/fixtures/saves/save_v2.json` copied from a current save so
  `saves_test` covers the v2 -> v3 migration.
- Respawn after death: power is set to at least 30.

## Files
- May edit: `godot/scripts/game.gd`, `player.gd`, `hud.gd`, `main.gd` (small hookups only),
  `scrap_pickup.gd`, `wildlife.gd` (cache reward only), `opening.gd` (battery reward only),
  `story.gd` (new lines), `save_migrations.gd`, tests and fixtures.
- New: `godot/tests/survival_test.gd` + `.tscn` (extends `test_base.gd`).
- Must not edit: `campaign.gd`, `mission_runner.gd`, creature scripts, `weapon.gd`, Blender files.
  Do not delete or loosen any existing test check.

## Tests (run them yourself, report pass/fail lines)
`survival_test` must check: drain outdoors over simulated time; no drain inside the hull;
sprint drains faster; regen spends power and stops at 0; no recharge at the hull before aux power
except the 50% solar cap in daylight; full recharge inside after aux power; power pickup adds 35;
save/load round trip keeps the value; a v2 save loads at 100.

Run: `godot --headless --path godot --import` once, then each of `survival_test`, `saves_test`,
`slice_test`, `opening_test`, `mechanics_test`, `smoke_test` with
`timeout 400 godot --headless --path godot res://tests/<name>.tscn` (at most two at once).

## Report
Short summary of what changed, the constants you chose, test results, and anything untested.
