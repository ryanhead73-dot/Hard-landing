@tool
class_name RelayStation
extends ExpeditionSite
## Abandoned relay station: the first expedition. One building holds the aux power cell; broken
## walls, a tipped container and crates give cover for fights on the approach. The doorway faces
## +Z. The mast beacon makes the site findable from Kestrel.

const CELL_POSITION := Vector3(0.0, 1.35, -7.6)
const CRATE_SCRAP := 10
## The station's console, on the desk at the back of the hut: once the generator is back, its
## traffic log points at Ilse's listening post up the south-east slope.
const CONSOLE_STAND := Vector3(-2.5, 0.0, -7.4)
const CONSOLE_RANGE := 1.8

var _station_lights: Array[OmniLight3D] = []
var _screen_mat: StandardMaterial3D


func _configure() -> void:
	component_id = "aux_cell"
	component_pos = CELL_POSITION
	component_stand = Vector3(0.0, 0.0, -6.3)
	# No resident pack: the yard has one territorial scuttler (see Opening), nothing more.
	spawn_pts = []
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
	# The hut and mast are modelled in this site's coordinates (blender/build_sites.py): a 10 x 4
	# x 7 m prefab round (0, 2, -5.5) with 0.2 m walls, a front door and two windows facing +z, a
	# side door in the east wall and a hole in the roof. Collision is boxes matching its walls.
	Rig.spawn_static("site_relay", self)
	AudioZones.reverb_area(self, Vector3(9.6, 3.7, 6.6), Vector3(0.0, 1.95, -5.5), 0.45)
	var wall := _mat(Color("8a8f86"), 0.9)
	_collider(Vector3(10.0, 4.0, 0.2), Vector3(0.0, 2.0, -8.9))
	_collider(Vector3(0.2, 4.0, 7.0), Vector3(-4.9, 2.0, -5.5))
	# East wall either side of the side door (z -6.55..-5.05, up to y 2.4), and over it.
	_collider(Vector3(0.2, 4.0, 2.45), Vector3(4.9, 2.0, -7.775))
	_collider(Vector3(0.2, 4.0, 3.05), Vector3(4.9, 2.0, -3.525))
	_collider(Vector3(0.2, 1.6, 1.5), Vector3(4.9, 3.2, -5.8))
	# Front wall: the door (x +-1, up to 2.6) and windows (2.2 < |x| < 4.2, y 1.4..2.4).
	for side in [-1.0, 1.0]:
		_collider(Vector3(0.8, 4.0, 0.2), Vector3(side * 4.6, 2.0, -2.1))
		_collider(Vector3(1.2, 4.0, 0.2), Vector3(side * 1.6, 2.0, -2.1))
		_collider(Vector3(2.0, 1.4, 0.2), Vector3(side * 3.2, 0.7, -2.1))
		_collider(Vector3(2.0, 1.6, 0.2), Vector3(side * 3.2, 3.2, -2.1))
	_collider(Vector3(2.0, 1.4, 0.2), Vector3(0.0, 3.3, -2.1))
	# Roof, round the hole over the cell (x 0..3, z -8.3..-5.3).
	_collider(Vector3(5.0, 0.2, 7.0), Vector3(-2.5, 3.9, -5.5))
	_collider(Vector3(2.0, 0.2, 7.0), Vector3(4.0, 3.9, -5.5))
	_collider(Vector3(3.0, 0.2, 0.7), Vector3(1.5, 3.9, -8.65))
	_collider(Vector3(3.0, 0.2, 3.3), Vector3(1.5, 3.9, -3.65))
	var slab := _static_box(Vector3(3.0, 0.2, 2.6), Vector3(2.4, 0.9, -4.6), wall)
	slab.rotation = Vector3(0.5, 0.2, 0.3)
	_static_box(Vector3(0.6, 1.0, 3.0), Vector3(-4.4, 0.6, -6.0), _mat(Color("24282b"), 0.5))
	_static_box(Vector3(2.4, 1.0, 0.6), Vector3(-2.5, 0.6, -8.5), _mat(Color("24282b"), 0.5))
	_screen_mat = _emissive(Color("3fd1b5"), 0.4)
	_static_box(Vector3(1.6, 0.6, 0.05), Vector3(-2.5, 1.6, -8.75), _screen_mat)


func _build_cover() -> void:
	# Jersey barriers and a tipped shipping container (modelled props over box collision).
	_prop("prop_barrier", Vector3(4.0, 1.2, 0.4), Vector3(-7.5, 0.7, 3.0))
	_prop("prop_barrier", Vector3(5.0, 1.2, 0.4), Vector3(7.0, 0.7, 1.0), Vector3(0.0, PI * 0.5, 0.0))
	_prop("prop_barrier", Vector3(5.0, 1.1, 0.4), Vector3(-1.5, 0.65, 7.0), Vector3(0.0, 0.25, 0.0))
	_prop("prop_barrier", Vector3(3.0, 1.0, 0.4), Vector3(10.5, 0.6, -6.0), Vector3(0.0, -0.6, 0.0))
	_prop("prop_container", Vector3(6.0, 2.6, 2.4), Vector3(-10.0, 1.3, -5.0), Vector3(0.0, 0.3, 0.08))
	_prop("prop_generator", Vector3(2.4, 1.6, 1.3), Vector3(5.6, 0.9, -12.2), Vector3(0.0, 0.1, 0.0))
	_prop("prop_pipes", Vector3(4.0, 0.9, 1.3), Vector3(-8.5, 0.55, -12.0))
	for p in [Vector3(3.0, 0.65, 4.5), Vector3(9.0, 0.65, -3.0), Vector3(-5.5, 0.65, 9.0), Vector3(4.2, 0.65, 9.5)]:
		_prop("prop_cargo_case", Vector3(1.1, 1.1, 1.1), p, Vector3(0.0, p.x, 0.0))


## The backup generator comes back: the station's lamps light, and the mast blinks.
func on_stage_done(stage: int, animate: bool) -> void:
	if animate:
		match stage:
			0:
				Sfx.play("breaker_clunk", to_global(Vector3(-12.0, 1.0, 0.5)), 0.0, 0.0)
			1:
				Sfx.play("relay_surge", to_global(Vector3(2.4, 1.5, -8.0)), -2.0, 0.0)
	if stage == 0 and _station_lights.is_empty():
		for p in [Vector3(-2.5, 3.4, -5.0), Vector3(2.5, 3.4, -7.0)]:
			_station_lights.append(_light(p, Color("ffd9a0"), 1.4, 8.0))
		_station_lights.append(_light(Vector3(6.0, 15.0, -8.0), Color("ff4030"), 1.0, 10.0))
		if _screen_mat:
			_screen_mat.emission_energy_multiplier = 2.2


## The backup generator is running: the first stage of the aux power mission is done.
func powered() -> bool:
	if Game.is_repaired("aux_power"):
		return true
	return int(Game.mission_stage.get("aux_power", 0)) >= 1


func console_read() -> bool:
	return Game.flags.get("post_located", false) == true


func console_point() -> Vector3:
	return to_global(CONSOLE_STAND)


func interaction(pos: Vector3) -> Dictionary:
	if console_read() or pos.distance_to(console_point()) > CONSOLE_RANGE:
		return {}
	if not powered():
		return {"label": "The station's console: dark, like everything else here"}
	return {"label": "[E] Read the station's traffic log", "action": read_console}


## Ilse's last traffic went to a listening post up the slope: the journal and map pick it up.
func read_console() -> void:
	if console_read() or not powered():
		return
	Game.set_flag("post_located")
	Sfx.play("log_chime", console_point(), -6.0)
	var n := get_parent()
	while n and n.get("voice") == null:
		n = n.get_parent()
	if n:
		n.voice.say(Story.RELAY_CONSOLE_LINES)


## The mast is part of the station model; its lattice collides as one slim box.
func _build_mast() -> void:
	_collider(Vector3(0.9, 16.0, 0.9), Vector3(6.0, 8.0, -8.0))

## The relay's mission: wire the battery contact (from the yard's scuttler) into the dead
## breaker, route current through the two live switchboxes (the third runs back to the old
## wreckage, and the live ones carry Kestrel's triple-click interference), then release the cell.
func _mission() -> Array:
	var J := Story.JUNO
	return [
		{
			"type": "activate", "text": "Wire the battery contact into the relay's dead breaker",
			"needs_flag": "relay_contact", "locked_label": "Dead breaker: a battery contact's missing",
			"devices": [
				{"pos": Vector3(-12.0, 0.1, 0.5), "kind": "breaker", "label": "Wire in the battery contact", "yaw": PI * 0.5},
			],
			"say": [[J, "Station's as dead as Kestrel. The breaker's missing its battery contact."]],
		},
		{
			"type": "activate", "text": "Route current to the cradle: listen for the two live switchboxes",
			"decoys": [0],
			"devices": [
				{"pos": Vector3(11.5, 0.1, 3.5), "kind": "breaker", "label": "Close the switchbox", "reading": "lamp steady, a flat hum", "yaw": -PI * 0.5},
				{"pos": Vector3(-4.5, 0.1, -10.8), "kind": "breaker", "label": "Close the switchbox", "reading": "lamp flickers, click-click-click", "yaw": PI},
				{"pos": Vector3(8.0, 0.1, -10.8), "kind": "breaker", "label": "Close the switchbox", "reading": "lamp flickers, click-click-click", "yaw": PI},
			],
			"wrong_text": "Sparks. That line runs out to the old wreckage, not the cradle.",
			"wrong_say": [[J, "Not that one. The live lines click in threes, like the noise before we fell."]],
			"say": [[J, "Lights. Three switchboxes, and only two run to the cradle."], [J, "That triple click on the way down... the live lines have it too. Listen."]],
		},
		{
			"type": "activate", "text": "Release the power cell from its charging cradle",
			"devices": [
				{"pos": Vector3(2.4, 0.1, -8.0), "kind": "cradle", "label": "Release the cell from the cradle", "hold": 2.0, "yaw": PI},
			],
			"say": [[J, "Current's at the cradle. Now let go of it, gently."]],
			"done_say": [[J, "Cradle's open. It's small enough for the shoulder pouch."]],
		},
	]
