"""Wheels: tyre with sidewall and tread blocks, spoked rim with depth, lug
nuts, brake disc and (separate, non-spinning) caliper. Built centred at the
origin with the axle along X and the outer face towards +X."""

import math

from mathutils import Vector

from . import core
from .core import MeshBuilder, lerp

# Per style: rim radius as a fraction of the tyre radius, tread kind, rim design.
WHEEL_STYLES = {
	"sedan": dict(rim=0.62, tread="road", spokes=10, design="twin", dish=0.035, nuts=5, disc=0.84, caliper=True),
	"sports": dict(rim=0.68, tread="road", spokes=5, design="split", dish=0.05, nuts=5, disc=0.88, caliper=True),
	"muscle": dict(rim=0.6, tread="road", spokes=5, design="star", dish=0.07, nuts=5, disc=0.78, caliper=True, lip=0.03),
	"van": dict(rim=0.56, tread="allterrain", spokes=8, design="slot", dish=0.06, nuts=6, disc=0.8, caliper=True, lip=0.025),
	"pickup": dict(rim=0.56, tread="allterrain", spokes=6, design="truck", dish=0.05, nuts=6, disc=0.82, caliper=True),
	"rally": dict(rim=0.62, tread="gravel", spokes=6, design="rally", dish=0.03, nuts=5, disc=0.84, caliper=True),
	"monster": dict(rim=0.5, tread="mud", spokes=8, design="beadlock", dish=0.09, nuts=8, disc=0.5, caliper=False),
}


def build_wheel(style, w):
	cfg = WHEEL_STYLES.get(style, WHEEL_STYLES["sedan"])
	R = w["r"]
	W = w["w"]
	rr = R * cfg["rim"]
	mb = MeshBuilder()
	tyre(mb, R, W, rr, cfg["tread"])
	rim(mb, R, W, rr, cfg)
	wheel = mb.build("Wheel", merge=0.0002)
	wheel.data.shade_smooth()
	wheel.data.set_sharp_from_angle(angle=math.radians(40.0))
	objs = [wheel]
	if cfg["caliper"]:
		cal = caliper(R, W, rr, cfg).build("Caliper")
		cal.data.shade_smooth()
		cal.data.set_sharp_from_angle(angle=math.radians(40.0))
		objs.append(cal)
	return objs


# ---------------------------------------------------------------------------


def tyre(mb, R, W, rr, tread):
	hw = W * 0.5
	h = R - rr
	mud = tread == "mud"
	tread_hw = hw * (0.92 if mud else 0.8)
	depth = {"road": 0.009, "allterrain": 0.016, "gravel": 0.014, "mud": 0.07}[tread] * (R / 0.36 if not mud else 1.0)
	base_r = R - depth
	# Sidewall from the outer bead up to the shoulder (the tread band is separate).
	if mud:
		side = [(rr - 0.005, hw * 0.8), (rr + 0.08 * h, hw * 0.93), (rr + 0.4 * h, hw), (rr + 0.78 * h, hw * 0.995),
			(base_r - 0.03, hw * 0.975), (base_r, tread_hw)]
	else:
		side = [(rr - 0.004, hw * 0.84), (rr + 0.12 * h, hw * 0.95), (rr + 0.42 * h, hw), (rr + 0.72 * h, hw * 0.985),
			(rr + 0.9 * h, hw * 0.94), (base_r - 0.008, hw * 0.87), (base_r, tread_hw)]
	segs = 42 if not mud else 56
	# Outer (+x) sidewall and inner (-x) sidewall.
	mb.add(core.lathe([(r, x) for r, x in side], segs, "Tyre", flip=True))
	mb.add(core.lathe([(r, -x) for r, x in side], segs, "Tyre"))
	# Raised lettering band hint: a thin ring on the outer sidewall.
	ring_r = rr + 0.55 * h
	mb.add(core.lathe([(ring_r - 0.012, hw + 0.0015), (ring_r + 0.012, hw + 0.0015)], segs, "Tyre", flip=True))
	# Inner barrel to close the tyre between the beads (hidden behind the rim).
	mb.add(core.lathe([(rr - 0.004, -hw * 0.84), (rr - 0.004, hw * 0.84)], segs, "Tyre", flip=True))
	tread_band(mb, R, base_r, tread_hw, tread)


def tread_band(mb, R, base_r, hw, kind):
	"""Blocks on top of the tread base: heightfield of cells with real walls."""
	if kind == "road":
		cols = [-1.0, -0.6, -0.48, 0.48, 0.6, 1.0]
		groove_cols = {1, 3}
		pitches = 21
		phases = [0.0, 0.18, 0.5, 0.6]

		def solid(ci, k):
			if ci in groove_cols:
				return False
			if ci in (0, 4):
				return k != 0
			return k != 2
	elif kind in ("allterrain", "gravel"):
		cols = [-1.0, -0.6, -0.52, -0.1, 0.1, 0.52, 0.6, 1.0]
		groove_cols = {1, 5}
		pitches = 20
		phases = [0.0, 0.25, 0.5, 0.75]

		def solid(ci, k):
			if ci in groove_cols:
				return False
			if ci in (0, 6):
				return k != 0
			if ci in (2, 4):
				return k != 2
			if ci == 3:
				return k not in (1, 3) if kind == "gravel" else k != 1
			return True
	else:  # mud: big staggered paddle lugs
		cols = [-1.0, -0.6, -0.12, 0.12, 0.6, 1.0]
		pitches = 16
		phases = [k / 6 for k in range(6)]

		def solid(ci, k):
			if ci == 0:
				return k in (0, 1)
			if ci == 1:
				return k in (1, 2)
			if ci == 2:
				return k in (1, 2, 4, 5)
			if ci == 3:
				return k in (4, 5)
			return k in (3, 4)

	angles = []
	for p in range(pitches):
		for ph in phases:
			angles.append((p + ph) / pitches * 2 * math.pi)
	angles.append(2 * math.pi)
	xs = [c * hw for c in cols]
	ncols = len(xs) - 1
	na = len(angles) - 1

	def height(ai, ci):
		if ai < 0 or ai >= na or ci < 0 or ci >= ncols:
			return None
		return R if solid(ci, ai % len(phases)) else base_r

	def pt(a, x, r):
		return Vector((x, r * math.cos(a), r * math.sin(a)))

	first = len(mb.faces)
	for ai in range(na):
		a0, a1 = angles[ai], angles[ai + 1]
		for ci in range(ncols):
			x0, x1 = xs[ci], xs[ci + 1]
			r = height(ai, ci)
			ids = [mb.v(pt(a0, x0, r)), mb.v(pt(a0, x1, r)), mb.v(pt(a1, x1, r)), mb.v(pt(a1, x0, r))]
			mb.f(ids, "Tyre", True)
			# Walls towards the next cell in angle and in x.
			rn = height((ai + 1) % na, ci)
			if rn is not None and abs(rn - r) > 1e-6:
				lo, hi = min(r, rn), max(r, rn)
				q = [mb.v(pt(a1, x0, lo)), mb.v(pt(a1, x1, lo)), mb.v(pt(a1, x1, hi)), mb.v(pt(a1, x0, hi))]
				mb.f(q if rn > r else q[::-1], "Tyre", False)
			rx = height(ai, ci + 1)
			if rx is not None and abs(rx - r) > 1e-6:
				lo, hi = min(r, rx), max(r, rx)
				q = [mb.v(pt(a0, x1, lo)), mb.v(pt(a1, x1, lo)), mb.v(pt(a1, x1, hi)), mb.v(pt(a0, x1, hi))]
				mb.f(q if rx < r else q[::-1], "Tyre", False)
			if ci == 0 and r > base_r + 1e-6:
				q = [mb.v(pt(a0, x0, base_r)), mb.v(pt(a0, x0, r)), mb.v(pt(a1, x0, r)), mb.v(pt(a1, x0, base_r))]
				mb.f(q, "Tyre", False)
			if ci == ncols - 1 and r > base_r + 1e-6:
				q = [mb.v(pt(a0, x1, base_r)), mb.v(pt(a1, x1, base_r)), mb.v(pt(a1, x1, r)), mb.v(pt(a0, x1, r))]
				mb.f(q, "Tyre", False)

	# The cells above were wound inwards; turn them all to face out.
	mb.faces[first:] = [tuple(reversed(f)) for f in mb.faces[first:]]

# ---------------------------------------------------------------------------


def rim(mb, R, W, rr, cfg):
	hw = W * 0.5
	lip_w = cfg.get("lip", 0.015)
	x_lip = hw * 0.86
	dish = cfg["dish"]
	x_face = x_lip - dish
	segs = 42
	# Outer lip and barrel (inside of the rim seen through the spokes).
	prof = [(rr - 0.006, x_lip - 0.02), (rr + 0.008, x_lip - 0.004), (rr + 0.01, x_lip + 0.004),
		(rr - 0.004, x_lip + 0.008), (rr - 0.014 - lip_w * 0.4, x_lip + 0.004)]
	mb.add(core.lathe(prof, segs, "Rim", flip=False))
	barrel = [(rr - 0.014 - lip_w * 0.4, x_lip + 0.004), (rr - 0.02, x_lip - 0.03), (rr - 0.025, -hw * 0.7), (rr - 0.01, -hw * 0.84)]
	mb.add(core.lathe(barrel, segs, "Rim", flip=False))
	rin = rr - 0.022
	hub_r = rr * 0.26
	design = cfg["design"]
	n = cfg["spokes"]
	# Hub disc and centre cap.
	hub = [(0.0, x_face + 0.03), (hub_r * 0.55, x_face + 0.028), (hub_r * 0.62, x_face + 0.02), (hub_r, x_face + 0.012), (hub_r * 1.05, x_face - 0.01)]
	mb.add(core.lathe(hub, 28, "Rim", flip=True))
	cap = [(0.0, x_face + 0.042), (hub_r * 0.4, x_face + 0.038), (hub_r * 0.5, x_face + 0.028)]
	mb.add(core.lathe(cap, 24, "Chrome", flip=True))
	# Lug nuts.
	pcd = hub_r * 0.78
	for k in range(cfg["nuts"]):
		a = 2 * math.pi * k / cfg["nuts"] + 0.3
		c = Vector((x_face + 0.03, pcd * math.cos(a), pcd * math.sin(a)))
		mb.add(core.cylinder(c - Vector((0.012, 0, 0)), c + Vector((0.008, 0, 0)), 0.011, 0.011, 6, "Chrome", smooth=False))
		mb.add(core.cylinder(c + Vector((0.008, 0, 0)), c + Vector((0.013, 0, 0)), 0.011, 0.006, 6, "Chrome", smooth=False))
	if design == "slot" or design == "beadlock":
		_dish_face(mb, rr, rin, hub_r, x_face, x_lip, n, design, cfg)
	else:
		_spokes(mb, rin, hub_r, x_face, x_lip, n, design)
	# Brake disc with a hat, visible through the spokes.
	disc_r = rr * cfg["disc"] - 0.01
	dx = x_face - 0.06
	disc = [(hub_r * 0.9, dx + 0.012), (disc_r, dx + 0.012), (disc_r, dx - 0.012), (hub_r * 0.9, dx - 0.012)]
	mb.add(core.lathe(disc, 36, "Brake", flip=True, close=True))
	mb.add(core.lathe([(hub_r * 0.9, dx + 0.012), (hub_r * 0.9, x_face - 0.012)], 24, "Brake", flip=True))
	# Ventilation slots on the disc face (dark lines).
	for k in range(8):
		a = 2 * math.pi * k / 8
		p0 = Vector((dx + 0.0125, (disc_r * 0.7) * math.cos(a), (disc_r * 0.7) * math.sin(a)))
		p1 = Vector((dx + 0.0125, (disc_r * 0.95) * math.cos(a + 0.15), (disc_r * 0.95) * math.sin(a + 0.15)))
		mb.add(core.cylinder(p0, p1, 0.003, 0.003, 4, "Gap", caps=False, smooth=False))


def _spokes(mb, rin, hub_r, x_face, x_lip, n, design):
	"""Spokes from the hub out to the lip, dished outwards."""
	def spoke(angle, width_hub, width_rim, thick, x_rim_off=0.0, curve=0.0):
		rows = []
		steps = 4
		for s in range(steps + 1):
			t = s / steps
			r = lerp(hub_r * 0.92, rin, t)
			x = lerp(x_face + 0.01, x_lip - 0.012 + x_rim_off, t ** 0.8) + math.sin(t * math.pi) * 0.006
			wdt = lerp(width_hub, width_rim, t)
			a = angle + curve * t * t
			d = Vector((0, math.cos(a), math.sin(a)))
			side = Vector((0, -math.sin(a), math.cos(a)))
			c = Vector((x, 0, 0)) + d * r
			prof = [(-wdt * 0.5, -thick), (-wdt * 0.5, 0.0), (-wdt * 0.38, thick * 0.35), (0.0, thick * 0.45),
				(wdt * 0.38, thick * 0.35), (wdt * 0.5, 0.0), (wdt * 0.5, -thick)]
			rows.append([c + side * pu + Vector((pv, 0, 0)) for pu, pv in prof])
		mb.grid(rows, "Rim", close_v=True, flip=False)

	if design == "twin":
		for k in range(n // 2):
			a = 2 * math.pi * k / (n // 2)
			spoke(a - 0.09, 0.03, 0.026, 0.022)
			spoke(a + 0.09, 0.03, 0.026, 0.022)
	elif design == "split":
		for k in range(n):
			a = 2 * math.pi * k / n
			spoke(a, 0.05, 0.022, 0.026, curve=-0.12)
			spoke(a + 0.16, 0.0, 0.022, 0.022, curve=0.1)
	elif design == "star":
		for k in range(n):
			a = 2 * math.pi * k / n
			spoke(a, 0.07, 0.04, 0.03, -0.01)
	elif design == "truck":
		for k in range(n):
			a = 2 * math.pi * k / n
			spoke(a, 0.06, 0.07, 0.03)
	elif design == "rally":
		for k in range(n):
			a = 2 * math.pi * k / n
			spoke(a, 0.055, 0.05, 0.02)
	else:
		for k in range(n):
			spoke(2 * math.pi * k / n, 0.04, 0.03, 0.024)


def _dish_face(mb, rr, rin, hub_r, x_face, x_lip, n, design, cfg):
	"""A solid dished face with slots / holes (classic mag or beadlock)."""
	segs = n * 6
	# Radii of the face rings; holes are made by leaving out quads.
	rings = [hub_r * 0.95, hub_r * 1.25, rin * 0.52, rin * 0.86, rin]
	xs = [x_face + 0.008, x_face + 0.012, x_face + 0.02, lerp(x_face, x_lip, 0.8), x_lip - 0.01]
	pts = []
	for r, x in zip(rings, xs):
		row = []
		for s in range(segs):
			a = 2 * math.pi * s / segs
			row.append(Vector((x, r * math.cos(a), r * math.sin(a))))
		pts.append(row)
	ids = [[mb.v(p) for p in row] for row in pts]
	for i in range(len(rings) - 1):
		for s in range(segs):
			hole = i in (1, 2) and (s % 6) in (2, 3, 4) if design == "slot" else i == 2 and (s % 6) in (2, 3)
			if hole:
				continue
			a, b = ids[i][s], ids[i + 1][s]
			c, d = ids[i + 1][(s + 1) % segs], ids[i][(s + 1) % segs]
			mb.f((a, d, c, b), "Rim", True)
	# Hole walls (so the slots have depth).
	for i in range(len(rings) - 1):
		for s in range(segs):
			hole = i in (1, 2) and (s % 6) in (2, 3, 4) if design == "slot" else i == 2 and (s % 6) in (2, 3)
			if not hole:
				continue
	if design == "beadlock":
		ring_x = x_lip + 0.004
		mb.add(core.lathe([(rr - 0.035, ring_x), (rr - 0.035, ring_x + 0.018), (rr + 0.012, ring_x + 0.018), (rr + 0.012, ring_x)], 64, "Rim", flip=True))
		for k in range(24):
			a = 2 * math.pi * k / 24
			c = Vector((ring_x + 0.018, (rr - 0.012) * math.cos(a), (rr - 0.012) * math.sin(a)))
			mb.add(core.cylinder(c, c + Vector((0.012, 0, 0)), 0.009, 0.009, 6, "Chrome", smooth=False))


def caliper(R, W, rr, cfg):
	hw = W * 0.5
	x_face = hw * 0.86 - cfg["dish"]
	dx = x_face - 0.06
	disc_r = rr * cfg["disc"] - 0.01
	mb = MeshBuilder()
	# A curved block straddling the disc edge at the top.
	rows = []
	for k in range(9):
		a = math.radians(lerp(60.0, 120.0, k / 8))
		row = []
		for (rad, x) in [(disc_r - 0.045, dx - 0.03), (disc_r + 0.012, dx - 0.03), (disc_r + 0.018, dx), (disc_r + 0.012, dx + 0.032),
				(disc_r - 0.045, dx + 0.032), (disc_r - 0.05, dx)]:
			row.append(Vector((x, rad * math.sin(a), rad * math.cos(a))))
		rows.append(row)
	mb.grid(rows, "Caliper", close_v=True, flip=True)
	mb.fan(rows[0], sum(rows[0], Vector()) / 6, "Caliper", flip=False)
	mb.fan(rows[-1], sum(rows[-1], Vector()) / 6, "Caliper", flip=True)
	return mb
