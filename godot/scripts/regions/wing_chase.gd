class_name WingChase
extends Node3D
## Repair 5, "Catch the ghost" (milestone B3): the wing-tip section, in the Shatterlands pocket,
## once Ferro-9's strut is on Reyes's hoist.
##
## Marigold had a compatible wing-tip section aboard, but a salvage tether robot has already
## taken it into the crags. The robot runs a fixed circuit east of the wreck (its tracks show it,
## the scanner's traces): three switchback legs between crag walls, then a long run back. It
## slows to a crawl at the three cable crossings, and bolts if Juno comes at it head-on. Two ways
## to take the panel: cut it off through a gap in the crag walls and grab it as it passes (or
## while it's on the cables), or power the decoy relay on the return leg, where it stops to feed
## and the panel is hers for the taking. Drifters gather off the return leg as the noisy robot
## first passes; Juno can fight them, keep clear, or shoot the robot's siren to pull them after
## it. The robot never escapes: it keeps running its circuit. Taking the panel sends it home with
## Reyes's runners: Game.deliver_component("wing_panel").
##
## Flags: wing_chase (started), wing_decoy (relay powered), wing_drifters (gathered once),
## marigold_wing (done). A load puts the robot back at the start of its circuit.

## The circuit (pocket-local). Cable crossings at the three turns marked true.
const CIRCUIT := [
	[Vector3(30.0, 0.0, -6.0), false], [Vector3(54.0, 0.0, -6.0), false], [Vector3(54.0, 0.0, -20.0), true],
	[Vector3(34.0, 0.0, -20.0), false], [Vector3(34.0, 0.0, -34.0), true], [Vector3(54.0, 0.0, -34.0), false],
	[Vector3(59.0, 0.0, -30.0), true], [Vector3(59.0, 0.0, 20.0), false], [Vector3(30.0, 0.0, 20.0), false],
]
## The crag walls between the switchback legs: [centre, size]. Each has a gap Juno can cut through.
const CRAGS := [
	[Vector3(36.5, 1.8, -13.0), Vector3(9.0, 3.6, 2.4)], [Vector3(49.0, 1.8, -13.0), Vector3(6.0, 3.6, 2.4)],
	[Vector3(39.5, 1.8, -27.0), Vector3(7.0, 3.6, 2.4)], [Vector3(52.5, 1.8, -27.0), Vector3(7.0, 3.6, 2.4)],
]
## The decoy relay beside the return leg, and where the drifters gather off it.
const DECOY := Vector3(45.0, 0.0, 22.6)
const DRIFTERS_AT := Vector3(54.0, 3.4, 4.0)
## Where Juno searches Marigold (Marigold's port flank, pocket-local).
const SEARCH := Vector3(8.6, 0.0, -9.0)
const SPEED := 5.2
const FLEE_SPEED := 8.5
const CABLE_SPEED := 1.0
const CABLE_TIME := 2.6
const FLEE_TIME := 3.0
## Head-on: Juno within this distance, inside this cone of its heading.
const SPOOK_RANGE := 9.0
const SPOOK_COS := 0.64
const GRAB_RANGE := 3.0
const DECOY_RANGE := 6.0
const DOCK_TIME := 12.0
const SIREN_TIME := 8.0
const SIREN_RANGE := 30.0
const USE_RANGE := 2.2
const AMBER := Color("e8a44e")

var scene: ShatterlandsThreshold
var robot: Node3D
var leg := 0
var along := 0.0
var flee := 0.0
var cable := 0.0
var docked := 0.0
var siren := 0.0
var spooks := 0
var laps := 0
var drifters: Array[Enemy] = []
var _cables_done: Array[bool] = []
var _panel: Node3D
var _beacon_mat: StandardMaterial3D
var _siren_mat: StandardMaterial3D
var _decoy_mat: StandardMaterial3D
var _tracks: MultiMeshInstance3D
var _t := 0.0


## Hit by a shot: the robot's siren goes off.
class Bot extends Node3D:
	var dead := false
	var velocity := Vector3.ZERO


func _ready() -> void:
	_build()
	_place()
	_sync()


func _exit_tree() -> void:
	Game.set_region_objective("")


func active() -> bool:
	return not done() and not Game.is_repaired("wing") and Game.flags.get("ferro_gear", false) == true


func done() -> bool:
	return Game.flags.get("marigold_wing", false) == true


func started() -> bool:
	return Game.flags.get("wing_chase", false) == true


func decoy_on() -> bool:
	return Game.flags.get("wing_decoy", false) == true


func search_pos() -> Vector3:
	return scene.to_global(SEARCH)


func decoy_pos() -> Vector3:
	return scene.to_global(DECOY)


func point(i: int) -> Vector3:
	return scene.to_global(CIRCUIT[i % CIRCUIT.size()][0])


func interaction(pos: Vector3) -> Dictionary:
	if not active():
		return {}
	if not started():
		if pos.distance_to(search_pos()) < USE_RANGE + 0.6:
			return {"label": "[E] Search Marigold for a wing-tip section", "action": start}
		return {}
	if pos.distance_to(robot.global_position) < GRAB_RANGE:
		return {"label": "[E] Take the wing-tip section off the tether robot", "action": grab}
	if not decoy_on() and pos.distance_to(decoy_pos()) < USE_RANGE + 0.4:
		return {"label": "[E] Power the decoy relay", "action": power_decoy}
	return {}


func start() -> void:
	if started():
		return
	Game.set_flag("wing_chase")
	leg = 0
	along = 0.0
	Sfx.play("scanner_ping", search_pos(), -4.0)
	scene._say(Story.WING_GONE)
	_sync()


func power_decoy() -> void:
	if decoy_on():
		return
	Game.set_flag("wing_decoy")
	Sfx.play("relay_two_note", decoy_pos(), -3.0)
	scene._say(Story.WING_DECOY)
	_sync()


func grab() -> void:
	if done() or not started():
		return
	Game.set_flag("marigold_wing")
	Sfx.play("repair_clunk", robot.global_position, 0.0)
	if not Game.is_repaired("wing"):
		Game.deliver_component(String(Campaign.get_repair("wing")["component"]))
	scene._say(Story.WING_TAKEN if docked > 0.0 else Story.WING_CAUGHT)
	siren = 0.0
	_end_siren()
	Game.set_region_objective("")
	_sync()


## Shot: the siren wails, and every drifter in earshot goes after the robot instead of Juno.
func trip_siren() -> void:
	if done() or not started():
		return
	siren = SIREN_TIME
	Sfx.play("hob_warning", robot.global_position, 2.0, 0.0)
	for e in _drifters_near():
		e.target = robot
		e.alert(false)


func _drifters_near() -> Array:
	var out := []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Drifter and not e.dead and (e as Node3D).global_position.distance_to(robot.global_position) < SIREN_RANGE:
			out.append(e)
	return out


func _end_siren() -> void:
	var main := scene.greenhouses._main() if scene.greenhouses else null
	for e in get_tree().get_nodes_in_group("enemies"):
		if e is Drifter and e.target == robot and main:
			e.target = main.player


func _process(delta: float) -> void:
	_t += delta
	if _beacon_mat:
		_beacon_mat.emission_energy_multiplier = 4.0 if fmod(_t, 0.9) < 0.2 else 0.5
	if _siren_mat:
		_siren_mat.emission_energy_multiplier = (6.0 if fmod(_t, 0.3) < 0.15 else 0.5) if siren > 0.0 else 0.3
	if siren > 0.0:
		siren -= delta
		if siren <= 0.0:
			_end_siren()
	if not active():
		return
	if started():
		_run(delta)
	Game.set_region_objective(objective())


func _run(delta: float) -> void:
	if docked > 0.0:
		docked -= delta
		if docked <= 0.0:
			Game.set_flag("wing_decoy", false)
			_sync()
		return
	var p := _player_pos()
	var heading := (point(leg + 1) - point(leg)).normalized()
	var to_p := p - robot.global_position
	to_p.y = 0.0
	# Head-on, it bolts.
	if flee <= 0.0 and cable <= 0.0 and to_p.length() < SPOOK_RANGE and to_p.normalized().dot(heading) > SPOOK_COS:
		flee = FLEE_TIME
		spooks += 1
		Sfx.play("scuttler_chitter", robot.global_position, -2.0)
	flee = maxf(0.0, flee - delta)
	cable = maxf(0.0, cable - delta)
	var spd := CABLE_SPEED if cable > 0.0 else (FLEE_SPEED if flee > 0.0 else SPEED)
	along += spd * delta / maxf(point(leg).distance_to(point(leg + 1)), 0.1)
	if along >= 1.0:
		along = 0.0
		leg = (leg + 1) % CIRCUIT.size()
		if leg == 0:
			laps += 1
		# At a cable crossing it slows to pick its way over.
		if CIRCUIT[leg][1]:
			cable = CABLE_TIME
			flee = 0.0
			Sfx.play("rifle_rail_align", robot.global_position, -6.0)
		# The first time it rattles down the return leg, drifters gather off it.
		if leg == 6 and not Game.flags.get("wing_drifters", false):
			_gather_drifters()
	_place()
	# Past the live decoy relay, it stops to feed.
	if decoy_on() and robot.global_position.distance_to(decoy_pos()) < DECOY_RANGE and leg == 7:
		docked = DOCK_TIME
		flee = 0.0
		robot.global_position = decoy_pos() + Vector3(-1.6, 0.0, -1.2)
		Sfx.play("relay_surge", decoy_pos(), -6.0)


func _gather_drifters() -> void:
	Game.set_flag("wing_drifters")
	var main := scene.greenhouses._main() if scene.greenhouses else null
	if main == null:
		return
	for k in 3:
		var e: Enemy = main.spawn_enemy("drifter", scene.to_global(DRIFTERS_AT + Vector3(k * 2.2 - 2.2, k * 0.4, k * 1.3)), "", scene)
		e.set("wander_radius", 3.0)
		drifters.append(e)
	scene._say(Story.WING_DRIFTERS)


func objective() -> String:
	if done():
		return ""
	if not started():
		return "Search the Marigold for a wing-tip section"
	if docked > 0.0:
		return "The tether robot's feeding at the decoy relay: take the panel (%d s)" % ceili(docked)
	if siren > 0.0:
		return "Its siren's pulling the drifters after it"
	if decoy_on():
		return "The decoy relay's live: the robot will stop there on its way past"
	return "Catch the tether robot: cut it off through the crags, or power the decoy relay"


func goal_point() -> Vector3:
	if not started():
		return search_pos() + Vector3.UP
	return robot.global_position + Vector3.UP * 1.5


func _place() -> void:
	if robot == null:
		return
	if done():
		robot.global_position = decoy_pos() + Vector3(-1.6, 0.0, -1.2)
		return
	if not started():
		robot.global_position = point(0)
		return
	var a := point(leg)
	var b := point(leg + 1)
	robot.global_position = a.lerp(b, clampf(along, 0.0, 1.0))
	var d := b - a
	if Vector2(d.x, d.z).length() > 0.1:
		robot.rotation.y = atan2(-d.x, -d.z)


func _player_pos() -> Vector3:
	var main := scene.greenhouses._main() if scene.greenhouses else null
	if main == null or main.get("player") == null:
		return Vector3.INF
	return main.player.global_position


func _build() -> void:
	var dark := scene._mat(Color("3a3f44"), 0.5)
	# The crag walls between the switchbacks, gaps and all.
	for c in CRAGS:
		scene._box(c[0], c[1], scene._basalt(5.0), true)
	# Cable crossings: two posts and a sagging cable over the track at each marked turn.
	var cable_mat := scene._mat(Color("c9c3b0"), 0.4)
	for i in CIRCUIT.size():
		if not CIRCUIT[i][1]:
			continue
		var at: Vector3 = CIRCUIT[i][0]
		for side in [-1.0, 1.0]:
			scene._box(at + Vector3(side * 1.8, 1.0, side * 1.8), Vector3(0.25, 2.0, 0.25), dark, true)
		# The cable: a thin bar sagging between the posts, across the track.
		scene._box(at + Vector3(0.0, 1.6, 0.0), Vector3(0.06, 0.06, 5.1), cable_mat, false, scene, Basis(Vector3.UP, PI * 0.25))
	# The tracks it has worn: faint amber marks the length of the circuit.
	var marks: Array[Vector3] = []
	for i in CIRCUIT.size():
		var a: Vector3 = CIRCUIT[i][0]
		var b: Vector3 = CIRCUIT[(i + 1) % CIRCUIT.size()][0]
		var n := int(a.distance_to(b) / 2.5)
		for k in n:
			marks.append(a.lerp(b, float(k) / n) + Vector3(0.0, 0.03, 0.0))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var dm := BoxMesh.new()
	dm.size = Vector3(0.5, 0.02, 0.22)
	mm.mesh = dm
	mm.instance_count = marks.size()
	for k in marks.size():
		mm.set_instance_transform(k, Transform3D(Basis(Vector3.UP, k * 0.37), marks[k]))
	_tracks = MultiMeshInstance3D.new()
	_tracks.multimesh = mm
	_tracks.material_override = scene._glow(AMBER, 0.5)
	_tracks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	scene.add_child(_tracks)
	# The decoy relay: a squat box with a lamp, wired to nothing that matters.
	scene._box(DECOY + Vector3(0.0, 0.5, 0.0), Vector3(1.0, 1.0, 0.8), scene._mat(ShatterScene.OXIDE, 0.55), true)
	var lamp := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.16
	lm.height = 0.32
	lamp.mesh = lm
	_decoy_mat = StandardMaterial3D.new()
	_decoy_mat.emission_enabled = true
	lamp.material_override = _decoy_mat
	scene.add_child(lamp)
	lamp.position = DECOY + Vector3(0.0, 1.2, 0.0)
	# A scrap marker at Marigold's flank, where the section was stowed.
	scene._box(SEARCH + Vector3(0.6, 0.35, -0.8), Vector3(1.6, 0.7, 1.0), scene._mat(ShatterScene.HULL.darkened(0.2), 0.6), true)
	# The robot: a squat tracked hauler with the panel strapped on, a beacon and a siren.
	robot = Bot.new()
	robot.name = "TetherRobot"
	robot.set_meta("no_batch", true)
	scene.add_child(robot)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	robot.add_child(body)
	var shape := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.2, 0.9, 1.6)
	shape.shape = bs
	shape.position.y = 0.6
	body.add_child(shape)
	body.set_meta("on_hit", trip_siren)
	scene._box(Vector3(0.0, 0.6, 0.0), Vector3(1.2, 0.7, 1.6), scene._mat(ShatterScene.HULL.darkened(0.15), 0.5), false, robot)
	scene._box(Vector3(0.0, 0.22, 0.0), Vector3(1.6, 0.44, 1.8), scene._mat(Color("2a2b2d"), 0.9), false, robot)
	_panel = Node3D.new()
	robot.add_child(_panel)
	scene._box(Vector3(0.0, 1.12, 0.2), Vector3(2.4, 0.1, 1.4), scene._mat(ShatterScene.HULL, 0.55), false, _panel)
	var beacon := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.14
	bm.height = 0.28
	beacon.mesh = bm
	_beacon_mat = scene._glow(AMBER, 1.0)
	beacon.material_override = _beacon_mat
	beacon.position = Vector3(-0.4, 1.4, -0.6)
	robot.add_child(beacon)
	var horn := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.18
	hm.bottom_radius = 0.1
	hm.height = 0.3
	horn.mesh = hm
	_siren_mat = scene._glow(Color("ff5a4a"), 0.3)
	horn.material_override = _siren_mat
	horn.position = Vector3(0.4, 1.35, -0.6)
	robot.add_child(horn)


func _sync() -> void:
	robot.visible = started() or done()
	_tracks.visible = started() and not done()
	_panel.visible = not done()
	_decoy_mat.albedo_color = (AMBER if decoy_on() else Color("3a3f44")).darkened(0.3)
	_decoy_mat.emission = AMBER
	_decoy_mat.emission_energy_multiplier = 2.5 if decoy_on() else 0.0
	_place()
