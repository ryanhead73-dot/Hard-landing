class_name MapPanel
extends UiPanel
## M: Juno's survey map of the basin. A shaded relief of the rock with the pools and the worn
## paths, Kestrel at the centre, every site (mended, next, or still to come), the drift caches
## she has spotted (lit until opened), the lurker pools she has found, where she's headed, and
## where she is.

const HALF := 140.0
const RES := 192
const VIEW := 560.0

## Built once: the relief is fixed (the basin's seed never changes).
static var _relief: ImageTexture

var main: Node
var _view: MapView


func _ready() -> void:
	super._ready()
	_title.text = "SURVEY MAP"
	_toggle_action = "map"
	_view = MapView.new()
	_view.panel = self
	_view.custom_minimum_size = Vector2(VIEW, VIEW)
	_content.add_child(_view)
	var key := Label.new()
	key.text = "◆ next   ● mended   ○ to come   ▪ drift cache   ✕ lurker pool"
	key.modulate = Color(1, 1, 1, 0.75)
	_content.add_child(key)


func _refresh() -> void:
	if _relief == null and main:
		_relief = ImageTexture.create_from_image(build_relief(main.site))
	_view.queue_redraw()


## The basin as an image: hill-shaded basalt, teal pools, lighter worn paths.
static func build_relief(site: CrashSite) -> Image:
	var img := Image.create(RES, RES, false, Image.FORMAT_RGB8)
	var step := HALF * 2.0 / RES
	var heights := PackedFloat32Array()
	heights.resize(RES * RES)
	for y in RES:
		for x in RES:
			var w := _world(x, y, step)
			heights[y * RES + x] = site.height_at(w.x, w.y)
	var light := Vector3(-0.6, 0.7, -0.4).normalized()
	for y in RES:
		for x in RES:
			var h := heights[y * RES + x]
			var hx := heights[y * RES + mini(x + 1, RES - 1)] - heights[y * RES + maxi(x - 1, 0)]
			var hz := heights[mini(y + 1, RES - 1) * RES + x] - heights[maxi(y - 1, 0) * RES + x]
			var n := Vector3(-hx, step * 2.0, -hz).normalized()
			var shade := clampf(n.dot(light), 0.0, 1.0)
			var base := Color("2a2e30").lerp(Color("6b6a63"), clampf(h / 14.0, 0.0, 1.0))
			var c := base * (0.55 + 0.6 * shade)
			var w := _world(x, y, step)
			if site.on_path(w.x, w.y, 3.5):
				c = c.lerp(Color("8f8676"), 0.35)
			if site.in_pool(Vector3(w.x, 0.0, w.y)):
				c = Color("1f5a55").lerp(Color("3fd1b5"), 0.25)
			if w.length() > HALF - 4.0:
				c = c.darkened(0.5)
			c.a = 1.0
			img.set_pixel(x, y, c)
	return img


static func _world(x: int, y: int, step: float) -> Vector2:
	return Vector2(-HALF + (x + 0.5) * step, -HALF + (y + 0.5) * step)


## World (x, z) to a point on the map view.
static func to_map(p: Vector3) -> Vector2:
	return Vector2((p.x + HALF) / (HALF * 2.0), (p.z + HALF) / (HALF * 2.0)) * VIEW


## What the map shows, for tests: [{kind, pos, label}].
func marks() -> Array:
	var out := []
	if main == null:
		return out
	out.append({"kind": "ship", "pos": main.kestrel.global_position, "label": "KESTREL"})
	var current := Game.current_repair()
	for r in Campaign.REPAIRS:
		var id: String = r["id"]
		var site: ExpeditionSite = main.sites[id]
		var state := "mended" if Game.is_repaired(id) else ("next" if id == current else "later")
		out.append({"kind": "site", "state": state, "pos": site.global_position, "label": String(r["site"]).capitalize()})
	var w: Wildlife = main.wildlife
	if w:
		for c in w.caches:
			if c.index in Game.caches_seen or c.opened:
				out.append({"kind": "cache", "pos": c.global_position, "opened": c.opened})
		for pool in w.lurker_pools:
			if pool[2]:
				out.append({"kind": "lurker", "pos": pool[0]})
	var goal = main.call("_waypoint")
	if goal is Vector3:
		out.append({"kind": "goal", "pos": goal})
	if main.player:
		var cam := main.get_viewport().get_camera_3d()
		var f: Vector3 = -cam.global_basis.z if cam else -main.player.global_basis.z
		var dir := Vector2(f.x, f.z)
		out.append({"kind": "player", "pos": main.player.global_position, "dir": dir.normalized() if dir.length() > 0.01 else Vector2.UP})
	return out


class MapView:
	extends Control
	var panel: MapPanel

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, Vector2(MapPanel.VIEW, MapPanel.VIEW))
		if MapPanel._relief:
			draw_texture_rect(MapPanel._relief, rect, false)
		draw_rect(rect, Color("c4622d"), false, 2.0)
		var font := get_theme_default_font()
		for m in panel.marks():
			var at := MapPanel.to_map(m["pos"])
			match m["kind"]:
				"ship":
					draw_rect(Rect2(at - Vector2(7, 4), Vector2(14, 8)), Color("efe6d2"))
					draw_string(font, at + Vector2(10, -6), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("efe6d2"))
				"site":
					var col := Color("3fd1b5") if m["state"] == "mended" else (Color("ffb347") if m["state"] == "next" else Color(0.75, 0.75, 0.75, 0.7))
					if m["state"] == "next":
						draw_colored_polygon(PackedVector2Array([at + Vector2(0, -9), at + Vector2(9, 0), at + Vector2(0, 9), at + Vector2(-9, 0)]), col)
					elif m["state"] == "mended":
						draw_circle(at, 6.0, col)
					else:
						draw_arc(at, 6.0, 0.0, TAU, 16, col, 2.0)
					draw_string(font, at + Vector2(11, 4), m["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
				"cache":
					var cc := Color(0.5, 0.45, 0.4, 0.8) if m["opened"] else Color("ffb347")
					draw_rect(Rect2(at - Vector2(3, 3), Vector2(6, 6)), cc)
				"lurker":
					var lc := Color("d0574a")
					draw_line(at + Vector2(-5, -5), at + Vector2(5, 5), lc, 2.0)
					draw_line(at + Vector2(5, -5), at + Vector2(-5, 5), lc, 2.0)
				"goal":
					draw_arc(at, 12.0, 0.0, TAU, 24, Color("ffb347"), 2.0)
				"player":
					var fwd: Vector2 = m["dir"]
					var side := Vector2(-fwd.y, fwd.x)
					draw_colored_polygon(PackedVector2Array([at + fwd * 10.0, at - fwd * 6.0 + side * 6.0, at - fwd * 3.0, at - fwd * 6.0 - side * 6.0]), Color.WHITE)
