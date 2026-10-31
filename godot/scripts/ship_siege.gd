class_name ShipSiege
extends Node
## Wildlife assaults on Kestrel. After certain repairs the ship's heat draws them in: when the
## player is back near the ship, waves come over the rim and go for the hull. Clear every wave to
## drive them off. If the hull fails they scatter, take a cut of the scrap, and come again later.

signal started(index: int)
signal wave_started(wave: int, total: int)
signal ended(success: bool)
signal hull_changed(hull: float, max_hull: float)

## Waves per siege: each wave is a list of enemy kinds. Index = which siege.
const SIEGES := [
	[["scuttler", "scuttler", "scuttler", "scuttler"], ["scuttler", "scuttler", "spitter", "scuttler", "scuttler"]],
	[["scuttler", "scuttler", "spitter", "scuttler", "scuttler"], ["ram", "scuttler", "scuttler", "spitter", "scuttler", "scuttler"]],
	[["scuttler", "spitter", "scuttler", "spitter", "scuttler", "scuttler"], ["ram", "scuttler", "scuttler", "spitter", "ram", "scuttler"], ["scuttler", "scuttler", "spitter", "spitter", "scuttler", "scuttler", "scuttler"]],
]
## Which repair arms which siege.
const ARMED_BY := {"canopy": 0, "landing_gear": 1, "wing": 2}
const MAX_HULL := 300.0
const TRIGGER_RANGE := 35.0
const ARM_DELAY := 6.0
const RETRY_DELAY := 25.0
const WAVE_GAP := 4.0
const SPAWN_RADIUS := Vector2(42.0, 55.0)
## Within this range of the player, a siege enemy forgets the hull and goes for them.
const AGGRO_RANGE := 8.0
const REWARD_SCRAP := 30
const FAIL_SCRAP_LOSS := 0.25

## Callable(kind: String, at: Vector3) -> Enemy, supplied by main.
var spawner: Callable
var kestrel: Kestrel
var player: Player

## Siege index waiting to happen, or -1.
var pending := -1
## When false, armed sieges wait and never start (tests that cover other systems turn this off).
var enabled := true
var active := -1
var wave := -1
var hull := MAX_HULL

var _arm_timer := 0.0
var _enemies: Array[Enemy] = []
var _gap := 0.0
var _retarget := 0.0
var _points: Array[HullPoint] = []


func _ready() -> void:
	for p in kestrel.hull_points():
		var hp := HullPoint.new()
		hp.siege = self
		kestrel.add_child(hp)
		hp.position = p
		_points.append(hp)


## Queues siege `index` to start the next time the player is home.
func arm(index: int, delay := ARM_DELAY) -> void:
	if index < 0 or index >= SIEGES.size():
		return
	pending = index
	_arm_timer = delay


func is_active() -> bool:
	return active >= 0


func _physics_process(delta: float) -> void:
	if active < 0:
		_arm_timer -= delta
		if enabled and pending >= 0 and _arm_timer <= 0.0 and not player.dead and player.global_position.distance_to(kestrel.global_position) < TRIGGER_RANGE:
			start(pending)
		return
	_enemies = _enemies.filter(func(e): return is_instance_valid(e) and not e.dead)
	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = 0.4
		_steer_enemies()
	if _enemies.is_empty():
		_gap -= delta
		if _gap <= 0.0:
			if wave + 1 < SIEGES[active].size():
				_spawn_wave(wave + 1)
			else:
				_finish(true)


## Starts a siege now (tests and scripted moments use this directly).
func start(index: int) -> void:
	active = index
	pending = -1
	hull = MAX_HULL
	hull_changed.emit(hull, MAX_HULL)
	started.emit(index)
	_spawn_wave(0)


func damage_hull(amount: float) -> void:
	if active < 0:
		return
	hull = maxf(hull - amount, 0.0)
	hull_changed.emit(hull, MAX_HULL)
	if hull <= 0.0:
		_finish(false)


func siege_enemies() -> Array[Enemy]:
	return _enemies


func _spawn_wave(i: int) -> void:
	wave = i
	_gap = WAVE_GAP
	var kinds: Array = SIEGES[active][i]
	var base := randf() * TAU
	for k in kinds.size():
		# They come over the rim from one side, in a spread.
		var a := base + randf_range(-0.7, 0.7)
		var r := randf_range(SPAWN_RADIUS.x, SPAWN_RADIUS.y)
		var at := kestrel.global_position + Vector3(cos(a) * r, 0.0, sin(a) * r)
		at.y = 0.5
		var e: Enemy = spawner.call(kinds[k], at)
		e.leash_range = 999.0
		e.target = _nearest_point(e.global_position)
		e.alert(false)
		_enemies.append(e)
	wave_started.emit(i, SIEGES[active].size())
	Sfx.play("siege_horn", null, -2.0, 0.0)


func _steer_enemies() -> void:
	for e in _enemies:
		var near_player := not player.dead and e.global_position.distance_to(player.global_position) < AGGRO_RANGE
		var want: Node3D = player if near_player else _nearest_point(e.global_position)
		if e.target != want:
			e.target = want
		# After a death and respawn, the pack picks the assault back up.
		if not e.hunting:
			e.alert(false)


func _nearest_point(from: Vector3) -> HullPoint:
	var best: HullPoint = null
	var best_d := INF
	for p in _points:
		var d := p.global_position.distance_to(from)
		if d < best_d:
			best = p
			best_d = d
	return best


func _finish(success: bool) -> void:
	var index := active
	active = -1
	wave = -1
	if success:
		Game.add_scrap(REWARD_SCRAP)
		Game.add_stims(1)
		Game.message.emit("They've scattered. Kestrel held. You pick %d scrap out of the wreckage they left." % REWARD_SCRAP)
	else:
		var lost := int(Game.scrap * FAIL_SCRAP_LOSS)
		Game.scrap -= lost
		Game.scrap_changed.emit(Game.scrap)
		Game.message.emit("The hull's breached and the stores are torn open: %d scrap gone. They'll be back." % lost)
		for e in _enemies:
			if is_instance_valid(e):
				e.queue_free()
		arm(index, RETRY_DELAY)
	_enemies.clear()
	hull_changed.emit(-1.0, MAX_HULL)
	ended.emit(success)
