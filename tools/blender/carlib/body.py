"""Lofted car body shells.

A body is a closed loft of cross-sections along Z (rear to front). Each
half cross-section runs from the bottom centre line, out and up the side to
the shoulder (belt line), then over the greenhouse or bonnet to the top
centre line. Every shape parameter is a smooth curve of Z, so one spec
describes the bumper, bonnet, windscreen, roof, rear window and boot.

Section parameters (all functions of z):
	yb  bottom height at the centre line
	ym  height of the widest point of the lower body
	ys  shoulder / belt line height
	yt  top centre line height (bumper top, bonnet, windscreen, roof ...)
	w   half width at ym
	wsh half width at the shoulder
	wg  half width where the greenhouse starts (wsh - wg is the shoulder ledge)
	wr  half width at the top (roof / bonnet crown)
	nb  bottom superellipse exponent (2 round .. 6 boxy)
	nu  upper superellipse exponent
The plan view corners are rounded with superellipse falloffs at the ends.
"""

import math

from mathutils import Vector

from . import core
from .core import Curve, MeshBuilder, clamp, lerp, smoothstep


class Body:
	def __init__(self, spec):
		self.spec = spec
		self.z0, self.z1 = spec["z"]
		self.c = {}
		spec.setdefault("cr", 0.13)
		spec.setdefault("bulge", 0.03)
		spec.setdefault("dip", 0.0)
		for key in ("yb", "ym", "ys", "yt", "w", "wsh", "wg", "wr", "nb", "nu", "cr", "bulge", "dip"):
			val = spec[key]
			if isinstance(val, (int, float)):
				val = [(0.0, val)]
			self.c[key] = Curve(val)
		self.front = spec.get("front", {})
		self.rear = spec.get("rear", {})
		self.ledge_h = spec.get("ledge_h", 0.03)
		self.na = spec.get("na", 12)
		self.nbs = spec.get("nbs", 6)
		self.nc = spec.get("nc", 22)
		self.stations_n = spec.get("stations", 100)
		self.extra_z = spec.get("extra_z", [])
		self.thickness = spec.get("thickness", 0.025)
		self.outer = None
		self.bvh = None

	# -- analytic shape ----------------------------------------------------

	def plan_factor(self, z):
		f = 1.0
		rf = self.front.get("R", 0.3)
		kf = self.front.get("k", 3.0)
		if z > self.z1 - rf:
			u = clamp((z - (self.z1 - rf)) / rf, 0.0, 1.0)
			f = (1.0 - u ** kf) ** (1.0 / kf) if u < 1.0 else 0.0
		rr = self.rear.get("R", 0.3)
		kr = self.rear.get("k", 3.0)
		if z < self.z0 + rr:
			u = clamp(((self.z0 + rr) - z) / rr, 0.0, 1.0)
			f = min(f, (1.0 - u ** kr) ** (1.0 / kr) if u < 1.0 else 0.0)
		return f

	def params(self, z):
		p = {k: c(z) for k, c in self.c.items()}
		# Keep the stack of heights ordered.
		p["ym"] = clamp(p["ym"], p["yb"] + 0.02, p["yt"] - 0.02)
		p["ys"] = clamp(p["ys"], p["ym"] + 0.01, p["yt"] - 0.005)
		return p

	def half_section_dense(self, z, n_a=40, n_b=16, n_c=80):
		"""Dense half section at z: list of (x, y) and segment start indices."""
		p = self.params(z)
		pf = self.plan_factor(z)
		yb, ym, ys, yt = p["yb"], p["ym"], p["ys"], p["yt"]
		w, wsh, wg, wr = p["w"], p["wsh"], p["wg"], p["wr"]
		nb, nu = p["nb"], p["nu"]
		pts = []
		for i in range(n_a):
			a = i / n_a
			phi = (1.0 - a) * math.pi / 2
			x = w * math.cos(phi) ** (2.0 / nb)
			y = ym - (ym - yb) * math.sin(phi) ** (2.0 / nb)
			pts.append((x, y))
		ib = len(pts)
		for i in range(n_b):
			u = i / n_b
			pts.append((w + (wsh - w) * u ** 1.5, ym + (ys - ym) * u))
		ic = len(pts)
		h = max(yt - ys, 1e-4)
		b = min(p["cr"], h)
		hs = h - b
		hl = self.ledge_h
		bulge = p["bulge"]
		n_side = int(n_c * 0.35) if hs > 1e-3 else 0
		n_top = n_c - n_side
		for i in range(n_side):
			u = i / n_side
			y = ys + hs * u
			yf = (y - ys) / h
			x = wr + (wg - wr) * (1.0 - yf) + (wsh - wg) * math.exp(-(y - ys) / hl) + bulge * math.sin(math.pi * u) * hs
			pts.append((x, y))
		for i in range(n_top + 1):
			phi = (i / n_top) * math.pi / 2
			x0 = math.cos(phi) ** (2.0 / nu)
			y0 = math.sin(phi) ** (2.0 / nu)
			y = ys + hs + b * y0
			yf = (y - ys) / h
			env = wr + (wg - wr) * (1.0 - yf) + (wsh - wg) * math.exp(-(y - ys) / hl)
			# dip lowers the middle of the top below its edges (bonnet between
			# raised wings).
			y -= p["dip"] * (1.0 - x0 * x0) ** 1.5
			pts.append((x0 * env, y))
		pts = [(x * pf, y) for x, y in pts]
		return pts, ib, ic

	def shear(self, z, y):
		dz = 0.0
		if self.front.get("rake"):
			rf = self.front.get("R", 0.3)
			wt = smoothstep(self.z1 - rf * 1.5, self.z1, z)
			dz += self.front["rake"] * (y - self.front.get("yref", 0.0)) * wt
		if self.rear.get("rake"):
			rr = self.rear.get("R", 0.3)
			wt = smoothstep(self.z0 + rr * 1.5, self.z0, z)
			dz -= self.rear["rake"] * (y - self.rear.get("yref", 0.0)) * wt
		return dz

	def half_section(self, z):
		"""Resampled half section with a fixed number of points per segment."""
		pts, ib, ic = self.half_section_dense(z)
		seg_a = core.resample_polyline(pts[: ib + 1], self.na + 1)
		seg_b = core.resample_polyline(pts[ib: ic + 1], self.nbs + 1)
		seg_c = core.resample_polyline(pts[ic:], self.nc + 1)
		out = seg_a[:-1] + seg_b[:-1] + seg_c
		return [(p.x, p.y) for p in out]

	def section_info(self, z):
		"""Dense half section with arc length and 2D normals, for windows etc."""
		pts, ib, ic = self.half_section_dense(z, 60, 24, 160)
		s = [0.0]
		for i in range(1, len(pts)):
			s.append(s[-1] + math.dist(pts[i], pts[i - 1]))
		nrm = []
		for i in range(len(pts)):
			a = pts[max(i - 1, 0)]
			b = pts[min(i + 1, len(pts) - 1)]
			tx, ty = b[0] - a[0], b[1] - a[1]
			ln = math.hypot(tx, ty) or 1.0
			nrm.append((ty / ln, -tx / ln))
		return {"pts": pts, "s": s, "n": nrm, "ib": ib, "ic": ic}

	def at_s(self, info, s):
		ss = info["s"]
		s = clamp(s, 0.0, ss[-1])
		lo, hi = 0, len(ss) - 1
		while hi - lo > 1:
			mid = (lo + hi) // 2
			if ss[mid] <= s:
				lo = mid
			else:
				hi = mid
		t = 0.0 if ss[hi] == ss[lo] else (s - ss[lo]) / (ss[hi] - ss[lo])
		a, b = info["pts"][lo], info["pts"][hi]
		return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))

	def corner_s(self, info, ny=0.707):
		"""Arc length where the upper section turns over into the top."""
		# Scan down from the top centre so the shoulder ledge is never mistaken
		# for the roof.
		for i in range(len(info["pts"]) - 1, info["ic"] - 1, -1):
			if info["n"][i][1] < ny:
				return info["s"][i]
		return info["s"][info["ic"]]

	def belt_s(self, info):
		return info["s"][info["ic"]]

	def surface_point(self, z, s, side=1.0):
		info = self.section_info(z)
		x, y = self.at_s(info, s)
		return Vector((x * side, y, z + self.shear(z, y)))

	# -- stations ------------------------------------------------------------

	def stations(self):
		n = 2400
		zs = [self.z0 + (self.z1 - self.z0) * i / (n - 1) for i in range(n)]
		pts = []
		for z in zs:
			p = self.params(z)
			pf = self.plan_factor(z)
			pts.append(Vector((z, p["w"] * pf, p["yt"] * 0.9, p["yb"] * 0.5)))
		acc = [0.0]
		for i in range(1, n):
			d = (pts[i] - pts[i - 1]).length
			turn = 0.0
			if 0 < i < n - 1:
				a = pts[i] - pts[i - 1]
				b = pts[i + 1] - pts[i]
				if a.length > 1e-9 and b.length > 1e-9:
					turn = a.angle(b, 0.0)
			acc.append(acc[-1] + d + 0.02 * turn)
		total = acc[-1]
		out = []
		k = 0
		m = self.stations_n
		for i in range(m):
			s = total * i / (m - 1)
			while k < n - 2 and acc[k + 1] < s:
				k += 1
			span = acc[k + 1] - acc[k]
			t = 0.0 if span < 1e-12 else (s - acc[k]) / span
			out.append(lerp(zs[k], zs[k + 1], clamp(t, 0, 1)))
		spacing = (self.z1 - self.z0) / m
		for ez in self.extra_z:
			out = [z for z in out if abs(z - ez) > spacing * 0.35 or z in (self.z0, self.z1)]
			out.append(ez)
		return sorted(set(out))

	# -- meshes --------------------------------------------------------------

	def rings(self, zs, shrink=0.0):
		rows = []
		for z in zs:
			half = self.half_section(z)
			left = [(x, y) for x, y in half]
			right = [(-x, y) for x, y in half[-2:0:-1]]
			ring = []
			for x, y in left + right:
				ring.append(Vector((x, y, z + self.shear(z, y))))
			rows.append(ring)
		return rows

	def build_outer(self, name="Shell"):
		zs = self.stations()
		self.zs = zs
		rows = self.rings(zs)
		mb = MeshBuilder()
		mb.grid(rows, "Paint", close_v=True)
		obj = mb.build(name, merge=0.0008, recalc=True)
		self._assign_underbody(obj)
		self.outer = obj
		self.bvh = core.bvh_of(obj)
		return obj

	def _assign_underbody(self, obj):
		me = obj.data
		names = [m.name for m in me.materials]
		if "Underbody" not in names:
			me.materials.append(core.material("Underbody"))
			names.append("Underbody")
		ui = names.index("Underbody")
		for p in me.polygons:
			c = p.center
			pr = self.params(c.z)
			if p.normal.y < -0.85 and c.y < pr["ym"]:
				p.material_index = ui

	def build_inner(self, name="Inner"):
		"""Coarser offset copy, facing inwards, for the inside of the panels."""
		zs = self.zs[::2]
		if zs[-1] != self.zs[-1]:
			zs.append(self.zs[-1])
		saved = (self.na, self.nbs, self.nc)
		self.na, self.nbs, self.nc = max(4, self.na // 2), max(3, self.nbs // 2), max(8, self.nc // 2)
		rows = self.rings(zs)
		self.na, self.nbs, self.nc = saved
		mb = MeshBuilder()
		mb.grid(rows, "Interior", close_v=True)
		obj = mb.build(name, merge=0.0008, recalc=True)
		me = obj.data
		t = self.thickness
		outer_bvh = self.bvh
		for v in me.vertices:
			p = v.co - v.normal * t
			if outer_bvh is not None:
				# Keep a full panel thickness from the outer skin everywhere.
				loc, nrm, _i, dist = outer_bvh.find_nearest(p)
				if loc is not None and ((p - loc).dot(nrm) > -t * 0.8):
					p = loc - nrm * t
			v.co = p
		me.flip_normals()
		me.update()
		return obj

	# -- queries ---------------------------------------------------------------

	def ray(self, origin, direction, dist=10.0):
		hit, nrm, _i, _d = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized(), dist)
		return hit, nrm

	def side_point(self, y, z, side=1.0):
		"""Point on the body side at height y and length z (ray along -x)."""
		hit, nrm = self.ray((side * 4.0, y, z), (-side, 0, 0), 8.0)
		return hit, nrm

	def top_point(self, x, z):
		hit, nrm = self.ray((x, 4.0, z), (0, -1, 0), 8.0)
		return hit, nrm

	def front_point(self, x, y, front=True):
		if front:
			hit, nrm = self.ray((x, y, self.z1 + 2.0), (0, 0, -1), 8.0)
		else:
			hit, nrm = self.ray((x, y, self.z0 - 2.0), (0, 0, 1), 8.0)
		return hit, nrm

	# -- window loops ------------------------------------------------------------

	def side_window_loop(self, z0, z1, belt_gap=0.025, top_gap=0.045, n=36, top_fn=None, bottom_fn=None):
		"""Loop of (z, y) points for a side window between z0 and z1."""
		bottom, top = [], []
		for i in range(n + 1):
			z = lerp(z0, z1, i / n)
			info = self.section_info(z)
			sb = self.belt_s(info) + belt_gap
			st = self.corner_s(info) - top_gap
			if top_fn:
				st = top_fn(z, info, st)
			if bottom_fn:
				sb = bottom_fn(z, info, sb)
			if st - sb < 0.015:
				continue
			xb, yb_ = self.at_s(info, sb)
			xt, yt_ = self.at_s(info, st)
			bottom.append((z + self.shear(z, yb_), yb_))
			top.append((z + self.shear(z, yt_), yt_))
		return bottom + top[::-1]

	def top_glass_loop(self, z0, z1, side_gap=0.04, n=24, across=14, edge_fn=None):
		"""3D loop for a windscreen / rear window spanning between the roof rails."""
		left = []
		for i in range(n + 1):
			z = lerp(z0, z1, i / n)
			info = self.section_info(z)
			s = self.corner_s(info) + side_gap
			if edge_fn:
				s = edge_fn(z, info, s)
			x, y = self.at_s(info, s)
			left.append(Vector((x, y, z + self.shear(z, y))))

		def across_pts(z, s_edge):
			info = self.section_info(z)
			total = info["s"][-1]
			out = []
			for k in range(across + 1):
				s = lerp(s_edge, total, k / across)
				x, y = self.at_s(info, s)
				out.append(Vector((x, y, z + self.shear(z, y))))
			mirrored = [Vector((-p.x, p.y, p.z)) for p in out[-2::-1]]
			return out + mirrored

		info0 = self.section_info(z0)
		info1 = self.section_info(z1)
		s0 = self.corner_s(info0) + side_gap
		s1 = self.corner_s(info1) + side_gap
		if edge_fn:
			s0 = edge_fn(z0, info0, s0)
			s1 = edge_fn(z1, info1, s1)
		front_edge = across_pts(z1, s1)  # left -> right at z1
		back_edge = across_pts(z0, s0)
		right = [Vector((-p.x, p.y, p.z)) for p in left]
		# loop: left side z0->z1, across at z1 left->right, right side z1->z0, across at z0 right->left
		loop = left[:-1] + front_edge[:-1] + right[::-1][:-1] + back_edge[::-1][:-1]
		return loop


def plane_frame(normal, up_hint=(0, 1, 0)):
	n = Vector(normal).normalized()
	u = Vector((1, 0, 0))
	if abs(n.dot(u)) > 0.9:
		u = Vector((0, 0, 1))
	u = (u - n * n.dot(u)).normalized()
	v = n.cross(u).normalized()
	if v.dot(Vector(up_hint)) < 0:
		v = -v
		u = -u
	return u, v, n


def project_loop(loop3d, origin, u, v):
	o = Vector(origin)
	return [((p - o).dot(u), (p - o).dot(v)) for p in loop3d]
