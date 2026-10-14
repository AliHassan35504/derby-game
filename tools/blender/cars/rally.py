"""Kestrel Rally: a hot hatchback in gravel rally trim: roof scoop, spot
lights, wide arches, mud flaps, rear wing and door numbers."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (1.8, 1.45, 4.0)
WHEEL = dict(r=0.34, w=0.26, x=0.809, y=-0.739, z=1.28)

BODY = dict(
	z=(-2.0, 2.0),
	yt=[(-2.0, 0.02), (-1.97, 0.2), (-1.9, 0.4), (-1.8, 0.5), (-1.62, 0.56), (-1.2, 0.61), (-0.5, 0.64),
		(0.15, 0.64), (0.3, 0.61), (0.92, 0.19), (0.98, 0.165), (1.15, 0.15), (1.6, 0.1), (1.86, 0.04), (2.0, -0.06)],
	yb=[(-2.0, -0.46), (-1.9, -0.63), (-1.6, -0.72), (-1.1, -0.79), (1.1, -0.79), (1.6, -0.72), (1.9, -0.63), (2.0, -0.46)],
	ym=[(-2.0, -0.24), (0.0, -0.27), (2.0, -0.26)],
	ys=[(-2.0, -0.04), (-1.92, 0.2), (-1.5, 0.25), (0.0, 0.22), (0.9, 0.16), (1.5, 0.08), (1.88, 0.01), (2.0, -0.08)],
	w=[(-2.0, 0.86), (-1.3, 0.9), (0.0, 0.88), (1.3, 0.9), (2.0, 0.86)],
	wsh=[(-2.0, 0.84), (-1.3, 0.875), (0.0, 0.86), (1.3, 0.875), (2.0, 0.84)],
	wg=[(-2.0, 0.83), (-1.85, 0.8), (-1.5, 0.79), (0.9, 0.79), (1.05, 0.86), (2.0, 0.83)],
	wr=[(-2.0, 0.72), (-1.85, 0.68), (-1.5, 0.66), (0.25, 0.66), (0.95, 0.78), (1.2, 0.78), (2.0, 0.74)],
	nb=3.4,
	nu=3.0,
	cr=0.12,
	bulge=0.02,
	ledge_h=0.022,
	front=dict(R=0.3, k=2.6, rake=-0.16, yref=-0.46),
	rear=dict(R=0.22, k=3.0, rake=-0.06, yref=-0.46),
	stations=104,
	extra_z=[-0.62, -0.78],
)


def build():
	cb = CarBuilder("rally", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.04, wr + 0.06, flare=dict(width=0.075, height=0.035, mat="Paint", angles=(-10.0, 190.0)))

	# --- glass
	ws = cb.top_window(0.33, 0.92, "Front", side_gap=0.05)
	cb.top_window(-1.93, -1.66, "Rear", side_gap=0.07, radius=0.04)
	cb.side_window(-0.62, 0.9, "F", top_gap=0.05)
	cb.side_window(-1.6, -0.78, "C", top_gap=0.06, top_fn=lambda z, info, st: st - lerp(0.0, 0.24, max(0.0, min(1.0, (-1.28 - z) / 0.32))))
	cb.blackout(-0.78, -0.62, top_gap=0.05, belt_gap=0.02)

	# --- front: headlights, grille, spot light bar, skid plate
	hit, nrm = b.front_point(0.55, 0.0)
	n = (nrm + Vector((0, 0, 0.6))).normalized()
	cb.lamp([(-0.17, -0.055), (0.15, -0.065), (0.2, -0.01), (0.18, 0.055), (-0.17, 0.055)], hit, n, "Glass",
		[("disc", (0.05, 0.0), 0.04, "Headlight"), ("bar", (-0.08, 0.0), (0.06, 0.07), "Headlight"), ("bar", (0.15, -0.02), (0.025, 0.04), "Indicator")],
		depth=0.07, housing="Chrome", back_mat="Trim", round_r=0.025)
	hit, nrm = b.front_point(0.0, -0.06)
	cb.grille(parts.rect(0.6, 0.12), hit, Vector((0, 0.2, 1)), "mesh", "Trim", 4, 0.05, round_r=0.03)
	hit, nrm = b.front_point(0.0, -0.36)
	cb.grille(parts.rect(0.9, 0.13), hit, Vector((0, -0.05, 1)), "mesh", "Trim", 4, 0.05, round_r=0.04)
	cb.bumper(True, -0.48, -0.17, 0.045, "Paint", theta=74.0, back=0.7)
	bar_z = b.front_point(0.0, -0.02)[0].z + 0.11
	cb.add(core.cylinder((-0.62, -0.13, bar_z - 0.04), (0.62, -0.13, bar_z - 0.04), 0.018, 0.018, 8, "Trim"))
	for x in (-0.48, -0.17, 0.17, 0.48):
		cb.spotlamp((x, -0.07, bar_z + 0.04), (0, 0, 1), 0.085, 0.08)
		cb.add(core.cylinder((x, -0.13, bar_z - 0.04), (x, -0.1, bar_z - 0.02), 0.012, 0.012, 6, "Trim"))
	cb.add(core.superquadric((0.0, -0.74, 1.6), (0.55, 0.025, 0.45), 0.3, 0.3, 12, 4, "Brake"))
	cb.plate(b.front_point(0.0, -0.23)[0] + Vector((0, 0, 0.02)), (0, 0, 1), "KST 27", size=(0.46, 0.1))

	# --- rear: tail lights, wing, exhaust, flaps
	hit, nrm = b.front_point(0.6, 0.2, front=False)
	n = (nrm + Vector((0, 0, -0.7))).normalized()
	cb.lamp([(-0.12, -0.12), (0.1, -0.12), (0.13, 0.0), (0.1, 0.12), (-0.12, 0.12)], hit, n, "Taillight",
		[("bar", (0.0, 0.03), (0.16, 0.12), "Taillight"), ("bar", (0.0, -0.08), (0.16, 0.04), "Chrome")],
		depth=0.05, housing="Chrome", back_mat="Taillight", round_r=0.03)
	cb.bumper(False, -0.47, -0.13, 0.05, "Paint", theta=72.0, back=0.6)
	cb.bumper(False, -0.53, -0.46, 0.035, "Trim", theta=60.0, back=0.6)
	cb.plate(b.front_point(0.0, -0.02, front=False)[0] + Vector((0, 0, -0.012)), (0, 0, -1), "KST 27", size=(0.46, 0.1))
	cb.exhaust(-0.5, -0.6, -2.02, 0.055, 0.3)
	wing_y = 0.585
	cb.add(core.superquadric((0.0, wing_y, -1.72), (0.72, 0.016, 0.12), 0.25, 0.25, 16, 6, "Paint",
		deform=lambda p: Vector((p.x, p.y + 0.6 * max(0.0, -p.z) * 0.6, p.z))))
	for x in (0.66, -0.66):
		cb.add(core.superquadric((x, wing_y - 0.025, -1.71), (0.012, 0.045, 0.11), 0.3, 0.3, 6, 6, "Trim"))
	cb.flaps((wz - wr - 0.08, -wz - wr - 0.12), 0.79, -0.72, -0.97, 0.3, "Trim")

	# --- roof scoop, gaps, livery, bolt-ons
	top, _ = b.top_point(0.0, 0.0)
	cb.add(core.superquadric(top + Vector((0, 0.015, 0.0)), (0.17, 0.06, 0.24), 0.25, 0.4, 14, 8, "Paint",
		deform=lambda p: Vector((p.x, p.y * (0.4 + 0.6 * max(0.0, p.z)) if p.y > 0 else p.y, p.z))))
	cb.add(core.prism(core.round_polygon(parts.rect(0.22, 0.05), 0.02, 2), top + Vector((0, 0.05, 0.235)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0.2, 1)), 0.0, 0.005, "Gap"))
	door_bot = -0.62
	cb.gap_side([(0.93, 0.12), (0.93, door_bot), (-0.7, door_bot), (-0.71, 0.22)], n=90)
	cb.gap_top([(-0.72, 1.0), (-0.74, 1.6), (-0.6, 1.9), (0.6, 1.9), (0.74, 1.6), (0.72, 1.0), (-0.72, 1.0)], n=90)
	cb.gap_dir([(-0.66, 0.0, -2.1), (0.66, 0.0, -2.1)], (0, 0, 1))
	cb.stripe_side(([(-1.95, 0.02), (1.95, -0.12)], [(-1.95, -0.1), (1.95, -0.24)]), "Livery")
	cb.stripe_side(([(-1.95, -0.12), (1.95, -0.26)], [(-1.95, -0.16), (1.95, -0.3)]), "Decal")
	cb.roundel(0.15, -0.17, 0.15, "27")
	cb.mirror(0.84, 0.19, out=0.03, rise=0.06, size=(0.085, 0.055, 0.05))
	cb.handle(-0.5, 0.15, 0.12)
	cb.wipers(ws, [0.28, -0.25], 0.5, 8.0)
	cb.stripe_side(([(-0.9, -0.63), (0.88, -0.63)], [(-0.9, -0.73), (0.88, -0.73)]), "Trim")
	cb.add(core.cylinder((-0.3, 0.64, -1.0), (-0.3, 0.98, -1.1), 0.004, 0.003, 5, "Trim"))

	# --- inside and underneath
	cb.interior(0.6, 0.04, 0.72, 0.12, -0.33, 0.36, rear_z=-0.68, rear_w=1.3, floor_y=-0.72, wheel_x=0.36)
	# Roll cage hoop behind the front seats.
	hoop = [Vector((0.62, -0.7, -0.35)), Vector((0.6, 0.45, -0.38)), Vector((0.45, 0.56, -0.38)), Vector((-0.45, 0.56, -0.38)), Vector((-0.6, 0.45, -0.38)), Vector((-0.62, -0.7, -0.35))]
	for p0, p1 in zip(hoop[:-1], hoop[1:]):
		cb.add(core.cylinder(p0, p1, 0.022, 0.022, 8, "Brake"))
	cb.underbody(-0.72, -1.7, 1.7, 0.45, -0.4, -1.95, tank_z=-1.0, axle_y=wy, axle_z=(wz, -wz), axle_x=0.66, diff_z=None, muffler_z=-1.6)
	return cb
