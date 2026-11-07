class_name Discoveries
extends Node
## The Kettle's optional discoveries: places off the repair routes that reward exploring
## (see scripts/discoveries/). Each builds itself on the terrain, keeps its state in Game.flags
## and offers its own interaction; quests in QuestDB start and finish on those flags.

const SCENES := {
	"listening_post": preload("res://scripts/discoveries/listening_post.gd"),
}

var main: Node
## id -> the built discovery node.
var built := {}


func setup(m: Node) -> void:
	main = m
	for id in SCENES:
		var d: Node3D = SCENES[id].new()
		d.name = "Discovery_" + id
		main.add_child(d)
		d.setup(main)
		built[id] = d


func ids() -> Array:
	return SCENES.keys()


## The first discovery offering an interaction at `pos`, or {}.
func interaction(pos: Vector3) -> Dictionary:
	for id in built:
		var i: Dictionary = built[id].interaction(pos)
		if not i.is_empty():
			return i
	return {}
