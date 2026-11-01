extends Node
## Shared harness for the headless test scenes: loads main, runs _run(), prints PASS/FAIL lines
## and exits 1 on any failure. Subclasses implement _run().

var main: Node3D
var kestrel: Kestrel
var player: Player
var failures := 0
var finished := false


func _ready() -> void:
	# Never touch a real save or depend on the player's difficulty setting.
	Game.save_path = "user://test_save.json"
	Game.delete_save()
	Game.difficulty = 1
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	# Storms change the light, sight ranges and voice lines; suites that want one start it.
	main.weather.enabled = false
	# Missions have their own suite; the others take components straight away.
	main.missions.bypass = _bypass_missions()
	main.missions.refresh(false)
	kestrel = main.kestrel
	player = main.player
	await _run()
	# A script error aborts _run without a FAIL line, so make sure it got to the end.
	_check("test ran to the end", finished)
	print("%s %s (%d failures)" % [_name(), "PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _name() -> String:
	return "TEST"


func _bypass_missions() -> bool:
	return true


func _run() -> void:
	finished = true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _clear_enemies() -> void:
	for s in get_tree().get_nodes_in_group("enemies"):
		s.remove_from_group("scuttlers")
		s.remove_from_group("enemies")
		s.queue_free()
	for a in get_tree().get_nodes_in_group("acid"):
		a.queue_free()


func _enemy_count() -> int:
	return get_tree().get_nodes_in_group("enemies").size()


func _place(pos: Vector3, yaw: float) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.face(yaw)


## Presses an action for a couple of frames. It starts on a physics frame: resuming from a
## SceneTreeTimer happens after this frame's _process calls, and a press made there would be
## stale ("just pressed" in a frame that has already been processed) by the next one.
func _press(action: String) -> void:
	await get_tree().physics_frame
	Input.action_press(action)
	await _frames(2)
	Input.action_release(action)
	await _frames(2)


func _walk(seconds: float) -> void:
	Input.action_press("move_forward")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("move_forward")
	await _frames(10)


## Walks through each point in turn, steering every frame. Returns false if it got stuck.
func _walk_path(points: Array, timeout_each := 8.0) -> bool:
	for target in points:
		var ok := false
		Input.action_press("move_forward")
		for i in int(timeout_each * 60.0):
			var to := (target as Vector3) - player.global_position
			if Vector2(to.x, to.z).length() < 0.5:
				ok = true
				break
			player.face(atan2(-to.x, -to.z))
			await get_tree().physics_frame
		Input.action_release("move_forward")
		if not ok:
			return false
	await _frames(10)
	return true


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _label() -> String:
	return main._interaction.get("label", "")


func _check(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures += 1
