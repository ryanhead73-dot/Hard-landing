class_name GearEscort
extends Node3D
## Repair 4, "Make a way through" (milestone B2): Ferro-9's landing-gear strut, salvaged in the
## Gillwood once her canopy is on the pad.
##
## Juno cuts the strut from under the aft section and mounts it on Ferro-9's damaged hauler
## drone. The drone follows its beacon along a route of power posts and only moves on toward a
## post Juno has powered, so she runs ahead and lights the way. At the fork she picks the route:
## the root tunnel (longer and safe from predators, but a squall floods it and the drone waits
## the water out) or the ridge (short, past spore pods that jam the drone if they burst on it:
## shoot them first). Reyes's salvage hoist stands in a clearing a brood holds; the drone won't
## go in till they're dealt with (a spore pod there splits them). A jammed drone is patched with
## the scrap lying about; it's never lost. At the hoist the strut goes up and Reyes's runners take
## it home: Game.deliver_component("struts").
##
## Path recovery: the route, the last point the drone reached and the powered posts are flags, so
## a load puts the drone back where it was. Flags: gear_cut, gear_mounted, gear_route ("low" or
## "high"), gear_at (point index), gear_posts (bitmask), gear_brood, ferro_gear (done).

## The two routes, Gillwood-local: [point, post?]. Both start at the drone and end at the hoist.
const START := Vector3(18.0, 0.0, -10.0)
const FORK := Vector3(24.0, 0.0, -1.0)
const HOIST := Vector3(34.0, 0.0, 37.0)
const ROUTES := {
	"low": [[START, false], [FORK, true], [Vector3(42.0, 0.0, -1.0), true], [Vector3(42.0, 0.0, 6.0), false],
		[Vector3(42.0, 0.0, 26.0), true], [Vector3(38.0, 0.0, 32.0), false], [HOIST, true]],
	"high": [[START, false], [FORK, true], [Vector3(24.0, 0.0, 4.0), false], [Vector3(24.0, 3.0, 11.0), true],
		[Vector3(24.0, 3.0, 23.0), false], [Vector3(24.0, 0.0, 30.0), true], [HOIST, true]],
}
## The ridge (high route): a basalt spine with ramps at each end; its spore pods.
const RIDGE := Vector3(24.0, 1.5, 17.0)
const RIDGE_SIZE := Vector3(5.0, 3.0, 13.0)
const PODS := [Vector3(23.4, 3.0, 14.5), Vector3(24.8, 3.0, 19.5)]
## The root tunnel (low route): arched roots over the channel between these, flooding in a squall.
const TUNNEL := [Vector3(42.0, 0.0, 6.0), Vector3(42.0, 0.0, 26.0)]
## The two route levers at the fork (east for the tunnel, north for the ridge).
const LEVER_LOW := FORK + Vector3(2.6, 0.0, 0.8)
const LEVER_HIGH := FORK + Vector3(-1.6, 0.0, 2.6)
## The pod in the hoist clearing that splits the brood.
const CLEARING_POD := HOIST + Vector3(-5.0, 0.0, -3.5)
const SPEED := 2.4
const HOVER := 0.7
const USE_RANGE := 2.2
const CUT_HOLD := 1.5
const PATCH_HOLD := 1.5
const SQUALL_TIME := 12.0
const POD_RANGE := 3.0
const BROOD := 4
const BROOD_WAKE := 15.0
const AMBER := Color("e8a44e")
const TEAL := Color("3fd1b5")

var gw: Gillwood
var drone: Node3D
var at := 0
## 0..1 along the segment from point `at` to the next.
var along := 0.0
var jammed := false
var squall := 0.0
var squalls := 0
var jams := 0
var pods: Array[SporePod] = []
var brood: Array[Enemy] = []
var _popped: Array[bool] = [false, false]
var _posts: Dictionary = {}
var _post_mats: Dictionary = {}
var _beacon_mat: StandardMaterial3D
var _cargo: Node3D
var _water: MeshInstance3D
var _smoke: CPUParticles3D
var _hoist_hook: Node3D
var _t := 0.0
var _hum := 0.0
var _arriving := false


func _ready() -> void:
	at = int(Game.flags.get("gear_at", 0))
	_build()
	_place_drone()
	_sync()


func _exit_tree() -> void:
	Game.set_region_objective("")


## True while the strut is Juno's to salvage here (after the canopy; not on old saves).
func active() -> bool:
	return not done() and not Game.is_repaired("landing_gear") and Game.flags.get("ferro_canopy", false) == true


func done() -> bool:
	return Game.flags.get("ferro_gear", false) == true


func cut() -> bool:
	return Game.flags.get("gear_cut", false) == true


func mounted() -> bool:
	return Game.flags.get("gear_mounted", false) == true


func route() -> String:
	return String(Game.flags.get("gear_route", ""))


func points() -> Array:
	return ROUTES.get(route() if route() != "" else "low")


func point(i: int) -> Vector3:
	return gw.to_global(points()[i][0])


func is_post(i: int) -> bool:
	return points()[i][1]


func powered(i: int) -> bool:
	return not is_post(i) or (int(Game.flags.get("gear_posts", 0)) & (1 << i)) != 0


func brood_cleared() -> bool:
	return Game.flags.get("gear_brood", false) == true


func post_pos(i: int) -> Vector3:
	return point(i) + _post_offset(i)


## Posts stand beside the path, not on it, so the drone passes them.
func _post_offset(i: int) -> Vector3:
	var pts := points()
	var a: Vector3 = pts[maxi(i - 1, 0)][0]
	var b: Vector3 = pts[i][0]
	var d := Vector3(b.x - a.x, 0.0, b.z - a.z)
	if d.length() < 0.1:
		return Vector3(1.6, 0.0, 0.0)
	return d.normalized().cross(Vector3.UP) * 1.8


## What the drone is waiting for: "", "route", "post", "jam", "squall", "brood", "hoist".
func waiting() -> String:
	if not mounted() or done():
		return ""
	if jammed:
		return "jam"
	if squall > 0.0:
		return "squall"
	var n := points().size()
	if at >= n - 1:
		return ""
	if route() == "":
		return "route" if along >= 1.0 else ""
	var next := at + 1
	if next == n - 1 and not brood_cleared():
		return "brood"
	if not powered(next):
		return "hoist" if next == n - 1 else "post"
	return ""


func interaction(pos: Vector3) -> Dictionary:
	if not active():
		return {}
	if not cut():
		if pos.distance_to(gw.strut_pos) < USE_RANGE:
			return {"label": "[Hold E] Cut the landing-gear strut free", "action": cut_strut, "hold": CUT_HOLD}
		return {}
	if not mounted():
		if pos.distance_to(drone.global_position) < USE_RANGE + 0.8:
			return {"label": "[E] Mount the strut on Ferro-9's hauler drone", "action": mount}
		return {}
	if jammed and pos.distance_to(drone.global_position) < USE_RANGE + 0.8:
		return {"label": "[Hold E] Patch the drone with scrap from the wreck", "action": patch, "hold": PATCH_HOLD}
	if route() == "":
		if pos.distance_to(gw.to_global(LEVER_LOW)) < USE_RANGE:
			return {"label": "[E] Send the drone by the root tunnel (safe, floods in a squall)", "action": choose.bind("low")}
		if pos.distance_to(gw.to_global(LEVER_HIGH)) < USE_RANGE:
			return {"label": "[E] Send the drone over the ridge (short, spore pods)", "action": choose.bind("high")}
		return {}
	for i in range(2, points().size()):
		if is_post(i) and not powered(i) and pos.distance_to(post_pos(i)) < USE_RANGE:
			if i == points().size() - 1:
				if not brood_cleared():
					return {"label": "Reyes's hoist: the brood's in the clearing"}
				return {"label": "[E] Power Reyes's hoist", "action": power.bind(i)}
			return {"label": "[E] Power the drone's route node", "action": power.bind(i)}
	return {}


func cut_strut() -> void:
	if cut():
		return
	Game.set_flag("gear_cut")
	Sfx.play("hull_groan", gw.strut_pos, -2.0)
	gw._say(Story.GEAR_CUT)
	gw._sync_parts(true)
	_sync()


func mount() -> void:
	if mounted() or not cut():
		return
	Game.set_flag("gear_mounted")
	Sfx.play("repair_clunk", drone.global_position, 0.0)
	gw._say(Story.GEAR_MOUNTED)
	gw._sync_parts()
	_sync()


func choose(which: String) -> void:
	if route() != "":
		return
	Game.set_flag("gear_route", which)
	Game.set_flag("gear_posts", 1 << 1)
	Sfx.play("breaker_clunk", gw.to_global(LEVER_LOW if which == "low" else LEVER_HIGH), -2.0)
	gw._say(Story.GEAR_LOW if which == "low" else Story.GEAR_HIGH)
	_build_posts()
	_sync()


func power(i: int) -> void:
	if powered(i):
		return
	Game.set_flag("gear_posts", int(Game.flags.get("gear_posts", 0)) | (1 << i))
	Sfx.play("relay_two_note", post_pos(i), -4.0)
	_sync()


func patch() -> void:
	if not jammed:
		return
	jammed = false
	Sfx.play("repair_clunk", drone.global_position, -2.0)
	_sync()


func _process(delta: float) -> void:
	_t += delta
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 4.0 if fmod(_t, 1.2) < 0.25 and mounted() and not done() else 0.6
	if not active():
		return
	if mounted():
		_tick_drone(delta)
	Game.set_region_objective(objective())


func _tick_drone(delta: float) -> void:
	if squall > 0.0:
		squall -= delta
		if _water:
			_water.position.y = lerpf(_water.position.y, 0.55, clampf(delta, 0.0, 1.0))
		if squall <= 0.0:
			gw._say(Story.GEAR_SQUALL_PASSED)
		return
	if _water:
		_water.position.y = lerpf(_water.position.y, -0.3, clampf(delta * 0.5, 0.0, 1.0))
	_wake_brood()
	_check_pods()
	if waiting() != "" or at >= points().size() - 1:
		return
	var next := at + 1
	var a: Vector3 = points()[at][0]
	var b: Vector3 = points()[next][0]
	along += SPEED * delta / maxf(a.distance_to(b), 0.1)
	# The first leg (drone to fork) runs on its own: the levers there pick the rest.
	if route() == "":
		along = minf(along, 1.0)
		_place_drone()
		return
	# Into the root tunnel, the first time: the squall comes.
	if route() == "low" and next == 4 and squalls == 0 and along > 0.35:
		squalls += 1
		squall = SQUALL_TIME
		Sfx.play("hull_groan", drone.global_position, -6.0)
		gw._say(Story.GEAR_SQUALL)
	_hum -= delta
	if _hum <= 0.0:
		_hum = 1.6
		Sfx.play("scanner_ping", drone.global_position, -16.0, 0.1)
	if along >= 1.0:
		at = next
		along = 0.0
		Game.set_flag("gear_at", at)
		if at == points().size() - 1:
			_arrive()
	_place_drone()


## A pod the drone comes near bursts on it and jams it, unless Juno burst it first.
func _check_pods() -> void:
	for k in pods.size():
		var pod := pods[k]
		if not is_instance_valid(pod):
			continue
		if pod.phase != TimedHazard.Phase.QUIET:
			if drone.global_position.distance_to(pod.global_position) < POD_RANGE + 0.4 and pod.is_active() and not _popped[k] and not jammed:
				_popped[k] = true
				_jam()
			_popped[k] = _popped[k] or (pod.is_active() and drone.global_position.distance_to(pod.global_position) >= POD_RANGE + 0.4)
			continue
		if not _popped[k] and route() == "high" and drone.global_position.distance_to(pod.global_position) < POD_RANGE:
			pod.trigger()


func _jam() -> void:
	jammed = true
	jams += 1
	Sfx.play("arc_zap", drone.global_position, -2.0)
	if jams == 1:
		gw._say(Story.GEAR_JAMMED)
	_sync()


## The brood in the hoist clearing wakes when the drone or Juno comes near.
func _wake_brood() -> void:
	if brood_cleared():
		return
	if brood.is_empty():
		var hoist := gw.to_global(HOIST)
		var near := drone.global_position.distance_to(hoist) < BROOD_WAKE + 4.0 or _player_pos().distance_to(hoist) < BROOD_WAKE
		if not near:
			return
		var main := gw.get_parent()
		if main == null or not main.has_method("spawn_enemy"):
			return
		for k in BROOD:
			var ang := TAU * k / BROOD
			var e: Enemy = main.spawn_enemy("scuttler", hoist + Vector3(cos(ang) * 3.0, 0.5, sin(ang) * 3.0), "", gw)
			e.add_to_group("gear_brood")
			brood.append(e)
		gw._say(Story.GEAR_BROOD)
		return
	if brood.all(func(e): return not is_instance_valid(e) or e.dead):
		Game.set_flag("gear_brood")
		_sync()


func _arrive() -> void:
	_arriving = true
	Game.set_flag("ferro_gear")
	Sfx.play("repair_clunk", drone.global_position, 0.0)
	if _hoist_hook and is_inside_tree():
		var tw := create_tween()
		tw.tween_property(_cargo, "global_position", _hoist_hook.global_position + Vector3.DOWN * 0.6, 1.5).set_trans(Tween.TRANS_SINE)
	if not Game.is_repaired("landing_gear"):
		Game.deliver_component(String(Campaign.get_repair("landing_gear")["component"]))
	gw._say(Story.GEAR_HOISTED)
	Game.set_region_objective("")
	_sync()


func objective() -> String:
	if done():
		return ""
	if not cut():
		return "Cut Ferro-9's landing-gear strut free from under her aft section"
	if not mounted():
		return "Mount the strut on Ferro-9's hauler drone"
	match waiting():
		"route":
			return "Pick the drone's route at the fork: the root tunnel or the ridge"
		"jam":
			return "The drone's jammed: patch it"
		"squall":
			return "Squall: the tunnel's flooding. The drone waits for the water to drop (%d s)" % ceili(squall)
		"brood":
			return "A brood holds the hoist clearing. Clear it (the spore pod there splits them)"
		"hoist":
			return "Power Reyes's hoist"
		"post":
			return "Power the next route node ahead of the drone"
	return "Keep ahead of the drone: it's heading for Reyes's hoist"


## The waypoint: whatever the drone is waiting on, or the drone.
func goal_point() -> Vector3:
	if not cut():
		return gw.strut_pos + Vector3.UP
	if not mounted():
		return drone.global_position + Vector3.UP
	match waiting():
		"route":
			return gw.to_global(FORK) + Vector3.UP * 1.5
		"brood":
			return gw.to_global(HOIST) + Vector3.UP
		"post", "hoist":
			return post_pos(at + 1) + Vector3.UP * 1.5
	for i in range(at + 1, points().size()):
		if is_post(i) and not powered(i):
			return post_pos(i) + Vector3.UP * 1.5
	return drone.global_position + Vector3.UP


func drone_pos() -> Vector3:
	var pts := points()
	if at >= pts.size() - 1:
		return gw.to_global(pts[pts.size() - 1][0])
	return gw.to_global((pts[at][0] as Vector3).lerp(pts[at + 1][0], clampf(along, 0.0, 1.0)))


func _place_drone() -> void:
	if drone == null:
		return
	var p := drone_pos()
	drone.global_position = p + Vector3.UP * HOVER
	var pts := points()
	if at < pts.size() - 1:
		var d: Vector3 = pts[at + 1][0] - pts[at][0]
		if Vector2(d.x, d.z).length() > 0.1:
			drone.rotation.y = atan2(-d.x, -d.z)


func _player_pos() -> Vector3:
	var main := gw.get_parent()
	if main == null or main.get("player") == null:
		return Vector3.INF
	return main.player.global_position


func _build() -> void:
	var dark := gw._mat(Color("3a3f44"), 0.5)
	# The drone: a slate hauler with amber trim, four teal lift pads and a beacon mast.
	drone = Node3D.new()
	drone.name = "HaulerDrone"
	drone.set_meta("no_batch", true)
	gw.add_child(drone)
	_box(drone, Vector3.ZERO, Vector3(1.5, 0.6, 2.2), gw.ferro_hull())
	_box(drone, Vector3(0.0, 0.05, 0.0), Vector3(1.55, 0.14, 2.25), gw._mat(Gillwood.FERRO_TRIM, 0.5))
	var pad_mat := gw._glow(TEAL, 2.0)
	for x in [-0.6, 0.6]:
		for z in [-0.85, 0.85]:
			_box(drone, Vector3(x, -0.36, z), Vector3(0.42, 0.1, 0.42), pad_mat)
	_box(drone, Vector3(0.55, 0.65, 0.8), Vector3(0.08, 0.7, 0.08), dark)
	var beacon := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.13
	bm.height = 0.26
	beacon.mesh = bm
	_beacon_mat = gw._glow(AMBER, 1.0)
	beacon.material_override = _beacon_mat
	beacon.position = Vector3(0.55, 1.05, 0.8)
	drone.add_child(beacon)
	# Its cargo once mounted: the strut on a cradle, and the wisp it makes when jammed.
	_cargo = Node3D.new()
	drone.add_child(_cargo)
	_cargo.position = Vector3(0.0, 0.55, 0.0)
	var leg := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.18
	lm.bottom_radius = 0.22
	lm.height = 2.2
	leg.mesh = lm
	leg.material_override = gw._mat(Color("8a9094"), 0.35)
	leg.rotation.x = PI * 0.5
	leg.position.y = 0.25
	_cargo.add_child(leg)
	var wheel := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.55
	wm.bottom_radius = 0.55
	wm.height = 0.35
	wheel.mesh = wm
	wheel.material_override = gw._mat(Color("2a2b2d"), 0.9)
	wheel.rotation.z = PI * 0.5
	wheel.position = Vector3(0.0, 0.4, 1.1)
	_cargo.add_child(wheel)
	_smoke = CPUParticles3D.new()
	_smoke.amount = 16
	_smoke.lifetime = 1.4
	_smoke.direction = Vector3.UP
	_smoke.spread = 20.0
	_smoke.initial_velocity_min = 0.6
	_smoke.initial_velocity_max = 1.2
	_smoke.gravity = Vector3(0.0, 0.4, 0.0)
	_smoke.color = Color(0.3, 0.3, 0.32, 0.6)
	var sm := SphereMesh.new()
	sm.radius = 0.12
	sm.height = 0.24
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	_smoke.mesh = sm
	_smoke.emitting = false
	_smoke.position = Vector3(0.0, 0.5, -0.6)
	drone.add_child(_smoke)
	# The fork's two levers, on short amber posts.
	for lever in [LEVER_LOW, LEVER_HIGH]:
		_box(gw, lever + Vector3(0.0, 0.6, 0.0), Vector3(0.3, 1.2, 0.3), dark, true)
		_box(gw, lever + Vector3(0.0, 1.25, 0.0), Vector3(0.12, 0.4, 0.12), gw._mat(Gillwood.FERRO_TRIM, 0.5))
	# The ridge: a basalt spine with a ramp up each end, and its spore pods.
	_box(gw, RIDGE, RIDGE_SIZE, gw._basalt(6.0), true)
	gw._ramp(Vector3(24.0, 0.0, 3.0), Vector3(24.0, 3.0, RIDGE.z - RIDGE_SIZE.z * 0.5 + 0.2), 3.2)
	gw._ramp(Vector3(24.0, 3.0, RIDGE.z + RIDGE_SIZE.z * 0.5 - 0.2), Vector3(24.0, 0.0, 31.0), 3.2)
	for p in PODS + [CLEARING_POD]:
		var pod := SporePod.new()
		gw.add_child(pod)
		pod.global_position = gw.to_global(p)
		if p != CLEARING_POD:
			pods.append(pod)
	# The root tunnel: arched roots over the channel, and the water that rises in a squall.
	var root_mat := gw._tex("fungus_stem", 2.0, true, Color(0.7, 0.75, 0.85), gw._mat(Gillwood.STEM, 0.7))
	var z: float = TUNNEL[0].z
	while z <= TUNNEL[1].z:
		var arch := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 2.6
		tm.outer_radius = 3.1
		tm.rings = 16
		tm.ring_segments = 6
		arch.mesh = tm
		arch.material_override = root_mat
		arch.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		gw.add_child(arch)
		arch.position = Vector3(TUNNEL[0].x, 0.0, z)
		z += 2.5
	for side in [-1.0, 1.0]:
		_box(gw, Vector3(TUNNEL[0].x + side * 3.1, 1.2, (TUNNEL[0].z + TUNNEL[1].z) * 0.5), Vector3(0.5, 2.4, TUNNEL[1].z - TUNNEL[0].z), root_mat, true)
	_water = MeshInstance3D.new()
	var wpm := PlaneMesh.new()
	wpm.size = Vector2(5.6, TUNNEL[1].z - TUNNEL[0].z + 2.0)
	_water.mesh = wpm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.2, 0.32, 0.4, 0.75)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.05
	wmat.metallic = 0.3
	_water.material_override = wmat
	gw.add_child(_water)
	_water.position = Vector3(TUNNEL[0].x, -0.3, (TUNNEL[0].z + TUNNEL[1].z) * 0.5)
	# Reyes's hoist: a gantry over the clearing, its hook hanging.
	var h := HOIST
	for x in [-2.2, 2.2]:
		_box(gw, h + Vector3(x, 3.0, 0.0), Vector3(0.3, 6.0, 0.3), dark, true)
	_box(gw, h + Vector3(0.0, 6.1, 0.0), Vector3(4.8, 0.3, 0.4), dark)
	_box(gw, h + Vector3(0.0, 6.3, 0.0), Vector3(4.9, 0.12, 0.45), gw._mat(Color("c98a3c"), 0.5))
	_hoist_hook = Node3D.new()
	_hoist_hook.set_meta("no_batch", true)
	gw.add_child(_hoist_hook)
	_hoist_hook.position = h + Vector3(0.0, 4.6, 0.0)
	_box(_hoist_hook, Vector3(0.0, 0.7, 0.0), Vector3(0.05, 1.4, 0.05), dark)
	_box(_hoist_hook, Vector3.ZERO, Vector3(0.4, 0.2, 0.4), gw._mat(Color("c98a3c"), 0.5))
	_build_posts()


var _post_nodes: Array[Node3D] = []


## Posts for the chosen route (none until the fork's lever is thrown).
func _build_posts() -> void:
	for n in _post_nodes:
		n.queue_free()
	_post_nodes.clear()
	_post_mats.clear()
	if route() == "":
		return
	for i in range(2, points().size()):
		if not is_post(i):
			continue
		var post := Node3D.new()
		gw.add_child(post)
		post.global_position = post_pos(i)
		_box(post, Vector3(0.0, 0.7, 0.0), Vector3(0.3, 1.4, 0.3), gw._mat(Color("3a3f44"), 0.5), true)
		var lamp := MeshInstance3D.new()
		var lm := SphereMesh.new()
		lm.radius = 0.16
		lm.height = 0.32
		lamp.mesh = lm
		var mat := StandardMaterial3D.new()
		mat.emission_enabled = true
		lamp.material_override = mat
		lamp.position = Vector3(0.0, 1.55, 0.0)
		post.add_child(lamp)
		_post_mats[i] = mat
		_post_nodes.append(post)


func _sync() -> void:
	_cargo.visible = mounted() and not done()
	if done():
		_cargo.visible = true
		if _hoist_hook and not _arriving:
			_cargo.global_position = _hoist_hook.global_position + Vector3.DOWN * 0.6
	_smoke.emitting = jammed
	for i in _post_mats:
		var on := powered(i)
		var m: StandardMaterial3D = _post_mats[i]
		m.albedo_color = (TEAL if on else AMBER).darkened(0.4)
		m.emission = TEAL if on else AMBER
		m.emission_energy_multiplier = 2.5 if on else 1.2


func _box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, solid := false) -> void:
	gw._box(pos, size, mat, solid, parent)
