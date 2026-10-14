class_name MeshKit
extends RefCounted
## Collects boxes, beams, tubes and rock shells into one mesh, so a structure
## made of hundreds of parts costs a single draw call. Positions are in the
## space of the node the finished mesh is attached to.
##
## Faces use Godot's clockwise front-face winding. UVs are in metres along
## each face, so tiling textures and shaders stay the same size everywhere.

## Vertex colour given to the parts added next. Shaders can read it as COLOR.
var color := Color.WHITE

var _st := SurfaceTool.new()
var _empty := true


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func is_empty() -> bool:
	return _empty


## An oriented box. The transform's basis may be rotated but should not be
## scaled; give the size in metres instead.
func box(xform: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var b := xform.basis.orthonormalized()
	var axes := [b.x, b.y, b.z]
	var halves := [h.x, h.y, h.z]
	for axis in 3:
		for side in [1.0, -1.0]:
			var n: Vector3 = axes[axis] * side
			# V runs along local Z on the four long sides, so UVs (and wood
			# grain) follow a beam's length.
			var ui := 0 if axis == 1 else (axis + 1) % 3
			var vi := 2 if axis == 1 else (axis + 2) % 3
			var u: Vector3 = axes[ui] * (-side if axis == 1 else side)
			var v: Vector3 = axes[vi]
			var hu: float = halves[ui]
			var hv: float = halves[vi]
			var c: Vector3 = xform.origin + n * float(halves[axis])
			_quad(c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv,
					n, Vector2(hu * 2.0, hv * 2.0))


## An axis-aligned box from its centre and size.
func cube(center: Vector3, size: Vector3) -> void:
	box(Transform3D(Basis.IDENTITY, center), size)


## A rectangular beam from a to b, width across and height up (relative to
## the up hint).
func beam(a: Vector3, b: Vector3, width: float, height: float, up_hint := Vector3.UP) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	box(Transform3D(frame(along / length, up_hint), (a + b) * 0.5), Vector3(width, height, length))


## An I-beam (two flanges and a web) from a to b.
func i_beam(a: Vector3, b: Vector3, width: float, height: float, up_hint := Vector3.UP) -> void:
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	var basis := frame(along / length, up_hint)
	var mid := (a + b) * 0.5
	var flange := height * 0.14
	box(Transform3D(basis, mid + basis.y * (height - flange) * 0.5), Vector3(width, flange, length))
	box(Transform3D(basis, mid - basis.y * (height - flange) * 0.5), Vector3(width, flange, length))
	box(Transform3D(basis, mid), Vector3(width * 0.16, height - flange * 2.0, length))


## A round tube from a to b. Radii may differ for a taper.
func tube(a: Vector3, b: Vector3, radius_a: float, radius_b := -1.0, segments := 8, caps := false) -> void:
	if radius_b < 0.0:
		radius_b = radius_a
	var along := b - a
	var length := along.length()
	if length < 0.001:
		return
	var basis := frame(along / length)
	var slope := (radius_a - radius_b) / length
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := basis.x * cos(a0) + basis.y * sin(a0)
		var d1 := basis.x * cos(a1) + basis.y * sin(a1)
		var n0 := (d0 + basis.z * slope).normalized()
		var n1 := (d1 + basis.z * slope).normalized()
		var u0 := radius_a * a0
		var u1 := radius_a * a1
		_vert(a + d0 * radius_a, n0, Vector2(u0, 0))
		_vert(b + d1 * radius_b, n1, Vector2(u1, length))
		_vert(a + d1 * radius_a, n1, Vector2(u1, 0))
		_vert(a + d0 * radius_a, n0, Vector2(u0, 0))
		_vert(b + d0 * radius_b, n0, Vector2(u0, length))
		_vert(b + d1 * radius_b, n1, Vector2(u1, length))
		if caps:
			_vert(b, basis.z, Vector2.ZERO)
			_vert(b + d1 * radius_b, basis.z, Vector2(cos(a1), sin(a1)) * radius_b)
			_vert(b + d0 * radius_b, basis.z, Vector2(cos(a0), sin(a0)) * radius_b)
			_vert(a, -basis.z, Vector2.ZERO)
			_vert(a + d0 * radius_a, -basis.z, Vector2(cos(a0), sin(a0)) * radius_a)
			_vert(a + d1 * radius_a, -basis.z, Vector2(cos(a1), sin(a1)) * radius_a)


## A cone or pyramid standing on a base centre, pointing up.
func cone(base: Vector3, radius: float, height: float, segments := 8) -> void:
	var tip := base + Vector3.UP * height
	var slope := radius / height
	for i in segments:
		var a0 := TAU * i / segments
		var a1 := TAU * (i + 1) / segments
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var nm := (d0 + d1).normalized()
		_vert(base + d0 * radius, (d0 + Vector3.UP * slope).normalized(), Vector2(a0 * radius, 0))
		_vert(base + d1 * radius, (d1 + Vector3.UP * slope).normalized(), Vector2(a1 * radius, 0))
		_vert(tip, (nm + Vector3.UP * slope).normalized(), Vector2((a0 + a1) * 0.5 * radius, height))


## One flat triangle, seen from the side its corners run clockwise on.
func triangle(a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (c - a).cross(b - a).normalized()
	var u := (b - a).normalized()
	var v := n.cross(u)
	_vert(a, n, Vector2.ZERO)
	_vert(b, n, Vector2((b - a).dot(u), (b - a).dot(v)))
	_vert(c, n, Vector2((c - a).dot(u), (c - a).dot(v)))


## A flat quad from four corners in clockwise order as seen from the front.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	triangle(a, b, c)
	triangle(a, c, d)


## A closed shell through rings of points (bottom ring first, each ring in
## order of increasing angle, i.e. point i at (cos a, y, sin a)), with smooth
## normals. Used for
## rock pillars, peaks and mesas. Caps the top ring when cap_top is set.
## The transform moves the points first (e.g. world to a piece's space).
func shell(rings: Array, cap_top := true, xform := Transform3D.IDENTITY) -> void:
	if xform != Transform3D.IDENTITY:
		var moved := []
		for ring in rings:
			var copy := PackedVector3Array()
			for p in ring:
				copy.append(xform * p)
			moved.append(copy)
		rings = moved
	var count: int = rings[0].size()
	var ring_total := rings.size()
	var normals := []
	for r in ring_total:
		var ring: PackedVector3Array = rings[r]
		var below: PackedVector3Array = rings[maxi(r - 1, 0)]
		var above: PackedVector3Array = rings[mini(r + 1, ring_total - 1)]
		var row := PackedVector3Array()
		var centre := Vector3.ZERO
		for p in ring:
			centre += p
		centre /= count
		for i in count:
			var tangent := ring[(i + 1) % count] - ring[(i - 1 + count) % count]
			var rise := above[i] - below[i]
			var n := rise.cross(tangent).normalized()
			if n.dot(ring[i] - centre) < 0.0:
				n = -n
			row.append(n)
		normals.append(row)
	var v_dist := 0.0
	for r in ring_total - 1:
		var lo: PackedVector3Array = rings[r]
		var hi: PackedVector3Array = rings[r + 1]
		var step := lo[0].distance_to(hi[0])
		var u := 0.0
		for i in count:
			var j := (i + 1) % count
			var du := lo[i].distance_to(lo[j])
			_vert(lo[i], normals[r][i], Vector2(u, v_dist))
			_vert(lo[j], normals[r][j], Vector2(u + du, v_dist))
			_vert(hi[i], normals[r + 1][i], Vector2(u, v_dist + step))
			_vert(lo[j], normals[r][j], Vector2(u + du, v_dist))
			_vert(hi[j], normals[r + 1][j], Vector2(u + du, v_dist + step))
			_vert(hi[i], normals[r + 1][i], Vector2(u, v_dist + step))
			u += du
		v_dist += step
	if cap_top:
		var top: PackedVector3Array = rings[ring_total - 1]
		var centre := Vector3.ZERO
		for p in top:
			centre += p
		centre /= count
		for i in count:
			var j := (i + 1) % count
			_vert(centre, Vector3.UP, Vector2(centre.x, centre.z))
			_vert(top[i], Vector3.UP, Vector2(top[i].x, top[i].z))
			_vert(top[j], Vector3.UP, Vector2(top[j].x, top[j].z))


## Builds the mesh. Returns null if nothing was added.
func commit(mat: Material = null) -> ArrayMesh:
	if _empty:
		return null
	_st.generate_tangents()
	var mesh := _st.commit()
	if mat:
		mesh.surface_set_material(0, mat)
	return mesh


## Builds the mesh and adds it to a parent as a MeshInstance3D.
func instance(parent: Node3D, mat: Material, shadows := true) -> MeshInstance3D:
	var mesh := commit(mat)
	if mesh == null:
		return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## An orthonormal basis whose Z runs along a direction and whose Y is as
## close to the up hint as possible.
static func frame(forward: Vector3, up_hint := Vector3.UP) -> Basis:
	var z := forward.normalized()
	var x := up_hint.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT.cross(z) if absf(z.x) < 0.9 else Vector3.FORWARD.cross(z)
	x = x.normalized()
	return Basis(x, z.cross(x).normalized(), z)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, uv_size: Vector2) -> void:
	# a, b, c, d run counter-clockwise seen from the front; emit clockwise.
	_vert(a, n, Vector2(0, 0))
	_vert(c, n, Vector2(uv_size.x, uv_size.y))
	_vert(b, n, Vector2(uv_size.x, 0))
	_vert(a, n, Vector2(0, 0))
	_vert(d, n, Vector2(0, uv_size.y))
	_vert(c, n, Vector2(uv_size.x, uv_size.y))


func _vert(p: Vector3, n: Vector3, uv: Vector2) -> void:
	_empty = false
	_st.set_color(color)
	_st.set_normal(n)
	_st.set_uv(uv)
	_st.add_vertex(p)
