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
var _since_damage := 99.0
var _combat_face := 0.0
var _plating_seen := 0
var _stride := 0.0
var _foot := 0
var _hold_fire := false


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
	_body.add_child(weapon)

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


func take_damage(amount: float, _from: Vector3 = Vector3.ZERO) -> bool:
	if dead:
		return false
	health = maxf(health - amount, 0.0)
	_since_damage = 0.0
	Sfx.play("player_hurt", null, -3.0)
	damaged.emit(amount)
	health_changed.emit(health, max_health())
	if health <= 0.0:
		dead = true
		velocity = Vector3.ZERO
		died.emit()
		return true
	return false


func revive(at: Vector3) -> void:
	dead = false
	health = max_health()
	velocity = Vector3.ZERO
	global_position = at
	face(0.0)
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


func _process(delta: float) -> void:
	var t := clampf(delta * 12.0, 0.0, 1.0)
	_camera.fov = lerpf(_camera.fov, aim_fov if aiming else fov, t)
	_arm.spring_length = lerpf(_arm.spring_length, aim_boom_length if aiming else boom_length, t)
	_arm.position.x = lerpf(_arm.position.x, aim_shoulder_offset if aiming else shoulder_offset, t)
	_since_damage += delta
	if not dead and _since_damage > regen_delay and health < max_health():
		health = minf(health + regen_rate * delta, max_health())
		health_changed.emit(health, max_health())


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	if dead:
		velocity.x = move_toward(velocity.x, 0.0, 20.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 20.0 * delta)
		move_and_slide()
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
	if crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint") and not aiming and Game.carrying == "":
		speed = sprint_speed
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


func _footsteps(delta: float) -> void:
	var moved := Vector2(velocity.x, velocity.z).length() * delta
	if not is_on_floor() or moved < 0.001:
		return
	_stride += moved
	if _stride >= (1.1 if crouching else 1.6):
		_stride = 0.0
		_foot = 1 - _foot
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
	_body.scale.y = h / stand_height
	_pitch.position.y = h - 0.1


func _build_body() -> void:
	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color("4a5a66")
	var torso := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = radius
	capsule_mesh.height = stand_height
	torso.mesh = capsule_mesh
	torso.material_override = suit
	torso.position.y = stand_height * 0.5
	_body.add_child(torso)
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("f2a93b")
	glow.emission_enabled = true
	glow.emission = Color("f2a93b")
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.4, 0.12, 0.12)
	visor.mesh = visor_mesh
	visor.material_override = glow
	visor.position = Vector3(0.0, 1.58, -0.3)
	_body.add_child(visor)
	# Whatever component is being carried rides on the back.
	for id in Campaign.PACKS:
		var spec: Array = Campaign.PACKS[id]
		var pack := MeshInstance3D.new()
		pack.name = "Pack_%s" % id
		var box := BoxMesh.new()
		box.size = spec[0]
		pack.mesh = box
		var mat := glow.duplicate() as StandardMaterial3D
		mat.albedo_color = spec[1]
		mat.emission = spec[1]
		mat.emission_energy_multiplier = spec[2]
		pack.material_override = mat
		pack.position = Vector3(0.0, 1.2, 0.3 + spec[0].z * 0.5)
		pack.visible = false
		_body.add_child(pack)
		_packs[id] = pack


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
