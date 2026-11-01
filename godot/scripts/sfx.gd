extends Node
## Sound effects. Autoloaded as "Sfx". Sounds live in res://audio named after their key: WAVs
## for effects (tools/audio/make_sfx.py), Ogg Vorbis for music and ambience beds
## (tools/audio/make_music.py), so a recorded file with the same name replaces a generated one.
## A sound can have variants, <id>__1, <id>__2...; each play picks one at random.

const SOUNDS: Array[String] = [
	"rifle_shot", "rifle_reload", "rifle_empty", "hit_tick", "kill_tick",
	"scuttler_alert", "scuttler_lunge", "scuttler_hurt", "scuttler_death",
	"player_hurt", "scrap_pickup", "cell_pickup", "power_up", "fabricate",
	"beacon_ping", "footstep_0", "footstep_1", "steam_hiss", "steam_burst", "manifold_pickup",
	"rock_impact", "arc_zap", "spore_burst", "loom_hum", "turret_shot",
	"scatter_shot", "lance_shot", "weapon_switch", "stim", "acid_splash", "spitter_charge", "spitter_spit",
	"ram_paw", "ram_charge", "ram_stun", "warden_roar", "siege_horn",
	"wind_loop", "ship_hum_loop",
	"music_calm", "music_combat", "music_finale",
	"amb_springs_loop", "amb_loom_loop", "amb_interior_loop", "spool_loop",
	"crash_impact", "repair_clunk", "log_chime", "ui_click", "warden_slam",
	"spitter_death", "ram_death", "launch_roar", "splash_0", "splash_1", "roll_whoosh",
	"step_metal", "amb_moss_loop", "amb_wreck_loop", "charge_throw", "charge_bounce", "charge_blast",
]
const MAX_VARIANTS := 8

var _streams: Dictionary = {}
var _variants: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in SOUNDS:
		var s := _load(id)
		if s == null:
			push_warning("Sfx: missing res://audio/%s" % id)
			continue
		_streams[id] = s
		var all: Array[AudioStream] = [s]
		for k in range(1, MAX_VARIANTS):
			var v := _load("%s__%d" % [id, k])
			if v == null:
				break
			all.append(v)
		_variants[id] = all


static func _load(id: String) -> AudioStream:
	for ext in [".wav", ".ogg"]:
		var path := "res://audio/%s%s" % [id, ext]
		if ResourceLoader.exists(path):
			var s: AudioStream = load(path)
			# Ogg beds are music and ambience: they always loop.
			if s is AudioStreamOggVorbis:
				(s as AudioStreamOggVorbis).loop = true
			return s
	return null


func variant_count(id: String) -> int:
	return _variants.get(id, []).size()


## One of the sound's variants, at random.
func pick(id: String) -> AudioStream:
	var all: Array = _variants.get(id, [])
	if all.is_empty():
		return null
	return all[randi() % all.size()]


func has_sound(id: String) -> bool:
	return _streams.has(id)


func stream(id: String) -> AudioStream:
	return _streams.get(id)


## A flat looping player owned by `owner` (so it goes when that scene does), on `bus`.
func loop_flat(id: String, owner: Node, volume_db := 0.0, bus := "Master") -> AudioStreamPlayer:
	if not _streams.has(id) or owner == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = _streams[id]
	p.volume_db = volume_db
	p.bus = bus
	owner.add_child(p)
	p.play()
	if _streams[id] is AudioStreamWAV and (_streams[id] as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		p.finished.connect(p.play)
	return p


## Whether a stream loops on its own (loop points in a WAV, or an Ogg set to loop).
static func loops(s: AudioStream) -> bool:
	if s is AudioStreamWAV:
		return (s as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	if s is AudioStreamOggVorbis:
		return (s as AudioStreamOggVorbis).loop
	return false


## Plays a one-shot. Pass a position for a 3D sound, or leave it out for a flat UI-style sound.
func play(id: String, at: Variant = null, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	if not _streams.has(id):
		return
	var chosen := pick(id)
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = chosen
		p3.volume_db = volume_db
		p3.unit_size = 8.0
		p3.max_distance = 80.0
		p3.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		add_child(p3)
		p3.global_position = at
		p3.play()
		p3.finished.connect(p3.queue_free)
	else:
		var p := AudioStreamPlayer.new()
		p.stream = chosen
		p.volume_db = volume_db
		p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


## Starts a looping 3D sound on `parent`. (Flat loops use loop_flat with an owner, so they never
## pile up on this autoload across scene changes.)
func loop(id: String, parent: Node3D, volume_db := 0.0) -> Node:
	if not _streams.has(id) or parent == null:
		return null
	# Loop points come from the WAV's smpl chunk (see tools/audio/make_sfx.py). A replacement file
	# without them still loops, by restarting when it ends.
	var s: AudioStream = _streams[id]
	var p3 := AudioStreamPlayer3D.new()
	p3.stream = s
	p3.volume_db = volume_db
	p3.unit_size = 6.0
	p3.max_distance = 40.0
	parent.add_child(p3)
	p3.play()
	if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		p3.finished.connect(p3.play)
	return p3
