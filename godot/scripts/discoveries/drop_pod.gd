class_name DropPod
extends Node3D
## Kettle side mission (X2.3): the last of Lt. Reyes's supply drops, half-buried on the north-west
## flats with its green distress light still blinking. The listening post picks up its beacon
## once it's awake. Juno pulls the pod's flight recorder: a download she has to hold the ground
## for while the noise draws scuttlers (and spitters, later in the campaign) out of the flats.
## The recorder holds Reyes's last log, which points the way to her people beyond the canyon.
##
## State in Game.flags: pod_found (Juno reached it), pod_downloaded (done). A download in
## progress isn't saved; it starts again.

const ID := "drop_pod"
const AT := Vector2(-53.0, -53.0)
const FOUND_RANGE := 14.0
## Juno must stay this close for the download to run.
const HOLD_RANGE := 12.0
const DOWNLOAD := 45.0
const WAVE_EVERY := 12.0
const RANGE := 2.4
const LOG_ID := "pod_1"
const GREEN := Color("6dff8a")
const IVORY := Color("d9d2c2")
const OXIDE := Color("bf6835")
const METAL := Color("3c4448")

var main: Node
var recorder_pos := Vector3.ZERO
## Seconds downloaded, or -1 when no download is running.
var progress := -1.0
var waves := 0
var _wave_timer := 0.0
var _stalled := false
var _time := 0.0
var _light_mat: StandardMaterial3D
var _light: OmniLight3D
var _mats := {}


func setup(m: Node) -> void:
	main = m
	position = Vector3(AT.x, main.site.height_at(AT.x, AT.y), AT.y)
	rotation.y = 0.7
	_build()


func is_done() -> bool:
	return Game.flags.get("pod_downloaded", false) == true


## Only once the listening post has picked up the beacon does the pod transmit.
func transmitting() -> bool:
	return Game.flags.get("post_awake", false) == true and not is_done()


func downloading() -> bool:
	return progress >= 0.0


func _process(delta: float) -> void:
	_time += delta
	var on := transmitting() and fmod(_time, 1.2) < 0.25
	_light_mat.emission_energy_multiplier = 5.0 if on else 0.2
	_light.light_energy = 2.5 if on else 0.0
	if not main or not transmitting():
		return
	var d: float = main.player.global_position.distance_to(global_position)
	if d < FOUND_RANGE and not Game.flags.get("pod_found", false):
		Game.set_flag("pod_found")
		main.voice.say([[Story.HOB, "That's Reyes's pod. The recorder's intact, but pulling it will be loud. Stay close while it downloads."]])
	if not downloading():
		return
	if main.player.dead:
		_abort()
		return
	if d > HOLD_RANGE:
		if not _stalled:
			_stalled = true
			main.hud.show_message("The download stalls. Get back to the pod.")
		return
	_stalled = false
	progress += delta
	_wave_timer -= delta
	if _wave_timer <= 0.0:
		_wave_timer = WAVE_EVERY
		_spawn_wave()
	if progress >= DOWNLOAD:
		_finish()


## The prompt at the recorder, or while the download runs, its progress; {} otherwise.
func interaction(pos: Vector3) -> Dictionary:
	if not transmitting():
		return {}
	if downloading():
		if pos.distance_to(global_position) <= HOLD_RANGE:
			return {"label": "Downloading the flight recorder  %d%%  ·  hold the ground" % int(progress / DOWNLOAD * 100.0)}
		return {}
	if pos.distance_to(recorder_pos) <= RANGE:
		return {"label": "[E] Pull the flight recorder", "action": start_download}
	return {}


func start_download() -> void:
	if downloading() or not transmitting():
		return
	progress = 0.0
	waves = 0
	_wave_timer = 4.0
	_stalled = false
	Game.set_flag("pod_found")
	Sfx.play("power_up", recorder_pos, -4.0)
	main.voice.say([[Story.JUNO, "Recorder's spinning up. Here they come."]])


## Each wave comes from one side of the flats, bigger as Kestrel comes back to life.
func _spawn_wave() -> void:
	waves += 1
	var kinds := ["scuttler", "scuttler"]
	if Game.repairs_done() >= 2:
		kinds.append("spitter")
	if waves >= 3:
		kinds.append("scuttler")
	var a := float(waves) * 2.1 + rotation.y
	for i in kinds.size():
		var off := Vector3(cos(a + i * 0.3), 0.0, sin(a + i * 0.3)) * 22.0
		var e: Enemy = main.spawn_enemy(kinds[i], global_position + off + Vector3.UP * 0.5)
		e.alert(false)
	Sfx.play("signal_ping", recorder_pos, -6.0)


func _finish() -> void:
	progress = -1.0
	Game.set_flag("pod_downloaded")
	Game.find_log(LOG_ID)
	Game.add_charges(2)
	Game.add_stims(1)
	main.hud.show_message("Recorder pulled. Two arc charges and a stim from the pod's locker.")
	main.voice.say(Story.POD_LINES)


func _abort() -> void:
	progress = -1.0
	_stalled = false


func _build() -> void:
	# The pod: a capsule nose-down in the ground, tipped on its side.
	var pod := Node3D.new()
	pod.rotation = Vector3(deg_to_rad(-25.0), 0.0, deg_to_rad(70.0))
	pod.position = Vector3(0.0, 0.6, 0.0)
	add_child(pod)
	var hull := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 1.2
	cap.height = 4.6
	hull.mesh = cap
	hull.material_override = _mat(IVORY, 0.6)
	pod.add_child(hull)
	for y in [-0.9, 0.9]:
		var band := MeshInstance3D.new()
		var ring := CylinderMesh.new()
		ring.top_radius = 1.24
		ring.bottom_radius = 1.24
		ring.height = 0.3
		band.mesh = ring
		band.material_override = _mat(OXIDE, 0.6)
		band.position.y = y
		pod.add_child(band)
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var cs := CapsuleShape3D.new()
	cs.radius = 1.2
	cs.height = 4.6
	shape.shape = cs
	body.add_child(shape)
	pod.add_child(body)
	# The distress lamp on an antenna, and the recorder housing on the ground beside the hatch.
	_box(Vector3(-1.6, 1.8, 0.4), Vector3(0.08, 3.6, 0.08), _mat(METAL, 0.4), false)
	_light_mat = StandardMaterial3D.new()
	_light_mat.albedo_color = GREEN.darkened(0.5)
	_light_mat.emission_enabled = true
	_light_mat.emission = GREEN
	var lamp := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.2
	s.height = 0.4
	lamp.mesh = s
	lamp.material_override = _light_mat
	lamp.position = Vector3(-1.6, 3.7, 0.4)
	add_child(lamp)
	_light = OmniLight3D.new()
	_light.light_color = GREEN
	_light.omni_range = 9.0
	_light.shadow_enabled = false
	_light.position = lamp.position
	add_child(_light)
	_box(Vector3(1.4, 0.4, 1.6), Vector3(0.9, 0.8, 0.6), _mat(OXIDE, 0.6), true)
	_box(Vector3(1.4, 0.85, 1.6), Vector3(0.7, 0.1, 0.45), _mat(METAL, 0.4), false)
	recorder_pos = to_global(Vector3(1.4, 0.0, 2.4))
	# Scattered cargo from the drop.
	_box(Vector3(-3.0, 0.3, -2.0), Vector3(1.0, 0.6, 0.7), _mat(IVORY, 0.7), true)
	_box(Vector3(3.2, 0.25, -1.4), Vector3(0.8, 0.5, 0.8), _mat(OXIDE, 0.7), true)


func _box(pos: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	if not solid:
		mi.position = pos
		add_child(mi)
		return
	var body := StaticBody3D.new()
	body.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.position = pos
	body.add_child(mi)
	body.add_child(shape)
	add_child(body)


func _mat(color: Color, roughness := 0.8) -> StandardMaterial3D:
	var key := "%s/%s" % [color.to_html(), roughness]
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = roughness
		_mats[key] = m
	return _mats[key]
