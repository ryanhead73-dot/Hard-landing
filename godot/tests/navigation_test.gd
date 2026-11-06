extends Node
## M14 AI navigation: creatures starting from every site's real spawn and ambush points reach
## Juno at the site's component, and a creature pinned in place works itself loose. Run:
##   godot --headless --path . res://tests/navigation_test.tscn

const CHASE_TIME := 14.0
## Close enough to count as having reached her (scuttlers ring at 4.2 m and wait their turn).
const REACHED := 6.5

var failures := 0
var main: Node


func _ready() -> void:
	Game.save_path = "user://navigation_test_scratch.json"
	Game.reset()
	Game.pending_load = {}
	Game.intro_pending = false
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	main.weather.enabled = false
	await get_tree().create_timer(0.5).timeout
	for id in main.sites:
		var s: ExpeditionSite = main.sites[id]
		var starts: Array = (s.spawn_pts + s.ambush_pts).map(func(p): return s.to_global(p))
		await _chase_from(id, s.to_global(s.component_stand), starts)
	# Round Kestrel's side door, where sieges come in.
	var door: Vector3 = main.kestrel.to_global(Vector3(14.0, 0.5, 2.0))
	var ring: Array = []
	for i in 8:
		ring.append(door + Vector3(cos(TAU * i / 8.0), 0.0, sin(TAU * i / 8.0)) * 16.0)
	await _chase_from("kestrel side door", door, ring)
	await _pinned()
	print("NAVIGATION TEST %s (%d failures)" % ["PASSED" if failures == 0 else "FAILED", failures])
	get_tree().quit(1 if failures else 0)


func _chase_from(place: String, at: Vector3, starts: Array) -> void:
	_clear()
	main.player.revive(at)
	await get_tree().create_timer(0.3).timeout
	at = main.player.global_position
	var es: Array = []
	for p in starts:
		var e: Enemy = main.spawn_enemy("scuttler", p)
		e.leash_range = 999.0
		es.append(e)
	await get_tree().physics_frame
	for e in es:
		e.alert(false)
	var best := {}
	var t := 0.0
	while t < CHASE_TIME and best.values().filter(func(d): return d < REACHED).size() < es.size():
		await get_tree().physics_frame
		t += get_physics_process_delta_time()
		main.player.health = main.player.max_health()
		for i in es.size():
			var d := _flat_dist(es[i].global_position, at)
			best[i] = minf(best.get(i, INF), d)
	var missed: Array = []
	for i in es.size():
		if best.get(i, INF) >= REACHED:
			missed.append("from (%.0f, %.0f) got to %.0f m" % [starts[i].x, starts[i].z, best.get(i, INF)])
	_check("%s: all %d creatures reach Juno" % [place, es.size()], missed.is_empty(), ", ".join(missed))


## A wall with a slot narrower than a scuttler: the feelers see the slot is too tight and it goes
## round the end. Then a wall its feelers can't see (a stand-in for anything they miss): it bumps
## into it, works itself loose and still gets there.
func _pinned() -> void:
	for hidden in [false, true]:
		_clear()
		var at: Vector3 = main.SPAWN + Vector3(-30.0, 0.0, 30.0)
		main.player.revive(at)
		await get_tree().create_timer(0.3).timeout
		at = main.player.global_position
		var walls := Node3D.new()
		main.add_child(walls)
		var mid: Vector3 = at + Vector3(0.0, 0.0, -9.0)
		var layer := Game.LAYER_ENEMY if hidden else Game.LAYER_WORLD
		if hidden:
			_wall(walls, mid + Vector3(0.0, 0.8, 0.0), Vector3(5.0, 1.6, 0.4), layer)
		else:
			# 0.9 m slot; the scuttler is 1.1 m wide.
			for x in [-1.95, 1.95]:
				_wall(walls, mid + Vector3(x, 0.8, 0.0), Vector3(3.0, 1.6, 0.4), layer)
		var e: Enemy = main.spawn_enemy("scuttler", mid + Vector3(0.0, 0.0, -1.2))
		e.leash_range = 999.0
		await get_tree().physics_frame
		e.alert(false)
		var t := 0.0
		var best := INF
		while t < CHASE_TIME and best >= REACHED:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			main.player.health = main.player.max_health()
			best = minf(best, _flat_dist(e.global_position, at))
		if hidden:
			_check("a scuttler pinned on a wall it can't see works itself loose and reaches Juno", best < REACHED and e.unstuck_count > 0,
				"got to %.1f m, worked loose %d times" % [best, e.unstuck_count])
		else:
			_check("a scuttler goes round a slot too narrow for it", best < REACHED, "got to %.1f m, worked loose %d times" % [best, e.unstuck_count])
		walls.queue_free()


func _wall(parent: Node3D, at: Vector3, size: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	body.global_position = at


func _clear() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.free()


static func _flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _check(what: String, ok: bool, detail := "") -> void:
	print("%s  %s  %s" % ["PASS" if ok else "FAIL", what, detail if not ok else ""])
	if not ok:
		failures += 1
