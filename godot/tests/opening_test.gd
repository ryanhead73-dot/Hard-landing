extends "res://tests/test_base.gd"
## The new-game opening (Opening, regions/approach.gd): a new game starts aboard the working
## Kestrel in orbit; the approach plays through the seat, the trace, the drift, the harness and
## the braces into the crash; Juno wakes in the wreck unarmed and punctured, seals the suit,
## crouches out of the bent door, scans three things, crosses the cable bridge to the cache,
## builds the rifle and tests it, watches the scuttler, wins the first fight, rewires the relay
## (a decoy switchbox trips without hurting her) and takes the cell at a run. Old saves never see
## it, and a player who has seen it can sleep through it. Run:
##   godot --headless --path . res://tests/opening_test.tscn

var op: Opening


func _name() -> String:
	return "OPENING TEST"


func _bypass_missions() -> bool:
	return false


func _ready() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Opening.SEEN_PATH))
	Game.intro_pending = true
	Game.flags.clear()
	super._ready()


func _run() -> void:
	op = main.opening
	await _frames(10)
	await _walk_to_seat()
	await _approach()
	await _wreck()
	await _outside()
	await _trail()
	await _yard()
	await _relay()
	await _skip()
	finished = true


func _hold(seconds: float) -> void:
	await get_tree().physics_frame
	Input.action_press("interact")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("interact")
	await _frames(3)


## From the bunk where she wakes, out of the cabin, round through the workshop, up the stairs
## to the copilot's seat, on foot (the cabin locker once blocked the door).
func _walk_to_seat() -> void:
	var a: Approach = main.regions.scene
	var route := [Vector3(10.0, 0.1, 10.9), Vector3(11.9, 0.1, 10.9), Vector3(12.3, 0.1, 13.0), Vector3(10.6, 0.1, 13.0), Vector3(8.4, 1.3, 13.0), Vector3(6.4, 1.3, 13.4)]
	var ok := await _walk_path(route.map(func(p): return a._at(p)), 4.0)
	_check("she can walk from the bunk to the copilot's seat", ok and _label().contains("copilot"), _label())


func _approach() -> void:
	_check("a new game starts in orbit, aboard", main.regions.current == "approach" and op.active() and op.beat() == Opening.Beat.APPROACH, main.regions.current)
	_check("and she isn't carrying a gun", not player.armed and not player.weapon.visible)
	_check("the objective is the copilot's seat", Game.objective_text().contains("copilot"), Game.objective_text())
	var a: Approach = main.regions.scene
	_check("the cockpit has a planet and stars outside", a._sky.get_child_count() >= 3)
	_check("no saving in orbit", not main.save_game())
	_place(a.kestrel.to_global(a._cup.position + Vector3(0.0, -0.85, 0.9)), 0.0)
	await _frames(8)
	_check("a sliding cup to catch", _label().contains("cup"), _label())
	await _press("interact")
	_check("caught", a.cup_caught)
	_place(a._at(Vector3(Approach.CONTRACT.x, 0.1, Approach.CONTRACT.z + 0.9)), 0.0)
	await _frames(5)
	await _press("interact")
	_check("the contract can be read", a.read.has("contract"), _label())
	_check("the skip isn't offered on a first playthrough", not _label().contains("Sleep"))
	_place(a._at(Vector3(Approach.SEAT.x + 0.9, 1.3, Approach.SEAT.z)), 0.0)
	await _frames(5)
	_check("the copilot's seat", _label().contains("copilot"), _label())
	await _press("interact")
	_check("seated: she can look but not walk", player.seated and a.beat == Approach.Beat.SEATED)
	var at := player.global_position
	await _walk(0.5)
	_check("pushing forward doesn't move her", _flat_distance(player.global_position, at) < 0.1)
	for i in 4:
		await _press("interact")
	_check("three points traced and the ship drifts", a.traced == 3 and a.beat == Approach.Beat.DRIFT, str(a.traced))
	await _press("interact")
	_check("the override is lost: hold the harness", a.beat == Approach.Beat.HARNESS and a._arc.visible)
	await _hold(1.4)
	_check("holding the harness starts the fall", a.beat == Approach.Beat.BRACE, str(a.beat))
	await _press("interact")
	await _frames(10)
	await _press("interact")
	for i in 120:
		if main.regions.current == "kettle":
			break
		await get_tree().physics_frame
	_check("two braces, then down to the Kettle", int(Game.flags.get("crash_braced", -1)) == 2 and main.regions.current == "kettle", str(Game.flags.get("crash_braced")))
	_check("the crash plays", main.intro_playing)
	main.end_intro()
	await _frames(5)


func _wreck() -> void:
	_check("she wakes in the wreck", op.beat() == Opening.Beat.WAKE and kestrel.is_inside(player.global_position))
	_check("down on the deck, unarmed, suit punctured", player.seated and player.crouching and not player.armed and player.regen_blocked and player.health == Opening.CRASH_HEALTH[2], "hp=%.0f" % player.health)
	_check("the crash is a checkpoint", Game.has_save())
	_check("nothing roams the basin during the opening", _enemy_count() == 0, "enemies=%d" % _enemy_count())
	await _frames(5)
	_check("first, get up", _label().contains("Get up"), _label())
	await _hold(1.2)
	_check("on her feet", not player.seated and not player.crouching)
	_check("the waypoint points at the med-seal", main._waypoint() is Vector3 and (main._waypoint() as Vector3).distance_to(op._ship(Opening.MEDSEAL)) < 0.1)
	_check("and its marker shows on the HUD, a few metres away across the cabin", main.hud._waypoint.visible and main.hud._waypoint.text.contains("m"), main.hud._waypoint.text)
	_place(op._ship(Opening.MEDSEAL) + Vector3(0.0, -1.2, -0.9), 0.0)
	await _frames(5)
	_check("the med-seal kit", _label().contains("med-seal"), _label())
	await _press("interact")
	_check("one med-seal", Game.stims == 1)
	await _press("stim")
	_check("sealed: the suit knits again", op.beat() == Opening.Beat.SEALED and not player.regen_blocked and player.health > Opening.CRASH_HEALTH[2])
	_place(op._ship(Opening.HOB_CONSOLE) + Vector3(0.8, -0.6, 0.0), 0.0)
	await _frames(5)
	_check("HOB doesn't answer", _label().contains("HOB"), _label())


func _outside() -> void:
	# Out of the side door: under the bent panel only crouched, then over the spar.
	var inside := op._ship(Vector3(12.9, 0.1, 15.6))
	var out := op._ship(Vector3(12.9, 0.1, 18.4))
	_place(inside, 0.0)
	await _frames(10)
	var ok := await _walk_path([out], 2.5)
	_check("standing, the bent panel blocks the door", not ok)
	_place(inside, 0.0)
	Input.action_press("crouch")
	await _frames(10)
	ok = await _walk_path([out], 5.0)
	Input.action_release("crouch")
	_check("crouched, she gets under it", ok, str(player.global_position))
	var past := op._ship(Vector3(12.9, 0.0, 23.5))
	past.y = main.site.height_at(past.x, past.z) + 0.3
	var foot := op._ship(Vector3(12.9, 0.0, 19.2))
	foot.y = player.global_position.y
	ok = await _walk_path([foot, past], 3.0)
	_check("the spar stops a plain walk", not ok)
	Input.action_press("jump")
	ok = await _walk_path([past], 3.0)
	Input.action_release("jump")
	_check("a jump clears it", ok)
	await _frames(10)
	_check("outside: a beat of its own", op.beat() == Opening.Beat.OUTSIDE, str(op.beat()))
	_check("the marker leads to something to scan", main._waypoint() is Vector3 and op._scans().any(func(sc): return (sc[1] as Vector3).distance_to(main._waypoint()) < 0.1))
	for s in op._scans():
		_place(s[1] + Vector3(0.0, 0.5, 1.6), 0.0)
		await _frames(5)
		await _press("interact")
	_check("three scans and the trail opens", op.beat() == Opening.Beat.TRAIL, Game.objective_text())
	_check("objective: follow the beads", Game.objective_text().contains("beads"))
	_check("no HUD arrow on the trail", main._waypoint() == null)


func _trail() -> void:
	_place(op._ground(Opening.SPOOL_AT, 0.5) + Vector3(0.0, 0.0, 1.5), 0.0)
	await _frames(5)
	await _press("interact")
	_check("the fibre spool", Game.flags.get("spool_scanned", false))
	# Up the shelf's ramp, crank the bridge, across to the island.
	var ramp_foot := op._ground(Opening.LEDGE_AT, 0.3) + Vector3(0.0, 0.0, -6.5)
	_place(ramp_foot, 0.0)
	await _frames(10)
	var top := op._ground(Opening.LEDGE_AT, 2.3) + Vector3(0.0, 0.0, 1.0)
	var ok := await _walk_path([op._ground(Opening.LEDGE_AT, 2.3) + Vector3(0.0, 0.0, -1.0), top], 6.0)
	_check("up the slabs onto the shelf", ok and player.global_position.y > top.y - 0.6, str(player.global_position))
	await _frames(5)
	_check("the bridge crank", _label().contains("bridge"), _label())
	await _hold(2.3)
	await get_tree().create_timer(1.6).timeout
	_check("the bridge is down", Game.flags.get("bridge_down", false))
	var island := op._ground(Opening.ISLAND_AT, 2.6)
	ok = await _walk_path([island + Vector3(-0.6, 0.0, -1.0)], 6.0)
	_check("across the bridge to the island", ok and player.global_position.y > island.y - 0.8, str(player.global_position))
	await _frames(5)
	_check("the cache: med-seals on this side", _label().contains("med-seals"), _label())
	var before := Game.stims
	await _press("interact")
	_check("two med-seals, and the choice is made", Game.stims == before + 2 and Game.flags.get("early_reward") == "seals")
	# The survey pod and its bench.
	var bench := op._ground(Opening.SURVEY_AT, 0.5) + Vector3(0.0, 0.0, 3.0)
	_place(bench, 0.0)
	await _frames(5)
	_check("pry the pod", _label().contains("Pry"), _label())
	await _hold(1.8)
	_check("open", Game.flags.get("pod_open", false))
	await _frames(3)
	await _press("interact")
	await _frames(3)
	await _press("interact")
	_check("two steps and the rifle works", op.beat() == Opening.Beat.ARMED and player.armed and player.weapon.visible)
	_check("the rifle is a checkpoint", Game.has_save())
	_place(bench + Vector3(0.0, 0.0, 1.0), 0.0)
	await _frames(5)
	await get_tree().create_timer(0.6).timeout
	player.aim_at(op._plate.global_position + Vector3(0.0, -0.6, 0.0))
	await _frames(3)
	Input.action_press("fire")
	for i in 40:
		player.aim_at(op._plate.global_position + Vector3(0.0, -0.6, 0.0))
		await get_tree().physics_frame
		if Game.flags.get("test_shot", false):
			break
	Input.action_release("fire")
	await _frames(5)
	_check("a test shot swings the sensor plate", Game.flags.get("test_shot", false))


func _yard() -> void:
	_place(op._ground(Opening.GULLY_AT, 0.5) + Vector3(1.6, 0.0, 1.6), 0.0)
	await _frames(5)
	_check("the dead drone", _label().contains("drone"), _label())
	_check("and the marker points at it", main._waypoint() is Vector3 and (main._waypoint() as Vector3).distance_to(op._ground(Opening.GULLY_AT, 1.0)) < 0.5)
	var hp := player.health
	await _press("interact")
	await _frames(10)
	_check("a scuttler watches, not hunting", op._watcher != null and is_instance_valid(op._watcher) and not op._watcher.hunting)
	await get_tree().create_timer(9.0).timeout
	_check("it goes, and the trail goes on", op.beat() == Opening.Beat.WATCHED and player.health >= hp)
	var yard: Vector3 = main.sites["aux_power"].global_position
	_place(yard + (op._ground(Vector2(-46.0, 49.5), 0.5) - yard).normalized() * 22.0, 0.0)
	await _frames(40)
	_check("the yard: one hungry scuttler", op._hungry != null and is_instance_valid(op._hungry) and _enemy_count() == 1, "enemies=%d" % _enemy_count())
	await get_tree().create_timer(1.0).timeout
	_check("it threatens, it doesn't charge yet", not op._hungry.hunting)
	_place(op._hungry.global_position + Vector3(0.0, 0.0, 7.0), 0.0)
	await get_tree().create_timer(2.4).timeout
	_check("after one warning, it comes", op._hungry.hunting)
	op._hungry.take_damage(999.0, op._hungry.global_position)
	await _frames(10)
	_check("it drops a battery contact", op._contact != null)
	_place(op._contact.global_position + Vector3(0.0, 0.3, 1.2), 0.0)
	await _frames(5)
	await _press("interact")
	_check("contact in hand", Game.flags.get("relay_contact", false) and op.beat() == Opening.Beat.YARD)
	_check("then the relay job's own marker takes over", main._waypoint() is Vector3, str(main._waypoint()))


func _relay() -> void:
	var runner: MissionRunner = main.missions
	var site: ExpeditionSite = main.sites["aux_power"]
	var dev := runner.device("aux_power", 0, 0)
	_place(dev.global_position + dev.global_basis.z * 1.2, 0.0)
	await _frames(5)
	await _press("interact")
	_check("the contact wires into the breaker", runner.stage_index("aux_power") == 1, _label())
	var decoy := runner.device("aux_power", 1, 0)
	_place(decoy.global_position + decoy.global_basis.z * 1.2, 0.0)
	await _frames(5)
	_check("each switchbox reads its hum", _label().contains("hum"), _label())
	var hp := player.health
	await _press("interact")
	_check("the dead line trips with sparks, not harm", Game.mission_done.is_empty() and player.health >= hp and runner.stage_index("aux_power") == 1)
	for i in [1, 2]:
		var d := runner.device("aux_power", 1, i)
		_place(d.global_position + d.global_basis.z * 1.2, 0.0)
		await _frames(5)
		await _press("interact")
	_check("two live lines route the current", runner.stage_index("aux_power") == 2)
	var cradle := runner.device("aux_power", 2, 0)
	_place(cradle.global_position + cradle.global_basis.z * 1.2, 0.0)
	await _frames(5)
	await _hold(2.4)
	await _frames(5)
	_check("the cradle lets go", runner.can_take("aux_power"), str(runner.stage_index("aux_power")))
	_place(site.component_point() + Vector3(0.0, 0.2, 0.0), 0.0)
	await _frames(5)
	await _press("interact")
	_check("the cell is in her pouch", Game.carrying == "aux_cell")
	_check("the opening is over", not op.active() and Opening.seen_before() and op.props == null)
	_check("no ambush on Normal; the roamers come out now", _enemy_count() == main.ROAMER_POINTS.size(), "enemies=%d" % _enemy_count())
	_clear_enemies()
	_check("objective: bring it home", Game.objective_text().contains("home"), Game.objective_text())
	_place(site.global_position + Vector3(0.0, 0.5, 20.0), 0.0)
	await _frames(5)
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await get_tree().create_timer(0.8).timeout
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("move_forward")
	Input.action_release("sprint")
	_check("she can run with it", speed > player.walk_speed + 1.0, "%.1f m/s" % speed)
	player.global_position = main.install_point("aux_power") + Vector3.UP * 0.3
	await _frames(5)
	await _press("interact")
	_check("installed", Game.is_repaired("aux_power"))
	var probe: Node3D = main.spawn_scuttler(player.global_position + Vector3(0.0, 0.0, 15.0))
	await _frames(3)
	_check("aux power wakes the suit scanner", main.scanner_marks().any(func(m): return m["kind"] == "enemy"))
	probe.queue_free()


## A second new game after one full opening: the bunk offers to sleep through it.
func _skip() -> void:
	Game.flags.clear()
	Game.intro_pending = true
	main.queue_free()
	await _frames(5)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	kestrel = main.kestrel
	player = main.player
	op = main.opening
	await _frames(10)
	var a: Approach = main.regions.scene
	_check("second time round, orbit again", main.regions.current == "approach")
	_place(a._at(Vector3(9.3, 0.1, 11.0)), 0.0)
	await _frames(5)
	_check("the bunk offers the skip", _label().contains("Sleep"), _label())
	await _press("interact")
	await _frames(10)
	_check("skipped: in the Kettle, armed, opening done, the relay's contact in hand", main.regions.current == "kettle" and player.armed and not op.active() and Game.flags.get("relay_contact", false))
	# A save from before the opening existed has no beat, so none of it runs.
	Game.flags.erase("opening")
	_check("old saves never see the opening", not op.active())
