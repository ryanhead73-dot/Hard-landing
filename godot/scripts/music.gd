class_name MusicDirector
extends Node
## Adaptive music. Three stems at the same tempo and length (tools/audio/make_music.py) start together
## and loop in lockstep; the mood only changes their volumes. Calm always plays. Combat comes in
## when wildlife is hunting near Juno or Kestrel is under siege, and the finale layer drives the
## engine spool and the launch.
##
## Three more cues are whole pieces of their own (Jake's, 2026-11-09), not stems: the Cantor's
## fight, the departure (which takes over from the stems for the finale's spool) and the ending
## sting. They run free, like the opening's cues, and start from the top when they come in.

const LAYERS := ["music_calm", "music_combat", "music_finale", "music_ship_theme", "music_sighting", "music_first_fight",
	"music_cantor", "music_departure", "music_patience", "music_crown",
	"music_shatterlands", "music_gillwood", "music_loom", "music_region_combat"]
## A region with a piece of its own, played instead of the stems while Juno is there.
const REGION_MUSIC := {
	"long_patience": "music_patience", "tuning_crown": "music_crown",
	"shatterlands": "music_shatterlands", "gillwood": "music_gillwood", "loom_expanse": "music_loom",
}
## Regions whose fights bring in the regional combat piece (the others keep their own throughout).
const COMBAT_REGIONS := ["shatterlands", "gillwood", "loom_expanse"]
## The opening's own cues (Opening.music_levels): free-running loops, restarted from the top
## whenever one comes in from silence, so each cue starts on its first bar.
const OPENING_LAYERS := ["music_ship_theme", "music_sighting", "music_first_fight"]
## Every free-running cue: the opening's and the two set pieces.
const FREE_LAYERS := ["music_ship_theme", "music_sighting", "music_first_fight", "music_cantor", "music_departure",
	"music_patience", "music_crown", "music_shatterlands", "music_gillwood", "music_loom", "music_region_combat"]
const ENDING := "music_ending"
const BASE_DB := {
	"music_calm": -8.0, "music_combat": -7.0, "music_finale": -6.0,
	"music_ship_theme": -11.0, "music_sighting": -9.0, "music_first_fight": -8.0,
	"music_cantor": -7.0, "music_departure": -6.0,
	# The stealth piece is mastered quiet on purpose (it sits under dialogue).
	"music_patience": -2.0, "music_crown": -7.0,
	# The exploration pieces are mastered quiet too (peaks near -18 dBFS).
	"music_shatterlands": -2.0, "music_gillwood": -2.0, "music_loom": -2.0, "music_region_combat": -3.0,
}
const COMBAT_RANGE := 45.0
const FADE := 0.5  ## Linear volume per second.

var main: Node
var mood := "calm"
var levels := {
	"music_calm": 1.0, "music_combat": 0.0, "music_finale": 0.0,
	"music_ship_theme": 0.0, "music_sighting": 0.0, "music_first_fight": 0.0,
	"music_cantor": 0.0, "music_departure": 0.0,
	"music_patience": 0.0, "music_crown": 0.0,
	"music_shatterlands": 0.0, "music_gillwood": 0.0, "music_loom": 0.0, "music_region_combat": 0.0,
}
var players := {}
## The ending sting (one play, when the ending card comes up).
var sting: AudioStreamPlayer
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
	sting = AudioStreamPlayer.new()
	sting.name = ENDING
	var s := Sfx.stream(ENDING)
	if s:
		# A one-shot: Sfx loads every Ogg looping, so this player gets its own copy that doesn't.
		s = s.duplicate()
		(s as AudioStreamOggVorbis).loop = false
	sting.stream = s
	sting.bus = "Music"
	sting.volume_db = -5.0
	add_child(sting)
	_apply()
	for id in LAYERS:
		if players[id].stream and id not in FREE_LAYERS:
			players[id].play()


func _process(delta: float) -> void:
	_check -= delta
	if _check <= 0.0:
		_check = 0.4
		var was := mood
		mood = pick_mood()
		if mood == "ending" and was != "ending" and sting.stream:
			# The sting has the room to itself: the departure piece cuts, it doesn't fade under it.
			for id in FREE_LAYERS:
				levels[id] = 0.0
				players[id].stop()
			sting.play()
	var want := targets(mood)
	for id in LAYERS:
		var target: float = want.get(id, 0.0)
		if id in FREE_LAYERS and levels[id] < 0.01 and target > 0.0 and players.has(id) and players[id].stream:
			players[id].play(0.0)
		levels[id] = move_toward(levels[id], target, FADE * delta)
		# A set piece that has faded right out stops, so it isn't decoding under everything else.
		if id in FREE_LAYERS and levels[id] <= 0.0 and target <= 0.0 and players.has(id) and players[id].playing:
			players[id].stop()
	_apply()


func targets(m: String) -> Dictionary:
	if m == "opening":
		var cue: Dictionary = main.opening.music_levels()
		cue.merge({"music_calm": 0.0, "music_combat": 0.0, "music_finale": 0.0})
		return cue
	match m:
		"combat":
			return {"music_calm": 0.8, "music_combat": 1.0, "music_finale": 0.0}
		"region_combat":
			return {"music_calm": 0.0, "music_combat": 0.0, "music_finale": 0.0, "music_region_combat": 1.0}
		"long_patience", "tuning_crown", "shatterlands", "gillwood", "loom_expanse":
			return {"music_calm": 0.0, "music_combat": 0.0, "music_finale": 0.0, REGION_MUSIC[m]: 1.0}
		"cantor":
			return {"music_calm": 0.0, "music_combat": 0.0, "music_finale": 0.0, "music_cantor": 1.0}
		"finale":
			return {"music_calm": 0.0, "music_combat": 0.0, "music_finale": 0.0, "music_departure": 1.0}
		"ending":
			# The sting has the room to itself; the calm stem comes back under its tail.
			return {"music_calm": 0.0 if sting and sting.playing and sting.get_playback_position() < 14.0 else 1.0, "music_combat": 0.0, "music_finale": 0.0}
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
	if get_tree().get_nodes_in_group("cantors").any(func(c): return not c.dead):
		return "cantor"
	if main.get("regions") and REGION_MUSIC.has(main.regions.current):
		if main.regions.current in COMBAT_REGIONS and _hunted():
			return "region_combat"
		return main.regions.current
	if main.siege.is_active():
		return "combat"
	return "combat" if _hunted() else "calm"


## Wildlife is hunting close to Juno.
func _hunted() -> bool:
	var p: Node3D = main.player
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.hunting and not e.dead and e.global_position.distance_to(p.global_position) < COMBAT_RANGE:
			return true
	return false


func _apply() -> void:
	for id in LAYERS:
		if players.has(id):
			players[id].volume_db = BASE_DB[id] + linear_to_db(maxf(levels[id], 0.0001))
