extends Node
## M14 AI navigation: creatures starting from every site's real spawn and ambush points reach
## Juno at the site's component, and a creature pinned in place works itself loose. Run:
##   godot --headless --path . res://tests/navigation_test.tscn

const CHASE_TIME := 14.0
## Close enough to count as having reached her. Scuttlers ring at 4.2 m and wait their turn,
## and with a dozen in one pack the outer ones can be held at about 7 m by the crowd; a creature
## that was actually wedged ends up tens of metres out.
const REACHED := 8.0
## A creature this close to one that reached her is queued behind the pack, not lost.
const CROWD := 3.5

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
	# A creature held back by the crowd (pressed up against one that did reach her) counts too:
	# it found its way, it is queued behind the pack. A wedged one is nowhere near the others.
	var queued := {}
	for i in es.size():
		if best.get(i, INF) >= REACHED and is_instance_valid(es[i]):
			for j in es.size():
				if j != i and best.get(j, INF) < REACHED and is_instance_valid(es[j]) \
						and _flat_dist(es[i].global_position, es[j].global_position) < CROWD:
					queued[i] = true
	var missed: Array = []
	for i in es.size():
		if best.get(i, INF) >= REACHED and not queued.has(i):
			var near := INF
			for j in es.size():
				if j != i and is_instance_valid(es[j]) and is_instance_valid(es[i]):
					near = minf(near, _flat_dist(es[i].global_position, es[j].global_position))
			var e: Enemy = es[i] if is_instance_valid(es[i]) else null
			missed.append("from (%.0f, %.0f) got to %.0f m (now %.1f m, nearest pack-mate %.1f m, worked loose %d)" % [starts[i].x, starts[i].z, best.get(i, INF),
				_flat_dist(e.global_position, at) if e else -1.0, near, e.unstuck_count if e else -1])
			if e:
				var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3.UP * 0.5, at + Vector3.UP * 0.5)
				q.exclude = [e.get_rid()]
				var hit := e.get_world_3d().direct_space_state.intersect_ray(q)
				print("  missed creature at %s, Juno at %s, first thing between them: %s at %s" % [e.global_position, at, hit["collider"].get_path() if hit else "nothing", hit.get("position", "-")])
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
