extends Node
## Headless walk-through of the blockout. Run:
##   godot --headless --path . res://tests/smoke_test.tscn
## Drives the player along the main route and through the crawlway, flips every repair,
## and prints PASS/FAIL lines. Exits with code 1 on any failure.

var main: Node3D
var kestrel: Kestrel
var player: Player
var failures := 0


func _ready() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	kestrel = main.kestrel
	player = main.player
	await _run()
	print("SMOKE TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _run() -> void:
	await _frames(30)
	_check("player lands at spawn", player.is_on_floor(), "y=%.2f" % player.global_position.y)

	# Door steps into the workshop: walk toward the ship (-Z).
	_place(kestrel.to_global(kestrel.plan(12.9, 0.0, 20.6)), 0.0)
	await _walk(3.0)
	var local := kestrel.to_local(player.global_position)
	_check("side door steps reach the workshop", local.z < 3.6 and local.y > -0.15, "local=%s" % local)

	# Workshop to cockpit up the stairs, facing the nose (-X).
	_place(kestrel.to_global(kestrel.plan(14.6, 0.1, 13.0)), PI * 0.5)
	await _frames(10)
	_check("workshop camera boom is clear", player.boom_current() > player.boom_length - 0.2, "boom=%.2f" % player.boom_current())
	await _walk(3.5)
	local = kestrel.to_local(player.global_position)
	_check("stairs reach the raised cockpit", local.x < kestrel.plan(8.0, 0, 0).x and local.y > 1.0, "local=%s" % local)

	# Cargo to port crawlway, crouched (port is -Z).
	_place(kestrel.to_global(kestrel.plan(27.0, 0.1, 13.0)), 0.0)
	Input.action_press("crouch")
	await _walk(2.5)
	local = kestrel.to_local(player.global_position)
	_check("crouch through crawlway hatch", local.z < kestrel.plan(0, 0, 10.1).z and local.z > kestrel.plan(0, 0, 9.3).z, "local=%s" % local)
	Input.action_release("crouch")
	await _frames(5)
	_check("stays crouched under crawlway ceiling", player.crouching)

	# Install aux power through the interaction.
	_place(kestrel.to_global(kestrel.interact_points["aux_power"]) + Vector3.UP * 0.1, 0.0)
	await _frames(10)
	Input.action_press("interact")
	await _frames(2)
	Input.action_release("interact")
	_check("E installs aux power", kestrel.is_repaired("aux_power"))

	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	await get_tree().create_timer(3.5).timeout
	_check("landing gear levels the ship", kestrel.rotation.length() < 0.001 and is_equal_approx(kestrel.position.y, Kestrel.LEVEL_DECK_Y), "rot=%s y=%.2f" % [kestrel.rotation, kestrel.position.y])
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, false)
	await _frames(5)
	_check("all repairs reset to damaged", Kestrel.REPAIR_ORDER.all(func(id): return not kestrel.is_repaired(id)))


func _place(pos: Vector3, yaw: float) -> void:
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.face(yaw)


func _walk(seconds: float) -> void:
	Input.action_press("move_forward")
	await get_tree().create_timer(seconds).timeout
	Input.action_release("move_forward")
	await _frames(10)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(label: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", label, detail])
	if not ok:
		failures += 1
