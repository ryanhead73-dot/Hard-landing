class_name Landmarks
extends Node3D
## The Kettle's big shapes (X2.7), so that every direction from Kestrel reads differently and a
## player can steer by them:
##   The Split: two leaning basalt spires either side of the canyon to the Shatterlands, with
##     violet fungus spilling over their crowns. It's the one notch in the rim, and the one
##     colour from the other side, long before Juno can go through.
##   The Chimney: a geyser on a mound of pale sinter between Kestrel and the relay. It erupts on
##     a slow cycle (`Geyser`), and standing on the vent when it goes throws Juno high.
## Built after the regions, since the Split stands round the canyon gate.

const VIOLET := Color("7f6bd6")
const VIOLET_PALE := Color("a49cff")
const BASALT := Color("1b1d1f")
const CHIMNEY_AT := Vector2(-21.0, 32.0)
## The spires, in the gate's frame (-Z leads out of the basin): x, z, height, lean (radians).
const SPIRES := [
	[-10.5, -9.0, 40.0, -0.10],
	[10.0, -8.0, 33.0, 0.13],
]

var main: Node
var split: Node3D
var chimney: Geyser
var _rock: StandardMaterial3D
var _caps: Array[StandardMaterial3D] = []


func setup(m: Node) -> void:
	main = m
	name = "Landmarks"
	_rock = StandardMaterial3D.new()
	_rock.albedo_color = BASALT
	_rock.roughness = 0.85
	_build_split()
	chimney = Geyser.new()
	chimney.name = "Chimney"
	add_child(chimney)
	chimney.setup(main, Vector3(CHIMNEY_AT.x, main.site.height_at(CHIMNEY_AT.x, CHIMNEY_AT.y), CHIMNEY_AT.y))


## The landmarks the map names: always shown, since they're what the player steers by.
func map_marks() -> Array:
	return [
		{"pos": split.global_position, "label": "The Split"},
		{"pos": chimney.global_position, "label": "The Chimney"},
	]


## Each spire is a bundle of hexagonal columns, tallest in the middle, leaning away from the cut.
func _build_split() -> void:
	var gate_pos: Vector3 = RegionDB.get_region("shatterlands")["gate_pos"]
	split = Node3D.new()
	split.name = "TheSplit"
	add_child(split)
	split.position = Vector3(gate_pos.x, 0.0, gate_pos.z)
	split.rotation.y = atan2(-gate_pos.x, -gate_pos.z)
	for i in 3:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("1a1426")
		m.emission_enabled = true
		m.emission = VIOLET.lerp(VIOLET_PALE, i * 0.5)
		m.emission_energy_multiplier = 1.6 + i * 0.6
		m.roughness = 0.6
		_caps.append(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4471
	for s in SPIRES:
		_spire(rng, float(s[0]), float(s[1]), float(s[2]), float(s[3]))


func _spire(rng: RandomNumberGenerator, x: float, z: float, height: float, lean: float) -> void:
	var base := split.to_global(Vector3(x, 0.0, z))
	var ground: float = main.site.height_at(base.x, base.z) - 1.5
	var spire := Node3D.new()
	spire.position = Vector3(x, ground, z)
	spire.rotation = Vector3(0.0, 0.0, lean)
	split.add_child(spire)
	# Columns: a fat core and a ring of shorter ones, so the top steps like the rim's basalt.
	var cols := 7
	for i in cols:
		var a := TAU * i / float(cols - 1)
		var r := 0.0 if i == 0 else rng.randf_range(1.6, 2.4)
		var h := height if i == 0 else height * rng.randf_range(0.45, 0.85)
		var radius := 2.2 if i == 0 else rng.randf_range(1.0, 1.5)
		var col := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.radial_segments = 6
		mesh.rings = 1
		mesh.top_radius = radius * 0.8
		mesh.bottom_radius = radius
		mesh.height = h
		col.mesh = mesh
		col.material_override = _rock
		col.position = Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		col.rotation.y = rng.randf() * TAU
		spire.add_child(col)
		# Fungus crowns the tallest columns and drips down their outer faces.
		if i == 0 or h > height * 0.7:
			_crown(rng, spire, col.position + Vector3(0.0, h * 0.5, 0.0), radius, i == 0)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 3.6
	cyl.height = height
	shape.shape = cyl
	shape.position.y = height * 0.5
	body.add_child(shape)
	spire.add_child(body)


func _crown(rng: RandomNumberGenerator, parent: Node3D, top: Vector3, radius: float, big: bool) -> void:
	var n := 5 if big else 2
	for i in n:
		var cap := MeshInstance3D.new()
		var s := SphereMesh.new()
		var r := (radius * 2.2 if big else radius * 1.4) * rng.randf_range(0.7, 1.0) * (1.0 - i * 0.12)
		s.radius = r
		s.height = r * 0.55
		s.radial_segments = 12
		s.rings = 4
		cap.mesh = s
		cap.material_override = _caps[mini(i, _caps.size() - 1)]
		var a := rng.randf() * TAU
		cap.position = top + Vector3(cos(a) * radius * 0.5 * i * 0.4, -i * rng.randf_range(1.2, 2.6), sin(a) * radius * 0.5 * i * 0.4)
		parent.add_child(cap)
