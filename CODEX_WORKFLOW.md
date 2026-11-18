# Hard Landing – Claude + Codex workflow

## Agent context
- **Claude (overseer and QA):** writes task briefs, reviews diffs, runs and checks tests, approves or rejects work. Does not do bulk edits.
- **GPT / Codex (workhorse):** does the implementation. Can generate images and control Blender.
  - **Sol 6.2:** main worker agent. Default for GDScript features, tests, refactors and batch fixes.
  - **Astra 5.2:** covers harder tasks, such as Blender work (scripts, rigs, animation) and tricky systems.
- **Chrome connections:** both Claude and GPT have Chrome access. Claude in Chrome can review ChatGPT's browser output (e.g. images). GPT's Chrome connection can handle web-only tasks.
- The project already has its own context (see `AGENTS.md` / `CLAUDE.md`). This file covers how to use Codex properly and efficiently.

## The loop
1. **Brief.** Claude writes a task: goal, files it may touch, files it must not touch, how to test, and "done" criteria. Vague briefs are the main cause of wasted runs.
2. **Branch.** Commit first. One branch per task, so any run can be reverted cleanly.
3. **Delegate.** Claude sends the brief to Codex, choosing Sol or Astra by difficulty. Use `/codex:help` for the exact commands. Use a background run if supported and keep working meanwhile.
4. **Verify.** Claude reads the diff, runs the `*_test.tscn` tests, and runs `/codex:review`. Use `/codex:adversarial-review` for save/load, mission state and enemy AI.
5. **Reject or merge.** On failure, send a specific fix list, not "try again". On success, merge.
6. **Human playtest.** Movement, combat feel and balance need a person.

## Efficiency rules
- Default to Sol. Escalate to Astra only for Blender and genuinely hard problems, to conserve the Pro allowance.
- One self-contained task per run. Don't batch unrelated changes.
- Never let two agents edit the same files at once.
- The model must run the tests itself and report results. No "should work".
- Reuse context via `AGENTS.md` / `CLAUDE.md`. Keep both updated when conventions change, and fill in the test command TODO.
- Ask for a short summary of what changed and what is untested.
- After two failed attempts in a row, stop and rewrite the brief instead of retrying.

## Blender
- Astra edits the scripts in `blender/*.py` and runs them headless (`blender -b -P script.py`), then exports GLB. Don't hand-edit `.blend` files.
- Claude checks the output: import the GLB, check clip names and counts, take a render if possible.

## Images
- Unconfirmed whether Codex can generate images on this plan. If not, generate in ChatGPT, drop into the repo, and add a row to `ASSETS.md`.
- Claude in Chrome can review the results before they are committed.

## Guardrails
- Agents must not delete tests or assets to get a check passing.
- Review anything touching the save format by hand.
- Verify the Astra/Sol model names and strengths in Codex's model picker; swap roles if real behaviour differs.
