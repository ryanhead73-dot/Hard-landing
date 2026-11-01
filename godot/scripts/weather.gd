class_name Weather
extends Node
## Squalls roll over the basin every few minutes: the cloud comes down, the light goes flat and
## grey, rain hammers the rock dark and glossy and stipples the pools, lightning flashes and the
## thunder follows. In the murk the wildlife can't see as far either, so a storm is a chance to
## slip past a pack as much as a danger. Inside Kestrel the rain drops to a drum on the hull.
## main.gd owns one; it drives main.storm / main.flash and re-applies the daylight blend.

enum State { CLEAR, BUILDING, STORM, CLEARING }

const FIRST_STORM := 260.0
const INTERVAL := Vector2(320.0, 520.0)
const BUILD_TIME := 25.0
const HOLD := Vector2(70.0, 110.0)
const CLEAR_TIME := 30.0
## How far wildlife can see at the height of a storm, as a share of clear weather.
const STORM_SIGHT := 0.6
const LINES := [
	[Story.JUNO, "Squall coming over the rim. Can't see a thing past twenty metres."],
	[Story.JUNO, "Rain again. Good. If I can't see them, they can't see me."],
	[Story.JUNO, "Here it comes. Stay low, stay quick."],
]

var main: Node
var state := State.CLEAR
## 0 clear .. 1 downpour.
var storm := 0.0
var storms := 0
var enabled := true

var _timer := FIRST_STORM
var _apply_timer := 0.0
var _bolt_timer := 10.0
var _rain: CPUParticles3D
var _splash: CPUParticles3D
var _rain_mat: StandardMaterial3D
var _loop: AudioStreamPlayer


func setup(m: Node) -> void:
	main = m
	_rain = _rain_emitter()
	_splash = _splash_emitter()
	_loop = Sfx.loop_flat("rain_loop", self, -80.0, "Ambience")


func _exit_tree() -> void:
	Enemy.sight_scale = 1.0


## Brings a storm in now (over BUILD_TIME, or at once).
func start_storm(immediate := false) -> void:
	state = State.BUILDING
	_timer = BUILD_TIME
	if immediate:
		storm = 1.0
		state = State.STORM
		_timer = randf_range(HOLD.x, HOLD.y)
	storms += 1
	if main and main.voice and not Game.launched:
		main.voice.say_line(LINES[(storms - 1) % LINES.size()])
	_apply()


## Lets the storm blow over (over CLEAR_TIME, or at once).
func clear_storm(immediate := false) -> void:
	state = State.CLEARING
	_timer = CLEAR_TIME
	if immediate:
		storm = 0.0
		state = State.CLEAR
		_timer = randf_range(INTERVAL.x, INTERVAL.y)
	_apply()


func _process(delta: float) -> void:
	if main == null or main.player == null:
		return
	var calm: bool = Game.launched or Game.phase() == "launch" or Game.phase() == "done" or main.intro_playing
	if calm and state != State.CLEAR and state != State.CLEARING:
		clear_storm()
	_timer -= delta
	match state:
		State.CLEAR:
			if _timer <= 0.0 and enabled and not calm:
				start_storm()
		State.BUILDING:
			storm = minf(storm + delta / BUILD_TIME, 1.0)
			if storm >= 1.0:
				state = State.STORM
				_timer = randf_range(HOLD.x, HOLD.y)
		State.STORM:
			_lightning(delta)
			if _timer <= 0.0:
				clear_storm()
		State.CLEARING:
			storm = maxf(storm - delta / CLEAR_TIME, 0.0)
			if storm <= 0.0:
				state = State.CLEAR
				_timer = randf_range(INTERVAL.x, INTERVAL.y)
	_follow()
	_apply_timer -= delta
	if _apply_timer <= 0.0 or main.flash > 0.0:
		_apply_timer = 0.2
		_apply()


func _apply() -> void:
	Enemy.sight_scale = lerpf(1.0, STORM_SIGHT, storm)
	if main == null:
		return
	main.storm = storm
	main.set_daylight(main.daylight)
	var inside: bool = main.kestrel.is_inside(main.player.global_position)
	var showing := storm > 0.12 and not inside
	_rain.emitting = showing
	_splash.emitting = showing and storm > 0.4
	_rain_mat.albedo_color.a = 0.32 * storm
	if _loop:
		var level := -9.0 + linear_to_db(maxf(storm, 0.0001))
		_loop.volume_db = level - (9.0 if inside else 0.0)


## The rain box rides above and around Juno, so it is always falling where she is.
func _follow() -> void:
	var at: Vector3 = main.player.global_position
	_rain.global_position = at + Vector3(0.0, 9.0, 0.0) + Vector3(main.player.velocity.x, 0.0, main.player.velocity.z) * 0.4
	_splash.global_position = Vector3(at.x, main.site.height_at(at.x, at.z) + 0.05, at.z)


func _lightning(delta: float) -> void:
	_bolt_timer -= delta
	if _bolt_timer > 0.0:
		return
	_bolt_timer = randf_range(9.0, 22.0)
	strike()


## A lightning flash (two quick pulses), then thunder a few seconds later.
func strike() -> void:
	var t := create_tween()
	t.tween_property(main, "flash", 2.2, 0.04)
	t.tween_property(main, "flash", 0.2, 0.08)
	t.tween_property(main, "flash", 1.5, 0.05)
	t.tween_property(main, "flash", 0.0, 0.35)
	var delay := randf_range(0.6, 3.5)
	get_tree().create_timer(delay).timeout.connect(func():
		if is_inside_tree():
			Sfx.play("thunder", null, -5.0 - delay * 2.0, 0.08))


func _rain_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Rain"
	p.top_level = true
	p.local_coords = false
	p.amount = 700 if Game.graphics >= 1 else 350
	p.lifetime = 0.55
	p.preprocess = 0.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16.0, 1.0, 16.0)
	p.direction = Vector3(0.12, -1.0, 0.05)
	p.spread = 3.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 17.0
	p.initial_velocity_max = 21.0
	var streak := QuadMesh.new()
	streak.size = Vector2(0.018, 0.55)
	_rain_mat = StandardMaterial3D.new()
	_rain_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_rain_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_rain_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain_mat.albedo_color = Color(0.82, 0.88, 0.9, 0.0)
	streak.material = _rain_mat
	p.mesh = streak
	p.emitting = false
	add_child(p)
	return p


func _splash_emitter() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "RainSplash"
	p.top_level = true
	p.local_coords = false
	p.amount = 160 if Game.graphics >= 1 else 70
	p.lifetime = 0.22
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(10.0, 0.05, 10.0)
	p.direction = Vector3.UP
	p.spread = 50.0
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	var dot := QuadMesh.new()
	dot.size = Vector2(0.05, 0.05)
	dot.material = Vfx.soft(Color(0.85, 0.9, 0.92, 0.7))
	p.mesh = dot
	p.emitting = false
	add_child(p)
	return p
