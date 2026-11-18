class_name Ambience
extends Node
## The basin's background sound, crossfaded by where Juno is: wind in the open, bubbling hot
## springs at the hauler wreck, the Loom's deep hum near the spire, insects and drips in the moss
## forest, groaning metal in the freighter graveyard, and creaking room tone inside Kestrel (her
## powered hum is a separate 3D loop in the workshop).

const LOOPS := {
	"wind": "wind_loop", "springs": "amb_springs_loop", "loom": "amb_loom_loop", "interior": "amb_interior_loop",
	"moss": "amb_moss_loop", "wreck": "amb_wreck_loop",
	"cold": "amb_cold_ship_loop", "basin": "amb_basin_loop", "gully": "amb_gully_loop",
}
const BASE_DB := {
	"wind": -14.0, "springs": -9.0, "loom": -7.0, "interior": -10.0, "moss": -9.0, "wreck": -9.0,
	"cold": -9.0, "basin": -12.0, "gully": -10.0,
}
## Which sites have their own ambience, and how close counts as being there.
const SITE_ZONES := {"cooling": "springs", "navigation": "loom", "wing": "moss", "engine": "wreck"}
const SITE_RADIUS := 36.0
const FADE := 0.6

var main: Node
var zone := "wind"
var levels := {
	"wind": 1.0, "springs": 0.0, "loom": 0.0, "interior": 0.0, "moss": 0.0, "wreck": 0.0,
	"cold": 0.0, "basin": 0.0, "gully": 0.0,
}
var players := {}


func setup(m: Node) -> void:
	main = m
	for z in LOOPS:
		var p := Sfx.loop_flat(LOOPS[z], self, -80.0, "Ambience")
		if p:
			players[z] = p
	_apply()


func _process(delta: float) -> void:
	zone = pick_zone()
	for z in LOOPS:
		var want := 1.0 if z == zone else 0.0
		# The wind never quite goes outdoors.
		if z == "wind" and zone not in ["interior", "cold", "basin", "gully"]:
			want = maxf(want, 0.35)
		levels[z] = move_toward(levels[z], want, FADE * delta)
	_apply()


func pick_zone() -> String:
	if main == null:
		return "wind"
	var at: Vector3 = main.player.global_position
	var opening: bool = main.opening != null and main.opening.active()
	if opening and main.regions.current == "approach":
		return "interior"
	if main.kestrel.is_inside(at):
		# Dead and cold until the aux cell is in: dripping coolant and ticking metal.
		return "interior" if main.kestrel.is_repaired("aux_power") else "cold"
	if opening:
		return main.opening.ambience_zone(at)
	for id in SITE_ZONES:
		var site: Node3D = main.sites.get(id)
		if site and site.global_position.distance_to(at) < SITE_RADIUS:
			return SITE_ZONES[id]
	return "wind"


func _apply() -> void:
	for z in players:
		players[z].volume_db = BASE_DB[z] + linear_to_db(maxf(levels[z], 0.0001))
