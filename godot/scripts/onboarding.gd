class_name Onboarding
extends Node
## First-time hints, shown one at a time when they become useful instead of a wall of controls:
## move and look at the start, sprint on the long walk out, aim and fire when something first
## hunts Juno, the roll when she's first hurt, a stim when she's low, flanking when shots first
## glance off armour. Each shows once per save (Game.hints_seen) and clears when the player does
## the thing, or after a while.

## id: [keyboard text, pad text, seconds before it gives up]
const HINTS := {
	"move": ["[WASD] move   [Mouse] look", "[L stick] move   [R stick] look", 20.0],
	"sprint": ["[Shift] sprint", "[L3] sprint", 12.0],
	"fight": ["[RMB] aim   [LMB] fire   Glowing spines take critical hits", "[LT] aim   [RT] fire   Glowing spines take critical hits", 14.0],
	"dodge": ["[V] roll through a lunge: you can't be hurt at the start of it", "[B] roll through a lunge: you can't be hurt at the start of it", 10.0],
	"stim": ["[Q] use a stim to patch the suit", "[LB] use a stim to patch the suit", 10.0],
	"armor": ["Shots are glancing off its armour: hit it from the side or behind, or when it opens up", "Shots are glancing off its armour: hit it from the side or behind, or when it opens up", 10.0],
}

var main: Node
var current := ""
var _left := 0.0
var _start := Vector3.ZERO
var _sprinted := 0.0
var _hits := 0
## Hits that did full damage since the armour hint showed.
var _clean_hits := 0
var _armor_pending := false
var _quiet := 0.0
var enabled := true


func setup(m: Node) -> void:
	main = m
	main.player.damaged.connect(func(_a): _on_hurt())
	main.player.weapon.hit_confirmed.connect(func(_k):
		_hits += 1
		_clean_hits += 1)
	main.player.weapon.deflected.connect(_on_deflected)
	Game.input_device_changed.connect(func(_p): _show())


func seen(id: String) -> bool:
	return id in Game.hints_seen


## Shows a hint now (if it hasn't been seen). Returns true if it showed.
func offer(id: String) -> bool:
	if not enabled or seen(id) or current != "" or not HINTS.has(id):
		return false
	current = id
	_left = HINTS[id][2]
	_start = main.player.global_position
	_sprinted = 0.0
	_hits = 0
	_show()
	return true


## Marks the current hint done and clears it.
func finish() -> void:
	if current == "":
		return
	if not current in Game.hints_seen:
		Game.hints_seen.append(current)
	current = ""
	main.hud.show_hint("")
	_quiet = 1.5


func _show() -> void:
	if current != "":
		main.hud.show_hint(HINTS[current][1] if Game.using_pad else Game.keyboard_text(HINTS[current][0]))


func _on_hurt() -> void:
	if current == "" and not seen("dodge") and _quiet <= 0.0:
		offer("dodge")


func _on_deflected() -> void:
	_clean_hits -= 1
	if not seen("armor"):
		_armor_pending = true


func _process(delta: float) -> void:
	if main == null or main.intro_playing or main.player.dead or get_tree().paused:
		return
	_quiet = maxf(_quiet - delta, 0.0)
	var p: Player = main.player
	if current != "":
		_left -= delta
		if _done(p, delta) or _left <= 0.0:
			finish()
		return
	if _quiet > 0.0:
		return
	if _armor_pending and not seen("armor"):
		_armor_pending = false
		if offer("armor"):
			_clean_hits = 0
	elif not seen("move"):
		offer("move")
	elif _hunted() and not seen("fight"):
		offer("fight")
	elif p.health < p.max_health() * 0.5 and Game.stims > 0 and not seen("stim"):
		offer("stim")
	elif not seen("sprint") and Game.carrying == "" and p.global_position.distance_to(_start) > 0.0 and _far_from_goal():
		offer("sprint")


func _done(p: Player, delta: float) -> bool:
	match current:
		"move":
			return p.global_position.distance_to(_start) > 4.0
		"sprint":
			if p._sprinting:
				_sprinted += delta
			return _sprinted > 1.5
		"fight":
			return _hits >= 3
		"dodge":
			return p.is_rolling()
		"stim":
			return p.health >= p.max_health() * 0.9
		"armor":
			return _clean_hits >= 2
	return true


func _hunted() -> bool:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.hunting and e.target == main.player and e.global_position.distance_to(main.player.global_position) < 25.0:
			return true
	return false


func _far_from_goal() -> bool:
	var w = main._waypoint()
	return w is Vector3 and (w as Vector3).distance_to(main.player.global_position) > 40.0
