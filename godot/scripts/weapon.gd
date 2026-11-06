class_name Weapon
extends Node3D
## The player's guns: salvage rifle, scattergun and arc lance. One node switches between them.
## Shots are traced from the camera so they land on the crosshair, then drawn from the muzzle so
## they read in third person. Ammo lives in Game so it saves with the rest of the inventory.

signal fired
signal ammo_changed(in_mag: int, mag_size: int, reloading: bool)
signal hit_confirmed(killed: bool)
## A shot landed on a weak spot (emitted after hit_confirmed).
signal crit_landed
## A shot that only glanced off armour (no kill, no weak spot).
signal deflected
signal switched(id: String)

const ORDER: Array[String] = ["rifle", "scattergun", "arc_lance"]
## reserve_max -1 means unlimited reserve. pierce: how many enemies one shot passes through.
const SPECS := {
	"rifle": {
		"name": "Salvage rifle", "damage": 18.0, "interval": 0.11, "mag": 24, "reload": 1.6, "pellets": 1,
		"hip": 0.012, "aim": 0.003, "range": 150.0, "reserve_max": -1, "pierce": 1, "sound": "rifle_shot",
	},
	"scattergun": {
		"name": "Scattergun", "damage": 11.0, "interval": 0.75, "mag": 6, "reload": 2.0, "pellets": 8,
		"hip": 0.075, "aim": 0.055, "range": 28.0, "reserve_max": 36, "pierce": 1, "sound": "scatter_shot",
	},
	"arc_lance": {
		"name": "Arc lance", "damage": 80.0, "interval": 1.0, "mag": 4, "reload": 2.4, "pellets": 1,
		"hip": 0.004, "aim": 0.0, "range": 90.0, "reserve_max": 16, "pierce": 4, "sound": "lance_shot",
	},
}
const SWITCH_TIME := 0.35
## Switching dips the muzzle this far (radians) as the old gun goes down and the new one comes up.
const SWITCH_DIP := 0.5
## Sustained fire blooms the spread (radians added per shot, and the most it can add); it settles
## once the trigger is let go.
const BLOOM := {"rifle": 0.0022, "scattergun": 0.0, "arc_lance": 0.0}
const BLOOM_MAX := 0.018
const BLOOM_SETTLE := 0.09
## Spent casings: colour and size per weapon (the arc lance has none).
const CASINGS := {"rifle": [Color("c9a24a"), 0.022], "scattergun": [Color("9c3324"), 0.035]}

var camera: Camera3D
var shooter: CollisionObject3D
var current := "rifle"
var reloading := false
## Rounds in the current weapon's magazine (kept in Game.ammo).
var in_mag: int:
	get:
		return Game.ammo_in_mag(current)
	set(value):
		Game.set_ammo(current, value, Game.ammo_reserve(current))
		ammo_changed.emit(in_mag, mag_size(), reloading)

var _cooldown := 0.0
var _reload_left := 0.0
var _muzzle: Node3D
var _star: MeshInstance3D
var _flash: OmniLight3D
var _tracer_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _models: Dictionary = {}
## 0 standing still .. 1 sprinting or in the air: moving spreads shots. The player sets it.
var move_penalty := 0.0
var bloom := 0.0
var _since_shot := 9.0
var _shots := 0
## Seconds left in a weapon switch, and the gun being put away.
var _swap_left := 0.0
var _swap_from := ""


func _ready() -> void:
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0.0, 0.01, -0.48)
	add_child(_muzzle)
	_flash = OmniLight3D.new()
	_flash.light_color = Color("ffc070")
	_flash.light_energy = 3.0
	_flash.omni_range = 4.0
	_flash.visible = false
	_muzzle.add_child(_flash)
	_star = Vfx.muzzle_star(Color("ffc070"))
	_muzzle.add_child(_star)
	_build_models()
	_tracer_mat = _glow_mat(Color("ffd08a"), Color("ffb24d"), 4.0)
	_beam_mat = _glow_mat(Color("bfeeff"), Color("7fd6ff"), 7.0)
	Game.upgrades_changed.connect(_on_upgrades_changed)
	Game.inventory_changed.connect(_emit_ammo)
	_show_model()


func _process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_since_shot += delta
	if _swap_left > 0.0:
		_swap_left = maxf(_swap_left - delta, 0.0)
		_show_model()
	if _since_shot > 0.12:
		bloom = move_toward(bloom, 0.0, BLOOM_SETTLE * delta)
	if reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_finish_reload()


func spec(id := "") -> Dictionary:
	return SPECS[id if id != "" else current]


func mag_size(id := "") -> int:
	id = id if id != "" else current
	var size: int = SPECS[id]["mag"]
	match id:
		"rifle":
			size += 12 if Game.has_upgrade("extended_mag") else 0
		"scattergun":
			size += 2 if Game.has_upgrade("scatter_choke") else 0
		"arc_lance":
			size += 2 if Game.has_upgrade("arc_capacitor") else 0
	return size


func shot_damage() -> float:
	return float(spec()["damage"]) * (1.3 if Game.has_upgrade("heavy_rounds") else 1.0)


func fire_interval() -> float:
	return float(spec()["interval"]) * (0.8 if Game.has_upgrade("rapid_cycler") else 1.0)


func reload_time() -> float:
	var t: float = spec()["reload"]
	if current == "arc_lance" and Game.has_upgrade("arc_capacitor"):
		t *= 0.7
	return t


## The spread a shot fired now would have: the weapon's base, widened by moving, plus bloom.
## The HUD sizes the crosshair from it.
func current_spread(aiming: bool) -> float:
	return spread(aiming) * (1.0 + 1.5 * move_penalty) + bloom * (0.5 if aiming else 1.0)


func spread(aiming: bool) -> float:
	var s: float = spec()["aim" if aiming else "hip"]
	if current == "scattergun" and Game.has_upgrade("scatter_choke"):
		s *= 0.6
	return s


## Switches to an owned weapon. Cancels a reload in progress.
func equip(id: String) -> bool:
	if id == current or not Game.owns_weapon(id):
		return false
	_swap_from = current if _swap_left <= SWITCH_TIME * 0.5 else _swap_from
	current = id
	reloading = false
	_cooldown = SWITCH_TIME
	_swap_left = SWITCH_TIME
	_show_model()
	Sfx.play("weapon_switch", null, -8.0, 0.0)
	switched.emit(id)
	_emit_ammo()
	return true


## Cycles through owned weapons: +1 next, -1 previous.
func cycle(step: int) -> void:
	var owned := ORDER.filter(func(w): return Game.owns_weapon(w))
	if owned.size() < 2:
		return
	var i := owned.find(current)
	equip(owned[(i + step + owned.size()) % owned.size()])


func start_reload() -> void:
	if reloading or in_mag >= mag_size() or Game.ammo_reserve(current) == 0:
		return
	reloading = true
	_reload_left = reload_time()
	Sfx.play("rifle_reload", null, -4.0, 0.0)
	ammo_changed.emit(in_mag, mag_size(), true)


func _finish_reload() -> void:
	reloading = false
	var need := mag_size() - in_mag
	var reserve := Game.ammo_reserve(current)
	var take := need if reserve < 0 else mini(need, reserve)
	Game.set_ammo(current, in_mag + take, reserve if reserve < 0 else reserve - take)
	_emit_ammo()


## Fills every owned weapon's magazine and reserve (respawn and the armoury).
func refill() -> void:
	reloading = false
	for id in ORDER:
		if Game.owns_weapon(id):
			var reserve_max: int = SPECS[id]["reserve_max"]
			Game.set_ammo(id, mag_size(id), reserve_max)
	_emit_ammo()


## Fires one shot if the weapon is ready. Returns true when it fired.
func try_fire(aiming: bool) -> bool:
	if reloading or _cooldown > 0.0 or camera == null:
		return false
	if in_mag <= 0:
		Sfx.play("rifle_empty", null, -6.0)
		start_reload()
		return false
	Game.set_ammo(current, in_mag - 1, Game.ammo_reserve(current))
	_cooldown = fire_interval()
	var s := spec()
	var hit_any := false
	var killed_any := false
	var crit_any := false
	var armored_all := true
	for p in int(s["pellets"]):
		var result := _trace(current_spread(aiming), float(s["range"]), int(s["pierce"]))
		hit_any = hit_any or result[0]
		killed_any = killed_any or result[1]
		crit_any = crit_any or result[2]
		armored_all = armored_all and (result[3] or not result[0])
	if hit_any:
		hit_confirmed.emit(killed_any)
		if crit_any:
			crit_landed.emit()
		if armored_all and not killed_any and not crit_any:
			# The glance itself (sparks, knock) plays at the plate; this is only the marker.
			deflected.emit()
		else:
			var tick := "kill_tick" if killed_any else ("hit_crit" if crit_any else "hit_tick")
			Sfx.play(tick, null, -4.0, 0.0)
	bloom = minf(bloom + float(BLOOM.get(current, 0.0)), BLOOM_MAX)
	_since_shot = 0.0
	_shots += 1
	_show_flash()
	_eject()
	Sfx.play(s["sound"], null, -3.0, 0.08)
	fired.emit()
	_emit_ammo()
	if in_mag == 0:
		start_reload()
	return true


## One ray (or pellet). Returns [hit an enemy, killed one, hit a weak spot, only glanced off armour].
func _trace(spread_amount: float, max_range: float, pierce: int) -> Array:
	var dir := -camera.global_basis.z
	dir = dir.rotated(camera.global_basis.x, randf_range(-spread_amount, spread_amount))
	dir = dir.rotated(camera.global_basis.y, randf_range(-spread_amount, spread_amount)).normalized()
	# Start past the player so walls behind the camera never eat the shot.
	var skip := camera.global_position.distance_to(_muzzle.global_position) * 0.8
	var origin := camera.global_position + dir * skip
	var exclude: Array[RID] = []
	if shooter:
		exclude.append(shooter.get_rid())
	var space := get_world_3d().direct_space_state
	var end := origin + dir * max_range
	var hit := false
	var killed := false
	var crit := false
	var armored := true
	var damage := shot_damage()
	for i in pierce:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_range, Game.LAYER_WORLD | Game.LAYER_ENEMY)
		query.exclude = exclude
		var result := space.intersect_ray(query)
		if result.is_empty():
			break
		end = result.position
		var target: Object = result.collider
		if target.has_method("take_damage"):
			# Scattergun pellets lose punch with distance.
			var falloff := 1.0
			if current == "scattergun":
				falloff = clampf(1.0 - (origin.distance_to(end) - 8.0) / 20.0, 0.35, 1.0)
			killed = target.take_damage(damage * falloff, result.position, dir) or killed
			crit = crit or bool(target.get("last_hit_crit"))
			armored = armored and bool(target.get("last_hit_armored"))
			hit = true
			_impact(result.position, result.normal, true, dir)
			exclude.append((target as CollisionObject3D).get_rid())
			continue
		if target.has_meta("on_hit"):
			(target.get_meta("on_hit") as Callable).call()
		_impact(result.position, result.normal)
		break
	if current == "arc_lance":
		_beam(_muzzle.global_position, end)
	else:
		_tracer(_muzzle.global_position, end)
	return [hit, killed, crit, hit and armored]


func _emit_ammo() -> void:
	ammo_changed.emit(in_mag, mag_size(), reloading)


func _on_upgrades_changed() -> void:
	_emit_ammo()


# --- Visuals ------------------------------------------------------------------------------

func _build_models() -> void:
	for id in ORDER:
		var holder := _model(id)
		var rig := Rig.spawn(id, holder)
		# Line each model's muzzle up with the shared muzzle point, so tracers leave the barrel.
		var tip := Rig.joint(rig, "Muzzle")
		if tip:
			rig.position = _muzzle.position - rig.to_local(tip.global_position)


func _model(id: String) -> Node3D:
	var n := Node3D.new()
	n.name = id
	add_child(n)
	_models[id] = n
	return n


## 0 normally; rises to 1 halfway through a switch (old gun down, new one about to come up).
func swap_dip() -> float:
	if _swap_left <= 0.0:
		return 0.0
	var k := 1.0 - _swap_left / SWITCH_TIME
	return 1.0 - absf(2.0 * k - 1.0)


## The gun in her hands: the old one until halfway through a switch, then the new one, each
## tipped muzzle-down by the dip.
func shown_model() -> String:
	return _swap_from if _swap_left > SWITCH_TIME * 0.5 and _swap_from != "" else current


func _show_model() -> void:
	var shown := shown_model()
	var dip := ease(swap_dip(), -2.0) * SWITCH_DIP
	for id in _models:
		var m: Node3D = _models[id]
		m.visible = id == shown
		m.rotation.x = -dip if id == shown else 0.0


func _glow_mat(albedo: Color, emission: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.emission_enabled = true
	m.emission = emission
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _show_flash() -> void:
	_flash.light_color = Color("9fd8ff") if current == "arc_lance" else Color("ffc070")
	_flash.visible = true
	_star.visible = true
	_star.rotation.z = randf() * TAU
	_star.scale = Vector3.ONE * (1.6 if current == "scattergun" else 1.0) * randf_range(0.8, 1.2)
	await get_tree().create_timer(0.04).timeout
	if is_instance_valid(_flash):
		_flash.visible = false
		_star.visible = false


## A spent casing flicked out of the ejection port to the right, and every few shots a wisp of
## smoke from the muzzle.
func _eject() -> void:
	if not is_inside_tree() or not is_visible_in_tree():
		return
	var scene := get_tree().current_scene
	if CASINGS.has(current):
		var c: Array = CASINGS[current]
		var port := global_transform * Vector3(0.05, 0.04, 0.02)
		var out := (global_basis.x * 1.0 + global_basis.y * 0.7 + global_basis.z * 0.2).normalized()
		Vfx.burst(scene, port, c[0], 1, 2.4, c[1], 0.6, out, 18.0, -9.8)
	if _shots % 3 == 0 or current != "rifle":
		Vfx.burst(scene, _muzzle.global_position, Color(0.55, 0.55, 0.52, 0.5), 2, 0.4, 0.09, 0.5, Vector3.UP, 30.0, 0.6)


func _tracer(from: Vector3, to: Vector3) -> void:
	_line(from, to, 0.015, _tracer_mat, 0.05)


func _beam(from: Vector3, to: Vector3) -> void:
	_line(from, to, 0.06, _beam_mat, 0.18)


func _line(from: Vector3, to: Vector3, radius: float, mat: Material, life: float) -> void:
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var tracer := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = length
	cyl.radial_segments = 4
	tracer.mesh = cyl
	tracer.material_override = mat
	tracer.top_level = true
	add_child(tracer)
	var mid := (from + to) * 0.5
	var axis := (to - from) / length
	var side := axis.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	tracer.global_transform = Transform3D(Basis(side, axis, side.cross(axis)), mid)
	get_tree().create_timer(life).timeout.connect(tracer.queue_free)


## Sparks where a shot lands. On a creature, a spray of dark ichor out of the far side too, so a
## hit reads as a hit even at range; on rock, a puff of grit.
func _impact(pos: Vector3, normal: Vector3, flesh := false, dir := Vector3.ZERO) -> void:
	if is_inside_tree():
		var scene := get_tree().current_scene
		if flesh:
			Vfx.burst(scene, pos, Color("1d4a44"), 8, 3.2, 0.07, 0.45, (dir + normal * 0.4).normalized(), 35.0, -9.0)
		elif current != "arc_lance":
			Vfx.burst(scene, pos + normal * 0.05, Color("6c6a64"), 6, 1.6, 0.12, 0.6, normal, 40.0, -2.0)
	var sparks := CPUParticles3D.new()
	sparks.top_level = true
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 10
	sparks.lifetime = 0.35
	sparks.direction = normal
	sparks.spread = 50.0
	sparks.initial_velocity_min = 2.0
	sparks.initial_velocity_max = 5.0
	sparks.scale_amount_min = 0.03
	sparks.scale_amount_max = 0.06
	var quad := QuadMesh.new()
	quad.material = _beam_mat if current == "arc_lance" else _tracer_mat
	sparks.mesh = quad
	add_child(sparks)
	sparks.global_position = pos
	sparks.emitting = true
	get_tree().create_timer(0.6).timeout.connect(sparks.queue_free)
