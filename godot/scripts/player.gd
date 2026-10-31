class_name Player
extends CharacterBody3D
## Third-person player: movement, over-the-shoulder aim, salvage rifle and health.

signal health_changed(health: float, max_health: float)
signal damaged(amount: float)
signal died

@export var walk_speed := 4.0
@export var sprint_speed := 7.0
@export var crouch_speed := 2.0
@export var carry_speed_factor := 0.85
@export var jump_velocity := 4.6
@export var boom_length := 2.5
@export var aim_boom_length := 1.6
@export var shoulder_offset := 0.75
@export var aim_shoulder_offset := 0.85
@export var fov := 70.0
@export var aim_fov := 52.0
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var radius := 0.35
@export var base_max_health := 100.0
@export var regen_delay := 4.0
@export var regen_rate := 12.0
## Sprinting widens the view a little, for a sense of speed.
@export var sprint_fov_boost := 7.0

## Dodge roll: a quick burst along the move direction (backwards if standing still), briefly
## untouchable at the start.
const ROLL_TIME := 0.5
const ROLL_SPEED := 8.5
const ROLL_GUARD := 0.32
const ROLL_COOLDOWN := 0.3
## Camera kick per shot (metres of view offset), by weapon.
const KICK := {"rifle": 0.035, "scattergun": 0.14, "arc_lance": 0.08}

var crouching := false
var aiming := false
var dead := false
var health := 100.0
var weapon: Weapon

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw: Node3D
var _pitch: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _body: Node3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _flashlight: SpotLight3D
## Carried components on the back, by Campaign component id.
var _packs: Dictionary = {}
## Juno's model (see Rig): Hips, Spine, Chest, Head, ArmL/R, ForearmL/R, LegL/R, ShinL/R.
var rig: Node3D
var anim: JunoAnimator
var _since_damage := 99.0
var _combat_face := 0.0
var _plating_seen := 0
var _stride := 0.0
var _foot := 0
var _hold_fire := false
## Dodge roll: time into the roll (-1 when not rolling) and its direction.
var roll_t := -1.0
var _roll_dir := Vector3.FORWARD
var _roll_cool := 0.0
## Camera shake: trauma (0-1) decays; the shake is trauma squared, so small knocks stay small.
var trauma := 0.0
var _kick := 0.0
var _shake_noise := FastNoiseLite.new()
var _shake_t := 0.0
var _airborne_speed := 0.0
var _sprinting := false
var _stop_until := 0
## Where the last hit came from (world space), for the HUD's damage arcs.
var last_hit_from := Vector3.ZERO


func _ready() -> void:
	add_to_group("player")
	collision_layer = Game.LAYER_PLAYER
	collision_mask = Game.LAYER_WORLD | Game.LAYER_ENEMY
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46.0)

	_capsule = CapsuleShape3D.new()
	_capsule.radius = radius
	_capsule.height = stand_height
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = stand_height * 0.5
	add_child(_shape)

	_build_body()

	_yaw = Node3D.new()
	_yaw.name = "CameraYaw"
	add_child(_yaw)
	_pitch = Node3D.new()
	_pitch.position.y = 1.7
	_yaw.add_child(_pitch)
	_arm = SpringArm3D.new()
	_arm.spring_length = boom_length
	_arm.margin = 0.15
	_arm.position.x = shoulder_offset
	_arm.collision_mask = Game.LAYER_WORLD
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_pitch.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = fov
	_camera.current = true
	_arm.add_child(_camera)

	_flashlight = SpotLight3D.new()
	_flashlight.position = Vector3(0.3, 0.0, 0.0)
	_flashlight.spot_range = 18.0
	_flashlight.spot_angle = 28.0
	_flashlight.light_energy = 2.0
	_flashlight.shadow_enabled = true
	_flashlight.visible = false
	_pitch.add_child(_flashlight)

	weapon = Weapon.new()
	weapon.name = "Rifle"
	weapon.position = Vector3(0.28, 1.22, -0.32)
	weapon.camera = _camera
	weapon.shooter = self
	# The weapon rides on Juno's chest so it follows her aim, lean and recoil with her hands.
	var chest := Rig.joint(rig, "Chest")
	if chest:
		weapon.position -= _body.to_local(chest.global_position)
		chest.add_child(weapon)
	else:
		_body.add_child(weapon)
	anim = JunoAnimator.new()
	anim.name = "Animator"
	add_child(anim)
	anim.setup(self, rig)
	weapon.fired.connect(_on_fired)
	weapon.hit_confirmed.connect(func(killed: bool):
		if killed:
			hit_stop(0.05)
			add_trauma(0.12))
	_shake_noise.frequency = 2.5

	Game.carrying_changed.connect(_on_carrying_changed)
	Game.upgrades_changed.connect(_on_upgrades_changed)
	health = max_health()


func max_health() -> float:
	return base_max_health + 40.0 * _plating_count()


func _plating_count() -> int:
	return int(Game.has_upgrade("plating")) + int(Game.has_upgrade("plating_2"))


func camera() -> Camera3D:
	return _camera


func boom_current() -> float:
	return _arm.get_hit_length()


func boom_target() -> float:
	return _arm.spring_length


func face(yaw: float) -> void:
	_yaw.rotation.y = yaw
	_body.rotation.y = yaw


## Points the crosshair at a world position (used by tests and scripted moments).
func aim_at(point: Vector3) -> void:
	for i in 3:
		var from := _arm.global_position
		var flat := Vector2(point.x - from.x, point.z - from.z)
		_yaw.rotation.y = atan2(-flat.x, -flat.y)
		_pitch.rotation.x = atan2(point.y - from.y, flat.length())
	_body.rotation.y = _yaw.rotation.y


func take_damage(amount: float, from: Vector3 = Vector3.ZERO) -> bool:
	if dead or is_dodging():
		return false
	last_hit_from = from
	amount *= Game.damage_taken_scale()
	health = maxf(health - amount, 0.0)
	_since_damage = 0.0
	Sfx.play("player_hurt", null, -3.0)
	add_trauma(clampf(amount / 45.0, 0.2, 0.6))
	damaged.emit(amount)
	health_changed.emit(health, max_health())
	if health <= 0.0:
		dead = true
		velocity = Vector3.ZERO
		died.emit()
		return true
	return false


## Shakes the camera. Amounts add up to 1.
func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func is_rolling() -> bool:
	return roll_t >= 0.0


## In the untouchable opening of a roll.
func is_dodging() -> bool:
	return roll_t >= 0.0 and roll_t < ROLL_GUARD


## Starts a dodge roll if on the ground and free to move. Returns true if it started.
func start_roll() -> bool:
	if dead or is_rolling() or _roll_cool > 0.0 or not is_on_floor() or crouching:
		return false
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() < 0.2:
		input = Vector2(0.0, 1.0)
	var dir := _yaw.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	_roll_dir = dir.normalized()
	roll_t = 0.0
	_body.rotation.y = atan2(-_roll_dir.x, -_roll_dir.z)
	Sfx.play("roll_whoosh", global_position, -4.0, 0.1)
	return true


## Freezes time for a beat (a kill landing). Skipped headless, where tests count frames.
func hit_stop(seconds: float) -> void:
	if DisplayServer.get_name() == "headless" or get_tree().paused:
		return
	_stop_until = maxi(_stop_until, Time.get_ticks_msec() + int(seconds * 1000.0))
	Engine.time_scale = 0.05
	get_tree().create_timer(seconds, true, false, true).timeout.connect(func():
		if Time.get_ticks_msec() >= _stop_until - 5:
			Engine.time_scale = 1.0)


func big_kill() -> void:
	hit_stop(0.16)
	add_trauma(0.55)


func _on_fired() -> void:
	_kick += KICK.get(weapon.current, 0.04)
	if weapon.current == "scattergun":
		add_trauma(0.18)


## Uses a stim if hurt and carrying one. Returns true if it healed.
func use_stim() -> bool:
	if dead or health >= max_health() or not Game.take_stim():
		return false
	health = minf(health + Game.STIM_HEAL, max_health())
	health_changed.emit(health, max_health())
	Sfx.play("stim", null, -4.0, 0.0)
	anim.play("stim")
	return true


## Back on your feet at `at`. A loaded game keeps its saved ammo, so it passes refill = false.
func revive(at: Vector3, refill := true) -> void:
	dead = false
	health = max_health()
	velocity = Vector3.ZERO
	global_position = at
	face(0.0)
	if refill:
		weapon.refill()
	health_changed.emit(health, max_health())


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_hold_fire = true
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		var sens := Game.mouse_sensitivity * (aim_fov / fov if aiming else 1.0)
		var look_y := -motion.relative.y if Game.invert_y else motion.relative.y
		_yaw.rotate_y(-motion.relative.x * sens)
		_pitch.rotation.x = clampf(_pitch.rotation.x - look_y * sens, deg_to_rad(-70.0), deg_to_rad(50.0))
	elif event.is_action_pressed("flashlight"):
		_flashlight.visible = not _flashlight.visible
	elif event.is_action_pressed("reload") and not dead:
		weapon.start_reload()
	elif event.is_action_pressed("weapon_next") and not dead:
		weapon.cycle(1)
	elif event.is_action_pressed("weapon_prev") and not dead:
		weapon.cycle(-1)


## Keyboard actions are polled so they also respond to simulated presses (tests, remapping).
func _poll_actions() -> void:
	if dead or Game.dev_panel_open or get_tree().paused:
		return
	if Input.is_action_just_pressed("stim"):
		use_stim()
	if Input.is_action_just_pressed("dodge"):
		start_roll()
	for i in Weapon.ORDER.size():
		if Input.is_action_just_pressed("weapon_%d" % (i + 1)):
			weapon.equip(Weapon.ORDER[i])


func _process(delta: float) -> void:
	_poll_actions()
	var t := clampf(delta * 12.0, 0.0, 1.0)
	var want_fov := aim_fov if aiming else fov + (sprint_fov_boost if _sprinting else 0.0)
	_camera.fov = lerpf(_camera.fov, want_fov, clampf(delta * (12.0 if aiming else 5.0), 0.0, 1.0))
	_update_shake(delta)
	_arm.spring_length = lerpf(_arm.spring_length, aim_boom_length if aiming else boom_length, t)
	_arm.position.x = lerpf(_arm.position.x, aim_shoulder_offset if aiming else shoulder_offset, t)
	_since_damage += delta
	var servo := Game.has_upgrade("regen_servo")
	if not dead and _since_damage > (regen_delay * 0.6 if servo else regen_delay) and health < max_health():
		health = minf(health + regen_rate * (1.5 if servo else 1.0) * delta, max_health())
		health_changed.emit(health, max_health())


func _update_shake(delta: float) -> void:
	_roll_cool = maxf(_roll_cool - delta, 0.0)
	trauma = maxf(trauma - delta * 1.5, 0.0)
	_kick = lerpf(_kick, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	_shake_t += delta
	var shake := trauma * trauma * Game.screen_shake
	_camera.h_offset = _shake_noise.get_noise_2d(_shake_t * 60.0, 0.0) * 0.22 * shake
	_camera.v_offset = _shake_noise.get_noise_2d(0.0, _shake_t * 60.0) * 0.22 * shake - _kick * Game.screen_shake
	# A roll of the view never moves the aim: shots follow the camera's forward axis.
	_camera.rotation.z = _shake_noise.get_noise_2d(_shake_t * 40.0, 50.0) * deg_to_rad(3.0) * shake


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
		_airborne_speed = minf(_airborne_speed, velocity.y)
	elif _airborne_speed < -6.0:
		# A hard landing thumps the camera.
		add_trauma(clampf(-_airborne_speed / 30.0, 0.1, 0.4))
		Sfx.play("footstep_%d" % _foot, global_position, -3.0, 0.1)
		_airborne_speed = 0.0
	else:
		_airborne_speed = 0.0
	if dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
		return
	if is_rolling():
		_roll(delta)
		return
	if is_on_floor() and Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = jump_velocity
	_update_crouch(Input.is_action_pressed("crouch"))
	aiming = Input.is_action_pressed("aim")
	# The click that captures the mouse shouldn't fire. Headless runs (tests) can't capture.
	if _hold_fire and not Input.is_action_pressed("fire"):
		_hold_fire = false
	var can_fire := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or DisplayServer.get_name() == "headless"
	var firing := can_fire and not _hold_fire and Input.is_action_pressed("fire")
	if firing and weapon.try_fire(aiming):
		_combat_face = 0.6

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _yaw.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var speed := walk_speed
	_sprinting = false
	if crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint") and not aiming and Game.carrying == "":
		speed = sprint_speed
		_sprinting = dir.length() > 0.3
	if aiming:
		speed = minf(speed, walk_speed * 0.7)
	if Game.carrying != "":
		speed *= carry_speed_factor
	velocity.x = move_toward(velocity.x, dir.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 30.0 * delta)

	# Face the crosshair while aiming or shooting; otherwise face the direction of travel.
	_combat_face = maxf(_combat_face - delta, 0.0)
	if aiming or _combat_face > 0.0:
		_body.rotation.y = lerp_angle(_body.rotation.y, _yaw.rotation.y, 20.0 * delta)
	elif dir.length() > 0.1:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
	move_and_slide()
	_footsteps(delta)


func _roll(delta: float) -> void:
	roll_t += delta
	var t := clampf(roll_t / ROLL_TIME, 0.0, 1.0)
	var speed := ROLL_SPEED * lerpf(1.0, 0.45, t * t)
	if Game.carrying != "":
		speed *= carry_speed_factor
	velocity.x = _roll_dir.x * speed
	velocity.z = _roll_dir.z * speed
	move_and_slide()
	if roll_t >= ROLL_TIME:
		roll_t = -1.0
		_roll_cool = ROLL_COOLDOWN
		_combat_face = 0.0


func _footsteps(delta: float) -> void:
	var moved := Vector2(velocity.x, velocity.z).length() * delta
	if not is_on_floor() or moved < 0.001:
		return
	_stride += moved
	if _stride >= (1.1 if crouching else 1.6):
		_stride = 0.0
		_foot = 1 - _foot
		var site = get_tree().get_first_node_in_group("crash_site")
		if site and site.in_pool(global_position):
			Vfx.splash(get_parent(), global_position + Vector3.UP * 0.05, 1.3 if _sprinting else 1.0)
			Sfx.play("splash_%d" % _foot, global_position, -12.0 if crouching else -6.0, 0.12)
		else:
			Sfx.play("footstep_%d" % _foot, global_position, -14.0 if crouching else -9.0, 0.1)


func _update_crouch(want: bool) -> void:
	if want == crouching:
		return
	# Stay crouched under low ceilings (crawlways) until there is room to stand.
	if not want and test_move(global_transform, Vector3.UP * (stand_height - crouch_height)):
		return
	crouching = want
	var h := crouch_height if crouching else stand_height
	_capsule.height = h
	_shape.position.y = h * 0.5
	_pitch.position.y = h - 0.1


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	rig = Rig.spawn("juno", _body)
	# Whatever component is being carried rides on the life-support pack.
	var mount := Rig.joint(rig, "PackMount")
	for id in Campaign.PACKS:
		var holder := Node3D.new()
		holder.name = "Pack_%s" % id
		var spec: Array = Campaign.PACKS[id]
		holder.position = Vector3(0.0, 0.0, 0.12 + spec[0].z * 0.5)
		(mount if mount else _body).add_child(holder)
		Rig.spawn(id, holder)
		holder.visible = false
		_packs[id] = holder


func _on_carrying_changed(item: String) -> void:
	for id in _packs:
		_packs[id].visible = id == item


func _on_upgrades_changed() -> void:
	var count := _plating_count()
	if count > _plating_seen:
		health += 40.0 * (count - _plating_seen)
	_plating_seen = count
	health = minf(health, max_health())
	health_changed.emit(health, max_health())
