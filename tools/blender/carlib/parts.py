"""Cutting the shell (arches, windows, lights, grilles) and building the
parts that fill the holes, plus small bolt-on details."""

import math

import bmesh
import bpy
from mathutils import Vector

from . import core
from .body import plane_frame, project_loop
from .core import MeshBuilder, lerp


# ---------------------------------------------------------------------------
# Cutters


class Cutter:
	"""A prism that cuts a hole through the shell. kind decides what fills it."""

	def __init__(self, poly2d, origin, u, v, w, w0, w1, reveal="Trim", fill=None, name="cut", data=None):
		self.poly = poly2d
		self.origin = Vector(origin)
		self.u, self.v, self.w = Vector(u), Vector(v), Vector(w)
		self.w0, self.w1 = w0, w1
		self.reveal = reveal
		self.fill = fill
		self.name = name
		self.data = data or {}

	def mesh(self, mat=None):
		return core.prism(self.poly, self.origin, self.u, self.v, self.w, self.w0, self.w1, mat or self.reveal)

	def to_3d(self, p2, w=0.0):
		return self.origin + self.u * p2[0] + self.v * p2[1] + self.w * w

	def mirrored(self, name=None):
		"""Mirror across x = 0 (the frame flips handedness; prism() copes)."""
		def mx(vec):
			return Vector((-vec.x, vec.y, vec.z))
		return Cutter(list(self.poly), mx(self.origin), mx(self.u), mx(self.v), mx(self.w), self.w0, self.w1,
			self.reveal, self.fill, name or self.name + "_R", dict(self.data))


def side_cutter(loop_zy, x_in, side=1.0, radius=0.035, **kw):
	poly = core.round_polygon(loop_zy, radius, 3)
	poly = [(p[0], p[1]) for p in poly]
	return Cutter(poly, (0, 0, 0), (0, 0, 1), (0, 1, 0), (side, 0, 0), x_in, 3.0, **kw)


def surface_cutter(loop3d, body, depth=0.35, radius=0.04, up=(0, 1, 0), **kw):
	"""Cutter for a 3D loop on the surface, extruded along the loop's mean normal."""
	centre = sum(loop3d, Vector()) / len(loop3d)
	# Mean normal from the shell at the loop centre.
	# Use Newell's method on the loop for a stable average orientation.
	n = Vector()
	for i in range(len(loop3d)):
		a = loop3d[i]
		b = loop3d[(i + 1) % len(loop3d)]
		n.x += (a.y - b.y) * (a.z + b.z)
		n.y += (a.z - b.z) * (a.x + b.x)
		n.z += (a.x - b.x) * (a.y + b.y)
	n.normalize()
	# Point it outwards (away from the body centre).
	if n.dot(centre) < 0:
		n = -n
	u, v, n = plane_frame(n, up)
	poly = project_loop(loop3d, centre, u, v)
	poly = core.round_polygon(poly, radius, 3)
	return Cutter(poly, centre, u, v, n, -depth, depth, **kw)


def flat_cutter(poly2d, centre, normal, depth=0.25, up=(0, 1, 0), round_r=0.0, **kw):
	u, v, n = plane_frame(normal, up)
	poly = core.round_polygon(poly2d, round_r, 3) if round_r > 0 else poly2d
	return Cutter(poly, centre, u, v, n, -depth, depth, **kw)


def rect(wd, ht, cx=0.0, cy=0.0):
	return [(cx - wd / 2, cy - ht / 2), (cx + wd / 2, cy - ht / 2), (cx + wd / 2, cy + ht / 2), (cx - wd / 2, cy + ht / 2)]


def ellipse(rx, ry, n=20, cx=0.0, cy=0.0):
	return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def superellipse(rx, ry, e=4.0, n=24, cx=0.0, cy=0.0):
	out = []
	for i in range(n):
		t = 2 * math.pi * i / n
		c, s = math.cos(t), math.sin(t)
		out.append((cx + rx * core.spow(c, 2.0 / e), cy + ry * core.spow(s, 2.0 / e)))
	return out


def arch_cutter(x_in, y, z, radius, side=1.0, squash=1.0, n_exp=2.0, segments=56, reveal="Paint"):
	"""Wheel arch: a (super)elliptic prism along x."""
	poly = []
	for i in range(segments):
		t = 2 * math.pi * i / segments
		c, s = math.cos(t), math.sin(t)
		poly.append((z + radius * core.spow(c, 2.0 / n_exp), y + radius * squash * core.spow(s, 2.0 / n_exp)))
	return Cutter(poly, (0, 0, 0), (0, 0, 1), (0, 1, 0), (side, 0, 0), x_in, 3.0, reveal=reveal, name="arch")


# ---------------------------------------------------------------------------
# Applying cutters


def cut_shell(shell, cutters):
	"""Boolean-difference all cutters from the shell in one go."""
	if not cutters:
		return
	mb = MeshBuilder()
	for c in cutters:
		mb.add(c.mesh())
	cut_obj = mb.build("Cutters")
	core.boolean(shell, cut_obj, "DIFFERENCE", "EXACT")


def surface_patch(ref_shell, cutter, mat, inset=0.0, name="Patch"):
	"""The piece of the (closed, outer) shell inside a cutter, as its own mesh."""
	piece = core.duplicate(ref_shell, name)
	cm = cutter.mesh("CutterMarker")
	cobj = cm.build("PatchCutter")
	core.boolean(piece, cobj, "INTERSECT", "EXACT")
	me = piece.data
	bm = bmesh.new()
	bm.from_mesh(me)
	marker = [i for i, m in enumerate(me.materials) if m and m.name.startswith("CutterMarker")]
	kill = [f for f in bm.faces if f.material_index in marker]
	bmesh.ops.delete(bm, geom=kill, context="FACES")
	bm.normal_update()
	if inset:
		for v in bm.verts:
			v.co -= v.normal * inset
	for f in bm.faces:
		f.smooth = True
	bm.to_mesh(me)
	bm.free()
	core.set_material_all(piece, mat)
	return piece


# ---------------------------------------------------------------------------
# Hole fillers


def light_housing(body, cutter, emitters, depth=0.075, scale=0.94, housing_mat="Chrome", back_mat=None):
	"""Reflector cup behind a light hole, with emitter shapes inside.
	emitters: list of (kind, (u, v), size, mat)."""
	mb = MeshBuilder()
	n = cutter.w
	rim = []
	cen2 = (sum(p[0] for p in cutter.poly) / len(cutter.poly), sum(p[1] for p in cutter.poly) / len(cutter.poly))
	for p in cutter.poly:
		q = (cen2[0] + (p[0] - cen2[0]) * 0.985, cen2[1] + (p[1] - cen2[1]) * 0.985)
		far = cutter.to_3d(q, 1.0)
		hit, _nrm = body.ray(far, -n, 3.0)
		if hit is None:
			hit = cutter.to_3d(q, 0.0)
		rim.append(hit - n * 0.012)
	chit, _ = body.ray(cutter.to_3d(cen2, 1.0), -n, 3.0)
	if chit is None:
		chit = cutter.to_3d(cen2, 0.0)
	back_c = chit - n * depth
	back = []
	for p in cutter.poly:
		q = (cen2[0] + (p[0] - cen2[0]) * scale, cen2[1] + (p[1] - cen2[1]) * scale)
		off = cutter.u * (q[0] - cen2[0]) + cutter.v * (q[1] - cen2[1])
		back.append(back_c + off)
	mb.grid([rim, back], housing_mat, close_v=True, smooth=False)
	mb.fan(back[::-1], back_c, back_mat or housing_mat, smooth=False)
	for kind, (eu, ev), size, mat in emitters:
		c = back_c + cutter.u * (eu - cen2[0] + cen2[0]) + cutter.v * (ev - cen2[1] + cen2[1])
		c = back_c + cutter.u * eu + cutter.v * ev
		if kind == "disc":
			# Projector: chrome cone with a bright lens dome.
			ring_out = [c + (cutter.u * math.cos(t) + cutter.v * math.sin(t)) * size for t in [2 * math.pi * i / 20 for i in range(20)]]
			ring_in = [c + n * (depth * 0.45) + (cutter.u * math.cos(t) + cutter.v * math.sin(t)) * size * 0.72 for t in [2 * math.pi * i / 20 for i in range(20)]]
			mb.grid([ring_out, ring_in], "Chrome", close_v=True)
			dome = []
			for k in range(1, 4):
				a = k / 4 * math.pi / 2
				dome.append([c + n * (depth * 0.45 + size * 0.45 * math.sin(a)) + (cutter.u * math.cos(t) + cutter.v * math.sin(t)) * size * 0.72 * math.cos(a) for t in [2 * math.pi * i / 20 for i in range(20)]])
			mb.grid([ring_in] + dome, mat, close_v=True)
			mb.fan(dome[-1], c + n * (depth * 0.45 + size * 0.45), mat)
		elif kind == "bar":
			wd, ht = size
			pts = [(eu - wd / 2, ev - ht / 2), (eu + wd / 2, ev - ht / 2), (eu + wd / 2, ev + ht / 2), (eu - wd / 2, ev + ht / 2)]
			pr = core.prism(core.round_polygon(pts, min(wd, ht) * 0.45, 2), back_c, cutter.u, cutter.v, n, 0.004, depth * 0.55, mat)
			mb.add(pr)
		elif kind == "bulb":
			sq = core.superquadric(c + n * (size * 0.8), (size, size, size), 1.0, 1.0, 12, 6, mat)
			# superquadric axes are game axes; fine for a round bulb
			mb.add(sq)
	return mb


def grille_insert(body, cutter, style="bars", mat="Trim", frame_mat=None, count=6, depth=0.06, bar_t=0.012, vertical=0):
	"""Grille behind a hole: a dark backing panel plus bars or a mesh."""
	mb = MeshBuilder()
	n = cutter.w
	us = [p[0] for p in cutter.poly]
	vs = [p[1] for p in cutter.poly]
	u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
	cen2 = ((u0 + u1) / 2, (v0 + v1) / 2)
	chit, _ = body.ray(cutter.to_3d(cen2, 1.0), -n, 3.0)
	if chit is None:
		chit = cutter.to_3d(cen2, 0.0)
	base = chit - cutter.u * cen2[0] - cutter.v * cen2[1]
	back = core.prism(cutter.poly, base, cutter.u, cutter.v, n, -depth - 0.01, -depth, "Trim")
	mb.add(back)
	bars = MeshBuilder()
	if style == "bars":
		for k in range(count):
			v = lerp(v0, v1, (k + 0.5) / count)
			c = base + cutter.u * cen2[0] + cutter.v * v - n * 0.018
			bars.add(_oriented_box(c, cutter.u, cutter.v, n, (u1 - u0) * 0.52, bar_t, 0.02, mat))
		for k in range(vertical):
			u = lerp(u0, u1, (k + 1) / (vertical + 1))
			c = base + cutter.u * u + cutter.v * cen2[1] - n * 0.03
			bars.add(_oriented_box(c, cutter.u, cutter.v, n, bar_t * 0.8, (v1 - v0) * 0.52, 0.018, mat))
	elif style == "mesh":
		step = (v1 - v0) / count
		cols = int((u1 - u0) / step) + 1
		for k in range(count + 1):
			for j in range(cols + 1):
				u = u0 + j * step + (step * 0.5 if k % 2 else 0.0)
				v = v0 + k * step
				c = base + cutter.u * u + cutter.v * v - n * 0.025
				bars.add(_oriented_box(c, cutter.u, cutter.v, n, step * 0.36, step * 0.36, 0.012, mat, rot45=True))
	elif style == "egg":
		for k in range(count):
			v = lerp(v0, v1, (k + 0.5) / count)
			c = base + cutter.u * cen2[0] + cutter.v * v - n * 0.02
			bars.add(_oriented_box(c, cutter.u, cutter.v, n, (u1 - u0) * 0.52, bar_t, 0.025, mat))
		cols = max(2, int(count * (u1 - u0) / (v1 - v0)))
		for k in range(cols):
			u = lerp(u0, u1, (k + 0.5) / cols)
			c = base + cutter.u * u + cutter.v * cen2[1] - n * 0.02
			bars.add(_oriented_box(c, cutter.u, cutter.v, n, bar_t, (v1 - v0) * 0.52, 0.025, mat))
	if bars.faces:
		bobj = bars.build("GrilleBars")
		clip = core.prism(cutter.poly, base, cutter.u, cutter.v, n, -0.5, 0.5, "CutterMarker").build("GrilleClip")
		core.boolean(bobj, clip, "INTERSECT", "EXACT")
		# The clip's faces cap the cut bar ends: give them the bar material.
		me = bobj.data
		keep = core.material(mat)
		if keep.name not in me.materials:
			me.materials.append(keep)
		k = list(me.materials).index(keep)
		marker = {i for i, m in enumerate(me.materials) if m and m.name.startswith("CutterMarker")}
		for poly in me.polygons:
			if poly.material_index in marker:
				poly.material_index = k
		return mb, bobj
	return mb, None


def _oriented_box(c, u, v, n, hu, hv, hn, mat, rot45=False):
	mb = MeshBuilder()
	if rot45:
		u, v = (u + v).normalized(), (v - u).normalized()
	corners = []
	for su in (-1, 1):
		for sv in (-1, 1):
			for sn in (-1, 1):
				corners.append(c + u * hu * su + v * hv * sv + n * hn * sn)
	ids = [mb.v(p) for p in corners]
	for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
		mb.f(tuple(ids[i] for i in f), mat, False)
	return mb


# ---------------------------------------------------------------------------
# Surface-following strips (panel gaps, rubbing strips, stripes)


def project_side(body, pts_zy, side=1.0, lift=0.0015):
	out = []
	for z, y in pts_zy:
		hit, nrm = body.side_point(y, z, side)
		if hit is not None:
			out.append((hit + nrm * lift, nrm))
	return out


def project_top(body, pts_xz, lift=0.0015):
	out = []
	for x, z in pts_xz:
		hit, nrm = body.top_point(x, z)
		if hit is not None:
			out.append((hit + nrm * lift, nrm))
	return out


def project_dir(body, pts3d, direction, lift=0.0015):
	d = Vector(direction).normalized()
	out = []
	for p in pts3d:
		hit, nrm = body.ray(Vector(p) - d * 2.0, d, 5.0)
		if hit is not None:
			out.append((hit + nrm * lift, nrm))
	return out


def ribbon(samples, width, mat="Gap", closed=False, height=0.0):
	"""Flat strip on the surface through (point, normal) samples."""
	mb = MeshBuilder()
	n = len(samples)
	if n < 2:
		return mb
	left, right = [], []
	for i in range(n):
		p, nrm = samples[i]
		if closed:
			t = samples[(i + 1) % n][0] - samples[i - 1][0]
		else:
			t = samples[min(i + 1, n - 1)][0] - samples[max(i - 1, 0)][0]
		if t.length < 1e-9:
			t = Vector((0, 0, 1))
		side = t.cross(nrm).normalized()
		left.append(p + side * width * 0.5 + nrm * height)
		right.append(p - side * width * 0.5 + nrm * height)
	rows = [[left[i], right[i]] for i in range(n)]
	mb.grid(rows, mat, close_u=closed)
	# Make sure the strip faces outwards.
	if mb.faces:
		f = mb.faces[0]
		a, b, c = (Vector(mb.verts[f[k]]) for k in range(3))
		if (b - a).cross(c - a).dot(samples[0][1]) < 0:
			mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
	return mb


def raised_strip(samples, width, height, mat, closed=False, round_top=True):
	"""A trim strip / moulding with a rounded cross-section along surface samples."""
	prof = []
	steps = 6
	for k in range(steps + 1):
		a = math.pi * k / steps
		prof.append((-math.cos(a) * width * 0.5, math.sin(a) * height if round_top else height))
	path = [p for p, _ in samples]
	ups = [n for _, n in samples]
	mb = core.sweep(path, prof, mat, ups=ups, closed_profile=False, closed_path=closed)
	# Face the outside of the strip away from the surface it lies on.
	if mb.faces:
		mid = len(prof) // 2 - 1
		f = mb.faces[min(len(mb.faces) - 1, (len(samples) // 2) * (len(prof) - 1) + mid)]
		a, b, c = (Vector(mb.verts[f[k]]) for k in range(3))
		if (b - a).cross(c - a).dot(samples[len(samples) // 2][1]) < 0:
			mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
	return mb


def polyline(points, n=40):
	"""Resample a polyline of 2D points to n points (no corner rounding)."""
	return [(p.x, p.y) for p in core.resample_polyline(points, n, 0.0)]
