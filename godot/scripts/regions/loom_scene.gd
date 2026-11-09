class_name LoomScene
extends ShatterScene
## Shared building for the Loom's regions (the Expanse, the Tuning Crown): braided fibre strands
## gathered into one multimesh, and arches braided from them.

var _strands: Array[Transform3D] = []


## One straight fibre strand from a to b, for the shared multimesh.
func _strand(a: Vector3, b: Vector3, r: float) -> void:
	var y := b - a
	if y.length() < 0.01:
		return
	var up := y.normalized()
	var side := up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()
	var fwd := side.cross(up)
	_strands.append(Transform3D(Basis(side * r, y, fwd * r), (a + b) * 0.5))


## A braided arch from a to b rising `height` over the straight line between them.
func _arch(a: Vector3, b: Vector3, height: float, thick: float, count := 4, segs := 10) -> void:
	var tangent := (b - a).normalized()
	var side := tangent.cross(Vector3.UP).normalized()
	if side.length() < 0.1:
		side = Vector3.RIGHT
	var twist := _rng.randf_range(2.0, 4.0)
	for k in count:
		var phase := float(k) / count * TAU
		var r := thick * _rng.randf_range(0.22, 0.34)
		var prev := Vector3.INF
		for i in segs + 1:
			var s := float(i) / segs
			var centre := a.lerp(b, s) + Vector3.UP * height * 4.0 * s * (1.0 - s)
			var normal := side.cross(tangent).normalized()
			var ang := phase + s * twist
			var p := centre + (side * cos(ang) + normal * sin(ang)) * thick * 0.4
			if prev != Vector3.INF:
				_strand(prev, p, r)
			prev = p


## Every strand so far as one multimesh in `mat`.
func _commit_strands(mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = 1.15
	mesh.radial_segments = 7
	mesh.rings = 1
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = _strands.size()
	for i in _strands.size():
		mm.set_instance_transform(i, _strands[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Strands"
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)
