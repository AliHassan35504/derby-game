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
	yt=[(-2.0, -0.2), (-1.97, 0.0), (-1.92, 0.25), (-1.82, 0.42), (-1.65, 0.5), (-1.2, 0.555), (-0.5, 0.57),
		(0.15, 0.565), (0.3, 0.54), (0.9, 0.06), (0.98, 0.035), (1.15, 0.02), (1.6, -0.03), (1.86, -0.1), (2.0, -0.22)],
	yb=[(-2.0, -0.56), (-1.9, -0.7), (-1.6, -0.78), (-1.1, -0.83), (1.1, -0.83), (1.6, -0.78), (1.9, -0.7), (2.0, -0.56)],
	ysl=[(-2.0, -0.5), (-1.6, -0.68), (-1.0, -0.72), (1.0, -0.72), (1.6, -0.68), (2.0, -0.5)],
	ym=[(-2.0, -0.4), (0.0, -0.42), (2.0, -0.42)],
	ys=[(-2.0, -0.2), (-1.92, -0.06), (-1.5, -0.04), (0.0, -0.07), (0.9, -0.1), (1.5, -0.13), (1.88, -0.17), (2.0, -0.24)],
	w=[(-2.0, 0.85), (-1.3, 0.875), (0.0, 0.865), (1.3, 0.875), (2.0, 0.85)],
	wsh=[(-2.0, 0.83), (-1.3, 0.855), (0.0, 0.845), (1.3, 0.855), (2.0, 0.83)],
	wg=[(-2.0, 0.82), (-1.85, 0.79), (-1.5, 0.78), (0.9, 0.78), (1.05, 0.845), (2.0, 0.82)],
	wr=[(-2.0, 0.7), (-1.85, 0.67), (-1.5, 0.65), (0.25, 0.65), (0.95, 0.77), (1.2, 0.77), (2.0, 0.73)],
	tuck=0.035,
	rb=0.05,
	nu=3.0,
	cr=0.11,
	bulge=0.02,
	ledge_h=0.022,
	front=dict(R=0.3, k=2.5, rake=-0.22, yref=-0.6),
	rear=dict(R=0.22, k=3.0, rake=-0.06, yref=-0.6),
	fenders=[dict(z=1.28, y=-0.72, r0=0.42, r1=0.7, amount=0.05, top=-0.16, top_w=0.2, kz=0.85),
		dict(z=-1.28, y=-0.72, r0=0.42, r1=0.72, amount=0.055, top=-0.12, top_w=0.2, kz=0.85)],
	stations=100,
	nc=20,
	extra_z=[-0.62, -0.78],
)


def build():
	cb = CarBuilder("rally", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.03, wr + 0.05, flare=dict(width=0.075, height=0.03, mat="Paint", angles=(-10.0, 190.0)))

	# --- glass
	ws = cb.top_window(0.33, 0.9, "Front", side_gap=0.05)
	cb.top_window(-1.93, -1.66, "Rear", side_gap=0.07, radius=0.04)
	cb.side_window(-0.62, 0.88, "F", top_gap=0.05)
	cb.side_window(-1.6, -0.78, "C", top_gap=0.06, top_fn=lambda z, info, st: st - lerp(0.0, 0.24, max(0.0, min(1.0, (-1.28 - z) / 0.32))))
	cb.blackout(-0.78, -0.62, top_gap=0.05, belt_gap=0.02)

	# --- front: headlights, grille, spot light bar, skid plate
	hit, nrm = b.front_point(0.55, -0.16)
	n = (nrm + Vector((0, 0.1, 0.6))).normalized()
	cb.lamp([(-0.17, -0.055), (0.15, -0.065), (0.2, -0.01), (0.18, 0.055), (-0.17, 0.055)], hit, n, "HeadLens",
		[("disc", (0.05, 0.0), 0.04, "Headlight"), ("disc", (-0.07, 0.0), 0.034, "Headlight"), ("outline", (0.5, 0.95), (0.01, 0.01), "Headlight"),
			("bar", (0.15, -0.02), (0.025, 0.04), "Indicator")],
		depth=0.07, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.025, marker="Headlight")
	hit, nrm = b.front_point(0.0, -0.22)
	cb.grille(parts.rect(0.56, 0.1), hit, Vector((0, 0.2, 1)), "mesh", "Trim", 4, 0.05, round_r=0.03)
	hit, nrm = b.front_point(0.0, -0.53)
	cb.grille(parts.rect(0.9, 0.12), hit, Vector((0, -0.05, 1)), "mesh", "Trim", 4, 0.05, round_r=0.04)
	cb.bumper(True, -0.66, -0.62, 0.03, "Trim", theta=70.0, back=0.7, p=2.0)
	bar_z = b.front_point(0.0, -0.4)[0].z + 0.1
	cb.add(core.cylinder((-0.62, -0.42, bar_z - 0.04), (0.62, -0.42, bar_z - 0.04), 0.018, 0.018, 8, "Trim"))
	for x in (-0.48, -0.17, 0.17, 0.48):
		cb.spotlamp((x, -0.36, bar_z + 0.04), (0, 0, 1), 0.08, 0.08)
		cb.add(core.cylinder((x, -0.42, bar_z - 0.04), (x, -0.39, bar_z - 0.02), 0.012, 0.012, 6, "Trim"))
	cb.add(core.superquadric((0.0, -0.8, 1.6), (0.55, 0.025, 0.42), 0.3, 0.3, 12, 4, "Brake"))

	# --- rear: tail lights, wing, exhaust, flaps
	hit, nrm = b.front_point(0.6, 0.02, front=False)
	n = (nrm + Vector((0, 0, -0.7))).normalized()
	cb.lamp([(-0.12, -0.12), (0.1, -0.12), (0.13, 0.0), (0.1, 0.12), (-0.12, 0.12)], hit, n, "TailLens",
		[("outline", (0.0, 1.0), (0.012, 0.014), "Taillight"), ("bar", (0.0, 0.03), (0.14, 0.1), "Taillight"), ("bar", (0.0, -0.08), (0.14, 0.04), "Chrome")],
		depth=0.05, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.03, marker="Taillight")
	cb.bumper(False, -0.66, -0.58, 0.035, "Trim", theta=62.0, back=0.6, p=3.0)
	cb.plate(b.front_point(0.0, -0.22, front=False)[0] + Vector((0, 0, -0.012)), (0, 0, -1), "KST 27", size=(0.46, 0.1))
	cb.exhaust(-0.5, -0.68, -2.02, 0.055, 0.3)
	wing_y = 0.52
	cb.add(core.superquadric((0.0, wing_y, -1.72), (0.72, 0.016, 0.12), 0.25, 0.25, 16, 6, "Paint",
		deform=lambda p: Vector((p.x, p.y + 0.6 * max(0.0, -p.z) * 0.6, p.z))))
	for x in (0.66, -0.66):
		cb.add(core.superquadric((x, wing_y - 0.025, -1.71), (0.012, 0.045, 0.11), 0.3, 0.3, 6, 6, "Trim"))
	cb.flaps((wz - wr - 0.08, -wz - wr - 0.12), 0.79, -0.76, -1.0, 0.3, "Trim")

	# --- roof scoop, gaps, livery, bolt-ons
	top, _ = b.top_point(0.0, 0.0)
	cb.add(core.superquadric(top + Vector((0, 0.015, 0.0)), (0.17, 0.06, 0.24), 0.25, 0.4, 14, 8, "Paint",
		deform=lambda p: Vector((p.x, p.y * (0.4 + 0.6 * max(0.0, p.z)) if p.y > 0 else p.y, p.z))))
	cb.add(core.prism(core.round_polygon(parts.rect(0.22, 0.05), 0.02, 2), top + Vector((0, 0.05, 0.235)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0.2, 1)), 0.0, 0.005, "Gap"))
	door_bot = -0.7
	cb.gap_side([(0.93, -0.1), (0.93, door_bot), (-0.7, door_bot), (-0.71, -0.06)], n=80)
	cb.gap_top([(-0.72, 1.84), (-0.72, 1.0), (0.72, 1.0), (0.72, 1.84)], n=80)
	cb.gap_dir([(-0.72, -0.13, 2.4), (0.72, -0.13, 2.4)], (0, 0, -1))
	cb.gap_dir([(-0.9, -0.34, 2.4), (0.9, -0.34, 2.4)], (0, 0, -1))
	cb.gap_side([(1.7, -0.34), (1.7, -0.72)])
	cb.gap_dir([(-0.9, -0.36, -2.4), (0.9, -0.36, -2.4)], (0, 0, 1))
	cb.gap_dir([(-0.66, -0.12, -2.1), (0.66, -0.12, -2.1)], (0, 0, 1))
	cb.panel_box("Part_Hood", -0.72, 0.72, -0.13, 1.0, 1.0, 2.6)
	cb.panel_box("Part_BumperFront", -1.2, 1.2, -1.0, -0.34, 1.7, 2.8)
	cb.panel_box("Part_BumperRear", -1.2, 1.2, -1.0, -0.36, -2.8, -1.7)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.64, 1.3) if sx > 0 else (-1.3, -0.64)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.7, 0.93, extra=[((0, -0.075, 0.0), (0, -1, 0.02))])
	cb.stripe_side(([(-1.95, -0.1), (1.6, -0.227)], [(-1.95, -0.22), (1.6, -0.347)]), "Livery")
	cb.stripe_side(([(-1.95, -0.24), (1.6, -0.367)], [(-1.95, -0.28), (1.6, -0.407)]), "Decal")
	cb.roundel(0.15, -0.36, 0.14, "27")
	cb.mirror(0.84, -0.04, out=0.03, rise=0.06, size=(0.085, 0.055, 0.05))
	cb.handle(-0.5, -0.15, 0.12)
	cb.wipers(ws, [0.28, -0.25], 0.5, 8.0)
	cb.stripe_side(([(-0.9, -0.71), (0.88, -0.71)], [(-0.9, -0.8), (0.88, -0.8)]), "Trim")
	cb.add(core.cylinder((-0.3, 0.57, -1.0), (-0.3, 0.9, -1.1), 0.004, 0.003, 5, "Trim"))

	# --- inside and underneath
	cb.engine_bay(1.05, 1.8, -0.7, -0.16, 0.56)
	cb.interior(0.6, -0.1, 0.72, 0.12, -0.45, 0.36, rear_z=-0.68, rear_w=1.3, floor_y=-0.76, wheel_x=0.36)
	# Roll cage hoop behind the front seats.
	hoop = [Vector((0.62, -0.74, -0.35)), Vector((0.6, 0.38, -0.38)), Vector((0.45, 0.5, -0.38)), Vector((-0.45, 0.5, -0.38)), Vector((-0.6, 0.38, -0.38)), Vector((-0.62, -0.74, -0.35))]
	for p0, p1 in zip(hoop[:-1], hoop[1:]):
		cb.add(core.cylinder(p0, p1, 0.022, 0.022, 8, "Brake"))
	cb.underbody(-0.76, -1.7, 1.7, 0.45, -0.4, -1.95, tank_z=-1.0, axle_y=wy, axle_z=(wz, -wz), axle_x=0.66, diff_z=None, muffler_z=-1.6)
	return cb
