class_name RegionScene
extends Node3D
## Base for a region that isn't the Kettle. RegionManager adds it at the region's origin, moves
## Juno to entry_point(), applies its look with apply_environment() and frees it on the way out.
## Subclasses build their geometry in build() and set the fields below (all in local space).

## Where Juno arrives, and which way she faces (yaw).
var entry := Vector3.ZERO
var entry_yaw := 0.0
## The way back: standing here offers the return trip.
var exit_point := Vector3.ZERO
var exit_label := "Return to the Kettle"
## Where the HUD waypoint points while here (local), or null for none.
var goal = null
## Environment settings while here: property name -> value on the main Environment, plus
## "sun_energy" / "sun_color" / "sun_rotation" for the sun. Restored on leaving.
var look := {}


func _ready() -> void:
	build()


func build() -> void:
	pass


## A prompt the region offers at `pos` (world space), {label, action?}, or {}.
func interaction(_pos: Vector3) -> Dictionary:
	return {}


func entry_global() -> Vector3:
	return to_global(entry)


func exit_global() -> Vector3:
	return to_global(exit_point)


## Ground height under a local x/z, for spawning (override for uneven ground).
func height_at(_x: float, _z: float) -> float:
	return 0.0


## Applies `look` and returns what it replaced, for restore_environment().
func apply_environment(env: Environment, sun: DirectionalLight3D) -> Dictionary:
	var old := {}
	for key in look:
		match key:
			"sun_energy":
				old[key] = sun.light_energy
				sun.light_energy = look[key]
			"sun_color":
				old[key] = sun.light_color
				sun.light_color = look[key]
			"sun_rotation":
				old[key] = sun.rotation_degrees
				sun.rotation_degrees = look[key]
			_:
				old[key] = env.get(key)
				env.set(key, look[key])
	return old


static func restore_environment(old: Dictionary, env: Environment, sun: DirectionalLight3D) -> void:
	for key in old:
		match key:
			"sun_energy":
				sun.light_energy = old[key]
			"sun_color":
				sun.light_color = old[key]
			"sun_rotation":
				sun.rotation_degrees = old[key]
			_:
				env.set(key, old[key])
