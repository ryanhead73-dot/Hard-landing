class_name Bevel
extends RefCounted
## Chamfered boxes: a box with every edge cut at 45 degrees, so edges catch the light the way
## real panels and castings do instead of meeting at a hard CG corner. Faces, chamfers and
## corners are flat-shaded pieces. No UVs: the game's surfaces are world-space triplanar.
## Meshes are cached by size, so repeated parts share one mesh.

const MAX_RADIUS := 0.05
## Below this thickness a part is a plate or a strip, and stays a plain box.
const MIN_SIZE := 0.05

static var _cache: Dictionary = {}


## A mesh for a box of `size` with chamfered edges (or a plain BoxMesh for thin parts).
static func box(size: Vector3, radius := -1.0) -> Mesh:
	var smallest := minf(size.x, minf(size.y, size.z))
	var r := radius if radius >= 0.0 else minf(MAX_RADIUS, smallest * 0.18)
	if smallest < MIN_SIZE or r < 0.004:
		var plain := BoxMesh.new()
		plain.size = size
		return plain
	var key := "%.3f/%.3f/%.3f/%.3f" % [size.x, size.y, size.z, r]
	if _cache.has(key):
		return _cache[key]
	var mesh := _build(size * 0.5, r)
	_cache[key] = mesh
	return mesh


static func _build(s: Vector3, r: float) -> ArrayMesh:
	var h := s - Vector3(r, r, r)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	# Six faces, each an inset rectangle.
	for axis in 3:
		for sign_ in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = sign_
			var u := (axis + 1) % 3
			var v := (axis + 2) % 3
			var quad: Array[Vector3] = []
			for c in [[-1, -1], [1, -1], [1, 1], [-1, 1]]:
				var p := Vector3.ZERO
				p[axis] = sign_ * s[axis]
				p[u] = c[0] * h[u]
				p[v] = c[1] * h[v]
				quad.append(p)
			_quad(verts, normals, quad, n)
	# Twelve edge chamfers: between face (a, sa) and face (b, sb), running along axis c.
	for a in 3:
		for b in range(a + 1, 3):
			var c := 3 - a - b
			for sa in [-1.0, 1.0]:
				for sb in [-1.0, 1.0]:
					var n := Vector3.ZERO
					n[a] = sa
					n[b] = sb
					var quad: Array[Vector3] = []
					for along in [-1.0, 1.0]:
						var p1 := Vector3.ZERO
						p1[a] = sa * s[a]
						p1[b] = sb * h[b]
						p1[c] = along * h[c]
						var p2 := Vector3.ZERO
						p2[a] = sa * h[a]
						p2[b] = sb * s[b]
						p2[c] = along * h[c]
						quad.append(p1)
						quad.append(p2)
					_quad(verts, normals, [quad[0], quad[1], quad[3], quad[2]], n.normalized())
	# Eight corner triangles.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var n := Vector3(sx, sy, sz).normalized()
				var a := Vector3(sx * s.x, sy * h.y, sz * h.z)
				var b := Vector3(sx * h.x, sy * s.y, sz * h.z)
				var c := Vector3(sx * h.x, sy * h.y, sz * s.z)
				_tri(verts, normals, a, b, c, n)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _quad(verts: PackedVector3Array, normals: PackedVector3Array, q: Array, n: Vector3) -> void:
	_tri(verts, normals, q[0], q[1], q[2], n)
	_tri(verts, normals, q[0], q[2], q[3], n)


## Godot's front faces wind clockwise seen from outside, so the triangle's right-hand normal
## must point inward.
static func _tri(verts: PackedVector3Array, normals: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	verts.append_array([a, b, c])
	normals.append_array([n, n, n])


## A flat-shaded copy of a primitive mesh's first surface: every triangle gets its own face
## normal, so a six-sided cylinder reads as a cut hexagonal prism. Faces keep the side the
## source normals point to.
static func flat(source: Mesh) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(src_v.size())
		for i in src_v.size():
			idx[i] = i
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for t in range(0, idx.size() - 2, 3):
		var a := src_v[idx[t]]
		var b := src_v[idx[t + 1]]
		var c := src_v[idx[t + 2]]
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			continue
		n = n.normalized()
		if n.dot(src_n[idx[t]] + src_n[idx[t + 1]] + src_n[idx[t + 2]]) < 0.0:
			n = -n
		verts.append_array([a, b, c])
		normals.append_array([n, n, n])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = verts
	out[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return mesh
