class_name AudioZones
extends RefCounted
## Enclosed spaces send their sounds to the Interior reverb bus (Game.ensure_buses), so a shot in
## Kestrel's workshop or a wreck's hold rings off the walls while out on the basin it doesn't.
## Godot sends a 3D sound to an area's reverb bus when the sound plays inside that area.

const BUS := "Interior"


static func reverb_area(parent: Node3D, size: Vector3, pos: Vector3, amount := 0.6, tag := "") -> Area3D:
	var area := Area3D.new()
	area.name = "ReverbZone" + ("_" + tag if tag else "")
	area.monitoring = false
	area.monitorable = false
	area.reverb_bus_enabled = true
	area.reverb_bus_name = BUS
	area.reverb_bus_amount = amount
	area.reverb_bus_uniformity = 0.6
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)
	area.position = pos
	parent.add_child(area)
	return area
