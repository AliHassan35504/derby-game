"""Stinger GT: a low two-door sports coupe with a fastback and ducktail."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (2.0, 0.85, 4.5)
WHEEL = dict(r=0.38, w=0.34, x=0.881, y=-0.455, z=1.53)

BODY = dict(
	z=(-2.25, 2.25),
	yt=[(-2.25, -0.04), (-2.21, 0.12), (-2.14, 0.165), (-2.0, 0.165), (-1.75, 0.2), (-1.3, 0.27), (-0.85, 0.36),
		(-0.5, 0.405), (-0.2, 0.415), (0.0, 0.405), (0.1, 0.38), (0.58, 0.06), (0.66, 0.035), (0.8, 0.03),
		(1.3, 0.03), (1.6, 0.015), (1.9, -0.05), (2.1, -0.15), (2.25, -0.29)],
	dip=[(-2.25, 0.0), (-2.0, 0.025), (-1.75, 0.02), (-1.5, 0.0), (0.62, 0.0), (0.8, 0.03), (1.4, 0.05), (1.9, 0.045), (2.25, 0.0)],
	yb=[(-2.25, -0.47), (-2.15, -0.56), (-1.85, -0.6), (-1.1, -0.62), (1.1, -0.62), (1.85, -0.6), (2.15, -0.57), (2.25, -0.47)],
	ym=[(-2.25, -0.25), (0.0, -0.27), (2.25, -0.3)],
	ys=[(-2.25, -0.07), (-2.15, 0.12), (-1.9, 0.135), (-1.6, 0.14), (-0.8, 0.11), (0.0, 0.07), (0.6, 0.02), (1.0, 0.0),
		(1.6, -0.015), (1.9, -0.08), (2.1, -0.18), (2.25, -0.32)],
	w=[(-2.25, 0.93), (-1.6, 1.0), (-1.2, 0.99), (-0.4, 0.955), (0.4, 0.955), (1.2, 0.985), (1.6, 0.99), (2.25, 0.93)],
	wsh=[(-2.25, 0.9), (-1.6, 0.975), (-0.4, 0.93), (0.4, 0.93), (1.5, 0.965), (2.25, 0.9)],
	wg=[(-2.25, 0.9), (-1.95, 0.93), (-1.45, 0.82), (0.5, 0.79), (0.72, 0.95), (2.25, 0.9)],
	wr=[(-2.25, 0.72), (-1.9, 0.78), (-1.3, 0.64), (-0.6, 0.6), (0.0, 0.6), (0.6, 0.76), (0.9, 0.74), (2.25, 0.7)],
	nb=3.0,
	nu=3.0,
	cr=0.1,
	bulge=0.03,
	ledge_h=0.03,
	front=dict(R=0.42, k=2.3, rake=-0.3, yref=-0.47),
	rear=dict(R=0.3, k=3.0, rake=0.12, yref=-0.47),
	stations=112,
)


def build():
	cb = CarBuilder("sports", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.02, wr + 0.045, flare=dict(width=0.045, height=0.01, mat="Paint", angles=(-5.0, 185.0)))

	# --- glass
	ws = cb.top_window(0.1, 0.6, "Front", side_gap=0.045)
	cb.top_window(-1.78, -0.78, "Rear", side_gap=0.075)

	def quarter(z, info, st):
		# Sweep the back of the side glass down to the belt (fastback quarter).
		return st - lerp(0.0, 0.3, max(0.0, min(1.0, (-0.55 - z) / 0.5)))
	cb.side_window(-1.12, 0.58, "S", top_gap=0.04, belt_gap=0.02, top_fn=quarter)

	# --- front: slim headlights up on the wings, big lower intake, splitter
	hit, nrm = b.front_point(0.66, -0.2)
	n = (nrm + Vector((0.0, 0.2, 0.4))).normalized()
	poly = [(-0.2, -0.03), (0.12, -0.05), (0.2, 0.0), (0.18, 0.035), (-0.16, 0.035)]
	cb.lamp(poly, hit, n, "Glass",
		[("disc", (0.08, -0.004), 0.03, "Headlight"), ("disc", (0.0, -0.004), 0.028, "Headlight"),
			("bar", (-0.05, -0.022), (0.24, 0.008), "Headlight"), ("bar", (0.15, 0.0), (0.02, 0.03), "Indicator")],
		depth=0.06, housing="Trim", back_mat="Trim", round_r=0.02)
	hit, nrm = b.front_point(0.0, -0.4)
	cb.grille([(-0.55, -0.07), (0.55, -0.07), (0.62, 0.05), (-0.62, 0.05)], hit, Vector((0, 0.05, 1)), "mesh", "Trim", 5, 0.06, round_r=0.04)
	hit, nrm = b.front_point(0.0, -0.28)
	cb.grille(parts.rect(0.42, 0.05), hit, Vector((0, 0.4, 1)), "bars", "Trim", 2, 0.04, 0.008, round_r=0.02)
	cb.bumper(True, -0.535, -0.49, 0.06, "Trim", theta=62.0, back=0.9, p=2.0)
	cb.plate(b.front_point(0.0, -0.395)[0] + Vector((0, 0, 0.02)), (0, 0.05, 1), "STG 911", size=(0.46, 0.1))

	# --- rear: slim tail lights, diffuser, quad exhausts
	hit, nrm = b.front_point(0.6, 0.06, front=False)
	n = (nrm + Vector((0, 0, -0.6))).normalized()
	cb.lamp([(-0.22, -0.03), (0.16, -0.035), (0.24, 0.0), (0.2, 0.03), (-0.22, 0.03)], hit, n, "Taillight",
		[("bar", (0.0, 0.0), (0.34, 0.03), "Taillight")], depth=0.04, housing="Trim", back_mat="Taillight", round_r=0.012)
	hit, nrm = b.front_point(0.0, 0.065, front=False)
	cb.lamp(parts.rect(0.7, 0.018), hit, (0, 0, -1), "Taillight", [], depth=0.02, housing="Trim", mirror=False, round_r=0.008)
	cb.bumper(False, -0.56, -0.44, 0.03, "Trim", theta=60.0, back=0.8, p=3.0)
	cb.plate(b.front_point(0.0, -0.2, front=False)[0] + Vector((0, 0, -0.01)), (0, 0, -1), "STG 911", size=(0.46, 0.1))
	for x in (0.42, -0.42):
		cb.exhaust(x, -0.47, -2.24, 0.042, 0.25, dual=True, spacing=0.1)

	# --- gaps, vents, bolt-ons
	cb.gap_side([(0.6, 0.03), (0.62, -0.5), (-0.62, -0.52), (-0.66, 0.1)], n=90)
	cb.gap_top([(-0.62, 0.7), (-0.66, 1.6), (-0.5, 2.05), (0.5, 2.05), (0.66, 1.6), (0.62, 0.7), (-0.62, 0.7)], n=90)
	cb.gap_dir([(-0.55, -0.08, -2.3), (0.55, -0.08, -2.3)], (0, 0, 1))
	# Side intake ahead of the rear wheel.
	for side in (1.0, -1.0):
		s = parts.project_side(b, [(-0.75, -0.12), (-1.05, -0.08), (-1.05, -0.3), (-0.82, -0.3)], side)
		pts = [p for p, _ in s]
		if len(pts) == 4:
			mb = core.MeshBuilder()
			mb.f([mb.v(p + n * 0.001) for p, n in s][:: (1 if side < 0 else -1)], "Gap", False)
			cb.add(mb)
	cb.mirror(0.5, 0.08, out=0.03, rise=0.07, size=(0.09, 0.05, 0.06))
	cb.handle(-0.35, 0.02, 0.12, "Trim", recess=True)
	cb.wipers(ws, [0.3, -0.25], 0.5, 6.0)
	cb.stripe_side(([(-1.05, -0.5), (1.05, -0.5)], [(-1.05, -0.6), (1.05, -0.6)]), "Trim")
	for z0, z1 in ((0.68, 2.12), (-0.74, 0.06), (-2.16, -1.84)):
		for xs in ((-0.13, 0.13), (0.17, 0.25), (-0.25, -0.17)):
			cb.stripe_top(xs, z0, z1, "Decal", n=max(8, int((z1 - z0) * 30)))

	# --- inside and underneath
	cb.interior(0.42, -0.05, 0.75, -0.25, -0.42, 0.4, floor_y=-0.56, wheel_x=0.4)
	cb.underbody(-0.55, -1.8, 1.8, 0.45, 0.3, -2.1, axle_y=wy, axle_z=(wz, -wz), axle_x=0.72, diff_z=-wz, muffler_z=-1.75)
	return cb
