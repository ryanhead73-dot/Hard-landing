class_name Finale
extends Node
## The departure. With the nav core in, the pilot's seat starts a 90 second engine spool. The
## noise brings every animal in the basin down on Kestrel (ShipSiege.FINALE). Hold the hull until
## the spool is full, get back to the seat, and launch. A breached hull dumps the spool.

signal state_changed(state: int)

enum State { IDLE, SPOOLING, READY, LAUNCHING }

const SPOOL_TIME := 90.0

var state := State.IDLE
var spool := 0.0

var siege: ShipSiege
var voice: Voice
var hud: Hud

var _spool_sound: AudioStreamPlayer3D
var _said_half := false
var _said_late := false


func _ready() -> void:
	siege.ended.connect(_on_siege_ended)


func can_start() -> bool:
	return state == State.IDLE and Game.current_repair() == "" and not Game.launched and not siege.is_active()


func start() -> void:
	if not can_start():
		return
	spool = 0.0
	_said_half = false
	_said_late = false
	_set_state(State.SPOOLING)
	# The finale is the last assault: one still waiting to happen is folded into it.
	siege.pending = -1
	siege.start_finale()
	voice.interrupt(Story.FINALE_START)
	Sfx.play("power_up", null, -4.0, 0.0)


func begin_launch() -> void:
	if state == State.READY:
		_set_state(State.LAUNCHING)


func progress() -> float:
	return clampf(spool / SPOOL_TIME, 0.0, 1.0)


## The text for the shared top bar while the spool runs.
func bar_text() -> String:
	return "ENGINE SPOOL %d%%" % int(progress() * 100.0)


func _physics_process(delta: float) -> void:
	if state != State.SPOOLING:
		return
	spool += delta
	if not _said_half and progress() >= 0.5:
		_said_half = true
		voice.say_line(Story.FINALE_HALF)
	if not _said_late and spool >= SPOOL_TIME - 10.0:
		_said_late = true
		voice.say_line(Story.FINALE_LATE)
	siege.kestrel.set_engine_power(0.15 + 0.45 * progress())
	if _spool_sound:
		_spool_sound.pitch_scale = 0.6 + 0.8 * progress()
	if spool >= SPOOL_TIME:
		spool = SPOOL_TIME
		_set_state(State.READY)
		siege.stand_down()
		voice.interrupt([Story.FINALE_READY])
	elif hud:
		hud.set_hull(siege.hull / ShipSiege.MAX_HULL, bar_text())


func _on_siege_ended(success: bool) -> void:
	if state != State.SPOOLING or success:
		return
	spool = 0.0
	siege.kestrel.set_engine_power(0.0)
	_set_state(State.IDLE)
	voice.interrupt([Story.FINALE_FAILED])


const OBJECTIVES := {
	State.IDLE: "",
	State.SPOOLING: "Hold Kestrel's hull while the engine spools",
	State.READY: "Get to the pilot's seat and launch",
	State.LAUNCHING: "",
}


func _set_state(s: State) -> void:
	state = s
	# The spool whine rises with the spool, holds while she's ready, and gives way to the launch.
	if s == State.SPOOLING and _spool_sound == null:
		_spool_sound = Sfx.loop("spool_loop", siege.kestrel, 2.0) as AudioStreamPlayer3D
		if _spool_sound:
			_spool_sound.max_distance = 120.0
			_spool_sound.unit_size = 14.0
			_spool_sound.pitch_scale = 0.6
	elif (s == State.IDLE or s == State.LAUNCHING) and _spool_sound:
		_spool_sound.queue_free()
		_spool_sound = null
	Game.launch_objective = OBJECTIVES[s]
	Game.objective_changed.emit(Game.objective_text())
	state_changed.emit(s)
