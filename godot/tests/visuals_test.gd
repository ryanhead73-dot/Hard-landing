extends "res://tests/test_base.gd"
## Milestone 4 visuals: every Blender model is exported with the joints animation will need, the
## game uses them (player, wildlife, weapons, components, crates), per-creature materials stay
## separate, hit flashes and particles fire, surfaces get their detail, Kestrel's engines burn
## during the spool, and the compass reads the heading. Run:
##   godot --headless --path . res://tests/visuals_test.tscn

const MODELS := {
	"juno": ["Hips", "Spine", "Chest", "Neck", "Head", "ArmL", "ArmR", "ForearmL", "ForearmR", "LegL", "LegR", "ShinL", "ShinR", "PackMount"],
	"scuttler": ["Body", "Head", "JawL", "JawR", "LegL1", "LegL2", "LegL3", "LegR1", "LegR2", "LegR3", "FootL1", "FootR3"],
	"spitter": ["Body", "Neck", "Head", "Sac", "LegL1", "LegL2", "LegR1", "LegR2", "FootL1"],
	"ram": ["Body", "Head", "Tail", "LegFL", "LegFR", "LegBL", "LegBR", "FootFL"],
	"warden": ["Body", "Core", "Head", "PlateL", "PlateR", "ArmL", "ArmR", "FistL", "FistR", "LegL1", "LegR3"],
	"rifle": ["Muzzle"],
	"scattergun": ["Muzzle", "Pump"],
	"arc_lance": ["Muzzle"],
	"aux_cell": [], "manifold": [], "glazing": [], "struts": [], "wing_panel": [], "drive_coil": [], "nav_core": [], "crate": [],
	"prop_container": [], "prop_barrier": [], "prop_generator": [], "prop_pipes": [],
	"prop_shard_0": [], "prop_shard_1": [], "prop_shard_2": [], "prop_gear": ["Wheel"], "prop_gear_broken": ["Wheel"],
	"prop_mast": ["Dish"], "prop_mast_down": ["Dish"],
}


func _name() -> String:
	return "VISUALS TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	_models()
	_player_and_weapons()
	await _wildlife()
	_surfaces()
	await _crates()
	await _engines()
	await _compass()
	await _day_cycle()
	_world()
	finished = true


## The basin: flat where the game happens, rising elsewhere; the collider matches the mesh;
## pools sit in hollows; the walk from the ship to every site is clear of rocks.
func _world() -> void:
	var site: CrashSite = main.site
	var flat := [Vector3.ZERO, main.SPAWN]
	for id in main.sites:
		flat.append(main.sites[id].global_position)
		flat.append(main.sites[id].component_point())
	_check("the ground is flat at the ship and every site", flat.all(func(p): return absf(site.height_at(p.x, p.z)) < 0.01))
	var space := main.get_world_3d().direct_space_state
	var worst := 0.0
	var rises := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 200:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-150.0, 150.0)
		var q := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -10.0, z), Game.LAYER_WORLD)
		q.exclude = []
		var hit := space.intersect_ray(q)
		if hit.is_empty() or not (hit.collider as Node).name == "Ground":
			continue
		var h := site.height_at(x, z)
		worst = maxf(worst, absf(hit.position.y - h))
		if h > 1.0:
			rises += 1
	_check("the ground collider follows the terrain", worst < 0.6, "worst %.2f m" % worst)
	_check("the basin has hills between the paths", rises > 30, "%d of 200 samples" % rises)
	var pools_ok := site.pools.all(func(pool): return site.height_at(pool[0].x, pool[0].z) < CrashSite.WATER_Y - 0.2)
	_check("pools sit in hollows under the water line", pools_ok and site.pools.size() >= 10)
	var blocked := []
	for id in main.sites:
		var c: Vector3 = main.sites[id].global_position
		var flat_c := Vector3(c.x, 0.0, c.z)
		var from := flat_c.normalized() * 34.0 + Vector3.UP * 1.0
		var to := flat_c - flat_c.normalized() * 30.0 + Vector3.UP * 1.0
		var q := PhysicsRayQueryParameters3D.create(from, to, Game.LAYER_WORLD)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			blocked.append("%s by %s at %s" % [id, (hit.collider as Node).get_parent().name, hit.position])
	_check("the way to every site is clear of rocks", blocked.is_empty(), str(blocked))


func _models() -> void:
	var missing: PackedStringArray = []
	var holder := Node3D.new()
	add_child(holder)
	for model in MODELS:
		if not Rig.exists(model):
			missing.append(model)
			continue
		var rig := Rig.spawn(model, holder)
		for j in MODELS[model]:
			if Rig.joint(rig, j) == null:
				missing.append("%s/%s" % [model, j])
		if Rig.meshes(rig).is_empty():
			missing.append(model + " has no meshes")
	holder.queue_free()
	_check("every model is exported with its joints", missing.is_empty(), ", ".join(missing))
	# Sites: modelled props fitted to their collision boxes, and a debris field round each.
	var short: PackedStringArray = []
	for id in main.sites:
		var site: ExpeditionSite = main.sites[id]
		var debris := site.get_children().filter(func(c): return String(c.name).begins_with("Debris")).size()
		if debris < 5:
			short.append("%s: %d" % [id, debris])
	_check("every site has a debris field", short.is_empty(), ", ".join(short))
	var container := main.station.find_child("PropContainer", false, false) as Node3D
	var fitted := false
	if container:
		var box := ExpeditionSite._model_aabb(container)
		fitted = box.size.distance_to(Vector3(6.0, 2.6, 2.4)) < 0.3
	_check("the relay's container is a modelled prop fitted to its box", fitted)
	_check("a missing model falls back to an empty node", Rig.spawn("no_such_model", self) is Node3D and not Rig.exists("no_such_model"))


func _player_and_weapons() -> void:
	_check("Juno is the Blender model", player.rig != null and Rig.joint(player.rig, "Head") != null)
	var pack: Node3D = player._packs.get("aux_cell")
	_check("carried components use their models", pack != null and not Rig.meshes(pack).is_empty() and not pack.visible)
	Game.take_component("aux_cell")
	_check("the carried pack shows on Juno's back", pack.visible)
	Game.carrying = ""
	Game.carrying_changed.emit("")
	var w := player.weapon
	var muzzle_ok := true
	for id in Weapon.ORDER:
		var tip := Rig.joint(w._models[id], "Muzzle")
		muzzle_ok = muzzle_ok and tip != null and tip.global_position.distance_to(w._muzzle.global_position) < 0.02
	_check("every weapon's barrel ends at the muzzle point", muzzle_ok)
	w._show_flash()
	_check("firing shows the muzzle star", w._star.visible)
	_check("moss motes drift around the player", player.get_node_or_null("Motes") is CPUParticles3D)


func _wildlife() -> void:
	var at := Vector3(45.0, 0.5, 45.0)
	player.revive(at + Vector3(0.0, 0.0, 30.0))
	var a: Scuttler = main.spawn_scuttler(at)
	var b: Scuttler = main.spawn_scuttler(at + Vector3(4.0, 0.0, 0.0))
	a.target = null
	b.target = null
	await _frames(3)
	_check("wildlife wear their models", a._rig != null and Rig.joint(a._rig, "LegL1") != null)
	a._glow_mat.emission_energy_multiplier = 9.0
	_check("one scuttler's glow doesn't light the pack", b._glow_mat != a._glow_mat and b._glow_mat.emission_energy_multiplier < 9.0)
	a._flash()
	var mesh: MeshInstance3D = a._flash_meshes[0]
	_check("a hit flashes the whole model", mesh.material_overlay != null)
	await get_tree().create_timer(0.15).timeout
	_check("the flash clears", mesh.material_overlay == null)
	var before := _bursts()
	a.take_damage(9999.0, a.global_position, Vector3.FORWARD)
	_check("a death gives off a teal puff", _bursts() > before)
	var kinds_ok := true
	for kind in ["spitter", "ram", "warden"]:
		var e: Enemy = main.spawn_enemy(kind, at + Vector3(-10.0, 0.0, 0.0))
		e.target = null
		kinds_ok = kinds_ok and e._rig != null and not Rig.meshes(e._rig).is_empty()
	_check("spitter, ram and Warden wear their models", kinds_ok)
	var sp: Spitter = get_tree().get_nodes_in_group("enemies").filter(func(e): return e is Spitter)[0]
	_check("the spitter's sac glow is its own", sp._sac != null and sp._sac.resource_name == "acid_sac")
	var splash := Vfx.acid(main, at)
	_check("acid splashes", splash.is_inside_tree() and splash.emitting and splash.is_in_group("vfx_burst"))
	_clear_enemies()


func _bursts() -> int:
	return get_tree().get_nodes_in_group("vfx_burst").size()


func _surfaces() -> void:
	var hull := kestrel._mat("hull")
	_check("Kestrel's hull has panelling", hull.albedo_texture != null and hull.uv1_triplanar and not hull.uv1_world_triplanar)
	_check("glass and glow stay untextured", kestrel._mat("glass").albedo_texture == null and kestrel._mat("amber_glow").albedo_texture == null)
	var stone: StandardMaterial3D = main.site._mat(Color("1b1d1f"), 0.95)
	_check("the basin floor is basalt", stone.albedo_texture == Surfaces._textures("basalt")[0] and stone.uv1_world_triplanar)


func _crates() -> void:
	var relay: ExpeditionSite = main.sites["aux_power"]
	var lid0: StandardMaterial3D = relay._crates[0].get_meta("lid")
	var lid1: StandardMaterial3D = relay._crates[1].get_meta("lid")
	_check("crates use the model with a lit lid", lid0 != null and lid0.emission_enabled and lid0 != lid1)
	relay.search_crate(0)
	_check("a searched crate goes dark, the rest stay lit", not lid0.emission_enabled and lid1.emission_enabled)
	await _frames(1)


func _engines() -> void:
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	main.siege.pending = -1
	main.finale.start()
	main.finale.spool = 45.0
	await _frames(3)
	var ex: Array = kestrel._exhausts
	_check("the engines burn while they spool", kestrel.engine_power > 0.3 and ex.size() == 2 and ex[0].emitting)
	main.siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(2)
	_check("a dumped spool cuts the engines", kestrel.engine_power == 0.0 and not ex[0].emitting)
	_clear_enemies()


func _compass() -> void:
	player.revive(main.SPAWN)
	player.face(0.0)
	player.aim_at(player.global_position + Vector3(0.0, 1.5, -30.0))
	await _frames(3)
	var north: float = main.hud.compass_heading()
	player.aim_at(player.global_position + Vector3(30.0, 1.5, 0.0))
	await _frames(3)
	var east: float = main.hud.compass_heading()
	_check("compass reads north and east", (north < 5.0 or north > 355.0) and absf(east - 90.0) < 5.0, "north=%.0f east=%.0f" % [north, east])


func _day_cycle() -> void:
	var L: float = main.DAY_LENGTH
	_check("the day starts in daylight and reaches full dusk", main.daylight_at(0.0) == 0.0 and main.daylight_at(L * 0.675) > 0.99 and main.daylight_at(L * 0.99) < 0.05)
	var t0: float = main.day_time
	await get_tree().create_timer(0.6).timeout
	_check("the day moves on", main.day_time > t0)
	main.set_daylight(0.5)
	var sun: DirectionalLight3D = main._sun
	_check("dusk comes in gradually", absf(sun.light_energy - 0.625) < 0.01 and not main.dusk)
	main.set_daylight(1.0)
	_check("full dusk is dim amber", sun.light_energy < 0.3 and main.dusk and main.site._moss_mat.emission_energy_multiplier > 0.05)
	main.day_time = L * 0.5
	_check("the time of day is saved", is_equal_approx(float(main.save_state()["day_time"]), L * 0.5))
	main.set_daylight(0.0)
