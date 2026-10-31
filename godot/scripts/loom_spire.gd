@tool
class_name LoomSpire
extends ExpeditionSite
## Where the Loom breaks the surface: a glassy basalt floor, a ring of standing stones and the
## spire, veined with the same teal as the moss and the scuttlers. Ilse Marrow's camp is at its
## foot, with the nav core she tuned to the pulses. The spire sends a ring of force out every few
## seconds: jump it. The approach faces +Z.

const SPIRE := Vector3(0.0, 0.0, -6.0)

var pulse: LoomPulse
var _veins: StandardMaterial3D


func _configure() -> void:
	component_id = "nav_core"
	component_pos = Vector3(0.0, 1.35, -2.0)
	component_stand = Vector3(0.0, 0.0, -0.7)
	spawn_pts = [
		Vector3(-9.0, 0.3, 4.0), Vector3(9.0, 0.3, 4.0), Vector3(-12.0, 0.3, -6.0), Vector3(12.0, 0.3, -6.0),
		Vector3(-8.0, 0.3, -15.0), Vector3(8.0, 0.3, -15.0), Vector3(0.0, 0.3, -18.0), Vector3(0.0, 0.3, 9.0),
	]
	ambush_pts = [
		Vector3(-14.0, 0.3, 12.0), Vector3(14.0, 0.3, 12.0), Vector3(0.0, 0.3, 18.0),
		Vector3(-17.0, 0.3, 0.0), Vector3(17.0, 0.3, 0.0),
	]
	spawn_kinds = ["", "", "spitter", "spitter", "ram", "", "", ""]
	ambush_kinds = ["", "", "spitter", "", ""]
	crate_pts = [Vector3(-6.0, 0.0, 4.0), Vector3(7.0, 0.0, 1.0), Vector3(-9.0, 0.0, -12.0)]
	crate_scrap = 16
	beacon_pos = SPIRE + Vector3(0.0, 26.5, 0.0)
	beacon_color = Color("3fd1b5")
	beacon_period = 3.0
	beacon_on = 1.0
	mission = _mission()


## Where the Warden surfaces: behind the spire.
func warden_point() -> Vector3:
	return to_global(SPIRE + Vector3(0.0, 0.5, -9.0))


func _build_site() -> void:
	var glass := _mat(Color("101416"), 0.25, 0.3)
	var stone := _mat(Color("1b1d1f"), 0.7)
	_veins = _emissive(Color("3fd1b5"), 1.5)
	_disc(Vector3(0.0, 0.0, -4.0), 20.0, 0.03, glass)
	# The spire: stacked, tapering prisms with glowing seams.
	var y := 0.0
	var r := 2.6
	for i in 6:
		var h := 4.4
		var seg := _column(SPIRE + Vector3(0.0, y, 0.0), r, h, stone, 6)
		seg.rotation.y = i * 0.35
		_mesh_box(Vector3(r * 2.05, 0.12, 0.25), SPIRE + Vector3(0.0, y + h, 0.0), _veins).rotation.y = i * 0.35
		y += h
		r *= 0.8
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		var vein := _mesh_box(Vector3(0.12, 14.0, 0.12), SPIRE + Vector3(cos(a) * 2.5, 7.0, sin(a) * 2.5), _veins)
		vein.rotation = Vector3(sin(a) * 0.12, 0.0, -cos(a) * 0.12)
	# Ring of standing stones.
	for i in 9:
		var a := TAU * i / 9.0 + 0.2
		var p := SPIRE + Vector3(cos(a) * 13.0, 0.0, sin(a) * 13.0)
		if p.z > 4.0 and absf(p.x) < 4.0:
			continue
		var stone_block := _static_box(Vector3(1.6, 7.0, 0.9), p + Vector3(0.0, 3.3, 0.0), stone)
		stone_block.rotation = Vector3(0.0, -a, 0.06)
		_mesh_box(Vector3(0.14, 5.0, 0.94), p + Vector3(0.0, 3.6, 0.0), _veins).rotation = stone_block.rotation
	_build_camp()
	if not Engine.is_editor_hint():
		pulse = LoomPulse.new()
		pulse.name = "LoomPulse"
		pulse.position = SPIRE
		pulse.glow = _veins
		add_child(pulse)


## Ilse's camp: a lean-to, a work bench and the pedestal she built for the core.
func _build_camp() -> void:
	var canvas := _mat(Color("8a7f66"), 0.95)
	var metal := _mat(Color("3a3f43"), 0.5, 0.6)
	var tent := _static_box(Vector3(3.0, 0.1, 2.6), Vector3(6.5, 1.3, -1.5), canvas)
	tent.rotation.z = 0.5
	_static_box(Vector3(0.1, 1.9, 0.1), Vector3(7.6, 0.95, -0.3), metal)
	_static_box(Vector3(0.1, 1.9, 0.1), Vector3(7.6, 0.95, -2.7), metal)
	_static_box(Vector3(1.8, 0.8, 0.7), Vector3(-4.0, 0.4, -1.0), metal)
	_mesh_box(Vector3(0.6, 0.4, 0.05), Vector3(-4.0, 1.0, -1.3), _emissive(Color("ffb24d"), 0.6))
	_light(Vector3(-3.0, 2.0, 0.0), Color("ffd9a0"), 0.6, 6.0)


func _build_component_visual(holder: Node3D) -> void:
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.2
	sphere.height = 0.4
	core.mesh = sphere
	core.material_override = _emissive(Color("3fd1b5"), 3.0)
	holder.add_child(core)
	for i in 3:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 0.26
		torus.outer_radius = 0.3
		ring.mesh = torus
		ring.material_override = _mat(Color("9aa0a3"), 0.35, 0.8)
		ring.rotation = Vector3(i * 1.05, i * 0.6, 0.0)
		holder.add_child(ring)

## The Loom's mission: tune the three resonators round the spire, each only in the quiet between
## pulses. Then the core comes free, and the Warden rises.
func _mission() -> Array:
	var H := Story.HOB
	return [
		{
			"type": "pulse", "text": "Tune the resonators between the Loom's pulses",
			"devices": [
				{"pos": Vector3(-7.5, 0.0, -3.0), "kind": "resonator", "label": "Tune the resonator", "hold": 2.5},
				{"pos": Vector3(7.5, 0.0, -4.0), "kind": "resonator", "label": "Tune the resonator", "hold": 2.5},
				{"pos": Vector3(0.0, 0.0, -14.5), "kind": "resonator", "label": "Tune the resonator", "hold": 2.5},
			],
			"say": [[H, "Ilse sealed the core with her resonators. They have to be tuned to the beat, and a pulse in the middle of tuning undoes it."], [H, "Wait for a ring to pass, jump it, then tune. You have a few seconds each time."]],
			"done_say": [[H, "All three are singing. The core is free. Juno... the ground's moving."]],
		},
	]
