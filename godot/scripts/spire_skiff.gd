@tool
class_name SpireSkiff
extends ExpeditionSite
## The survey skiff Lark, perched on a mesa of basalt columns. A route of fallen slabs climbs three
## platforms to the top, where the canopy glazing panel sits in the skiff's cradle. The approach
## faces +Z. Scuttlers hold the ledges; falling off means climbing again.

## Platform tops: [centre (x, z), radius, height].
const PLATFORMS := [
	[Vector2(-5.0, -2.0), 2.2, 1.6],
	[Vector2(3.0, -5.0), 2.2, 3.2],
	[Vector2(0.0, -12.0), 4.5, 4.8],
]
## The climb: each slab starts on the surface below and tops out exactly at the edge of the
## platform above, so there is no lip to catch on.
const ROUTE := [
	[Vector3(-5.0, 0.0, 5.0), Vector3(-5.0, 1.6, 0.2)],
	[Vector3(-3.2, 1.6, -3.0), Vector3(0.905, 3.2, -4.324)],
	[Vector3(3.79, 3.2, -3.16), Vector3(1.776, 4.8, -7.855)],
]
const TOP := 4.8
## How far the Lark lurches toward the brink each time the anchor clock runs out.
const SLIP_STEP := Vector3(-0.12, -0.03, -0.18)

var _skiff: Node3D


func _configure() -> void:
	component_id = "glazing"
	component_pos = Vector3(1.2, TOP + 1.35, -12.5)
	component_stand = Vector3(1.2, TOP, -11.2)
	spawn_pts = [
		Vector3(-8.0, 0.3, 8.0), Vector3(8.0, 0.3, 6.0), Vector3(7.0, 0.3, -2.0),
		Vector3(3.0, 3.5, -5.0), Vector3(-1.5, 5.1, -11.0),
	]
	ambush_pts = [Vector3(-10.0, 0.3, 10.0), Vector3(10.0, 0.3, 10.0), Vector3(0.0, 0.3, 14.0), Vector3(-8.0, 0.3, -6.0)]
	spawn_kinds = ["", "", "", "spitter", "spitter"]
	ambush_kinds = ["", "", "spitter", ""]
	crate_pts = [Vector3(6.0, 0.0, 4.0), Vector3(-5.8, 1.6, -2.6), Vector3(-1.8, TOP, -9.8)]
	crate_scrap = 12
	beacon_pos = Vector3(-2.6, 9.2, -15.0)
	beacon_color = Color("ffd23a")
	beacon_period = 1.3
	beacon_on = 0.35
	mission = _mission()


## Where to walk, in order, to climb from the foot of the route to the panel (local space).
func climb_path() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for leg in ROUTE:
		out.append(to_global(leg[0]))
		out.append(to_global(leg[1]))
	out.append(component_point())
	return out


func _build_site() -> void:
	var basalt := _mat(Color("17191b"), 0.75)
	var slate := _mat(Color("2c3236"), 0.85)
	var rubble := _mat(Color("26292b"), 0.95)
	_disc(Vector3.ZERO, 18.0, 0.02, rubble)
	for p in PLATFORMS:
		var c: Vector2 = p[0]
		_column(Vector3(c.x, 0.0, c.y), p[1], p[2], basalt)
	for leg in ROUTE:
		_slab(leg[0], leg[1], 2.2, 0.4, slate, 0.5)
	# Free-standing columns around the mesa: cover, and the silhouette seen from Kestrel.
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 22:
		var a := TAU * i / 22.0 + rng.randf_range(-0.1, 0.1)
		var d := rng.randf_range(8.5, 16.0)
		var p := Vector3(cos(a) * d, 0.0, sin(a) * d - 4.0)
		# Keep the foot of the climb and the approach open.
		if p.z > 1.0 and absf(p.x + 5.0) < 3.5 or _blocks_route(Vector2(p.x, p.z), 1.4):
			continue
		_column(p, rng.randf_range(0.7, 1.3), rng.randf_range(3.0, 13.0), basalt)
	_build_skiff()


## True if a column at this spot would sit on a platform or across the climb.
func _blocks_route(at: Vector2, radius: float) -> bool:
	for p in PLATFORMS:
		if at.distance_to(p[0]) < p[1] + radius + 0.6:
			return true
	for leg in ROUTE:
		var a := Vector2(leg[0].x, leg[0].z)
		var b := Vector2(leg[1].x, leg[1].z)
		var t := clampf((at - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		if at.distance_to(a.lerp(b, t)) < radius + 1.8:
			return true
	return false


func _build_skiff() -> void:
	var paint := _mat(Color("d8d2bf"), 0.7)
	var stripe := _mat(Color("3f6f8a"), 0.6)
	var dark := _mat(Color("24282b"), 0.5)
	var skiff := Node3D.new()
	_skiff = skiff
	skiff.name = "SkiffLark"
	skiff.position = Vector3(-2.2, TOP, -14.2)
	skiff.rotation = Vector3(0.12, 0.7, -0.08)
	add_child(skiff)
	_static_box(Vector3(2.2, 1.5, 6.0), Vector3(0.0, 0.9, 0.0), paint, skiff)
	_mesh_box(Vector3(2.24, 0.25, 6.04), Vector3(0.0, 0.9, 0.0), stripe, skiff)
	# Empty canopy frame at the nose: the pane you came for is in the cradle.
	_mesh_box(Vector3(1.8, 0.08, 1.4), Vector3(0.0, 1.9, -2.2), dark, skiff)
	_mesh_box(Vector3(0.08, 0.7, 1.4), Vector3(-0.86, 1.55, -2.2), dark, skiff)
	_mesh_box(Vector3(0.08, 0.7, 1.4), Vector3(0.86, 1.55, -2.2), dark, skiff)
	# Stub wings and a tail fin carrying the flare.
	_mesh_box(Vector3(5.5, 0.15, 1.6), Vector3(0.0, 0.7, 0.6), paint, skiff)
	_mesh_box(Vector3(0.15, 1.8, 1.4), Vector3(0.0, 2.4, 2.4), paint, skiff)
	_light(Vector3(1.2, TOP + 2.2, -11.6), Color("ffe2a8"), 0.8, 6.0)


func _build_component_visual(holder: Node3D) -> void:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.9, 0.95, 0.55)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.emission_enabled = true
	glass.emission = Color("bfe3ea")
	glass.emission_energy_multiplier = 0.4
	_mesh_box(Vector3(1.0, 0.8, 0.06), Vector3.ZERO, glass, holder)
	_mesh_box(Vector3(1.08, 0.06, 0.1), Vector3(0.0, 0.42, 0.0), _mat(Color("7d8c84"), 0.5, 0.6), holder)
	_mesh_box(Vector3(1.08, 0.06, 0.1), Vector3(0.0, -0.42, 0.0), _mat(Color("7d8c84"), 0.5, 0.6), holder)

## The skiff's mission: climb to the Lark, then lock her winch anchors before she slides off the
## brink, so the glazing can come out of its cradle.
func _mission() -> Array:
	var H := Story.HOB
	return [
		{
			"type": "reach", "pos": component_stand, "radius": 4.0,
			"text": "Climb the basalt spires to the skiff Lark",
			"say": [[H, "The Lark's right on the edge up there. Climb the slabs, and please don't test gravity."]],
		},
		{
			"type": "activate", "text": "Lock the Lark's winch anchors before she slides",
			"pos": Vector3(0.0, TOP, -12.0), "timer": 40.0, "timer_range": 7.0, "timer_bar": "THE LARK IS SLIPPING",
			"harass": ["skimmer", "skimmer"],
			"harass_pts": [Vector3(14.0, TOP + 5.0, -16.0), Vector3(-13.0, TOP + 5.0, -6.0)],
			"devices": [
				{"pos": Vector3(3.2, TOP, -13.2), "kind": "winch", "label": "Lock the winch anchor", "hold": 2.0, "yaw": 0.6},
				{"pos": Vector3(-3.4, TOP, -10.2), "kind": "winch", "label": "Lock the winch anchor", "hold": 2.0, "yaw": 0.6},
				{"pos": Vector3(3.6, TOP, -10.4), "kind": "winch", "label": "Lock the winch anchor", "hold": 2.0, "yaw": -0.4},
			],
			"say": [
				[H, "She's moving! If that skiff goes over, the glazing goes with her. Lock all three winch anchors, fast."],
				[H, "Forty seconds, maybe. And something's circling the spires."],
			],
			"slip_text": "The Lark slid and tore the anchors loose. Lock them again.",
			"slip_say": [[H, "She slid! Anchors tore out. Again, and faster."]],
			"done_say": [[H, "Anchors hold. Lift the pane out gently."]],
		},
	]


## The anchor clock ran out: the Lark lurches toward the brink (never quite over it).
func on_slip(count: int) -> void:
	if _skiff == null:
		return
	var step := mini(count, 4)
	var to := Vector3(-2.2, TOP, -14.2) + SLIP_STEP * step
	var roll := -0.08 - 0.025 * step
	var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_skiff, "position", to, 0.6)
	tw.parallel().tween_property(_skiff, "rotation:z", roll, 0.6)
	Vfx.burst(get_tree().current_scene, to_global(to + Vector3(0.0, 0.3, 0.0)), Color("4a4540"), 28, 2.5, 0.12, 0.9, Vector3.UP, 80.0, -2.0)
