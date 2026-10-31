@tool
class_name RelayStation
extends ExpeditionSite
## Abandoned relay station: the first expedition. One building holds the aux power cell; broken
## walls, a tipped container and crates give cover for fights on the approach. The doorway faces
## +Z. The mast beacon makes the site findable from Kestrel.

const CELL_POSITION := Vector3(0.0, 1.35, -7.6)
const CRATE_SCRAP := 10

var _station_lights: Array[OmniLight3D] = []


func _configure() -> void:
	component_id = "aux_cell"
	component_pos = CELL_POSITION
	component_stand = Vector3(0.0, 0.0, -6.3)
	spawn_pts = [
		Vector3(-6.0, 0.3, 4.0), Vector3(6.0, 0.3, 5.0), Vector3(0.0, 0.3, 10.0),
		Vector3(-9.0, 0.3, -9.0), Vector3(9.0, 0.3, -10.0),
	]
	crate_pts = [Vector3(-3.8, 0.1, -3.2), Vector3(-8.0, 0.0, -1.2), Vector3(8.5, 0.0, 6.5), Vector3(3.5, 0.0, -10.4)]
	crate_scrap = CRATE_SCRAP
	beacon_pos = Vector3(6.0, 16.3, -8.0)
	beacon_color = Color("ff4030")
	beacon_period = 1.6
	mission = _mission()


func _build_site() -> void:
	_station_lights.clear()
	_build_pad_and_building()
	_build_cover()
	_build_mast()


## Backwards-compatible name for the cell pickup point.
func cell_point() -> Vector3:
	return component_point()


func _build_pad_and_building() -> void:
	_static_box(Vector3(26.0, 0.2, 24.0), Vector3(0.0, 0.0, -1.0), _mat(Color("4a4f52"), 0.95))
	var shell := CSGCombiner3D.new()
	shell.name = "Building"
	shell.use_collision = true
	add_child(shell)
	var wall := _mat(Color("8a8f86"), 0.9)
	var inner := _mat(Color("5c615c"), 0.9)
	_csg(shell, Vector3(10.0, 4.0, 7.0), Vector3(0.0, 2.0, -5.5), wall)
	_csg(shell, Vector3(9.6, 3.7, 6.6), Vector3(0.0, 1.95, -5.5), inner, true)
	_csg(shell, Vector3(2.0, 2.5, 0.8), Vector3(0.0, 1.35, -2.0), inner, true)
	_csg(shell, Vector3(2.0, 1.0, 0.8), Vector3(3.2, 1.9, -2.0), inner, true)
	_csg(shell, Vector3(2.0, 1.0, 0.8), Vector3(-3.2, 1.9, -2.0), inner, true)
	_csg(shell, Vector3(0.8, 2.3, 1.5), Vector3(5.0, 1.25, -5.8), inner, true)
	# Collapsed roof section lets a shaft of daylight onto the cell.
	_csg(shell, Vector3(3.0, 0.8, 3.0), Vector3(1.5, 4.0, -6.8), inner, true)
	var slab := _static_box(Vector3(3.0, 0.2, 2.6), Vector3(2.4, 0.9, -4.6), wall)
	slab.rotation = Vector3(0.5, 0.2, 0.3)
	_static_box(Vector3(0.6, 1.0, 3.0), Vector3(-4.4, 0.6, -6.0), _mat(Color("24282b"), 0.5))
	_static_box(Vector3(2.4, 1.0, 0.6), Vector3(-2.5, 0.6, -8.5), _mat(Color("24282b"), 0.5))
	_static_box(Vector3(1.6, 0.6, 0.05), Vector3(-2.5, 1.6, -8.75), _emissive(Color("3fd1b5"), 0.4))


func _build_cover() -> void:
	# Jersey barriers and a tipped shipping container (modelled props over box collision).
	_prop("prop_barrier", Vector3(4.0, 1.2, 0.4), Vector3(-7.5, 0.7, 3.0))
	_prop("prop_barrier", Vector3(5.0, 1.2, 0.4), Vector3(7.0, 0.7, 1.0), Vector3(0.0, PI * 0.5, 0.0))
	_prop("prop_barrier", Vector3(5.0, 1.1, 0.4), Vector3(-1.5, 0.65, 7.0), Vector3(0.0, 0.25, 0.0))
	_prop("prop_barrier", Vector3(3.0, 1.0, 0.4), Vector3(10.5, 0.6, -6.0), Vector3(0.0, -0.6, 0.0))
	_prop("prop_container", Vector3(6.0, 2.6, 2.4), Vector3(-10.0, 1.3, -5.0), Vector3(0.0, 0.3, 0.08))
	_prop("prop_generator", Vector3(2.4, 1.6, 1.3), Vector3(5.6, 0.9, -12.2), Vector3(0.0, 0.1, 0.0))
	_prop("prop_pipes", Vector3(4.0, 0.9, 1.3), Vector3(-8.5, 0.55, -12.0))
	for p in [Vector3(3.0, 0.6, 4.5), Vector3(9.0, 0.6, -3.0), Vector3(-5.5, 0.6, 9.0), Vector3(4.2, 0.6, 9.5)]:
		var crate := _static_box(Vector3(1.1, 1.1, 1.1), p, _mat(Color("6b6a52"), 0.9))
		crate.rotation.y = p.x


## The backup generator comes back: the station's lamps light, and the mast blinks.
func on_stage_done(stage: int, _animate: bool) -> void:
	if stage == 0 and _station_lights.is_empty():
		for p in [Vector3(-2.5, 3.4, -5.0), Vector3(2.5, 3.4, -7.0)]:
			_station_lights.append(_light(p, Color("ffd9a0"), 1.4, 8.0))
		_station_lights.append(_light(Vector3(6.0, 15.0, -8.0), Color("ff4030"), 1.0, 10.0))


func _build_mast() -> void:
	_static_box(Vector3(0.3, 16.0, 0.3), Vector3(6.0, 8.0, -8.0), _mat(Color("3a3f43"), 0.5))
	_static_box(Vector3(2.0, 0.1, 0.1), Vector3(6.0, 14.0, -8.0), _mat(Color("3a3f43"), 0.5))

## The relay's mission: restart the backup generator, then hold the station while the charging
## cradle lets go of the cell.
func _mission() -> Array:
	var J := Story.JUNO
	return [
		{
			"type": "activate", "text": "Restart the relay's backup generator: throw the breakers",
			"devices": [
				{"pos": Vector3(-12.0, 0.1, 0.5), "kind": "breaker", "label": "Throw the breaker", "yaw": PI * 0.5},
				{"pos": Vector3(11.5, 0.1, 3.5), "kind": "breaker", "label": "Throw the breaker", "yaw": -PI * 0.5},
				{"pos": Vector3(-4.5, 0.1, -10.8), "kind": "breaker", "label": "Throw the breaker", "yaw": PI},
			],
			"say": [[J, "Station's as dead as Kestrel. The backup generator's tripped."], [J, "Three breakers on the outside walls. Then the cradle should give up the cell."]],
		},
		{
			"type": "defend", "text": "Release the power cell from its charging cradle",
			"running_text": "Hold the station while the cradle releases the cell",
			"device": {"pos": Vector3(2.4, 0.1, -8.0), "kind": "cradle", "label": "Start the cradle release", "yaw": PI},
			"bar": "CRADLE RELEASE", "seconds": 35.0, "radius": 11.0, "wave_every": 10.0, "lift": 0.0,
			"waves": [["scuttler", "scuttler", "scuttler"], ["scuttler", "scuttler", "scuttler", "scuttler"], ["scuttler", "scuttler", "scuttler"]],
			"say": [[J, "Lights. Good. The cradle wants half a minute to let go of the cell."]],
			"start_say": [[J, "And that whine's going to carry for kilometres. Here they come."]],
			"done_say": [[J, "Cradle's open. Now to haul this thing home."]],
		},
	]
