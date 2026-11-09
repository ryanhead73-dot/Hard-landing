extends "res://tests/test_base.gd"
## The departure crisis: the spool stalls on tethers until their knots are shot through, an
## overheat must be vented at the cooling manifold or costs a quarter of the spool, a tripped aux
## breaker stalls it until rerouted, a breach clears every crisis, and the launch goes only in the
## quiet between Loom pulses. Run:
##   godot --headless --path . res://tests/finale_test.tscn


func _name() -> String:
	return "FINALE TEST"


func _run() -> void:
	await _frames(30)
	_clear_enemies()
	for id in Kestrel.REPAIR_ORDER:
		kestrel.set_repaired(id, true)
	main.siege.pending = -1
	var f: Finale = main.finale
	player.revive(main.install_point("launch") + Vector3.UP * 0.2)
	await _frames(10)
	await _press("interact")
	_check("the seat starts the spool", f.state == Finale.State.SPOOLING and f.crisis == Finale.Crisis.NONE)

	# 30%: tethers.
	f.spool = Finale.SPOOL_TIME * 0.3 + 0.05
	await _frames(3)
	_check("at 30% the tethers knot on", f.crisis == Finale.Crisis.TETHERS and f.knots_left() == 3 and main.voice.heard("Fibre"))
	_check("the objective is the knots", Game.objective_text().contains("tether knots") and Game.objective_text().contains("3 left"), Game.objective_text())
	_check("the top bar says it's stalled", f.bar_text().contains("TETHERS"), f.bar_text())
	var held := f.spool
	await get_tree().create_timer(1.0).timeout
	_check("held down, the spool doesn't climb", absf(f.spool - held) < 0.01, "%.2f -> %.2f" % [held, f.spool])
	var w = main._waypoint()
	_check("the scanner marks the nearest knot", w is Vector3 and [0, 1, 2].any(func(i): return (w as Vector3).distance_to(f.knot_position(i)) < 0.1))
	var bodies := []
	for n in kestrel.get_parent().get_children():
		if String(n.name).begins_with("Tether"):
			bodies.append(n.get_child(0))
	_check("each knot is something to shoot", bodies.size() == 3 and bodies.all(func(b): return b is StaticBody3D and b.has_meta("on_hit")), "%d" % bodies.size())
	for i in Finale.KNOT_HITS - 1:
		(bodies[0].get_meta("on_hit") as Callable).call()
	_check("a knot takes a few hits", f.knots_left() == 3)
	(bodies[0].get_meta("on_hit") as Callable).call()
	_check("then it's shot through", f.knots_left() == 2 and Game.objective_text().contains(": 2"), Game.objective_text())
	for b in bodies.slice(1):
		for i in Finale.KNOT_HITS:
			(b.get_meta("on_hit") as Callable).call()
	await _frames(3)
	_check("with every knot cut the spool climbs again", f.crisis == Finale.Crisis.NONE and f.spool > held and main.voice.heard("Spool's climbing"))
	_check("and the tethers are gone", kestrel.get_parent().get_children().all(func(n): return not String(n.name).begins_with("Tether") or n.is_queued_for_deletion()))

	# 55%: overheat, let it run out.
	f.spool = Finale.SPOOL_TIME * 0.55 + 0.05
	await _frames(3)
	_check("at 55% the drive overheats", f.crisis == Finale.Crisis.OVERHEAT and f.vent_t > Finale.VENT_TIME - 1.0 and Game.objective_text().contains("cooling"), Game.objective_text())
	_check("the scanner points at the manifold", (main._waypoint() as Vector3).distance_to(main.install_point("cooling")) < 0.1)
	_check("the spool still climbs while it's hot", not f.stalled())
	var before := f.spool
	f.vent_t = 0.05
	await _frames(4)
	_check("unvented, a quarter of the spool bleeds off", f.crisis == Finale.Crisis.NONE and f.spool < before - Finale.SPOOL_TIME * 0.2 and main.voice.heard("bleed off"), "%.1f -> %.1f" % [before, f.spool])
	_check("and it doesn't strike again on the way back up", f.stage == 2)

	# The overheat, vented in time (a second spool, below).
	# 80%: the breaker.
	f.spool = Finale.SPOOL_TIME * 0.8 + 0.05
	await _frames(3)
	_check("at 80% the aux breaker trips", f.crisis == Finale.Crisis.POWER and f.stalled() and Game.objective_text().contains("aux"), Game.objective_text())
	_check("and Kestrel's on emergency lights", not kestrel._aux_lights.is_empty() and not kestrel._aux_lights[0].visible)
	player.revive(main.install_point("aux_power") + Vector3.UP * 0.2)
	await _frames(5)
	_check("the aux bay offers the reroute", _label().contains("Reroute"), _label())
	await _press("interact")
	_check("rerouted, the lights and the spool come back", f.crisis == Finale.Crisis.NONE and kestrel._aux_lights[0].visible and main.voice.heard("rerouted"))

	# A breach clears whatever is running, and a new spool meets the crises again.
	f.spool = Finale.SPOOL_TIME * 0.3 + 0.05
	f.stage = 0
	await _frames(3)
	_check("tethers again", f.crisis == Finale.Crisis.TETHERS)
	main.siege.damage_hull(ShipSiege.MAX_HULL)
	await _frames(3)
	_check("a breach dumps the spool and the tethers", f.state == Finale.State.IDLE and f.crisis == Finale.Crisis.NONE and f.stage == 0 and f.knots_left() == 0)
	player.revive(main.install_point("launch") + Vector3.UP * 0.2)
	await _frames(5)
	await _press("interact")
	f.skip_crises()
	f.stage = 1
	f.spool = Finale.SPOOL_TIME * 0.55 + 0.05
	await _frames(3)
	player.revive(main.install_point("cooling") + Vector3.UP * 0.2)
	await _frames(5)
	_check("the manifold offers the vent", _label().contains("Vent"), _label())
	await _press("interact")
	_check("vented, the spool keeps every second", f.crisis == Finale.Crisis.NONE and f.spool >= Finale.SPOOL_TIME * 0.55 and main.voice.heard("Vented"))

	# The launch, in the gap.
	f.skip_crises()
	f.spool = Finale.SPOOL_TIME - 0.05
	await _frames(4)
	_check("full spool: ready, and the ground answers with a pulse", f.state == Finale.State.READY and f.pulses == 1)
	_check("the objective says to wait for the quiet", Game.objective_text().contains("quiet"), Game.objective_text())
	player.revive(main.install_point("launch") + Vector3.UP * 0.2)
	await _frames(5)
	f.pulse_t = 0.3
	await _frames(1)
	_check("on the pulse the seat says wait", _label().contains("wait"), _label())
	await _press("interact")
	_check("launching on the pulse is called off, no harm done", not Game.launched and f.state == Finale.State.READY and f.aborts == 1 and main.voice.heard("Not on the pulse"))
	f.pulse_t = Finale.PULSE_PERIOD - 0.05
	await _frames(4)
	_check("the pulses keep coming", f.pulses == 2)
	f.pulse_t = Finale.GAP_FROM + 0.2
	await _frames(1)
	_check("in the quiet the seat says go", _label().contains("go"), _label())
	await _press("interact")
	_check("and Kestrel lifts", Game.launched and f.state == Finale.State.LAUNCHING)
	finished = true
