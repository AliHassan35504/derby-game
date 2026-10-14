"""CarBuilder: one car = a lofted shell plus everything cut into it and
bolted onto it. Each car module calls these methods and then finish()."""

import math

import bmesh
import bpy
from mathutils import Vector

from . import core, parts
from .body import Body
from .core import MeshBuilder, lerp


class CarBuilder:
	def __init__(self, style, size, wheel, body_spec=None):
		"""wheel: dict(r, w, x, y, z) of the settled wheel centre (front, left)."""
		self.style = style
		self.size = Vector(size)
		self.wheel = wheel
		self.cutters = []
		self.patch_specs = []
		self.parts = []
		self.objects = []
		self.glass = []
		self.markers = {}
		self.shells = []
		self.panel_specs = []
		self.panel_objs = []
		self.arches = []
		self.body = None
		if body_spec:
			self.body = self.add_shell(body_spec)

	# -- shells ------------------------------------------------------------------

	def add_shell(self, spec, name="Shell"):
		b = Body(spec)
		outer = b.build_outer(name + "_out")
		inner = b.build_inner(name + "_in")
		ref = core.duplicate(outer, name + "_ref")
		solid = core.join([outer, inner], name)
		b.solid = solid
		b.ref = ref
		b.outer = ref
		b.cutters = []
		self.shells.append(b)
		return b

	def cut(self, cutter, shell=None, mirror=False):
		shell = shell or self.body
		shell.cutters.append(cutter)
		if mirror:
			m = cutter.mirrored()
			shell.cutters.append(m)
			return cutter, m
		return cutter, None

	def patch(self, cutter, mat, inset=0.0, name="Patch", glass=False, shell=None):
		self.patch_specs.append((shell or self.body, cutter, mat, inset, name, glass))

	def add(self, mb):
		if mb is not None and (not isinstance(mb, MeshBuilder) or mb.faces):
			self.parts.append(mb)

	def marker(self, name, pos):
		self.markers[name] = Vector(pos)

	# -- wheel arches -------------------------------------------------------------

	def arch(self, z, y, radius, x_in=None, squash=1.0, n_exp=2.0, flare=None, lip=0.0, shell=None, tub=True, both=True):
		"""Cut a wheel arch on both sides, add a wheel well liner and optional flare.
		flare: dict(width, height, mat, extend) for a moulded/plastic arch flare."""
		b = shell or self.body
		if x_in is None:
			x_in = self.wheel["x"] - self.wheel["w"] * 0.7
		self.arches.append((z, y, radius * max(1.0, squash) + (flare.get("width", 0.08) if flare else 0.0)))
		cut = parts.arch_cutter(x_in, y, z, radius, 1.0, squash, n_exp, reveal="Underbody")
		self.cut(cut, b, mirror=both)
		if tub:
			self.add(self._tub(b, x_in, y, z, radius + 0.012, squash, n_exp))
		if flare:
			self.add(self._flare(b, y, z, radius, squash, n_exp, flare))

	def _arch_point(self, y, z, r, squash, n_exp, t):
		c, s = math.cos(t), math.sin(t)
		return z + r * core.spow(c, 2.0 / n_exp), y + r * squash * core.spow(s, 2.0 / n_exp)

	def _tub(self, b, x_in, y, z, r, squash, n_exp):
		mb = MeshBuilder()
		for side in (1.0, -1.0):
			rows = []
			centre_pts = []
			ts = [math.radians(lerp(-25.0, 205.0, i / 40)) for i in range(41)]
			for t in ts:
				zz, yy = self._arch_point(y, z, r, squash, n_exp, t)
				hit, _n = b.side_point(yy, zz, side)
				if hit is None:
					continue
				x_out = abs(hit.x) - 0.012
				if x_out < x_in + 0.02:
					continue
				rows.append([Vector((side * x_in, yy, zz)), Vector((side * x_out, yy, zz))])
				centre_pts.append(Vector((side * x_in, yy, zz)))
			if len(rows) < 2:
				continue
			mb.grid(rows, "Underbody", flip=(side < 0), smooth=True)
			# Inner wall: fan from the axle line.
			c = Vector((side * x_in, y, z))
			for i in range(len(centre_pts) - 1):
				tri = (mb.v(c), mb.v(centre_pts[i]), mb.v(centre_pts[i + 1]))
				mb.f(tri if side < 0 else tri[::-1], "Underbody", False)
		return mb

	def _flare(self, b, y, z, r, squash, n_exp, fl):
		mb = MeshBuilder()
		width = fl.get("width", 0.08)
		height = fl.get("height", 0.03)
		mat = fl.get("mat", "Paint")
		a0, a1 = fl.get("angles", (-12.0, 192.0))
		for side in (1.0, -1.0):
			samples = []
			for i in range(32):
				t = math.radians(lerp(a0, a1, i / 31))
				zz, yy = self._arch_point(y, z, r + width * 0.5, squash, n_exp, t)
				hit, nrm = b.side_point(yy, zz, side)
				if hit is None:
					continue
				samples.append((hit, nrm))
			if len(samples) < 3:
				continue
			mb.add(parts.raised_strip(samples, width, height, mat))
		return mb

	# -- glass ------------------------------------------------------------------

	def side_window(self, z0, z1, name, belt_gap=0.025, top_gap=0.045, reveal="Trim", x_in=None, radius=0.035, inset=0.009, top_fn=None, bottom_fn=None, shell=None):
		b = shell or self.body
		loop = b.side_window_loop(z0, z1, belt_gap, top_gap, top_fn=top_fn, bottom_fn=bottom_fn)
		if len(loop) < 3:
			return None
		if x_in is None:
			x_in = 0.25
		cut = parts.side_cutter(loop, x_in, 1.0, radius, reveal=reveal, name=name)
		c, m = self.cut(cut, b, mirror=True)
		self.patch(c, "Glass", inset, "Glass_%s_L" % name, True, b)
		self.patch(m, "Glass", inset, "Glass_%s_R" % name, True, b)
		return c

	def side_window_poly(self, poly_zy, name, x_in=0.25, reveal="Trim", radius=0.03, inset=0.009, shell=None, mat="Glass"):
		b = shell or self.body
		cut = parts.side_cutter(poly_zy, x_in, 1.0, radius, reveal=reveal, name=name)
		c, m = self.cut(cut, b, mirror=True)
		self.patch(c, mat, inset, "Glass_%s_L" % name, mat == "Glass", b)
		self.patch(m, mat, inset, "Glass_%s_R" % name, mat == "Glass", b)
		return c

	def top_window(self, z0, z1, name, side_gap=0.045, reveal="Trim", radius=0.05, inset=0.008, edge_fn=None, shell=None):
		b = shell or self.body
		loop = b.top_glass_loop(z0, z1, side_gap, edge_fn=edge_fn)
		cut = parts.surface_cutter(loop, b, 0.3, radius, reveal=reveal, name=name)
		self.cut(cut, b)
		self.patch(cut, "Glass", inset, "Glass_" + name, True, b)
		return cut

	def flat_window(self, poly2d, centre, normal, name, depth=0.2, reveal="Trim", inset=0.008, round_r=0.04, shell=None, mirror=False):
		b = shell or self.body
		cut = parts.flat_cutter(poly2d, centre, normal, depth, round_r=round_r, reveal=reveal, name=name)
		c, m = self.cut(cut, b, mirror=mirror)
		self.patch(c, "Glass", inset, "Glass_" + name + ("_L" if mirror else ""), True, b)
		if m:
			self.patch(m, "Glass", inset, "Glass_" + name + "_R", True, b)
		return cut

	# -- lights -------------------------------------------------------------------

	def lamp(self, poly2d, centre, normal, lens="HeadLens", emitters=(), depth=0.07, reveal="Chrome", housing="Chrome", round_r=0.0, mirror=True, cut_depth=0.18, lens_inset=0.003, back_mat=None, shell=None, up=(0, 1, 0), marker=None):
		"""A light: hole in the shell, reflector housing with emitters, lens patch.
		lens is HeadLens (clear) or TailLens (red) so the game can light them up.
		marker names empties at the lens centre (<marker>_L / _R) for lamps."""
		b = shell or self.body
		cut = parts.flat_cutter(poly2d, centre, normal, cut_depth, up=up, round_r=round_r, reveal=reveal, name="lamp")
		c, m = self.cut(cut, b, mirror=mirror)
		if marker:
			p0 = Vector(centre)
			self.markers[marker + ("_L" if p0.x >= 0 else "_R")] = p0.copy()
			if m is not None:
				self.markers[marker + ("_R" if p0.x >= 0 else "_L")] = Vector((-p0.x, p0.y, p0.z))
		for cc in (c, m):
			if cc is None:
				continue
			mirrored = cc is m
			ems = []
			for kind, (eu, ev), sz, mat in emitters:
				ems.append((kind, (eu, ev), sz, mat))
			self.add(parts.light_housing(b, cc, ems, depth, housing_mat=housing, back_mat=back_mat))
			self.patch(cc, lens, lens_inset, "Lens", False, b)
		return c

	def grille(self, poly2d, centre, normal, style="bars", mat="Trim", count=6, depth=0.06, bar_t=0.012, vertical=0, reveal="Trim", round_r=0.0, shell=None):
		b = shell or self.body
		cut = parts.flat_cutter(poly2d, centre, normal, 0.2, round_r=round_r, reveal=reveal, name="grille")
		self.cut(cut, b)
		back, bars = parts.grille_insert(b, cut, style, mat, None, count, depth, bar_t, vertical)
		self.add(back)
		if bars:
			self.objects.append(bars)
		return cut

	# -- strips ---------------------------------------------------------------------

	def gap_side(self, pts_zy, width=0.006, both=True, n=60, shell=None, mat="Gap", closed=False):
		b = shell or self.body
		pts = parts.polyline([Vector(p) for p in pts_zy], n) if not closed else [(p[0], p[1]) for p in core.resample_polyline([Vector(p) for p in list(pts_zy) + [pts_zy[0]]], n, 0.0)][:-1]
		for side in ((1.0, -1.0) if both else (1.0,)):
			s = parts.project_side(b, pts, side)
			self.add(parts.ribbon(s, width, mat, closed))

	def gap_top(self, pts_xz, width=0.006, n=60, shell=None, mat="Gap", mirror=False):
		b = shell or self.body
		pts = parts.polyline([Vector(p) for p in pts_xz], n)
		s = parts.project_top(b, pts)
		self.add(parts.ribbon(s, width, mat))
		if mirror:
			s = parts.project_top(b, [(-x, z) for x, z in pts])
			self.add(parts.ribbon(s, width, mat))

	def gap_dir(self, pts3d, direction, width=0.006, n=60, shell=None, mat="Gap", mirror=False):
		b = shell or self.body
		pts = [Vector(p) for p in core.resample_polyline([Vector(p) for p in pts3d], n, 0.0)]
		s = parts.project_dir(b, pts, direction)
		self.add(parts.ribbon(s, width, mat))
		if mirror:
			d = Vector(direction)
			s = parts.project_dir(b, [Vector((-p.x, p.y, p.z)) for p in pts], Vector((-d.x, d.y, d.z)))
			self.add(parts.ribbon(s, width, mat))

	def strip_side(self, pts_zy, width, height, mat="Chrome", n=40, shell=None, both=True, steps=3):
		b = shell or self.body
		pts = parts.polyline([Vector(p) for p in pts_zy], n)
		for side in ((1.0, -1.0) if both else (1.0,)):
			s = parts.project_side(b, pts, side, 0.0)
			self.add(parts.raised_strip(s, width, height, mat, steps=steps))

	def stripe_side(self, pts_zy_loop, mat="Decal", lift=0.002, both=True, shell=None, n=80, nv=4):
		"""A painted stripe: a band between two side-view polylines (top, bottom)."""
		b = shell or self.body
		top, bottom = pts_zy_loop
		top = parts.polyline([Vector(p) for p in top], n)
		bottom = parts.polyline([Vector(p) for p in bottom], n)
		for side in ((1.0, -1.0) if both else (1.0,)):
			rows = []
			for (zt, yt), (zb, yb) in zip(top, bottom):
				if any(math.hypot(zz - az, yy - ay) < ar + 0.025 for az, ay, ar in self.arches for zz, yy in ((zt, yt), (zb, yb))):
					# Over a wheel arch: leave a break in the stripe.
					if rows:
						self._stripe_rows(rows, mat, side)
						rows = []
					continue
				col = []
				for k in range(nv):
					y = lerp(yb, yt, k / (nv - 1))
					z = lerp(zb, zt, k / (nv - 1))
					hit, nrm = b.side_point(y, z, side)
					if hit is None:
						col = None
						break
					col.append(hit + nrm * lift)
				if col:
					rows.append(col)
			if rows:
				self._stripe_rows(rows, mat, side)

	def _stripe_rows(self, rows, mat, side):
		if len(rows) < 2:
			return
		mb = MeshBuilder()
		mb.grid(rows, mat)
		if mb.faces:
			f = mb.faces[len(mb.faces) // 2]
			a_, b_, c_ = (Vector(mb.verts[f[q]]) for q in range(3))
			if (b_ - a_).cross(c_ - a_).x * side < 0:
				mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
		self.add(mb)

	def stripe_top(self, xs, z0, z1, mat="Decal", lift=0.002, n=60, shell=None):
		"""A painted stripe over the top between x-range xs=(x0, x1), z0..z1."""
		b = shell or self.body
		rows = []
		for i in range(n + 1):
			z = lerp(z0, z1, i / n)
			col = []
			for k in range(4):
				x = lerp(xs[0], xs[1], k / 3)
				hit, nrm = b.top_point(x, z)
				if hit is None:
					col = None
					break
				col.append(hit + nrm * lift)
			if col:
				rows.append(col)
		mb = MeshBuilder()
		mb.grid(rows, mat)
		if mb.faces:
			f = mb.faces[len(mb.faces) // 2]
			a_, b_, c_ = (Vector(mb.verts[f[q]]) for q in range(3))
			if (b_ - a_).cross(c_ - a_).y < 0:
				mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
		self.add(mb)

	# -- bolt-on parts ----------------------------------------------------------

	def mirror(self, z, y, out=0.06, rise=0.07, size=(0.1, 0.06, 0.05), mat="Paint", shell=None, arm_mat="Trim", glass_mat="Chrome"):
		"""Door mirrors on both sides: base on the door at (y, z), pod out and up."""
		b = shell or self.body
		hx, hy, hz = size
		for side in (1.0, -1.0):
			hit, nrm = b.side_point(y, z, side)
			if hit is None:
				continue
			c = Vector((hit.x + side * (out + hx), y + rise, z - 0.02))
			# Pod: rounded at the front, flat at the back where the glass sits.
			pod = core.superquadric(c, (hx, hy, hz), 0.45, 0.55, 16, 10, mat,
				deform=lambda p: Vector((p.x * (1.0 - 0.12 * max(p.y, 0.0)), p.y, p.z * (0.7 if p.z < 0 else 1.0))))
			self.add(pod)
			self.add(core.superquadric(c + Vector((side * 0.004, 0.0, -hz * 0.66)), (hx * 0.86, hy * 0.8, 0.006), 0.3, 0.3, 12, 4, glass_mat))
			base = hit - Vector((side * 0.01, 0.0, 0.0))
			mid = Vector(((base.x + c.x - side * hx * 0.8) * 0.5, (y + c.y) * 0.5 - 0.01, z))
			self.add(core.superquadric(mid, (abs(c.x - side * hx * 0.8 - base.x) * 0.55 + 0.01, abs(c.y - y) * 0.5 + 0.015, 0.04), 0.4, 0.4, 10, 6, arm_mat))

	def bumper(self, front, y0, y1, out=0.035, mat="Paint", theta=72.0, back=0.85, kind="round", gap=0.03,
			thick=0.05, n=44, k=8, taper=0.22, shell=None, p=4.0, sides=None):
		"""Bumper around one end of the car. 'round' bulges out of the body
		(a bumper cover); 'blade' is a separate bar standing off the body."""
		b = shell or self.body
		zc = (b.z1 - back) if front else (b.z0 + back)
		sgn = 1.0 if front else -1.0
		rows = []
		for i in range(n + 1):
			th = math.radians(lerp(-theta, theta, i / n))
			d = Vector((math.sin(th), 0.0, sgn * math.cos(th)))
			ends = abs(i / n - 0.5) * 2.0
			fade = 1.0 - core.smoothstep(1.0 - taper, 1.0, ends) if kind == "round" else 1.0
			col = []
			prof = []
			if kind == "round":
				for j in range(k + 1):
					t = j / k
					u = out * fade * max(0.0, 1.0 - abs(2 * t - 1) ** p) ** (1.0 / p)
					prof.append((lerp(y0, y1, t), u + 0.002))
			else:
				for j in range(k + 1):
					a = math.pi * j / k
					prof.append((lerp(y0, y1, 0.5) - math.cos(a) * (y1 - y0) * 0.5, gap + thick * (0.35 + 0.65 * math.sin(a))))
				for j in range(1, k):
					t = j / k
					prof.append((lerp(y1, y0, t), gap))
			for (y, u) in prof:
				origin = Vector((0.0, y, zc)) + d * 4.0
				hit, nrm = b.ray(origin, -d, 6.0)
				if hit is None:
					col = None
					break
				hn = Vector((nrm.x, 0.0, nrm.z))
				if hn.length < 1e-4:
					hn = d.copy()
				hn.normalize()
				col.append(hit + hn * u)
			if col:
				rows.append(col)
		mb = MeshBuilder()
		mb.grid(rows, mat, close_v=(kind != "round"))
		if mb.faces and rows:
			nv = len(rows[0])
			iv = nv if kind != "round" else nv - 1
			f = mb.faces[min(len(mb.faces) - 1, (len(rows) // 2) * iv + k // 2)]
			a_, b_, c_ = (Vector(mb.verts[f[q]]) for q in range(3))
			centre = Vector((0.0, (y0 + y1) * 0.5, zc))
			if (b_ - a_).cross(c_ - a_).dot(a_ - centre) < 0:
				mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
		self.add(mb)
		return rows

	def spotlamp(self, centre, normal=(0, 0, 1), r=0.09, depth=0.09, housing="Trim", lens="Headlight", bezel="Chrome", guard=True):
		"""Round auxiliary lamp pod (rally spot light, roof light bar lamp)."""
		c = Vector(centre)
		n = Vector(normal).normalized()
		back = c - n * depth
		self.add(core.cylinder(back, c - n * 0.004, r * 0.92, r, 20, housing, caps=True))
		ring = core.cylinder(c - n * 0.01, c + n * 0.008, r * 1.03, r * 1.0, 20, bezel, caps=False)
		self.add(ring)
		# Lens: a shallow dome.
		mb = MeshBuilder()
		u = n.cross(Vector((0, 1, 0)) if abs(n.y) < 0.9 else Vector((1, 0, 0))).normalized()
		v = n.cross(u).normalized()
		rings = []
		for k in range(4):
			a = k / 3 * math.pi * 0.5
			rr = r * 0.9 * math.cos(a)
			h = r * 0.18 * math.sin(a)
			rings.append([c + n * h + (u * math.cos(t) + v * math.sin(t)) * rr for t in [2 * math.pi * q / 20 for q in range(20)]])
		mb.grid(rings, lens, close_v=True)
		mb.fan(rings[-1], c + n * r * 0.18, lens)
		# Point the dome outwards.
		f = mb.faces[0]
		a_, b_, c_ = (Vector(mb.verts[f[q]]) for q in range(3))
		if (b_ - a_).cross(c_ - a_).dot(n) < 0:
			mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
		self.add(mb)
		# Cross-hair guard, very rally.
		for t in ((0.0, math.pi * 0.5) if guard else ()):
			d = u * math.cos(t) + v * math.sin(t)
			self.add(core.cylinder(c + n * (r * 0.2) - d * r * 0.9, c + n * (r * 0.2) + d * r * 0.9, 0.005, 0.005, 6, "Trim", caps=False))

	def roundel(self, z, y, r=0.17, text="27", mat="Plate", text_mat="Trim", shell=None):
		"""Competition number disc on both doors."""
		b = shell or self.body
		for side in (1.0, -1.0):
			pts = parts.ellipse(r, r, 28, z, y)
			s = parts.project_side(b, pts, side, 0.0025)
			if len(s) < 3:
				continue
			cen, cn = b.side_point(y, z, side)
			mb = MeshBuilder()
			mb.fan([p for p, _ in s], cen + cn * 0.0025, mat)
			f = mb.faces[0]
			a_, b_, c_ = (Vector(mb.verts[f[q]]) for q in range(3))
			if (b_ - a_).cross(c_ - a_).dot(cn) < 0:
				mb.faces = [tuple(reversed(ff)) for ff in mb.faces]
			self.add(mb)
			self.add(core.text_mesh(text, r * 1.15, 0.002, text_mat, cen + cn * 0.003, Vector((0, 0, -side)), Vector((0, 1, 0)), cn))

	def flaps(self, zs, x, y_top, y_bottom, width=0.3, mat="Trim"):
		"""Mud flaps hanging behind the wheels at each z."""
		for z in zs:
			for side in (1.0, -1.0):
				self.add(core.box((side * x, (y_top + y_bottom) * 0.5, z), (width * 0.5, (y_top - y_bottom) * 0.5, 0.006), mat))

	def box_cut(self, x0, x1, y0, y1, z0, z1, reveal="Paint", shell=None):
		"""Cut a box (x0..x1 across, y0..y1, z0..z1) out of a shell, e.g. a pickup bed."""
		b = shell or self.body
		poly = [(z0, y0), (z1, y0), (z1, y1), (z0, y1)]
		cut = parts.Cutter(poly, (0, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0, 0), x0, x1, reveal=reveal, name="box")
		self.cut(cut, b)
		return cut

	def bed_tub(self, x, y_floor, y_top, z0, z1, mat="Underbody", ribs=7, rib_mat="Underbody"):
		"""Load bed liner: floor with ribs, side walls, front wall and tailgate."""
		mb = MeshBuilder()
		def quad(a, b, c, d, m=mat):
			mb.f((mb.v(a), mb.v(b), mb.v(c), mb.v(d)), m, False)
		quad((-x, y_floor, z0), (-x, y_floor, z1), (x, y_floor, z1), (x, y_floor, z0))
		quad((x, y_floor, z0), (x, y_floor, z1), (x, y_top, z1), (x, y_top, z0))
		quad((-x, y_top, z0), (-x, y_top, z1), (-x, y_floor, z1), (-x, y_floor, z0))
		quad((-x, y_floor, z1), (-x, y_top, z1), (x, y_top, z1), (x, y_floor, z1))
		quad((x, y_floor, z0), (x, y_top, z0), (-x, y_top, z0), (-x, y_floor, z0))
		self.add(mb)
		for k in range(ribs):
			xx = lerp(-x * 0.85, x * 0.85, k / max(1, ribs - 1))
			self.add(core.superquadric((xx, y_floor + 0.006, (z0 + z1) * 0.5), (0.025, 0.012, (z1 - z0) * 0.49), 0.3, 0.6, 8, 4, rib_mat))

	def interior(self, dash_z, dash_y, half_w, seat_z, seat_y, seat_x=0.38, rear_z=None, rear_w=None, floor_y=None, wheel_x=0.38, seats=2, mat="Interior", bench_front=False, seat_mat="Seat"):
		"""Dashboard, steering wheel, seats and console."""
		self.dashboard(dash_z, dash_y, half_w, wheel_x=wheel_x, mat=mat)
		if bench_front:
			self.seat(0.0, seat_y, seat_z, width=half_w * 1.7, mat=seat_mat, bench=True)
		else:
			for sx in (seat_x, -seat_x):
				self.seat(sx, seat_y, seat_z, mat=seat_mat)
				if floor_y is not None:
					self.add(core.box((sx, (floor_y + seat_y - 0.1) * 0.5, seat_z - 0.25), (0.2, max(0.02, (seat_y - 0.1 - floor_y) * 0.5), 0.2), "Trim"))
			if floor_y is not None:
				self.console(seat_z - 0.45, dash_z + 0.05, floor_y, seat_y + 0.05, 0.09, mat)
		if rear_z is not None:
			self.seat(0.0, seat_y + 0.02, rear_z, width=rear_w or half_w * 1.6, mat=seat_mat, bench=True, recline=22.0)

	def underbody(self, y, z0, z1, rail_x=0.5, exhaust_x=-0.3, exhaust_z1=None, tank_z=None, axle_y=None, axle_z=(), axle_x=0.7, diff_z=None, muffler_z=None):
		"""Simple chassis below the floor so the car is not hollow from low angles."""
		self.frame_rails(rail_x, y - 0.05, z0, z1, 0.1, 0.07)
		for zz in (z0 + 0.2, (z0 + z1) * 0.5, z1 - 0.2):
			self.add(core.box((0, y - 0.05, zz), (rail_x, 0.04, 0.035), "Underbody"))
		ez1 = exhaust_z1 if exhaust_z1 is not None else z0
		self.add(core.cylinder((exhaust_x, y - 0.1, z1 - 0.3), (exhaust_x, y - 0.1, ez1), 0.035, 0.035, 10, "Brake", caps=False))
		if muffler_z is not None:
			self.add(core.superquadric((exhaust_x, y - 0.1, muffler_z), (0.14, 0.07, 0.22), 0.5, 0.5, 12, 6, "Brake"))
		if tank_z is not None:
			self.add(core.superquadric((0.15, y - 0.06, tank_z), (0.38, 0.08, 0.22), 0.3, 0.3, 12, 6, "Underbody"))
		if axle_y is not None:
			for az in axle_z:
				self.add(core.cylinder((-axle_x, axle_y, az), (axle_x, axle_y, az), 0.035, 0.035, 10, "Brake"))
				for sx in (1.0, -1.0):
					# Control arm from the rail to the hub.
					self.add(core.cylinder((sx * rail_x, y - 0.03, az + 0.25), (sx * axle_x, axle_y, az), 0.025, 0.025, 8, "Underbody"))
					self.add(core.cylinder((sx * rail_x, y - 0.03, az - 0.25), (sx * axle_x, axle_y, az), 0.025, 0.025, 8, "Underbody"))
		if diff_z is not None and axle_y is not None:
			self.add(core.superquadric((0, axle_y, diff_z), (0.14, 0.12, 0.14), 0.7, 0.7, 12, 8, "Brake"))
		# Engine sump / gearbox tunnel under the front.
		self.add(core.superquadric((0, y - 0.04, z1 - 0.6), (0.3, 0.09, 0.4), 0.3, 0.3, 10, 6, "Underbody"))

	def blackout(self, z0, z1, top_gap=0.03, belt_gap=0.0, mat="Trim", shell=None, n=8):
		"""Gloss black panel on a pillar between z0 and z1 (side view)."""
		b = shell or self.body
		top, bottom = [], []
		for i in range(n + 1):
			z = lerp(z0, z1, i / n)
			info = b.section_info(z)
			yt = b.at_s(info, b.corner_s(info) - top_gap)[1]
			yb = b.at_s(info, b.belt_s(info) + belt_gap)[1]
			top.append((z, yt))
			bottom.append((z, yb))
		self.stripe_side((top, bottom), mat, 0.0025, shell=b, n=n)

	def handle(self, z, y, length=0.13, mat="Chrome", recess=True, shell=None):
		b = shell or self.body
		for side in (1.0, -1.0):
			hit, nrm = b.side_point(y, z, side)
			if hit is None:
				continue
			c = hit + nrm * 0.008
			self.add(core.superquadric(c, (0.014, 0.016, length * 0.5), 0.35, 0.35, 10, 6, mat))
			if recess:
				pts = parts.ellipse(length * 0.42, 0.028, 16, z, y - 0.004)
				s = parts.project_side(b, pts, side, 0.0012)
				ring = MeshBuilder()
				cen = sum((p for p, _ in s), Vector()) / len(s)
				cn = sum((n for _, n in s), Vector()).normalized()
				ring.fan([p for p, _ in s], cen, "Gap", flip=(side > 0))
				self.add(ring)

	def plate(self, centre, normal, text="DRB 707", size=(0.52, 0.12), mat="Plate", up=(0, 1, 0), frame=True):
		n = Vector(normal).normalized()
		u, v, n = parts.plane_frame(n, up)
		c = Vector(centre)
		w, h = size
		poly = core.round_polygon(parts.rect(w, h), 0.012, 2)
		self.add(core.prism(poly, c, u, v, n, 0.0, 0.006, mat))
		if frame:
			outer = core.round_polygon(parts.rect(w + 0.025, h + 0.025), 0.018, 2)
			self.add(core.prism(outer, c, u, v, n, -0.004, 0.004, "Trim"))
		self.add(core.text_mesh(text, h * 0.62, 0.003, "Trim", c + n * 0.006 + v * (-h * 0.02), u, v, n))

	def exhaust(self, x, y, z, r=0.04, length=0.25, mat="Chrome", angle=0.0, dual=False, spacing=0.11, inner="Gap", name="Exhaust", shape="round"):
		"""Exhaust tip(s) pointing backwards (-z). Adds a marker for nitro flames.
		shape "oval" or "square" makes a wide tip set in the bumper."""
		xs = [x - spacing / 2, x + spacing / 2] if dual else [x]
		for i, xx in enumerate(xs):
			tip = Vector((xx, y, z))
			back = tip + Vector((0, math.sin(angle) * length, length))
			if shape != "round":
				ax, ay = (r * 1.7, r * 0.85)
				e = 2.0 if shape == "oval" else 5.0
				outer = [(ax * core.spow(math.cos(t), 2.0 / e), ay * core.spow(math.sin(t), 2.0 / e)) for t in [2 * math.pi * k / 24 for k in range(24)]]
				inner_p = [(u * 0.84, v * 0.76) for u, v in outer]
				self.add(core.sweep([back, tip], outer, mat, ups=[(0, 1, 0), (0, 1, 0)]))
				# Rolled lip from the outer skin into the dark pipe.
				lip = MeshBuilder()
				ro = [tip + Vector((-u, v, 0)) for u, v in outer]
				ri = [tip + Vector((-u, v, 0.004)) for u, v in inner_p]
				lip.grid([ro, ri], mat, close_v=True)
				self.add(lip)
				self.add(core.sweep([tip + Vector((0, 0, 0.004)), tip + Vector((0, 0, 0.06))], inner_p, inner, ups=[(0, 1, 0), (0, 1, 0)], caps=True))
				continue
			self.add(core.cylinder(back, tip, r, r * 1.05, 18, mat, caps=False))
			# Rolled lip and dark inside.
			self.add(core.cylinder(tip + Vector((0, 0, 0.002)), tip + Vector((0, 0, 0.03)), r * 0.86, r * 0.86, 18, inner, caps=False))
			self.add(core.cylinder(tip + Vector((0, 0, 0.03)), tip + Vector((0, 0, 0.031)), r * 0.86, r * 0.86, 18, inner, caps=True))
		self.markers["%s_%d" % (name, len([k for k in self.markers if k.startswith(name)]))] = Vector((x, y, z - 0.02))

	def engine_bay(self, z0, z1, y_floor, y_top, half_w):
		"""Engine, radiator and bits under the bonnet, seen if it is torn off."""
		zc = (z0 + z1) * 0.5
		hz = (z1 - z0) * 0.5
		h = y_top - y_floor
		# Engine block with two cam covers and an intake plenum.
		self.add(core.superquadric((0.0, y_floor + h * 0.35, zc - hz * 0.15), (half_w * 0.45, h * 0.32, hz * 0.55), 0.25, 0.25, 12, 6, "Brake"))
		for sx in (1.0, -1.0):
			self.add(core.superquadric((sx * half_w * 0.25, y_floor + h * 0.7, zc - hz * 0.15), (half_w * 0.12, h * 0.08, hz * 0.5), 0.3, 0.3, 10, 4, "Trim"))
		self.add(core.superquadric((0.0, y_floor + h * 0.78, zc - hz * 0.1), (half_w * 0.16, h * 0.09, hz * 0.32), 0.3, 0.3, 10, 4, "Chrome"))
		# Radiator across the front, airbox and battery at the sides.
		self.add(core.box((0.0, y_floor + h * 0.45, z1), (half_w * 0.85, h * 0.4, 0.03), "Trim"))
		self.add(core.superquadric((half_w * 0.72, y_floor + h * 0.62, zc + hz * 0.3), (half_w * 0.16, h * 0.14, hz * 0.25), 0.4, 0.4, 10, 6, "Underbody"))
		self.add(core.box((-half_w * 0.72, y_floor + h * 0.55, zc + hz * 0.25), (half_w * 0.13, h * 0.12, hz * 0.18), "Trim"))
		# Strut towers.
		for sx in (1.0, -1.0):
			self.add(core.cylinder((sx * half_w * 0.86, y_floor, zc - hz * 0.3), (sx * half_w * 0.86, y_top - 0.02, zc - hz * 0.3), 0.06, 0.05, 10, "Underbody"))

	def wipers(self, ws_cutter, pivots, length=0.5, angle=12.0, mat="Trim"):
		"""Wiper arms lying on the windscreen glass. pivots: list of x at the base."""
		b = self.body
		n = ws_cutter.w
		vdir = ws_cutter.v
		for px in pivots:
			# Base point near the bottom edge of the windscreen.
			vmin = min(p[1] for p in ws_cutter.poly)
			base = ws_cutter.origin + ws_cutter.u * px + vdir * (vmin + 0.03)
			ang = math.radians(angle)
			d = (ws_cutter.u * math.sin(ang) + vdir * math.cos(ang))
			d = (ws_cutter.u * -math.cos(ang) + vdir * math.sin(ang))
			pts = [base + d * length * k / 10 for k in range(11)]
			s = parts.project_dir(b, pts, -n, 0.012)
			if len(s) < 2:
				continue
			self.add(parts.raised_strip(s, 0.016, 0.012, mat))
			arm = [(p + nn * 0.012, nn) for p, nn in s[: max(2, len(s) // 3)]]
			self.add(core.cylinder(s[0][0] - n * 0.01, s[0][0] + n * 0.03, 0.018, 0.016, 10, mat))

	def seat(self, x, y, z, width=0.5, back_h=0.62, cushion_d=0.5, mat="Interior", recline=16.0, headrest=True, bench=False):
		"""A seat (x, y, z = front centre of the cushion at cushion height)."""
		mb = MeshBuilder()
		c = Vector((x, y - 0.05, z - cushion_d * 0.5))
		mb.add(core.superquadric(c, (width * 0.5, 0.07, cushion_d * 0.5), 0.35, 0.3, 12, 6, mat))
		rec = math.radians(recline)
		back_c = Vector((x, y + back_h * 0.5 * math.cos(rec), z - cushion_d - back_h * 0.5 * math.sin(rec) + 0.05))

		def tilt(p):
			return p

		back = core.superquadric((0, 0, 0), (width * 0.5, back_h * 0.5, 0.07), 0.3, 0.35, 12, 8, mat)
		back.transform(lambda p: Vector((p.x, p.y * math.cos(rec) + p.z * math.sin(rec), -p.y * math.sin(rec) + p.z * math.cos(rec))) + back_c)
		mb.add(back)
		if headrest and not bench:
			hc = back_c + Vector((0, back_h * 0.5 * math.cos(rec) + 0.08, -back_h * 0.5 * math.sin(rec) - 0.02))
			mb.add(core.superquadric(hc, (0.13, 0.08, 0.05), 0.4, 0.4, 10, 6, mat))
		self.add(mb)

	def dashboard(self, z, y, half_w, depth=0.35, height=0.18, mat="Interior", wheel_x=0.38, wheel_r=0.18, gauge=True):
		"""Dash panel spanning the cabin at z (its back face), with a steering wheel."""
		c = Vector((0, y, z + depth * 0.5))
		self.add(core.superquadric(c, (half_w, height * 0.5, depth * 0.5), 0.25, 0.25, 16, 8, mat))
		# Hood over the gauges.
		self.add(core.superquadric(Vector((wheel_x, y + height * 0.5, z + 0.06)), (0.2, 0.05, 0.1), 0.4, 0.4, 10, 6, "Trim"))
		# Steering wheel: rim (torus) + hub + spokes, tilted towards the driver.
		wc = Vector((wheel_x, y + 0.02, z - 0.16))
		tilt = math.radians(28.0)
		axis = Vector((0, math.sin(tilt), -math.cos(tilt)))
		ring = []
		prof = [(math.cos(t) * 0.018, math.sin(t) * 0.018) for t in [2 * math.pi * k / 8 for k in range(8)]]
		u = Vector((1, 0, 0))
		v = axis.cross(u).normalized()
		path = [wc + (u * math.cos(t) + v * math.sin(t)) * wheel_r for t in [2 * math.pi * k / 28 for k in range(28)]]
		ups = [axis for _ in path]
		self.add(core.sweep(path, prof, "Trim", ups=None, closed_path=True))
		self.add(core.cylinder(wc + axis * 0.02, wc - axis * 0.03, 0.05, 0.05, 12, "Trim"))
		for t in (math.pi * 0.0, math.pi, math.pi * 1.5):
			end = wc + (u * math.cos(t) + v * math.sin(t)) * wheel_r
			self.add(core.cylinder(wc, end, 0.012, 0.012, 6, "Trim", caps=False))
		self.add(core.cylinder(wc - axis * 0.03, Vector((wheel_x, y - 0.05, z + 0.05)), 0.03, 0.04, 8, "Trim"))

	def console(self, z0, z1, y0, y1, half_w=0.1, mat="Interior"):
		self.add(core.superquadric(Vector((0, (y0 + y1) / 2, (z0 + z1) / 2)), (half_w, (y1 - y0) / 2, (z1 - z0) / 2), 0.2, 0.25, 8, 6, mat))

	def frame_rails(self, x, y, z0, z1, h=0.12, w=0.06, mat="Underbody"):
		for side in (1.0, -1.0):
			self.add(core.box((side * x, y, (z0 + z1) / 2), (w / 2, h / 2, (z1 - z0) / 2), mat))

	# -- finishing ------------------------------------------------------------------

	def finish(self, use_self=True):
		"""Cut the shells, build patches and join everything.
		Returns (body_obj, glass_objs, marker dict)."""
		shell_objs = []
		for b in self.shells:
			if b.cutters:
				mb = MeshBuilder()
				for c in b.cutters:
					mb.add(c.mesh())
				cut_obj = mb.build("Cutters")
				mod = b.solid.modifiers.new("bool", "BOOLEAN")
				mod.operation = "DIFFERENCE"
				mod.solver = "EXACT"
				mod.object = cut_obj
				mod.material_mode = "TRANSFER"
				mod.use_self = use_self
				core.apply_modifiers(b.solid)
				core.delete(cut_obj)
			shell_objs.append(b.solid)
		glass = []
		lens_objs = []
		for b, cutter, mat, inset, name, is_glass in self.patch_specs:
			p = parts.surface_patch(b.ref, cutter, mat, inset, name)
			if len(p.data.polygons) == 0:
				core.delete(p)
				continue
			if is_glass:
				glass.append(p)
			else:
				lens_objs.append(p)
		for b in self.shells:
			core.delete(b.ref)
		part_objs = []
		for i, mb in enumerate(self.parts):
			if isinstance(mb, MeshBuilder):
				part_objs.append(mb.build("Part%d" % i))
			else:
				part_objs.append(mb)
		body = core.join(shell_objs + lens_objs + part_objs + self.objects, "Body")
		self._mark_sharp(body)
		for g in glass:
			g.data.shade_smooth()
		self.panel_objs = []
		for name, planes, bbox in self.panel_specs:
			obj = self._split_panel(body, name, planes, bbox)
			if obj is not None:
				self.panel_objs.append(obj)
		return body, glass, dict(self.markers)

	def _mark_sharp(self, body, angle=38.0, crease_angle=7.0):
		"""Smooth shading with hard edges above angle, plus the shells' character
		lines (shoulder crease, sill) wherever they bend more than crease_angle."""
		me = body.data
		me.shade_smooth()
		paint = {i for i, m in enumerate(me.materials) if m and m.name.split(".")[0] in ("Paint", "Decal", "Livery")}
		bm = bmesh.new()
		bm.from_mesh(me)
		lim = math.radians(angle)
		clim = math.radians(crease_angle)
		for e in bm.edges:
			if len(e.link_faces) != 2:
				e.smooth = False
				continue
			a = e.calc_face_angle(0.0)
			sharp = a > lim
			if not sharp and a > clim and all(f.material_index in paint for f in e.link_faces):
				mid = (e.verts[0].co + e.verts[1].co) * 0.5
				sharp = any(b.is_crease(mid) for b in self.shells)
			e.smooth = not sharp
		bm.to_mesh(me)
		bm.free()
		me.update()

	# -- detachable panels ----------------------------------------------------

	def panel(self, name, planes, bbox):
		"""Register a detachable panel: every face of the finished body whose
		centre lies inside bbox ((x0, y0, z0), (x1, y1, z1)) and on the positive
		side of every plane (point, normal) is split off into its own object.
		The body is bisected along the planes first so the edges are clean."""
		self.panel_specs.append((name, [(Vector(p), Vector(n).normalized()) for p, n in planes], (Vector(bbox[0]), Vector(bbox[1]))))

	def panel_box(self, name, x0, x1, y0, y1, z0, z1, extra=()):
		planes = [((x0, 0, 0), (1, 0, 0)), ((x1, 0, 0), (-1, 0, 0)), ((0, y0, 0), (0, 1, 0)), ((0, y1, 0), (0, -1, 0)),
			((0, 0, z0), (0, 0, 1)), ((0, 0, z1), (0, 0, -1))] + list(extra)
		self.panel(name, planes, ((x0, y0, z0), (x1, y1, z1)))

	def _split_panel(self, body, name, planes, bbox):
		me = body.data
		bm = bmesh.new()
		bm.from_mesh(me)
		lo, hi = bbox
		pad = Vector((0.03, 0.03, 0.03))

		def near(f):
			c = f.calc_center_median()
			return all(lo[k] - pad[k] <= c[k] <= hi[k] + pad[k] for k in range(3))

		for co, no in planes:
			faces = [f for f in bm.faces if near(f)]
			if not faces:
				break
			edges = list({e for f in faces for e in f.edges})
			verts = list({v for f in faces for v in f.verts})
			bmesh.ops.bisect_plane(bm, geom=faces + edges + verts, plane_co=co, plane_no=no, dist=0.0005)

		def inside(f):
			c = f.calc_center_median()
			if not all(lo[k] <= c[k] <= hi[k] for k in range(3)):
				return False
			return all((c - co).dot(no) >= 0.0 for co, no in planes)

		take = [f for f in bm.faces if inside(f)]
		if not take:
			bm.free()
			return None
		# Copy the faces into a new mesh, then remove them from the body.
		bm.verts.index_update()
		verts, faces, fmats, fsmooth = [], [], [], []
		vmap = {}
		for f in take:
			ids = []
			for v in f.verts:
				if v.index not in vmap:
					vmap[v.index] = len(verts)
					verts.append(tuple(v.co))
				ids.append(vmap[v.index])
			faces.append(tuple(ids))
			fmats.append(me.materials[f.material_index].name.split(".")[0])
			fsmooth.append(f.smooth)
		sharp_pairs = set()
		for f in take:
			for e in f.edges:
				if not e.smooth:
					sharp_pairs.add(frozenset(vmap[v.index] for v in e.verts if v.index in vmap))
		bmesh.ops.delete(bm, geom=take, context="FACES")
		bm.to_mesh(me)
		bm.free()
		me.update()
		obj = core.make_object(name, verts, faces, fmats, fsmooth)
		pm = obj.data
		pm.shade_smooth()
		pb = bmesh.new()
		pb.from_mesh(pm)
		for e in pb.edges:
			if frozenset(v.index for v in e.verts) in sharp_pairs or len(e.link_faces) != 2:
				e.smooth = False
		pb.to_mesh(pm)
		pb.free()
		pm.update()
		return obj
