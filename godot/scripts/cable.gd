class_name Cable
extends RefCounted
## Cables as thin tube meshes: power lines sagging between pylons (a catenary-like parabola),
## lines snapped and trailing to the ground, and runs laid along the ground between machines.


## A sagging span from a to b (parent space). `sag` is how far the middle hangs below the chord.
static func span(parent: Node, a: Vector3, b: Vector3, sag: float, radius: float, mat: Material, segments := 18) -> MeshInstance3D:
	var pts: Array[Vector3] = []
	for i in segments + 1:
		var t := float(i) / segments
		pts.append(a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t))
	return tube(parent, pts, radius, mat)


## A tube through a list of points (parent space).
static func tube(parent: Node, pts: Array[Vector3], radius: float, mat: Material, sides := 6) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for i in pts.size():
		var fwd: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var side := fwd.cross(Vector3.UP)
		if side.length() < 0.01:
			side = fwd.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(fwd).normalized()
		var ring: Array = []
		for k in sides:
			var a := TAU * k / sides
			ring.append([pts[i] + (side * cos(a) + up * sin(a)) * radius, side * cos(a) + up * sin(a)])
		rings.append(ring)
	for i in pts.size() - 1:
		for k in sides:
			var k2 := (k + 1) % sides
			for v in [rings[i][k], rings[i + 1][k], rings[i + 1][k2], rings[i][k], rings[i + 1][k2], rings[i][k2]]:
				st.set_normal(v[1])
				st.add_vertex(v[0])
	var mesh := MeshInstance3D.new()
	mesh.name = "Cable"
	mesh.mesh = st.commit()
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mesh)
	return mesh


## A run laid along the ground from a to b, following `ground` (a Callable(x, z) -> height in
## parent space), with a little wander so it doesn't read as ruled.
static func ground_run(parent: Node, a: Vector3, b: Vector3, ground: Callable, radius: float, mat: Material, wander := 0.25) -> MeshInstance3D:
	var pts: Array[Vector3] = []
	var length := a.distance_to(b)
	var count := maxi(int(length / 0.6), 2)
	var across := (b - a).cross(Vector3.UP).normalized()
	for i in count + 1:
		var t := float(i) / count
		var p := a.lerp(b, t)
		if i > 0 and i < count:
			p += across * sin(t * PI * 3.0 + length) * wander * sin(t * PI)
			p.y = float(ground.call(p.x, p.z)) + radius
		pts.append(p)
	return tube(parent, pts, radius, mat)


## A cable snapped near `b`: hangs from a and trails along the ground for `trail` metres.
static func snapped(parent: Node, a: Vector3, toward: Vector3, ground: Callable, trail: float, radius: float, mat: Material) -> MeshInstance3D:
	var flat := Vector3(toward.x - a.x, 0.0, toward.z - a.z).normalized()
	var drop := a + flat * 1.2
	drop.y = float(ground.call(drop.x, drop.z)) + radius
	var pts: Array[Vector3] = []
	for i in 9:
		var t := float(i) / 8.0
		# Hangs nearly straight down, curling out at the foot.
		var p := a.lerp(drop, t * t)
		p.y = lerpf(a.y, drop.y, sqrt(t))
		pts.append(p)
	var end := drop + flat * trail
	var count := maxi(int(trail / 0.6), 2)
	for i in range(1, count + 1):
		var t := float(i) / count
		var p := drop.lerp(end, t) + flat.cross(Vector3.UP) * sin(t * 5.0) * 0.4
		p.y = float(ground.call(p.x, p.z)) + radius
		pts.append(p)
	return tube(parent, pts, radius, mat)
