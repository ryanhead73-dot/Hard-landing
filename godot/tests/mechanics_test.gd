extends "res://tests/test_base.gd"
## Milestone 2 mechanics: weapons and ammo, stims, fabricator list, inventory, the spitter, ram and
## Warden, ship sieges, difficulty, balance numbers, save/load and the title screen. Run:
##   godot --headless --path . res://tests/mechanics_test.tscn

const ARENA := Vector3(45.0, 0.5, 45.0)


func _name() -> String:
	return "MECHANICS TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	await _weapons()
	await _supplies()
	await _spitter()
	await _ram()
	await _warden()
	await _siege()
	_difficulty_and_balance()
	await _save_load()
	await _title()
	finished = true


func _weapons() -> void:
	var w := player.weapon
	_check("start with the rifle only", Game.weapons == ["rifle"] and w.current == "rifle")
	_check("can't equip a weapon you don't own", not w.equip("scattergun") and w.current == "rifle")
	Game.give_weapon("scattergun")
	await _press("weapon_2")
	_check("2 switches to the scattergun", w.current == "scattergun", w.current)
	await _press("weapon_1")
	_check("1 switches back to the rifle", w.current == "rifle")
	w.cycle(1)
	_check("wheel cycles owned weapons", w.current == "scattergun")
	_check("scattergun has a 6-shell tube and limited reserve", w.mag_size() == 6 and Game.ammo_reserve("scattergun") == 36)

	# Scattergun up close.
	player.revive(ARENA)
	await get_tree().create_timer(SWITCH_WAIT).timeout
	var near: Scuttler = main.spawn_scuttler(ARENA + Vector3(0.0, 0.0, -4.0))
	near.target = null
	await _frames(5)
	var shots := 0
	Input.action_press("fire")
	for i in 240:
		if not is_instance_valid(near) or near.dead:
			break
		player.aim_at(near.global_position + Vector3.UP * 0.55)
		if w.in_mag < 6 - shots:
			shots = 6 - w.in_mag
		await get_tree().physics_frame
	Input.action_release("fire")
	_check("scattergun drops a scuttler at 4 m in two shells or fewer", is_instance_valid(near) and near.dead and shots <= 2, "shells=%d" % shots)
	_clear_enemies()

	# Reload draws from the reserve; an empty reserve can't reload.
	w.equip("scattergun")
	await get_tree().create_timer(SWITCH_WAIT).timeout
	var reserve := Game.ammo_reserve("scattergun")
	w.in_mag = 1
	w.start_reload()
	await get_tree().create_timer(w.reload_time() + 0.1).timeout
	_check("reload takes shells from the reserve", w.in_mag == 6 and Game.ammo_reserve("scattergun") == reserve - 5, "mag=%d reserve=%d" % [w.in_mag, Game.ammo_reserve("scattergun")])
	Game.set_ammo("scattergun", 0, 0)
	w.start_reload()
	_check("no reserve, no reload", not w.reloading)
	_check("ammo pickups cap at the reserve max", Game.add_ammo("scattergun", 999) == 36 and Game.ammo_reserve("scattergun") == 36)
	_check("rifle reserve is unlimited", Game.add_ammo("rifle", 10) == 0 and Game.ammo_reserve("rifle") == -1)

	# Arc lance pierces a line of targets.
	Game.give_weapon("arc_lance")
	w.equip("arc_lance")
	await get_tree().create_timer(SWITCH_WAIT).timeout
	player.revive(ARENA)
	await _frames(5)
	var line: Array[Scuttler] = []
	for i in 3:
		var s: Scuttler = main.spawn_scuttler(ARENA + Vector3(0.0, 0.0, -6.0 - i * 2.5))
		s.target = null
		line.append(s)
	await _frames(10)
	# Line them up on the camera's own ray, which runs off the shoulder and slightly down.
	player.aim_at(ARENA + Vector3(0.0, 0.55, -10.0))
	await _frames(2)
	var cam := player.get_viewport().get_camera_3d()
	for i in 3:
		line[i].set_physics_process(false)
		line[i].global_position = cam.global_position - cam.global_basis.z * (8.0 + i * 2.5) - Vector3.UP * 0.4
	await get_tree().physics_frame
	w.try_fire(true)
	await _frames(2)
	var hurt := line.filter(func(s): return not is_instance_valid(s) or s.dead or s.health < s.max_health).size()
	_check("arc lance pierces a line of three", hurt == 3, "hit=%d" % hurt)
	_clear_enemies()
	w.equip("rifle")
	Game.weapons.erase("arc_lance")
	Game.ammo.erase("arc_lance")
	await get_tree().create_timer(SWITCH_WAIT).timeout


const SWITCH_WAIT := 0.45


func _supplies() -> void:
	player.revive(main.SPAWN)
	await _frames(5)
	Game.stims = 0
	Game.add_stims(1)
	_check("stim not used at full health", not player.use_stim() and Game.stims == 1)
	player.take_damage(60.0)
	var before := player.health
	await _press("stim")
	_check("Q uses a stim and heals", Game.stims == 0 and player.health > before + 50.0, "health %.0f -> %.0f" % [before, player.health])
	_check("stims cap at 3", Game.add_stims(9) == 3 and Game.stims == 3)
	Game.upgrades["stim_pouch"] = true
	_check("stim pouch carries 5", Game.max_stims() == 5)
	Game.upgrades.erase("stim_pouch")
	Game.stims = 3

	var listed := Game.listed_upgrades()
	_check("scattergun choke is listed once you own the scattergun", "scatter_choke" in listed)
	Game.weapons.erase("scattergun")
	_check("weapon add-ons hide without the weapon", not "scatter_choke" in Game.listed_upgrades() and not Game.can_fabricate("scatter_choke"))
	Game.give_weapon("scattergun")
	_check("arc lance needs engine bleed", FabricatorMenu.blocker("arc_lance").contains("engine"), FabricatorMenu.blocker("arc_lance"))
	kestrel.set_repaired("engine", true)
	Game.add_scrap(200)
	_check("fabricating the arc lance hands it over", main.fabricator.build("arc_lance") and Game.owns_weapon("arc_lance"))
	_check("stims can be fabricated", Game.stims < Game.max_stims() or main.fabricator.build("stim") == false)
	kestrel.set_repaired("engine", false)

	main.inventory.open()
	_check("Tab inventory pauses and lists weapons", main.inventory.is_open() and get_tree().paused and main.inventory._content.get_child_count() > 6)
	main.inventory.close()
	await _frames(2)
	_check("inventory closes and resumes", not get_tree().paused)


func _spitter() -> void:
	player.revive(ARENA)
	await _frames(5)
	var sp: Spitter = main.spawn_enemy("spitter", ARENA + Vector3(0.0, 0.0, -14.0))
	await _frames(5)
	sp.alert(false)
	var before := player.health
	var closest := 99.0
	for i in 60 * 7:
		await get_tree().physics_frame
		closest = minf(closest, sp.global_position.distance_to(player.global_position))
		if player.health < before:
			break
	_check("spitter's acid glob hits a standing target", player.health < before, "health=%.0f" % player.health)
	_check("spitter keeps its distance", closest > sp.keep_min - 2.0, "closest=%.1f" % closest)
	_clear_enemies()
	player.revive(main.SPAWN)
	await _frames(5)


func _ram() -> void:
	player.revive(ARENA)
	await _frames(5)
	var ram: Ram = main.spawn_enemy("ram", ARENA + Vector3(0.0, 0.0, -20.0))
	ram.target = null
	await _frames(10)
	ram.rotation.y = 0.0  # facing -Z, away from the player
	var hp := ram.health
	ram.take_damage(20.0, ram.global_position, Vector3(0.0, 0.0, -1.0))
	var rear := hp - ram.health
	ram.rotation.y = PI  # facing the player
	hp = ram.health
	ram.take_damage(20.0, ram.global_position, Vector3(0.0, 0.0, -1.0))
	var front := hp - ram.health
	_check("ram's head plate soaks shots from the front", front < 6.0 and rear > 25.0, "front=%.1f rear=%.1f" % [front, rear])
	ram.target = player
	ram.calm()
	ram.alert(false)
	var before := player.health
	var charged := false
	for i in 60 * 8:
		await get_tree().physics_frame
		charged = charged or ram.state == Ram.State.CHARGE
		if player.health < before:
			break
	_check("ram paws, charges and hits", charged and player.health < before, "health=%.0f" % player.health)
	_clear_enemies()

	# Charging into solid scenery stuns it and opens it up.
	var wall := StaticBody3D.new()
	wall.collision_layer = Game.LAYER_WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8.0, 3.0, 0.6)
	shape.shape = box
	wall.add_child(shape)
	main.add_child(wall)
	wall.global_position = ARENA + Vector3(0.0, 1.0, -6.0)
	var ram2: Ram = main.spawn_enemy("ram", ARENA + Vector3(0.0, 0.0, -12.0))
	ram2.target = null
	await _frames(10)
	ram2.target = player
	ram2.state = Ram.State.PAW
	ram2._timer = 0.0
	player.revive(ARENA)
	var stunned := false
	for i in 120:
		await get_tree().physics_frame
		if ram2.is_stunned():
			stunned = true
			break
	_check("ram stuns itself charging into a wall", stunned)
	hp = ram2.health
	ram2.take_damage(20.0, ram2.global_position, Vector3(0.0, 0.0, -1.0))
	_check("stunned ram takes double damage", hp - ram2.health > 35.0, "took %.1f" % (hp - ram2.health))
	wall.queue_free()
	_clear_enemies()
	player.revive(main.SPAWN)
	await _frames(5)


func _warden() -> void:
	player.revive(ARENA)
	await _frames(5)
	var w: Warden = main.spawn_enemy("warden", ARENA + Vector3(0.0, 0.0, -18.0))
	w.target = null
	await _frames(10)
	var hp := w.health
	w.take_damage(100.0)
	var armoured := hp - w.health
	w._open(2.0)
	hp = w.health
	w.take_damage(100.0)
	var open := hp - w.health
	_check("Warden's carapace turns damage until it's open", armoured < 60.0 and open > 150.0, "armoured=%.0f open=%.0f" % [armoured, open])
	var before := _enemy_count()
	w.health = w.max_health * 0.6
	w.take_damage(1.0)
	await _frames(5)
	_check("Warden calls the pack at two-thirds health", w.phase == 1 and _enemy_count() >= before + 3, "phase=%d enemies=%d" % [w.phase, _enemy_count()])
	_clear_enemies()
	await _frames(5)
	w = main.spawn_enemy("warden", ARENA + Vector3(0.0, 0.0, -5.0))
	await _frames(10)
	w.target = player
	before = player.health
	w._slam()
	await get_tree().create_timer(1.0).timeout
	_check("Warden slam sends a ring that hits a grounded player", player.health < before, "health=%.0f" % player.health)
	main.hud.show_boss(w)
	await _frames(2)
	_check("boss bar shows while the Warden lives", main.hud.bar_visible())
	w.take_damage(99999.0)
	await _frames(2)
	_check("boss bar hides when it dies", not main.hud.bar_visible())
	_clear_enemies()
	player.revive(main.SPAWN)
	await _frames(5)


func _siege() -> void:
	var siege: ShipSiege = main.siege
	_clear_enemies()
	player.revive(ARENA + Vector3(60.0, 0.0, 60.0))
	siege.arm(0, 0.0)
	await _frames(10)
	_check("siege waits until the player is home", not siege.is_active())
	player.revive(main.SPAWN)
	await _frames(10)
	_check("siege starts when the player is near Kestrel", siege.is_active() and siege.siege_enemies().size() == ShipSiege.SIEGES[0][0].size())
	_check("hull bar shows during the siege", main.hud.bar_visible())
	_check("besiegers go for the hull", siege.siege_enemies().all(func(e): return e.target is HullPoint))
	# Even with every repair done, Kestrel can't lift off with wildlife on the hull.
	var saved_repairs := {}
	for id in Kestrel.REPAIR_ORDER:
		saved_repairs[id] = kestrel.is_repaired(id)
		kestrel.set_repaired(id, true)
	main.launch()
	_check("no launch during a siege", not Game.launched)
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, saved_repairs[id])
	# Let them reach the hull with the player out of the way inside the cockpit.
	player.revive(kestrel.to_global(kestrel.plan(6.0, 1.3, 13.0)))
	var hull_before := siege.hull
	for i in 60 * 20:
		await get_tree().physics_frame
		if siege.hull < hull_before:
			break
	_check("besiegers damage the hull", siege.hull < hull_before, "hull=%.0f" % siege.hull)
	_check("with Juno aboard, besiegers stay on the hull", kestrel.is_inside(player.global_position) and siege.siege_enemies().all(func(e): return e.target is HullPoint))
	var buried: PackedStringArray = []
	var space := player.get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var ball := SphereShape3D.new()
	ball.radius = 0.2
	probe.shape = ball
	probe.collision_mask = Game.LAYER_WORLD
	for hp in siege._points:
		probe.transform = Transform3D(Basis(), Vector3(hp.global_position.x, 0.25, hp.global_position.z))
		if not space.intersect_shape(probe, 1).is_empty():
			buried.append(str(hp.global_position))
	_check("every hull point stands in the open, where wildlife can reach it", buried.is_empty(), ", ".join(buried))
	_check("outside isn't aboard", not kestrel.is_inside(main.SPAWN + Vector3(0.0, 0.0, 12.0)))
	# Clear every wave by hand.
	var scrap_before := Game.scrap
	for wave_i in ShipSiege.SIEGES[0].size():
		for e in siege.siege_enemies().duplicate():
			e.take_damage(99999.0)
		await get_tree().create_timer(ShipSiege.WAVE_GAP + 0.3).timeout
	_check("clearing every wave ends the siege with a reward", not siege.is_active() and Game.scrap >= scrap_before + ShipSiege.REWARD_SCRAP, "active=%d scrap=%d" % [siege.active, Game.scrap])
	_check("hull bar hides after the siege", not main.hud.bar_visible())

	Game.scrap = 100
	siege.start(1)
	await _frames(5)
	siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(5)
	_check("a breached hull ends the siege and costs scrap", not siege.is_active() and Game.scrap == 75 and siege.pending == 1, "scrap=%d pending=%d" % [Game.scrap, siege.pending])
	_check("besiegers leave when the hull fails", _enemy_count() == 0, "enemies=%d" % _enemy_count())
	siege.pending = -1
	_clear_enemies()


func _difficulty_and_balance() -> void:
	player.revive(main.SPAWN)
	Game.difficulty = 0
	var before := player.health
	player.take_damage(20.0)
	var story := before - player.health
	Game.difficulty = 2
	before = player.health
	player.take_damage(20.0)
	var hard := before - player.health
	_check("difficulty scales damage taken", is_equal_approx(story, 10.0) and is_equal_approx(hard, 28.0), "story=%.1f hard=%.1f" % [story, hard])
	var tough: Scuttler = main.spawn_scuttler(ARENA)
	_check("hard gives wildlife more health", is_equal_approx(tough.max_health, 72.0), "hp=%.0f" % tough.max_health)
	Game.difficulty = 1
	_clear_enemies()

	# Balance: rounds to kill on Normal with no upgrades, from the damage numbers.
	var rifle: float = Weapon.SPECS["rifle"]["damage"]
	var scatter: float = Weapon.SPECS["scattergun"]["damage"] * Weapon.SPECS["scattergun"]["pellets"]
	var lance: float = Weapon.SPECS["arc_lance"]["damage"]
	var scuttler_rounds := ceili(60.0 / rifle)
	var ram_rear := ceili(170.0 / (rifle * 1.5))
	var ram_front := ceili(170.0 / (rifle * 0.25))
	var warden_rifle := ceili(1400.0 / (rifle * 0.55))
	var warden_lance_open := ceili(1400.0 / (lance * 1.8))
	_check("balance: a scuttler takes 3-5 rifle rounds", scuttler_rounds >= 3 and scuttler_rounds <= 5, str(scuttler_rounds))
	_check("balance: flanking a ram is 4x+ faster than hitting its plate", ram_front >= ram_rear * 4, "rear=%d front=%d" % [ram_rear, ram_front])
	_check("balance: one close scattergun blast nearly kills a scuttler", scatter >= 60.0 * 0.85, "%.0f" % scatter)
	_check("balance: Warden is a fight, not a wall (rifle 100-160 rounds, lance on openings 8-14)", warden_rifle >= 100 and warden_rifle <= 160 and warden_lance_open >= 8 and warden_lance_open <= 14, "rifle=%d lance=%d" % [warden_rifle, warden_lance_open])


func _save_load() -> void:
	_clear_enemies()
	# Build up a state worth saving.
	for id in ["aux_power", "cooling", "canopy"]:
		kestrel.set_repaired(id, true)
	Game.scrap = 77
	Game.upgrades["extended_mag"] = true
	Game.stims = 2
	Game.set_ammo("scattergun", 3, 20)
	var gear: QuarryCrawler = main.sites["landing_gear"]
	gear.search_crate(1)
	gear.take_component()
	Game.take_component("struts")
	main.siege.arm(1)
	player.weapon.equip("scattergun")
	await get_tree().create_timer(SWITCH_WAIT).timeout
	_check("saving writes the file", main.save_game() and Game.has_save())
	var data := Game.read_save()
	_check("save reads back", data.get("scrap", 0) == 77 and data.get("carrying", "") == "struts", str(data.get("scrap", "?")))

	# Fresh game scene, as Continue would start it.
	main.queue_free()
	await _frames(3)
	Game.reset()
	Game.pending_load = data
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	main.spawn_packs = false
	kestrel = main.kestrel
	player = main.player
	await _frames(20)
	_check("load restores repairs", kestrel.is_repaired("canopy") and not kestrel.is_repaired("landing_gear") and Game.current_repair() == "landing_gear")
	_check("load restores scrap, upgrades, stims and what you carry", Game.scrap == 77 and Game.has_upgrade("extended_mag") and Game.stims == 2 and Game.carrying == "struts" and Game.phase() == "return")
	_check("load restores weapons and ammo", Game.owns_weapon("scattergun") and Game.ammo_in_mag("scattergun") == 3 and Game.ammo_reserve("scattergun") == 20 and player.weapon.current == "scattergun")
	var gear2: QuarryCrawler = main.sites["landing_gear"]
	_check("load restores site state", not gear2.has_component() and gear2.crate_searched(1) and not gear2.crate_searched(0))
	_check("load re-arms the pending siege", main.siege.pending == 1)
	_check("loaded game starts at Kestrel", player.global_position.distance_to(main.SPAWN) < 2.0, str(player.global_position))
	main.siege.pending = -1
	player.revive(main.install_point("bunk") + Vector3.UP * 0.2)
	await _frames(10)
	_check("bunk offers rest and save", _label().contains("Rest"), _label())
	Game.delete_save()
	await _press("interact")
	_check("resting saves", Game.has_save())


func _title() -> void:
	Game.delete_save()
	var title: Node = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	await _frames(5)
	_check("title: Continue is greyed out with no save", title.continue_button.disabled)
	title.queue_free()
	await _frames(2)
	Game.write_save(main.save_state())
	title = load("res://scenes/title.tscn").instantiate()
	add_child(title)
	await _frames(5)
	_check("title: Continue is offered with a save", not title.continue_button.disabled)
	title.queue_free()
	Game.delete_save()
	await _frames(2)
