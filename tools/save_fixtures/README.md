# Save fixtures

`godot/tests/fixtures/saves/*.json` are saves written by builds Jake has played, at several points
of progress. `godot/tests/saves_test.tscn` loads every one in the current build.

To add a build: `git worktree add ../wt/<commit> <commit>`, copy `make_fixture.gd` and
`make_fixture.tscn` into its `godot/tests/`, run `godot --headless --path . --import`, then
`godot --headless --path . res://tests/make_fixture.tscn -- <out dir> <commit>` and copy the JSON
files into `godot/tests/fixtures/saves/`.
