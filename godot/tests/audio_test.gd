extends "res://tests/test_base.gd"
## Milestone 6 audio: every sound loads, loops loop, the music stems line up, the buses and music
## volume work, the adaptive music follows the action, the ambience follows Juno around, the
## engine spool whines, and story moments make their sounds. Run:
##   godot --headless --path . res://tests/audio_test.tscn

const ARENA := Vector3(45.0, 0.5, 45.0)
const LOOPS := ["wind_loop", "ship_hum_loop", "music_calm", "music_combat", "music_finale", "amb_springs_loop", "amb_loom_loop",
	"amb_interior_loop", "amb_moss_loop", "amb_wreck_loop", "spool_loop"]


func _name() -> String:
	return "AUDIO TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	_library()
	await _variants()
	_buses()
	await _music()
	await _ambience()
	await _spool()
	await _moments()
	finished = true


func _library() -> void:
	var missing: PackedStringArray = []
	for id in Sfx.SOUNDS:
		if not Sfx.has_sound(id):
			missing.append(id)
	_check("every sound loads", missing.is_empty(), ", ".join(missing))
	var not_looping: PackedStringArray = []
	for id in LOOPS:
		if not Sfx.loops(Sfx.stream(id)):
			not_looping.append(id)
	_check("loops have loop points", not_looping.is_empty(), ", ".join(not_looping))
	var lengths := [Sfx.stream("music_calm").get_length(), Sfx.stream("music_combat").get_length(), Sfx.stream("music_finale").get_length()]
	_check("music stems are the same length", absf(lengths[0] - lengths[1]) < 0.01 and absf(lengths[0] - lengths[2]) < 0.01 and lengths[0] > 10.0, str(lengths))
	var stray := Sfx.get_children().filter(func(c): return c is AudioStreamPlayer and (c as AudioStreamPlayer).stream in LOOPS.map(func(id): return Sfx.stream(id)))
	_check("no loops left running on the Sfx autoload", stray.is_empty())


func _variants() -> void:
	_check("rifle shots have variants", Sfx.variant_count("rifle_shot") >= 3, str(Sfx.variant_count("rifle_shot")))
	_check("footsteps have variants", Sfx.variant_count("footstep_0") >= 4 and Sfx.variant_count("step_metal") >= 4)
	var seen := {}
	for i in 40:
		seen[Sfx.pick("rifle_shot")] = true
	_check("plays pick between variants", seen.size() >= 2, str(seen.size()))
	var interior := AudioServer.get_bus_index("Interior")
	_check("an Interior reverb bus feeds Master", interior > 0 and AudioServer.get_bus_effect(interior, 0) is AudioEffectReverb)
	var zones := kestrel.find_children("ReverbZone*", "Area3D", true, false)
	_check("Kestrel's rooms send to the reverb bus", zones.size() >= 4 and (zones[0] as Area3D).reverb_bus_name == "Interior", str(zones.size()))
	player.revive(kestrel.to_global(kestrel.plan(6.0, 1.3, 13.0)))
	await _frames(3)
	_check("Juno's boots ring on Kestrel's deck", player._on_metal())
	player.revive(ARENA)
	await _frames(3)
	_check("and crunch on the basin", not player._on_metal())


func _buses() -> void:
	var music := AudioServer.get_bus_index("Music")
	var amb := AudioServer.get_bus_index("Ambience")
	_check("Music and Ambience buses feed Master", music > 0 and amb > 0 and AudioServer.get_bus_send(music) == "Master" and AudioServer.get_bus_send(amb) == "Master")
	var before := Game.music_volume
	Game.music_volume = 0.25
	Game.apply_settings()
	_check("music volume sets the Music bus", absf(AudioServer.get_bus_volume_db(music) - linear_to_db(0.25)) < 0.01)
	Game.music_volume = before
	Game.apply_settings()


func _music() -> void:
	var m: MusicDirector = main.music
	var playing := m.players.values().all(func(p): return p.playing and p.bus == "Music")
	_check("all three music layers play together", m.players.size() == 3 and playing)
	player.revive(ARENA)
	await get_tree().create_timer(0.6).timeout
	_check("music starts calm", m.mood == "calm" and m.levels["music_combat"] < 0.1)
	var e: Enemy = main.spawn_scuttler(ARENA + Vector3(0.0, 0.0, -12.0))
	e.alert(false)
	await get_tree().create_timer(1.6).timeout
	_check("hunting wildlife brings in the combat layer", m.mood == "combat" and m.levels["music_combat"] > 0.4, "%s %.2f" % [m.mood, m.levels["music_combat"]])
	_clear_enemies()
	await get_tree().create_timer(2.6).timeout
	_check("it settles back to calm", m.mood == "calm" and m.levels["music_combat"] < 0.2)
	main.siege.arm(0, 0.0)
	player.revive(main.SPAWN)
	await get_tree().create_timer(0.8).timeout
	_check("a siege is combat", main.siege.is_active() and m.mood == "combat")
	main.siege.stand_down()
	_clear_enemies()
	_check("the finale has its own layer", m.targets("finale")["music_finale"] == 1.0 and m.targets("combat")["music_finale"] == 0.0)


func _ambience() -> void:
	var a: Ambience = main.ambience
	player.revive(ARENA)
	await _frames(5)
	_check("open ground is wind", a.zone == "wind")
	player.revive(kestrel.to_global(kestrel.plan(6.0, 1.3, 13.0)))
	await _frames(5)
	_check("inside Kestrel is the interior", a.zone == "interior")
	player.revive(main.sites["cooling"].global_position + Vector3(0.0, 1.0, 6.0))
	await _frames(5)
	_check("the hauler wreck has the hot springs", a.zone == "springs", a.zone)
	player.revive(main.sites["navigation"].global_position + Vector3(0.0, 1.0, 6.0))
	await get_tree().create_timer(1.0).timeout
	_check("the Loom spire hums", a.zone == "loom" and a.levels["loom"] > 0.4, a.zone)
	player.revive(main.sites["wing"].global_position + Vector3(0.0, 1.0, 6.0))
	await _frames(5)
	_check("the moss forest has its own bed", a.zone == "moss", a.zone)
	player.revive(main.sites["engine"].global_position + Vector3(0.0, 1.0, 6.0))
	await _frames(5)
	_check("the freighter graveyard groans", a.zone == "wreck", a.zone)
	_check("ambience plays on its own bus", a.players.size() == Ambience.LOOPS.size() and a.players.values().all(func(p): return p.playing and p.bus == "Ambience"))
	player.revive(main.SPAWN)


func _spool() -> void:
	var f: Finale = main.finale
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	main.siege.pending = -1
	f.start()
	await _frames(3)
	_check("the engine spool whines", f._spool_sound != null and f._spool_sound.playing)
	var low := f._spool_sound.pitch_scale
	f.spool = 60.0
	await _frames(3)
	_check("its pitch climbs with the spool", f._spool_sound.pitch_scale > low + 0.3)
	await get_tree().create_timer(0.6).timeout
	_check("the finale music comes in", main.music.mood == "finale")
	main.siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(3)
	_check("a dumped spool goes quiet", f._spool_sound == null)
	_clear_enemies()


func _sounds_named(id: String) -> int:
	var s := Sfx.stream(id)
	return Sfx.get_children().filter(func(c): return (c is AudioStreamPlayer or c is AudioStreamPlayer3D) and c.stream == s).size()


func _moments() -> void:
	var before := _sounds_named("log_chime")
	Game.find_log(Story.log_at("aux_power", "crate:0"))
	_check("finding a log chimes", _sounds_named("log_chime") > before)
	Game.take_component("aux_cell")
	before = _sounds_named("repair_clunk")
	main._install("aux_power")
	_check("installing a part clunks into place", _sounds_named("repair_clunk") > before)
	main.play_intro()
	await get_tree().create_timer(main.INTRO_FALL + 0.2).timeout
	_check("the crash lands with a crash", _sounds_named("crash_impact") > 0)
	main.end_intro()
