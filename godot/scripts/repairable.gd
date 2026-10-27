class_name Repairable
extends Node3D
## One repairable part of Kestrel. Holds a damaged and a repaired child that share this
## node's origin (the mount point). Only one of them is visible and collidable at a time.
## Children are found by name: "Damaged"/"Repaired", or anything ending in "_damaged"/"_repaired"
## (the names the Blender template exports).

signal state_changed(repaired: bool)

@export var repair_id := ""
@export var display_name := ""
@export var repaired := false:
	set(value):
		if value == repaired:
			return
		repaired = value
		apply_state()
		state_changed.emit(repaired)


func _ready() -> void:
	apply_state()


func apply_state() -> void:
	for child in get_children():
		var child_name := String(child.name).to_lower()
		if child_name == "damaged" or child_name.ends_with("_damaged"):
			_set_active(child, not repaired)
		elif child_name == "repaired" or child_name.ends_with("_repaired"):
			_set_active(child, repaired)


static func _set_active(node: Node, active: bool) -> void:
	if node is Node3D:
		(node as Node3D).visible = active
	_set_collision(node, active)


static func _set_collision(node: Node, active: bool) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", not active)
		_set_collision(child, active)
