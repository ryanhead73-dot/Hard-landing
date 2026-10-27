extends Node
## Sound effects. Autoloaded as "Sfx". Sounds are WAVs in res://audio named after their key,
## so a recorded file with the same name replaces the generated placeholder.

const SOUNDS: Array[String] = [
	"rifle_shot", "rifle_reload", "rifle_empty", "hit_tick", "kill_tick",
	"scuttler_alert", "scuttler_lunge", "scuttler_hurt", "scuttler_death",
	"player_hurt", "scrap_pickup", "cell_pickup", "power_up", "fabricate",
	"beacon_ping", "footstep_0", "footstep_1", "wind_loop", "ship_hum_loop",
]

var _streams: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for id in SOUNDS:
		var path := "res://audio/%s.wav" % id
		if ResourceLoader.exists(path):
			_streams[id] = load(path)
		else:
			push_warning("Sfx: missing %s" % path)


func has_sound(id: String) -> bool:
	return _streams.has(id)


## Plays a one-shot. Pass a position for a 3D sound, or leave it out for a flat UI-style sound.
func play(id: String, at: Variant = null, volume_db := 0.0, pitch_jitter := 0.06) -> void:
	if not _streams.has(id):
		return
	if at is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = _streams[id]
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
		p.stream = _streams[id]
		p.volume_db = volume_db
		p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
		add_child(p)
		p.play()
		p.finished.connect(p.queue_free)


## Starts a looping sound. With a parent it plays in 3D from that node, otherwise flat.
func loop(id: String, parent: Node3D = null, volume_db := 0.0) -> Node:
	if not _streams.has(id):
		return null
	# Loop points come from the WAV's smpl chunk (see tools/make_sfx.py). A replacement file
	# without them still loops, by restarting when it ends.
	var stream: AudioStream = _streams[id]
	var needs_restart := stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED
	var player: Node
	if parent:
		var p3 := AudioStreamPlayer3D.new()
		p3.stream = stream
		p3.volume_db = volume_db
		p3.unit_size = 6.0
		p3.max_distance = 40.0
		parent.add_child(p3)
		p3.play()
		player = p3
	else:
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = volume_db
		add_child(p)
		p.play()
		player = p
	if needs_restart:
		player.finished.connect(player.play)
	return player
