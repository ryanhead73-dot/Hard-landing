class_name MusicDirector
extends Node
## Adaptive music. Three stems at the same tempo and length (tools/audio/make_music.py) start together
## and loop in lockstep; the mood only changes their volumes. Calm always plays. Combat comes in
## when wildlife is hunting near Juno or Kestrel is under siege, and the finale layer drives the
## engine spool and the launch.

const LAYERS := ["music_calm", "music_combat", "music_finale", "music_ship_theme", "music_sighting", "music_first_fight"]
## The opening's own cues (Opening.music_levels): free-running loops, restarted from the top
## whenever one comes in from silence, so each cue starts on its first bar.
const OPENING_LAYERS := ["music_ship_theme", "music_sighting", "music_first_fight"]
const BASE_DB := {
	"music_calm": -8.0, "music_combat": -7.0, "music_finale": -6.0,
	"music_ship_theme": -11.0, "music_sighting": -9.0, "music_first_fight": -8.0,
}
const COMBAT_RANGE := 45.0
const FADE := 0.5  ## Linear volume per second.

var main: Node
var mood := "calm"
var levels := {
	"music_calm": 1.0, "music_combat": 0.0, "music_finale": 0.0,
	"music_ship_theme": 0.0, "music_sighting": 0.0, "music_first_fight": 0.0,
}
var players := {}
var _check := 0.0


func setup(m: Node) -> void:
	main = m
	# Keeps playing under the pause menu and panels.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in LAYERS:
		var p := AudioStreamPlayer.new()
		p.name = id
		p.stream = Sfx.stream(id)
		p.bus = "Music"
		add_child(p)
		players[id] = p
	_apply()
	for id in LAYERS:
		if players[id].stream:
			players[id].play()


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		mood = pick_mood()
	var want := targets(mood)
	for id in LAYERS:
		var target: float = want.get(id, 0.0)
		if id in OPENING_LAYERS and levels[id] < 0.01 and target > 0.0 and players.has(id) and players[id].stream:
			players[id].play(0.0)
		levels[id] = move_toward(levels[id], target, FADE * delta)
	_apply()


func targets(m: String) -> Dictionary:
	if m == "opening":
		var cue: Dictionary = main.opening.music_levels()
		cue.merge({"music_calm": 0.0, "music_combat": 0.0, "music_finale": 0.0})
		return cue
	match m:
		"combat":
			return {"music_calm": 0.8, "music_combat": 1.0, "music_finale": 0.0}
		"finale":
			return {"music_calm": 0.5, "music_combat": 1.0, "music_finale": 1.0}
		"ending":
			return {"music_calm": 1.0, "music_combat": 0.0, "music_finale": 0.0}
	return {"music_calm": 1.0, "music_combat": 0.0, "music_finale": 0.0}


func pick_mood() -> String:
	if main == null:
		return "calm"
	if main.ending_shown:
		return "ending"
	if main.opening and main.opening.active():
		return "opening"
	if main.finale.state != Finale.State.IDLE:
		return "finale"
	if main.siege.is_active():
		return "combat"
	var p: Node3D = main.player
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.hunting and not e.dead and e.global_position.distance_to(p.global_position) < COMBAT_RANGE:
			return "combat"
	return "calm"


func _apply() -> void:
	for id in LAYERS:
		if players.has(id):
			players[id].volume_db = BASE_DB[id] + linear_to_db(maxf(levels[id], 0.0001))
