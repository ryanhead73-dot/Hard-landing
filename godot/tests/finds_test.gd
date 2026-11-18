extends "res://tests/test_base.gd"
## Walk finds (WalkFinds): each Kettle find announces itself, offers its prompt, pays off and
## stays done; the glass-wind lock takes the wind's order and resets on a wrong key; the loose
## bolt only appears after the canopy repair and goes back on Kestrel's bench; the Shatterlands
## and Gillwood finds are built when Juno arrives and pay off there.
## Run:
##   godot --headless --path . res://tests/finds_test.tscn


func _name() -> String:
	return "FINDS TEST"


func _run() -> void:
	await _frames(20)
	_clear_enemies()
	var finds: WalkFinds = main.finds
	_check("every Kettle find is built", WalkFinds.KETTLE.keys().all(func(id): return finds.nodes.has(id)))
	_check("all ten finds, the tenth in the Loom", WalkFinds.all_ids().size() == 10)
	_check("none found on a new game", WalkFinds.all_ids().all(func(id): return not WalkFinds.found(id)))

	# Rain cup: the first time it upgrades the scanner.
	Game.flags.erase("scanner_battery")
	await _use_at("rain_cup", "rainwater")
	_check("the rain cup gives the scanner its range", WalkFinds.found("rain_cup") and Game.flags.get("scanner_battery", false))
	await _place_at("rain_cup")
	_check("and is done after", _label() == "", _label())

	var stims := Game.stims
	Game.stims = 0
	await _use_at("towing_marks", "crawlspace")
	_check("the crawlspace holds a med-seal", Game.stims == 1)
	Game.stims = stims

	var scrap := Game.scrap
	await _use_at("silent_beacon", "dish", true)
	_check("turning the beacon's dish pays scrap and marks a bearing", Game.scrap == scrap + 15 and Game.flags.get("find_beacon_bearing", false))

	scrap = Game.scrap
	await _use_at("helmet", "recorder")
	_check("the helmet's recorder pays a little scrap", Game.scrap == scrap + 12)

	# The glass wind: a wrong key resets the lock; the wind's order opens it.
	var lock: Node3D = finds.nodes["glass_wind"]
	await _press_key(lock, 1)
	_check("a wrong first key resets the lock", finds._lock_input.is_empty() and not WalkFinds.found("glass_wind"))
	scrap = Game.scrap
	for k in WalkFinds.TONE_ORDER:
		await _press_key(lock, k)
	_check("the wind's order opens it for 30 scrap", WalkFinds.found("glass_wind") and Game.scrap == scrap + 30)

	# The bolt: hidden until the canopy's fixed, then back on the bench.
	var bolt: Node3D = finds.nodes["hob_bolt"]
	_check("no loose bolt before the canopy repair", not bolt.visible)
	kestrel.set_repaired("aux_power", true)
	kestrel.set_repaired("canopy", true)
	finds._sync()
	_check("it shakes loose after", bolt.visible)
	await _use_at("hob_bolt", "bolt", false, false)
	_check("picked up, it leaves the ground", not bolt.visible and not WalkFinds.found("hob_bolt"))
	var bench: Vector3 = kestrel.to_global(kestrel.plan(WalkFinds.BOLT_RETURN_AT.x, 0.3, WalkFinds.BOLT_RETURN_AT.z))
	_place(bench, 0.0)
	await _frames(8)
	_check("the bench offers to take it back", _label().contains("bench"), _label())
	await _press("interact")
	await _frames(4)
	_check("returned, it sits on the bench", WalkFinds.found("hob_bolt") and kestrel.get_node_or_null("ReturnedBolt") != null)

	# Region finds.
	var rm: RegionManager = main.regions
	Game.set_flag("shatterlands_open", true)
	rm.travel("shatterlands", true)
	await _wait_travel(rm)
	_check("the boot is built in the Shatterlands", finds._live("boot") != null)
	stims = Game.stims
	Game.stims = 0
	await _use_at("boot", "boot")
	_check("the boot's ration is a med-seal", Game.stims == 1 and Game.flags.get("greenhouse_coords", false))
	Game.stims = stims
	Game.set_flag("reyes_talked", true)
	rm.travel("gillwood", true)
	await _wait_travel(rm)
	_check("the orchard and the pocket weather are built in the Gillwood", finds._live("static_orchard") != null and finds._live("pocket_weather") != null)
	var charges := Game.charges
	Game.charges = 0
	await _use_at("static_orchard", "seed pods")
	_check("a seed pod gives an arc charge", Game.charges == 1)
	Game.charges = charges
	scrap = Game.scrap
	await _use_at("pocket_weather", "rain")
	_check("the pocket weather gives a Loom clue and spore fibre", Game.flags.get("clue_loom_threes", false) and Game.scrap == scrap + 20)
	Game.set_flag("loom_open", true)
	rm.travel("loom_expanse", true)
	await _wait_travel(rm)
	_check("the signal flag is built in the Loom Expanse", finds._live("signal_flag") != null)
	var loom := rm.scene as LoomExpanse
	_check("the bypass is laced shut before the flag", loom != null and not loom.bypass_open())
	await _use_at("signal_flag", "flag")
	_check("the flag opens the bypass lane", loom.bypass_open() and not (loom.bypass.get_child(loom.bypass.get_child_count() - 1) as StaticBody3D).collision_layer)
	_check("every find is done", WalkFinds.all_ids().all(func(id): return WalkFinds.found(id)))
	finished = true


func _place_at(id: String) -> void:
	var root: Node3D = main.finds.nodes[id]
	var lift := 0.8 if id == "silent_beacon" else 0.4
	_place(root.global_position + Vector3(0.0, lift, 1.2), 0.0)
	await _frames(6)


func _use_at(id: String, word: String, hold := false, done := true) -> void:
	await _place_at(id)
	_check("%s offers its prompt" % id, _label().to_lower().contains(word), _label())
	if hold:
		await get_tree().physics_frame
		Input.action_press("interact")
		await get_tree().create_timer(2.0).timeout
		Input.action_release("interact")
		await _frames(4)
	else:
		await _press("interact")
		await _frames(4)
	if done:
		_check("%s is found" % id, WalkFinds.found(id))


func _press_key(lock: Node3D, key: int) -> void:
	_place(lock.to_global(Vector3(-0.4 + key * 0.4, 0.4, 1.4)), 0.0)
	await _frames(6)
	await _press("interact")
	await _frames(4)


func _wait_travel(rm: RegionManager) -> void:
	await _frames(2)
	var t := 0.0
	while rm.travelling and t < 5.0:
		await get_tree().process_frame
		t += get_process_delta_time()
	await _frames(10)
