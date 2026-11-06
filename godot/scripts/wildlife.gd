class_name Wildlife
extends Node
## Life in the open basin between the sites, so the walks out and back are never empty:
## - Mire lurkers lie in the larger pools and wake the first time Juno comes near.
## - Roaming packs cross the ground ahead of her, tougher as Kestrel comes back to life
##   (spitters once two repairs are in, skimmers overhead from three, rams from four). Never
##   near the ship, never in a site's own patch, never during a siege or the launch, and they
##   wander off when left far behind.
## - Drift caches: cargo flung loose by ships that came down over the years, half-buried out
##   between the paths, their locator beams showing from far off. Each holds scrap and supplies,
##   some a log, and a few sit on a scuttler nest that boils up when the lid comes off.
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
const CACHE_COUNT := 8
const CACHE_SEED := 7741
## Caches with a nest dug in under them.
const CACHE_GUARDED := [1, 4, 6]
const CACHE_SPACING := 24.0
## How close Juno must come for a cache to go on her map.
const CACHE_SPOT := 55.0
const CACHE_LINES := [
	[Story.JUNO, "Movement under the lid. Oh, that's a nest."],
	[Story.JUNO, "Should have checked the ground first. Here they come."],
	[Story.JUNO, "Of course it's guarded. Of course it is."],
]

var main: Node
## [centre, radius, spawned] for each pool a lurker lives in.
var lurker_pools: Array = []
var roamers: Array[Enemy] = []
var packs_sent := 0
var caches: Array[BasinCache] = []

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
	_place_caches()


## Ticks the basin: wakes lurkers in range, counts down to the next pack, culls far stragglers.
func update(delta: float) -> void:
	var player: Node3D = main.player
	if player == null or player.dead or Game.launched:
		return
	_wake_lurkers(player.global_position)
	_spot_caches(player.global_position)
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
	if repairs >= 3 and randf() < 0.45:
		kinds.append("skimmer")
		if repairs >= 5:
			kinds.append("skimmer")
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
	# Ahead first; if ahead is all ship, site, pool or rim, swing wider round to the sides.
	for attempt in 24:
		var spread := 0.8 if attempt < 12 else 1.8
		var angle := randf_range(-spread, spread)
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


# --- Drift caches ---------------------------------------------------------------------------

func _place_caches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = CACHE_SEED
	var spots: Array[Vector3] = []
	var tries := 0
	while spots.size() < CACHE_COUNT and tries < 3000:
		tries += 1
		var a := rng.randf() * TAU
		var d := rng.randf_range(SHIP_CLEAR + 12.0, 118.0)
		var p: Vector3 = main.kestrel.global_position + Vector3(cos(a) * d, 0.0, sin(a) * d)
		p.y = main.site.height_at(p.x, p.z)
		if _cache_spot_ok(p, spots):
			spots.append(p)
	for i in spots.size():
		var c := BasinCache.new()
		c.name = "DriftCache%d" % i
		c.index = i
		c.guarded = i in CACHE_GUARDED
		c.opened = i in Game.caches_opened
		add_child(c)
		c.global_position = spots[i]
		c.rotation.y = rng.randf() * TAU
		caches.append(c)


## Open, level ground off the paths, clear of the sites, the pools, rocks and the other caches.
func _cache_spot_ok(p: Vector3, others: Array[Vector3]) -> bool:
	if _flat(p).length() > BASIN_LIMIT - 20.0 or main.site.in_pool(p):
		return false
	if main.site.on_path(p.x, p.z, 11.0):
		return false
	for o in others:
		if _flat(p - o).length() < CACHE_SPACING:
			return false
	for id in main.sites:
		var site: ExpeditionSite = main.sites[id]
		if _flat(p - site.global_position).length() < site.wake_radius * 0.7:
			return false
	for pool in main.site.pools:
		if _flat(p - pool[0]).length() < float(pool[1]) + 6.0:
			return false
	# Level enough to sit on.
	for o in [Vector3(1.2, 0, 0), Vector3(-1.2, 0, 0), Vector3(0, 0, 1.2), Vector3(0, 0, -1.2)]:
		if absf(main.site.height_at(p.x + o.x, p.z + o.z) - p.y) > 0.45:
			return false
	# No boulder or column in the way.
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 1.6
	q.shape = sphere
	q.transform = Transform3D(Basis(), p + Vector3.UP * 2.0)
	q.collision_mask = Game.LAYER_WORLD
	return space.intersect_shape(q, 1).is_empty()


## Caches within sight of Juno go on her map.
func _spot_caches(pos: Vector3) -> void:
	for c in caches:
		if not c.index in Game.caches_seen and _flat(pos - c.global_position).length() < CACHE_SPOT:
			Game.caches_seen.append(c.index)


## What [E] does near an unopened cache, or {} when none is in reach.
func cache_interaction(pos: Vector3, reach: float) -> Dictionary:
	for c in caches:
		if not c.opened and _flat(pos - c.global_position).length() < reach + 0.4:
			return {"label": "[E] Prise open the drift cache", "action": open_cache.bind(c.index)}
	return {}


## Scanner contacts for the caches still shut within `radius`.
func cache_marks(pos: Vector3, radius: float) -> Array:
	var marks := []
	for c in caches:
		if not c.opened and c.global_position.distance_to(pos) < radius:
			marks.append({"pos": c.global_position, "kind": "crate"})
	return marks


## Opens cache `i`: scrap, a share of supplies, its log if it holds one, and the nest if there is
## one. Returns the guards it woke (empty for most).
func open_cache(i: int) -> Array[Enemy]:
	var guards: Array[Enemy] = []
	if i < 0 or i >= caches.size() or not caches[i].open():
		return guards
	var c := caches[i]
	Game.caches_opened.append(i)
	if main.player and main.player.anim:
		main.player.anim.play("interact")
	var rng := RandomNumberGenerator.new()
	rng.seed = CACHE_SEED + i * 31
	var found := rng.randi_range(12, 22) + (8 if c.guarded else 0)
	Game.add_scrap(found)
	var extras: PackedStringArray = []
	var limited := Game.ammo_weapons()
	if not limited.is_empty():
		var w: String = limited[rng.randi() % limited.size()]
		var got := Game.add_ammo(w, main.AMMO_BUNDLE[w])
		if got > 0:
			extras.append("%d %s rounds" % [got, Weapon.SPECS[w]["name"].to_lower()])
	if (c.guarded or rng.randf() < 0.5) and Game.add_charges(1) > 0:
		extras.append("an arc charge")
	if rng.randf() < 0.4 and Game.add_stims(1) > 0:
		extras.append("a stim")
	var log_id := Story.log_at("basin", "cache:%d" % i)
	if log_id != "":
		Game.find_log(log_id)
	if main.hud:
		main.hud.show_message("Drift cache: %d scrap%s." % [found, "" if extras.is_empty() else ", " + " and ".join(extras)])
	if c.guarded:
		guards = _wake_nest(c)
	return guards


## The nest under a cache boils up: scuttlers burst out of the ground around it, already angry.
func _wake_nest(c: BasinCache) -> Array[Enemy]:
	var guards: Array[Enemy] = []
	var kinds := ["scuttler", "scuttler", "scuttler"]
	if Game.repairs_done() >= 2:
		kinds.append("spitter")
	if Game.difficulty == 2:
		kinds.append("scuttler")
	for k in kinds.size():
		var a := TAU * k / kinds.size() + randf_range(-0.3, 0.3)
		var p := c.global_position + Vector3(cos(a), 0.0, sin(a)) * randf_range(5.0, 7.5)
		p.y = main.site.height_at(p.x, p.z)
		var e: Enemy = main.spawn_enemy(kinds[k], p)
		e.add_to_group("roamers")
		roamers.append(e)
		guards.append(e)
		Vfx.burst(main, p + Vector3.UP * 0.2, Color("4a4038"), 18, 4.0, 0.1, 0.8, Vector3.UP, 35.0, -9.0)
	for e in guards:
		e.alert(false)
	Sfx.play("scuttler_lunge", c.global_position, 2.0, 0.1)
	if main.voice:
		main.voice.say_line(CACHE_LINES[CACHE_GUARDED.find(c.index) % CACHE_LINES.size()])
	return guards


## After a load: the caches already opened go dark.
func restore() -> void:
	for c in caches:
		if c.index in Game.caches_opened and not c.opened:
			c.set_opened()


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
