class_name Player
extends CharacterBody3D
## Greybox third-person player: just enough to walk Kestrel and judge camera clearance.

@export var walk_speed := 4.0
@export var sprint_speed := 7.0
@export var crouch_speed := 2.0
@export var jump_velocity := 4.6
@export var mouse_sensitivity := 0.0025
@export var boom_length := 2.5
@export var shoulder_offset := 0.45
@export var stand_height := 1.8
@export var crouch_height := 1.1
@export var radius := 0.35

var crouching := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _yaw: Node3D
var _pitch: Node3D
var _arm: SpringArm3D
var _camera: Camera3D
var _body: Node3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _flashlight: SpotLight3D


func _ready() -> void:
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(46.0)

	_capsule = CapsuleShape3D.new()
	_capsule.radius = radius
	_capsule.height = stand_height
	_shape = CollisionShape3D.new()
	_shape.shape = _capsule
	_shape.position.y = stand_height * 0.5
	add_child(_shape)

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
	var visor := MeshInstance3D.new()
	var visor_mesh := BoxMesh.new()
	visor_mesh.size = Vector3(0.4, 0.12, 0.12)
	visor.mesh = visor_mesh
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("f2a93b")
	glow.emission_enabled = true
	glow.emission = Color("f2a93b")
	visor.material_override = glow
	visor.position = Vector3(0.0, 1.58, -0.3)
	_body.add_child(visor)

	_yaw = Node3D.new()
	_yaw.name = "CameraYaw"
	add_child(_yaw)
	_pitch = Node3D.new()
	_pitch.position.y = 1.6
	_yaw.add_child(_pitch)
	_arm = SpringArm3D.new()
	_arm.spring_length = boom_length
	_arm.margin = 0.15
	_arm.position.x = shoulder_offset
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_pitch.add_child(_arm)
	_camera = Camera3D.new()
	_camera.fov = 70.0
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


func boom_current() -> float:
	return _arm.get_hit_length()


func face(yaw: float) -> void:
	_yaw.rotation.y = yaw
	_body.rotation.y = yaw


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		_yaw.rotate_y(-motion.relative.x * mouse_sensitivity)
		_pitch.rotation.x = clampf(_pitch.rotation.x - motion.relative.y * mouse_sensitivity, deg_to_rad(-70.0), deg_to_rad(50.0))
	elif event.is_action_pressed("flashlight"):
		_flashlight.visible = not _flashlight.visible


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump") and not crouching:
		velocity.y = jump_velocity
	_update_crouch(Input.is_action_pressed("crouch"))

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := _yaw.global_basis * Vector3(input.x, 0.0, input.y)
	dir.y = 0.0
	dir = dir.normalized() * minf(input.length(), 1.0)
	var speed := walk_speed
	if crouching:
		speed = crouch_speed
	elif Input.is_action_pressed("sprint"):
		speed = sprint_speed
	velocity.x = move_toward(velocity.x, dir.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 30.0 * delta)
	if dir.length() > 0.1:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-dir.x, -dir.z), 12.0 * delta)
	move_and_slide()


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
	_pitch.position.y = h - 0.2
