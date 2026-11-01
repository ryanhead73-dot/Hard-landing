class_name RouteDressing
extends RefCounted
## The opening expedition's walk from Kestrel to the relay station, dressed around what the
## player does there (CrashSite builds it after the terrain, in its own space = world space).
##
## Beats, ship to relay (see docs/OPENING_EXPEDITION.md):
## 1. The threshold: two basalt mounds topped with columns frame the way out from the crash.
## 2. The hollow: wet slate among steaming pools, the dead geothermal wellhead the relay ran on.
##    The old power line climbs from it towards the relay: follow the pylons. One is down, its
##    cables in the mud, which is why the station is on its backup generator.
## 3. The climb: the line goes up onto the relay's basalt shelf; the mast's red beacon shows over
##    the lip the whole way, the compound itself only at the crest.
## 4. The return: low basalt cover where the ambush comes from on the walk home with the cell.

## The walk's axis: from the ship to the relay (world XZ).
const RELAY := Vector2(-60.0, 58.0)
## Unit normal to the walk, pointing south-east (the side the return ambush comes from).
const SE := Vector2(0.695, 0.719)
## Pylon line: the wellhead, then the towers ("down" is the toppled one). [t along the walk,
## metres to the north-west of it].
const WELLHEAD_AT := [0.5, 7.0]
const PYLONS := [[0.62, 7.0, "up"], [0.73, 7.0, "down"], [0.84, 6.5, "up"]]
## Where the line lands at the relay: a junction pole on the station pad (relay site space).
const RELAY_DROP := Vector3(8.0, 0.0, 4.0)
## Cable attach points on a standing pylon (local), and on the wellhead's line pole.
const PYLON_PINS := [Vector3(-1.8, 6.46, 0.0), Vector3(1.8, 6.46, 0.0)]
const WELLHEAD_PINS := [Vector3(0.7, 4.62, -0.75), Vector3(2.0, 4.62, -0.75)]

static var _cable_mat: StandardMaterial3D


static func build(site: CrashSite) -> Node3D:
	var root := Node3D.new()
	root.name = "RouteToRelay"
	site.add_child(root)
	var ground := site.height_at
	_power_line(root, ground, site)
	_threshold(root, ground)
	_cover(root, ground)
	_shelf_edge(root, ground)
	return root


static func walk_point(t: float, nw: float) -> Vector3:
	var p := RELAY * t - SE * nw
	return Vector3(p.x, 0.0, p.y)


static func cable_material() -> StandardMaterial3D:
	if _cable_mat == null:
		_cable_mat = StandardMaterial3D.new()
		_cable_mat.albedo_color = Color("16181a")
		_cable_mat.roughness = 0.45
		_cable_mat.metallic = 0.3
	return _cable_mat


static func _on_ground(p: Vector3, ground: Callable, sink := 0.0) -> Vector3:
	return Vector3(p.x, float(ground.call(p.x, p.z)) - sink, p.z)


static func _power_line(root: Node3D, ground: Callable, site: CrashSite) -> void:
	var dir := Vector3(RELAY.x, 0.0, RELAY.y).normalized()
	var yaw := atan2(dir.x, dir.z)
	var well := _on_ground(walk_point(WELLHEAD_AT[0], WELLHEAD_AT[1]), ground, 0.15)
	var wellhead := _prop(root, "prop_wellhead", well, yaw + PI * 0.5, Vector3(3.6, 1.2, 3.0))
	# Steam leaks from the capped bore: it still runs hot, it just isn't generating.
	site.vent_steam(well + Vector3(0.0, 2.6, 0.0), 0.3)
	var prev_pins: Array = []
	for pin in WELLHEAD_PINS:
		prev_pins.append(wellhead.to_global(pin))
	var prev_down := false
	for i in PYLONS.size():
		var spec: Array = PYLONS[i]
		var at := _on_ground(walk_point(spec[0], spec[1]), ground, 0.1)
		if spec[2] == "down":
			var fallen := _prop(root, "prop_pylon_down", at, yaw + 0.25, Vector3(2.4, 1.6, 2.4))
			var length := CollisionShape3D.new()
			var lbox := BoxShape3D.new()
			lbox.size = Vector3(2.0, 1.4, 8.0)
			length.shape = lbox
			length.position = Vector3(0.0, 0.7, 5.2)
			fallen.add_child(length)
			# The spans either side snapped when it fell: one trails from the last tower's
			# insulators into the mud, the next hangs from the far tower back towards it.
			for p in prev_pins:
				Cable.snapped(root, p, at, ground, 5.5, 0.025, cable_material())
			prev_down = true
			prev_pins = [at]
			continue
		var tower := _prop(root, "prop_pylon", at, yaw, Vector3(2.3, 2.0, 2.3))
		var pins: Array = []
		for pin in PYLON_PINS:
			pins.append(tower.to_global(pin))
		if prev_down:
			for p in pins:
				Cable.snapped(root, p, prev_pins[0], ground, 4.0, 0.025, cable_material())
		else:
			for k in pins.size():
				Cable.span(root, prev_pins[k], pins[k], 0.9, 0.025, cable_material())
		prev_down = false
		prev_pins = pins
	# Last tower to the relay: a span down to the junction pole on the station pad.
	var relay := root.get_tree().root.find_child("RelayStation", true, false) as Node3D if root.is_inside_tree() else null
	var drop := Vector3.ZERO
	if relay:
		drop = relay.to_global(RELAY_DROP)
	else:
		# Built before the station (the editor): the station's transform from main.tscn.
		var basis := Basis(Vector3(-0.688, 0.0, -0.725), Vector3.UP, Vector3(0.725, 0.0, -0.688))
		drop = Vector3(RELAY.x, CrashSite.RELAY_SHELF, RELAY.y) + basis * RELAY_DROP
	var pole := _prop(root, "prop_junction", Vector3(drop.x, float(ground.call(drop.x, drop.z)), drop.z), yaw, Vector3(0.4, 1.4, 0.4))
	for k in prev_pins.size():
		Cable.span(root, prev_pins[k], pole.to_global(Vector3(-0.15 + 0.3 * k, 1.3, 0.0)), 0.6, 0.022, cable_material())


## Two mounds frame the way out from the crash, each crowned with columns.
static func _threshold(root: Node3D, ground: Callable) -> void:
	for spec in [[Vector3(-22.5, 0.0, 11.5), "basalt_cluster_1", 1.1, 0.4], [Vector3(-7.5, 0.0, 25.0), "basalt_cluster_0", 1.25, 2.1]]:
		WorldProps.place(root, spec[1], _on_ground(spec[0], ground, 0.6), spec[3], spec[2])


## Low basalt where the return ambush comes from: cover for the walk home with the cell.
static func _cover(root: Node3D, ground: Callable) -> void:
	for spec in [[0.65, -4.5, "basalt_step_0", 0.9, 0.3], [0.45, 4.5, "boulder_1", 1.25, 1.2], [0.25, -4.8, "boulder_2", 1.15, 2.4],
			[0.78, 5.0, "basalt_step_0", 0.8, 2.0], [0.56, -6.5, "boulder_0", 0.9, 0.6]]:
		var at := walk_point(spec[0], spec[1])
		WorldProps.place(root, spec[2], _on_ground(at, ground, 0.15), spec[4], spec[3])


## Columns round the relay shelf's flanks and back, keeping the approach from the ship open:
## they wall the fight in and break the long sightlines across the pad.
static func _shelf_edge(root: Node3D, ground: Callable) -> void:
	var toward_ship := (-RELAY).normalized()
	var props := ["basalt_cluster_0", "basalt_cluster_2", "basalt_cluster_1", "basalt_cluster_2", "basalt_cluster_0"]
	var angles := [deg_to_rad(80.0), deg_to_rad(125.0), PI, deg_to_rad(-125.0), deg_to_rad(-80.0)]
	for i in angles.size():
		var d := toward_ship.rotated(angles[i]) * (26.0 + (i % 2) * 2.5)
		var at := Vector3(RELAY.x + d.x, 0.0, RELAY.y + d.y)
		WorldProps.place(root, props[i], _on_ground(at, ground, 0.5), float(i) * 1.7, 1.2 + (i % 3) * 0.2)


static func _prop(root: Node3D, model: String, at: Vector3, yaw: float, solid: Vector3) -> Node3D:
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	body.name = model.to_pascal_case()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = solid
	shape.shape = box
	shape.position.y = solid.y * 0.5
	body.add_child(shape)
	body.position = at
	body.rotation.y = yaw
	root.add_child(body)
	Rig.spawn(model, body)
	return body
