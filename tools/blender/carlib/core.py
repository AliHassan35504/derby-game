"""Core helpers for the procedural car builder.

All geometry is authored in *game* coordinates (Godot): +X is the car's
left, +Y is up and +Z is forward. Meshes keep that data as-is while the car
is built; `bake_to_blender()` rotates everything into Blender's Z-up frame
right before rendering or exporting, so the glTF exporter (which converts
back to Y-up) writes game coordinates again.
"""

import math

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

# Godot (x, y, z) -> Blender (x, -z, y): a +90 degree turn about X.
G2B = Matrix.Rotation(math.radians(90.0), 4, "X")


def g2b(p):
	return (G2B @ Vector(p).to_4d()).to_3d()


# ---------------------------------------------------------------------------
# Small maths helpers


def clamp(v, a, b):
	return a if v < a else b if v > b else v


def lerp(a, b, t):
	return a + (b - a) * t


def smoothstep(a, b, x):
	if a == b:
		return 0.0 if x < a else 1.0
	t = clamp((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


def spow(v, e):
	"""Sign-preserving power."""
	return math.copysign(abs(v) ** e, v)


class Curve:
	"""Monotone cubic (PCHIP) interpolation through (x, y) keys, flat outside."""

	def __init__(self, keys):
		keys = sorted(keys)
		self.x = [float(k[0]) for k in keys]
		self.y = [float(k[1]) for k in keys]
		n = len(self.x)
		if n == 1:
			self.m = [0.0]
			return
		d = [(self.y[i + 1] - self.y[i]) / (self.x[i + 1] - self.x[i]) for i in range(n - 1)]
		m = [0.0] * n
		m[0] = d[0]
		m[-1] = d[-1]
		for i in range(1, n - 1):
			if d[i - 1] * d[i] <= 0.0:
				m[i] = 0.0
			else:
				h0 = self.x[i] - self.x[i - 1]
				h1 = self.x[i + 1] - self.x[i]
				w1 = 2.0 * h1 + h0
				w2 = h1 + 2.0 * h0
				m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
		self.m = m

	def __call__(self, x):
		xs = self.x
		if x <= xs[0]:
			return self.y[0]
		if x >= xs[-1]:
			return self.y[-1]
		lo, hi = 0, len(xs) - 1
		while hi - lo > 1:
			mid = (lo + hi) // 2
			if xs[mid] <= x:
				lo = mid
			else:
				hi = mid
		h = xs[hi] - xs[lo]
		t = (x - xs[lo]) / h
		t2 = t * t
		t3 = t2 * t
		return ((2 * t3 - 3 * t2 + 1) * self.y[lo] + (t3 - 2 * t2 + t) * h * self.m[lo]
			+ (-2 * t3 + 3 * t2) * self.y[hi] + (t3 - t2) * h * self.m[hi])


def resample_polyline(pts, n, corner_weight=0.04):
	"""Resample a 2D/3D polyline to n points, spacing by arc length plus a
	little extra density where it turns (corner_weight metres per radian)."""
	pts = [Vector(p) for p in pts]
	acc = [0.0]
	for i in range(1, len(pts)):
		seg = (pts[i] - pts[i - 1]).length
		turn = 0.0
		if 0 < i < len(pts) - 1:
			a = pts[i] - pts[i - 1]
			b = pts[i + 1] - pts[i]
			if a.length > 1e-9 and b.length > 1e-9:
				turn = a.angle(b, 0.0)
		acc.append(acc[-1] + seg + corner_weight * turn)
	total = acc[-1]
	if total < 1e-9:
		return [pts[0].copy() for _ in range(n)]
	out = []
	k = 0
	for i in range(n):
		s = total * i / (n - 1)
		while k < len(acc) - 2 and acc[k + 1] < s:
			k += 1
		span = acc[k + 1] - acc[k]
		t = 0.0 if span < 1e-12 else (s - acc[k]) / span
		out.append(pts[k].lerp(pts[k + 1], clamp(t, 0.0, 1.0)))
	return out


def round_polygon(poly, radius, steps=4):
	"""Round the corners of a closed 2D polygon with quadratic arcs."""
	n = len(poly)
	out = []
	for i in range(n):
		p0 = Vector(poly[i - 1])
		p1 = Vector(poly[i])
		p2 = Vector(poly[(i + 1) % n])
		a = p0 - p1
		b = p2 - p1
		la, lb = a.length, b.length
		if la < 1e-6 or lb < 1e-6:
			continue
		ang = a.angle(b, math.pi)
		if ang > math.radians(165.0):
			out.append(p1)
			continue
		r = min(radius, la * 0.45, lb * 0.45)
		q0 = p1 + a.normalized() * r
		q2 = p1 + b.normalized() * r
		for s in range(steps + 1):
			t = s / steps
			out.append(q0 * (1 - t) ** 2 + p1 * 2 * t * (1 - t) + q2 * t * t)
	return out


# ---------------------------------------------------------------------------
# Materials (Blender side; Godot re-creates them by name)

MATERIAL_LOOKS = {
	# name: (base colour, metallic, roughness, extra)
	"Paint": ((0.75, 0.06, 0.05), 0.55, 0.38, {"coat": 1.0}),
	"Glass": ((0.22, 0.26, 0.27), 0.0, 0.02, {"transmission": 1.0, "alpha": 1.0}),
	"Chrome": ((0.92, 0.92, 0.94), 1.0, 0.07, {}),
	"Trim": ((0.025, 0.025, 0.028), 0.0, 0.45, {}),
	"Gap": ((0.006, 0.006, 0.006), 0.0, 0.8, {}),
	"Headlight": ((0.95, 0.95, 0.92), 0.0, 0.2, {"emission": (1.0, 0.97, 0.9), "strength": 3.0}),
	"Taillight": ((0.55, 0.02, 0.02), 0.0, 0.15, {"emission": (1.0, 0.04, 0.02), "strength": 2.0}),
	"Indicator": ((0.9, 0.42, 0.04), 0.0, 0.15, {"emission": (1.0, 0.45, 0.05), "strength": 0.6}),
	"HeadLens": ((0.95, 0.96, 0.97), 0.0, 0.02, {"transmission": 1.0}),
	"TailLens": ((0.7, 0.03, 0.03), 0.0, 0.04, {"transmission": 0.85, "emission": (1.0, 0.05, 0.03), "strength": 0.3}),
	"LightbarRed": ((0.8, 0.03, 0.03), 0.0, 0.1, {"emission": (1.0, 0.03, 0.02), "strength": 4.0}),
	"LightbarBlue": ((0.03, 0.08, 0.8), 0.0, 0.1, {"emission": (0.05, 0.2, 1.0), "strength": 4.0}),
	"Seat": ((0.16, 0.15, 0.14), 0.0, 0.75, {}),
	"Interior": ((0.11, 0.1, 0.095), 0.0, 0.8, {}),
	"Tyre": ((0.03, 0.03, 0.03), 0.0, 0.88, {}),
	"Rim": ((0.62, 0.63, 0.65), 1.0, 0.22, {}),
	"Brake": ((0.28, 0.27, 0.26), 1.0, 0.45, {}),
	"Caliper": ((0.7, 0.05, 0.04), 0.3, 0.35, {}),
	"Plate": ((0.9, 0.9, 0.86), 0.0, 0.4, {}),
	"Underbody": ((0.035, 0.035, 0.035), 0.0, 0.9, {}),
	"Frame": ((0.85, 0.6, 0.03), 0.3, 0.35, {}),
	"Decal": ((0.92, 0.92, 0.9), 0.1, 0.3, {"coat": 1.0}),
	"Livery": ((0.05, 0.05, 0.06), 0.1, 0.3, {"coat": 1.0}),
}

_materials = {}


def material(name):
	"""Return the Blender material with this name, creating it on first use."""
	if name in _materials and _materials[name].name in bpy.data.materials:
		return _materials[name]
	col, metal, rough, extra = MATERIAL_LOOKS.get(name, ((0.5, 0.5, 0.5), 0.0, 0.5, {}))
	mat = bpy.data.materials.new(name)
	mat.use_nodes = True
	mat.diffuse_color = (*col, 1.0)
	bsdf = mat.node_tree.nodes.get("Principled BSDF")
	bsdf.inputs["Base Color"].default_value = (*col, 1.0)
	bsdf.inputs["Metallic"].default_value = metal
	bsdf.inputs["Roughness"].default_value = rough
	if "coat" in extra:
		bsdf.inputs["Coat Weight"].default_value = extra["coat"]
		bsdf.inputs["Coat Roughness"].default_value = 0.03
	if "transmission" in extra:
		bsdf.inputs["Transmission Weight"].default_value = extra["transmission"]
		bsdf.inputs["IOR"].default_value = 1.5
	if "emission" in extra:
		bsdf.inputs["Emission Color"].default_value = (*extra["emission"], 1.0)
		bsdf.inputs["Emission Strength"].default_value = extra["strength"]
	_materials[name] = mat
	return mat


def set_paint_colour(rgb, name="Paint"):
	mat = material(name)
	mat.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1.0)
	mat.diffuse_color = (*rgb, 1.0)


# ---------------------------------------------------------------------------
# Mesh building


class MeshBuilder:
	"""Collects vertices and faces (with material names) and turns them into
	a Blender object. Coordinates are game coordinates."""

	def __init__(self):
		self.verts = []
		self.faces = []
		self.fmats = []
		self.fsmooth = []

	def v(self, p):
		self.verts.append((float(p[0]), float(p[1]), float(p[2])))
		return len(self.verts) - 1

	def f(self, idx, mat, smooth=True):
		if len(set(idx)) < 3:
			return
		self.faces.append(tuple(idx))
		self.fmats.append(mat)
		self.fsmooth.append(smooth)

	def grid(self, rows, mat, close_u=False, close_v=False, flip=False, smooth=True):
		"""rows[i][j] -> quads. mat is a name or f(i, j) -> name."""
		idx = [[self.v(p) for p in row] for row in rows]
		nu = len(rows)
		nv = len(rows[0])
		iu = nu if close_u else nu - 1
		iv = nv if close_v else nv - 1
		for i in range(iu):
			for j in range(iv):
				a = idx[i][j]
				b = idx[(i + 1) % nu][j]
				c = idx[(i + 1) % nu][(j + 1) % nv]
				d = idx[i][(j + 1) % nv]
				m = mat(i, j) if callable(mat) else mat
				if flip:
					self.f((a, d, c, b), m, smooth)
				else:
					self.f((a, b, c, d), m, smooth)
		return idx

	def fan(self, ring, centre, mat, flip=False, smooth=True):
		c = self.v(centre)
		ids = [self.v(p) for p in ring]
		n = len(ids)
		for i in range(n):
			tri = (c, ids[i], ids[(i + 1) % n])
			self.f(tri[::-1] if flip else tri, mat, smooth)

	def add(self, other):
		base = len(self.verts)
		self.verts.extend(other.verts)
		for face, m, s in zip(other.faces, other.fmats, other.fsmooth):
			self.faces.append(tuple(i + base for i in face))
			self.fmats.append(m)
			self.fsmooth.append(s)

	def transform(self, fn):
		self.verts = [tuple(fn(Vector(p))) for p in self.verts]

	def build(self, name, merge=0.0, recalc=False, sharp_angle=None):
		return make_object(name, self.verts, self.faces, self.fmats, self.fsmooth, merge, recalc, sharp_angle)


def make_object(name, verts, faces, fmats, fsmooth=None, merge=0.0, recalc=False, sharp_angle=None):
	mesh = bpy.data.meshes.new(name)
	mesh.from_pydata(verts, [], faces)
	obj = bpy.data.objects.new(name, mesh)
	bpy.context.scene.collection.objects.link(obj)
	names = []
	for m in fmats:
		if m not in names:
			names.append(m)
	for n in names:
		mesh.materials.append(material(n))
	lookup = {n: i for i, n in enumerate(names)}
	mesh.polygons.foreach_set("material_index", [lookup[m] for m in fmats])
	if fsmooth is None:
		fsmooth = [True] * len(faces)
	mesh.polygons.foreach_set("use_smooth", fsmooth)
	if merge > 0.0 or recalc:
		bm = bmesh.new()
		bm.from_mesh(mesh)
		if merge > 0.0:
			bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
		if recalc:
			bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
		bm.to_mesh(mesh)
		bm.free()
	if sharp_angle is not None:
		mesh.set_sharp_from_angle(angle=math.radians(sharp_angle))
	mesh.update()
	return obj


def apply_modifiers(obj):
	dg = bpy.context.evaluated_depsgraph_get()
	ev = obj.evaluated_get(dg)
	mesh = bpy.data.meshes.new_from_object(ev, preserve_all_data_layers=True, depsgraph=dg)
	old = obj.data
	obj.modifiers.clear()
	obj.data = mesh
	bpy.data.meshes.remove(old)


def boolean(obj, cutter, op="DIFFERENCE", solver="EXACT", keep_cutter=False):
	mod = obj.modifiers.new("bool", "BOOLEAN")
	mod.operation = op
	mod.solver = solver
	mod.object = cutter
	if hasattr(mod, "material_mode"):
		mod.material_mode = "TRANSFER"
	apply_modifiers(obj)
	if not keep_cutter:
		delete(cutter)


def delete(obj):
	mesh = obj.data
	bpy.data.objects.remove(obj, do_unlink=True)
	if mesh is not None and mesh.users == 0 and isinstance(mesh, bpy.types.Mesh):
		bpy.data.meshes.remove(mesh)


def duplicate(obj, name):
	new = obj.copy()
	new.data = obj.data.copy()
	new.name = name
	bpy.context.scene.collection.objects.link(new)
	return new


def join(objs, name):
	"""Join objects (already in the scene) into one, merging material slots by name."""
	objs = [o for o in objs if o is not None]
	verts, faces, fmats, fsmooth = [], [], [], []
	for o in objs:
		me = o.data
		mw = o.matrix_world
		base = len(verts)
		verts.extend(tuple(mw @ v.co) for v in me.vertices)
		for p in me.polygons:
			faces.append(tuple(base + i for i in p.vertices))
			fmats.append(me.materials[p.material_index].name.split(".")[0] if me.materials else "Paint")
			fsmooth.append(p.use_smooth)
	out = make_object(name, verts, faces, fmats, fsmooth)
	for o in objs:
		delete(o)
	return out


def join_keep_normals(objs, name):
	"""Join objects with bpy.ops so custom/sharp normals survive."""
	objs = [o for o in objs if o is not None]
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.context.view_layer.objects.active = objs[0]
	with bpy.context.temp_override(active_object=objs[0], selected_editable_objects=objs, selected_objects=objs):
		bpy.ops.object.join()
	objs[0].name = name
	objs[0].data.name = name
	merge_material_slots(objs[0])
	return objs[0]


def merge_material_slots(obj):
	me = obj.data
	names = []
	remap = []
	for m in me.materials:
		base = m.name.split(".")[0] if m else "Paint"
		if base not in names:
			names.append(base)
		remap.append(names.index(base))
	idx = [0] * len(me.polygons)
	me.polygons.foreach_get("material_index", idx)
	idx = [remap[i] if i < len(remap) else 0 for i in idx]
	me.materials.clear()
	for n in names:
		me.materials.append(material(n))
	me.polygons.foreach_set("material_index", idx)
	me.update()


def set_material_all(obj, name):
	me = obj.data
	me.materials.clear()
	me.materials.append(material(name))
	me.polygons.foreach_set("material_index", [0] * len(me.polygons))


def tri_count(obj):
	return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def bvh_of(obj):
	me = obj.data
	return BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])


def bvh_from(verts, faces):
	return BVHTree.FromPolygons([Vector(v) for v in verts], faces)


# ---------------------------------------------------------------------------
# Primitive generators (all return MeshBuilder)


def lathe(profile, segments, mat, axis="x", centre=(0, 0, 0), close=True, smooth=True, angle0=0.0, flip=False):
	"""Revolve a profile of (radius, axial) points around an axis."""
	mb = MeshBuilder()
	rows = []
	c = Vector(centre)
	for s in range(segments):
		a = angle0 + 2.0 * math.pi * s / segments
		ca, sa = math.cos(a), math.sin(a)
		row = []
		for r, h in profile:
			if axis == "x":
				row.append(c + Vector((h, r * ca, r * sa)))
			elif axis == "y":
				row.append(c + Vector((r * ca, h, r * sa)))
			else:
				row.append(c + Vector((r * ca, r * sa, h)))
		rows.append(row)
	mb.grid(rows, mat, close_u=close, flip=flip, smooth=smooth)
	return mb


def superquadric(centre, half, e1=0.3, e2=0.3, nu=16, nv=10, mat="Paint", deform=None, smooth=True):
	"""Rounded box: |x|^(2/e2) + ... style superellipsoid. e -> 0 is boxy, 1 is round.
	deform(p_local_unit) -> offset vector applied before scaling."""
	mb = MeshBuilder()
	c = Vector(centre)
	rows = []
	for i in range(nv + 1):
		v = -math.pi / 2 + math.pi * i / nv
		cv, sv = math.cos(v), math.sin(v)
		row = []
		for j in range(nu):
			u = -math.pi + 2 * math.pi * j / nu
			cu, su = math.cos(u), math.sin(u)
			x = spow(cv, e1) * spow(cu, e2)
			z = spow(cv, e1) * spow(su, e2)
			y = spow(sv, e1)
			p = Vector((x, y, z))
			if deform:
				p = deform(p)
			row.append(c + Vector((p.x * half[0], p.y * half[1], p.z * half[2])))
		rows.append(row)
	idx = [[mb.v(p) for p in row] for row in rows]
	for i in range(nv):
		for j in range(nu):
			a = idx[i][j]
			b = idx[i][(j + 1) % nu]
			cc = idx[i + 1][(j + 1) % nu]
			d = idx[i + 1][j]
			mb.f((a, d, cc, b), mat, smooth)
	return mb


def box(centre, half, mat, smooth=False):
	c = Vector(centre)
	hx, hy, hz = half
	mb = MeshBuilder()
	p = [c + Vector((sx * hx, sy * hy, sz * hz)) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
	ids = [mb.v(q) for q in p]
	# index = (sx>0)*4 + (sy>0)*2 + (sz>0)
	for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
		mb.f(tuple(ids[i] for i in f), mat, smooth)
	return mb


def cylinder(p0, p1, r0, r1=None, segments=16, mat="Chrome", caps=True, smooth=True, cap_mat=None):
	"""Cylinder / cone between two points."""
	r1 = r0 if r1 is None else r1
	a = Vector(p0)
	b = Vector(p1)
	d = (b - a)
	length = d.length
	axis = d.normalized()
	ref = Vector((0, 1, 0)) if abs(axis.y) < 0.9 else Vector((1, 0, 0))
	u = axis.cross(ref).normalized()
	v = axis.cross(u).normalized()
	mb = MeshBuilder()
	ring0, ring1 = [], []
	for s in range(segments):
		t = 2 * math.pi * s / segments
		off = u * math.cos(t) + v * math.sin(t)
		ring0.append(a + off * r0)
		ring1.append(b + off * r1)
	mb.grid([ring0, ring1], mat, close_v=True, smooth=smooth, flip=True)
	if caps:
		cm = cap_mat or mat
		mb.fan(ring0, a, cm, flip=False, smooth=False)
		mb.fan(ring1, b, cm, flip=True, smooth=False)
	return mb


def sweep(path, profile, mat, ups=None, closed_profile=True, closed_path=False, smooth=True, scales=None, caps=False):
	"""Sweep a 2D profile [(u, v)] along a 3D path. ups gives the 'v' direction
	per path point (defaults to +Y). u is to the side (tangent x up)."""
	pts = [Vector(p) for p in path]
	n = len(pts)
	rows = []
	for i in range(n):
		if closed_path:
			t = pts[(i + 1) % n] - pts[i - 1]
		else:
			t = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
		t.normalize()
		up = Vector(ups[i]) if ups else Vector((0, 1, 0))
		side = t.cross(up)
		if side.length < 1e-6:
			side = t.cross(Vector((1, 0, 0)))
		side.normalize()
		upn = side.cross(t).normalized()
		s = scales[i] if scales else 1.0
		row = [pts[i] + side * (pu * s) + upn * (pv * s) for pu, pv in profile]
		rows.append(row)
	mb = MeshBuilder()
	mb.grid(rows, mat, close_u=closed_path, close_v=closed_profile, smooth=smooth)
	if caps and not closed_path:
		mb.fan(rows[0], sum(rows[0], Vector()) / len(rows[0]), mat, flip=True, smooth=False)
		mb.fan(rows[-1], sum(rows[-1], Vector()) / len(rows[-1]), mat, smooth=False)
	return mb


def prism(poly2d, origin, axis_u, axis_v, axis_w, w0, w1, mat):
	"""Extrude a closed 2D polygon (in the u/v frame at origin) along w from w0 to w1."""
	o = Vector(origin)
	u = Vector(axis_u)
	v = Vector(axis_v)
	w = Vector(axis_w)
	mb = MeshBuilder()
	bottom = [mb.v(o + u * p[0] + v * p[1] + w * w0) for p in poly2d]
	top = [mb.v(o + u * p[0] + v * p[1] + w * w1) for p in poly2d]
	n = len(poly2d)
	# Orientation: make the polygon counter-clockwise in (u, v).
	area = sum(poly2d[i][0] * poly2d[(i + 1) % n][1] - poly2d[(i + 1) % n][0] * poly2d[i][1] for i in range(n))
	handed = u.cross(v).dot(w) > 0
	ccw = area > 0
	flip = ccw != handed
	for i in range(n):
		j = (i + 1) % n
		q = (bottom[i], bottom[j], top[j], top[i])
		mb.f(q[::-1] if flip else q, mat, False)
	cap_b = tuple(bottom[::-1]) if not flip else tuple(bottom)
	cap_t = tuple(top) if not flip else tuple(top[::-1])
	mb.f(cap_b, mat, False)
	mb.f(cap_t, mat, False)
	return mb


def text_mesh(text, size, depth, mat, centre, axis_u, axis_v, axis_w):
	"""Build a text label (Blender's built-in font) laid out in the u/v plane."""
	curve = bpy.data.curves.new("txt", type="FONT")
	curve.body = text
	curve.size = size
	curve.extrude = depth * 0.5
	curve.align_x = "CENTER"
	curve.align_y = "CENTER"
	curve.resolution_u = 2
	obj = bpy.data.objects.new("txt", curve)
	bpy.context.scene.collection.objects.link(obj)
	dg = bpy.context.evaluated_depsgraph_get()
	me = bpy.data.meshes.new_from_object(obj.evaluated_get(dg), depsgraph=dg)
	bpy.data.objects.remove(obj, do_unlink=True)
	bpy.data.curves.remove(curve)
	c = Vector(centre)
	u, v, w = Vector(axis_u), Vector(axis_v), Vector(axis_w)
	mb = MeshBuilder()
	ids = [mb.v(c + u * p.co.x + v * p.co.y + w * (p.co.z + depth * 0.5)) for p in me.vertices]
	for p in me.polygons:
		mb.f(tuple(ids[i] for i in p.vertices), mat, False)
	bpy.data.meshes.remove(me)
	return mb


def bake_to_blender(objs):
	"""Rotate mesh data from game coordinates into Blender's Z-up frame."""
	for o in objs:
		if o.type == "MESH":
			o.data.transform(G2B)
			o.data.update()
		o.location = g2b(o.location)
