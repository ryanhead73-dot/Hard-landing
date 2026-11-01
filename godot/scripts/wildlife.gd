class_name Wildlife
extends Node
## Life in the open basin between the sites, so the walks out and back are never empty:
## - Mire lurkers lie in the larger pools and wake the first time Juno comes near.
## - Roaming packs cross the ground ahead of her, more often and tougher as Kestrel comes back
##   to life (spitters once two repairs are in, rams from four). Never near the ship, never in
##   a site's own patch, never during a siege or the launch, and they wander off when left far
##   behind.
## main.gd owns one and calls update() twice a second while packs are on.

const LURKER_POOL_MIN := 4.5
const LURKER_POOLS := 4
const LURKER_WAKE := 48.0
## No roaming packs inside this radius of Kestrel (and no lurker pools).
const SHIP_CLEAR := 34.0
const BASIN_LIMIT := 140.0
## Seconds out in the open before the first pack, then between packs.
const ROAM_FIRST := 35.0
const ROAM_INTERVAL := Vector2(50.0, 90.0)
const ROAM_SPAWN := Vector2(27.0, 36.0)
const ROAM_MAX_ALIVE := 7
const ROAM_DESPAWN := 105.0

var main: Node
## [centre, radius, spawned] for each pool a lurker lives in.
var lurker_pools: Array = []
var roamers: Array[Enemy] = []
var packs_sent := 0

var _roam_timer := ROAM_FIRST


func setup(owner_main: Node) -> void:
	main = owner_main
	var ship: Vector3 = main.kestrel.global_position
	var candidates: Array = []
	for pool in main.site.pools:
		var centre: Vector3 = pool[0]
		if float(pool[1]) >= LURKER_POOL_MIN and _flat(centre - ship).length() > SHIP_CLEAR + float(pool[1]):
			candidates.append(pool)
	candidates.sort_custom(func(a, b): return float(a[1]) > float(b[1]))
	for pool in candidates.slice(0, LURKER_POOLS):
		lurker_pools.append([pool[0], pool[1], false])


## Ticks the basin: wakes lurkers in range, counts down to the next pack, culls far stragglers.
func update(delta: float) -> void:
	var player: Node3D = main.player
	if player == null or player.dead or Game.launched:
		return
	_wake_lurkers(player.global_position)
	roamers.assign(roamers.filter(func(e): return is_instance_valid(e) and not e.dead))
	for e in roamers.duplicate():
		if _flat(e.global_position - player.global_position).length() > ROAM_DESPAWN and not e.hunting:
			roamers.erase(e)
			e.queue_free()
	if not in_the_open(player.global_position):
		return
	_roam_timer -= delta
	if _roam_timer <= 0.0:
		_roam_timer = randf_range(ROAM_INTERVAL.x, ROAM_INTERVAL.y)
		send_pack()


func _wake_lurkers(pos: Vector3) -> void:
	for pool in lurker_pools:
		if pool[2] or _flat(pos - pool[0]).length() > LURKER_WAKE:
			continue
		pool[2] = true
		var lk: Lurker = main.spawn_enemy("lurker", pool[0])
		lk.pool_radius = pool[1]


## True out on the open basin: away from the ship, the sites, sieges and the finale.
func in_the_open(pos: Vector3) -> bool:
	if main.kestrel.is_inside(pos) or _flat(pos - main.kestrel.global_position).length() < SHIP_CLEAR:
		return false
	if main.siege.active >= 0 or Game.phase() == "launch" or Game.phase() == "done":
		return false
	for id in main.sites:
		var site: ExpeditionSite = main.sites[id]
		if _flat(pos - site.global_position).length() < site.wake_radius * 0.5:
			return false
	return true


## What the next pack is made of, by how far the repairs have come.
func pack_kinds() -> Array:
	var repairs := Game.repairs_done()
	var kinds := ["scuttler", "scuttler"]
	if randf() < 0.5:
		kinds.append("scuttler")
	if repairs >= 2 and randf() < 0.6:
		kinds.append("spitter")
	if repairs >= 4 and randf() < 0.4:
		kinds[0] = "ram"
	if Game.difficulty == 2:
		kinds.append("scuttler")
	return kinds


## Sends a pack across Juno's way: ahead of her toward her objective, off to one side, out of
## sight. Returns the pack (empty if there was no room for one).
func send_pack() -> Array[Enemy]:
	var pack: Array[Enemy] = []
	if roamers.size() >= ROAM_MAX_ALIVE:
		return pack
	var player: Node3D = main.player
	var at := _pack_point(player.global_position, _heading(player))
	if at == Vector3.INF:
		return pack
	for kind in pack_kinds():
		var p: Vector3 = at + Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		var e: Enemy = main.spawn_enemy(kind, p)
		e.add_to_group("roamers")
		roamers.append(e)
		pack.append(e)
	packs_sent += 1
	return pack


func _heading(player: Node3D) -> Vector3:
	var goal = main.call("_waypoint")
	if goal is Vector3:
		var d := _flat(goal - player.global_position)
		if d.length() > 1.0:
			return d.normalized()
	var fwd := _flat(-player.global_basis.z)
	return fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD


## A spot ahead and to one side, on open ground: not near the ship, a site, a pool or the rim.
func _pack_point(from: Vector3, heading: Vector3) -> Vector3:
	for attempt in 12:
		var angle := randf_range(-0.8, 0.8)
		var dist := randf_range(ROAM_SPAWN.x, ROAM_SPAWN.y)
		var p := from + heading.rotated(Vector3.UP, angle) * dist
		p.y = main.site.height_at(p.x, p.z)
		if _flat(p).length() > BASIN_LIMIT or main.site.in_pool(p):
			continue
		if _flat(p - main.kestrel.global_position).length() < SHIP_CLEAR:
			continue
		var near_site := false
		for id in main.sites:
			var site: ExpeditionSite = main.sites[id]
			if _flat(p - site.global_position).length() < site.wake_radius * 0.5:
				near_site = true
		if not near_site:
			return p
	return Vector3.INF


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
