"""Stinger GT: a low two-door sports coupe with a long bonnet, a fastback,
muscular rear haunches and a ducktail."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (2.0, 0.85, 4.5)
WHEEL = dict(r=0.38, w=0.34, x=0.881, y=-0.455, z=1.53)

BODY = dict(
	z=(-2.25, 2.25),
	yt=[(-2.25, -0.16), (-2.21, -0.02), (-2.15, 0.035), (-2.0, 0.045), (-1.8, 0.065), (-1.4, 0.16), (-0.9, 0.3),
		(-0.5, 0.385), (-0.2, 0.41), (0.0, 0.405), (0.1, 0.385), (0.58, 0.06), (0.66, 0.04), (0.85, 0.035),
		(1.3, 0.035), (1.7, 0.0), (2.0, -0.1), (2.17, -0.2), (2.25, -0.3)],
	dip=[(-2.25, 0.0), (-2.0, 0.02), (-1.5, 0.0), (0.62, 0.0), (0.8, 0.035), (1.4, 0.06), (1.9, 0.05), (2.25, 0.0)],
	yb=[(-2.25, -0.5), (-2.15, -0.6), (-1.85, -0.66), (-1.1, -0.68), (1.1, -0.68), (1.85, -0.66), (2.15, -0.6), (2.25, -0.5)],
	ysl=[(-2.25, -0.45), (-1.9, -0.57), (-1.0, -0.58), (1.0, -0.58), (1.9, -0.57), (2.25, -0.45)],
	ym=[(-2.25, -0.34), (0.0, -0.36), (2.25, -0.38)],
	ys=[(-2.25, -0.2), (-2.15, -0.03), (-1.9, 0.0), (-1.5, 0.01), (-0.8, -0.02), (0.0, -0.05), (0.6, -0.05),
		(1.0, -0.03), (1.5, 0.0), (1.85, -0.05), (2.1, -0.17), (2.25, -0.32)],
	w=[(-2.25, 0.92), (-1.5, 0.945), (0.0, 0.945), (1.5, 0.945), (2.25, 0.915)],
	wsh=[(-2.25, 0.89), (-1.5, 0.92), (0.0, 0.915), (1.5, 0.915), (2.25, 0.885)],
	wg=[(-2.25, 0.89), (-1.95, 0.9), (-1.6, 0.8), (0.5, 0.78), (0.72, 0.9), (2.25, 0.88)],
	wr=[(-2.25, 0.72), (-1.9, 0.78), (-1.3, 0.62), (-0.6, 0.57), (0.0, 0.57), (0.6, 0.76), (0.9, 0.76), (2.25, 0.7)],
	tuck=0.035,
	rb=0.045,
	nu=3.0,
	cr=0.1,
	bulge=0.03,
	ledge_h=0.03,
	front=dict(R=0.34, k=2.3, rake=-0.38, yref=-0.62),
	rear=dict(R=0.34, k=2.6, rake=0.08, yref=-0.62),
	fenders=[dict(z=1.53, y=-0.44, r0=0.47, r1=0.85, amount=0.095, top=-0.06, top_w=0.2, kz=0.85),
		dict(z=-1.53, y=-0.42, r0=0.48, r1=1.05, amount=0.11, top=0.0, top_w=0.22, kz=0.75)],
	stations=100,
	nc=20,
)


def build():
	cb = CarBuilder("sports", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.015, wr + 0.04)

	# --- glass
	ws = cb.top_window(0.08, 0.6, "Front", side_gap=0.045)
	cb.top_window(-1.75, -0.76, "Rear", side_gap=0.075)

	def quarter(z, info, st):
		# Sweep the back of the side glass down to the belt (fastback quarter).
		return st - lerp(0.0, 0.3, max(0.0, min(1.0, (-0.55 - z) / 0.5)))
	cb.side_window(-1.12, 0.58, "S", top_gap=0.04, belt_gap=0.02, top_fn=quarter)

	# --- front: slim headlights on the wings, big lower intake, splitter
	hit, nrm = b.front_point(0.64, -0.2)
	n = (nrm + Vector((0.0, 0.45, 0.3))).normalized()
	poly = [(-0.22, -0.03), (0.12, -0.045), (0.25, 0.0), (0.22, 0.035), (-0.18, 0.035)]
	cb.lamp(poly, hit, n, "HeadLens",
		[("disc", (0.07, -0.004), 0.028, "Headlight"), ("disc", (-0.01, -0.004), 0.026, "Headlight"),
			("outline", (0.45, 0.98), (0.01, 0.01), "Headlight"), ("bar", (0.19, 0.0), (0.03, 0.03), "Indicator")],
		depth=0.06, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.02, marker="Headlight")
	hit, nrm = b.front_point(0.0, -0.47)
	cb.grille([(-0.52, -0.08), (0.52, -0.08), (0.6, 0.06), (-0.6, 0.06)], hit, Vector((0, 0.05, 1)), "mesh", "Trim", 6, 0.06, round_r=0.04)
	hit, nrm = b.front_point(0.0, -0.31)
	cb.grille(parts.rect(0.42, 0.05), hit, Vector((0, 0.4, 1)), "bars", "Trim", 2, 0.04, 0.008, round_r=0.02)
	for side in (1.0, -1.0):
		hit, nrm = b.front_point(side * 0.72, -0.5)
		cb.add(core.prism(core.round_polygon(parts.rect(0.1, 0.012), 0.005, 1), hit + Vector((0, 0, -0.004)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 0.0, 0.006, "Headlight"))
	cb.bumper(True, -0.6, -0.56, 0.05, "Trim", theta=66.0, back=0.9, p=2.0)
	cb.plate(b.front_point(0.0, -0.39)[0] + Vector((0, 0, 0.012)), (0, 0.15, 1), "STG 911", size=(0.46, 0.1))

	# --- rear: slim tail lights joined by a light bar, diffuser, quad exhausts
	hit, nrm = b.front_point(0.62, -0.07, front=False)
	n = (nrm + Vector((0, 0.1, -0.6))).normalized()
	cb.lamp([(-0.22, -0.03), (0.16, -0.04), (0.25, 0.0), (0.2, 0.035), (-0.22, 0.03)], hit, n, "TailLens",
		[("outline", (0.0, 1.0), (0.012, 0.012), "Taillight"), ("bar", (0.0, 0.0), (0.3, 0.02), "Taillight")],
		depth=0.045, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.012, marker="Taillight")
	hit, nrm = b.front_point(0.0, -0.065, front=False)
	cb.lamp(parts.rect(0.66, 0.016), hit, (0, 0, -1), "TailLens", [("bar", (0.0, 0.0), (0.62, 0.008), "Taillight")], depth=0.02,
		housing="Trim", reveal="Trim", mirror=False, round_r=0.006)
	cb.bumper(False, -0.6, -0.46, 0.035, "Trim", theta=60.0, back=0.8, p=3.0)
	cb.plate(b.front_point(0.0, -0.21, front=False)[0] + Vector((0, 0, -0.01)), (0, 0, -1), "STG 911", size=(0.46, 0.1))
	for x in (0.42, -0.42):
		cb.exhaust(x, -0.49, -2.25, 0.04, 0.25, dual=True, spacing=0.1)

	# --- panel gaps; bonnet, bumpers and doors are detachable panels
	door_bot = -0.55
	cb.gap_side([(0.6, -0.06), (0.62, door_bot), (-0.62, door_bot), (-0.64, -0.01)], n=70)
	cb.gap_top([(-0.64, 1.98), (-0.64, 0.7), (0.64, 0.7), (0.64, 1.98), (-0.64, 1.98)], n=90)
	cb.gap_dir([(-0.9, -0.29, 2.8), (0.9, -0.29, 2.8)], (0, 0, -1))
	cb.gap_side([(1.96, -0.29), (1.96, -0.6)])
	cb.gap_dir([(-0.9, -0.25, -2.8), (0.9, -0.25, -2.8)], (0, 0, 1))
	cb.gap_side([(-1.98, -0.25), (-1.98, -0.6)])
	cb.gap_top([(-0.6, -2.12), (-0.66, -1.85), (0.66, -1.85), (0.6, -2.12), (-0.6, -2.12)], n=60)
	cb.panel_box("Part_Hood", -0.64, 0.64, -0.25, 1.0, 0.7, 1.98)
	cb.panel_box("Part_BumperFront", -1.2, 1.2, -1.0, -0.29, 1.96, 2.8)
	cb.panel_box("Part_BumperRear", -1.2, 1.2, -1.0, -0.25, -2.8, -1.98)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.7, 1.3) if sx > 0 else (-1.3, -0.7)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.63, 0.61, extra=[((0, -0.04, 0.0), (0, -1, -0.03))])
	# Side intake ahead of the rear wheel.
	for side in (1.0, -1.0):
		s = parts.project_side(b, [(-0.75, -0.16), (-1.02, -0.1), (-1.02, -0.32), (-0.82, -0.32)], side, 0.002)
		if len(s) == 4:
			mb = core.MeshBuilder()
			mb.f([mb.v(p) for p, _n in s][:: (1 if side < 0 else -1)], "Gap", False)
			cb.add(mb)
	cb.mirror(0.5, -0.03, out=0.03, rise=0.07, size=(0.09, 0.05, 0.06))
	cb.handle(-0.35, -0.12, 0.12, "Trim", recess=True)
	cb.wipers(ws, [0.3, -0.25], 0.5, 6.0)
	cb.stripe_side(([(-1.08, -0.56), (1.08, -0.56)], [(-1.08, -0.65), (1.08, -0.65)]), "Trim")
	for z0, z1 in ((0.68, 2.12), (-0.74, 0.06), (-2.16, -1.84)):
		for xs in ((-0.13, 0.13), (0.17, 0.25), (-0.25, -0.17)):
			cb.stripe_top(xs, z0, z1, "Decal", n=max(8, int((z1 - z0) * 24)))

	# --- inside and underneath
	cb.engine_bay(0.9, 1.9, -0.55, -0.22, 0.6)
	cb.interior(0.42, -0.2, 0.75, -0.25, -0.5, 0.4, floor_y=-0.62, wheel_x=0.4)
	cb.underbody(-0.6, -1.8, 1.8, 0.45, 0.3, -2.1, axle_y=wy, axle_z=(wz, -wz), axle_x=0.72, diff_z=-wz, muffler_z=-1.75)
	return cb
