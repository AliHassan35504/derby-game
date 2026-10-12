"""Cruiser Sedan: a full-size four-door saloon."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (1.9, 1.45, 4.8)
WHEEL = dict(r=0.36, w=0.28, x=0.852, y=-0.692, z=1.488)

BODY = dict(
	z=(-2.40, 2.40),
	yt=[(-2.40, 0.12), (-2.36, 0.22), (-2.25, 0.265), (-1.75, 0.285), (-1.56, 0.30), (-1.46, 0.34), (-1.15, 0.545),
		(-0.90, 0.655), (-0.50, 0.70), (0.05, 0.71), (0.28, 0.695), (0.38, 0.66), (1.00, 0.22), (1.06, 0.19),
		(1.15, 0.178), (1.70, 0.142), (2.15, 0.105), (2.32, 0.062), (2.40, 0.0)],
	yb=[(-2.40, -0.50), (-2.30, -0.62), (-2.0, -0.68), (-1.6, -0.75), (-1.0, -0.79), (1.0, -0.79), (1.7, -0.73), (2.2, -0.68), (2.40, -0.52)],
	ym=[(-2.4, -0.2), (0.0, -0.24), (2.4, -0.22)],
	ys=[(-2.4, 0.10), (-2.25, 0.215), (-1.6, 0.238), (-1.0, 0.228), (0.0, 0.192), (1.0, 0.155), (1.7, 0.112), (2.3, 0.035), (2.4, 0.0)],
	w=[(-2.4, 0.93), (-1.5, 0.95), (0, 0.95), (1.5, 0.948), (2.4, 0.928)],
	wsh=[(-2.4, 0.922), (0.0, 0.925), (2.4, 0.92)],
	wg=[(-2.4, 0.915), (-1.62, 0.912), (-1.46, 0.862), (1.0, 0.858), (1.12, 0.915), (2.4, 0.912)],
	wr=[(-2.4, 0.80), (-1.6, 0.845), (-1.35, 0.765), (-0.9, 0.672), (0.3, 0.682), (1.0, 0.85), (1.2, 0.845), (2.4, 0.80)],
	nb=3.4,
	nu=3.0,
	cr=0.12,
	bulge=0.025,
	ledge_h=0.022,
	front=dict(R=0.27, k=2.8, rake=-0.16, yref=-0.5),
	rear=dict(R=0.25, k=2.8, rake=-0.08, yref=-0.5),
	stations=96,
	nc=18,
	extra_z=[0.02, -0.2],
)


def build():
	cb = CarBuilder("sedan", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.02, wr + 0.055, flare=dict(width=0.05, height=0.012, mat="Paint", angles=(-8.0, 188.0)))

	# --- glass
	ws = cb.top_window(0.40, 1.00, "Front", side_gap=0.05)
	cb.top_window(-1.44, -0.90, "Rear", side_gap=0.095)

	def c_pillar(z, info, st):
		# Slant the back edge of the rear door glass along the C-pillar.
		return st - lerp(0.0, 0.42, max(0.0, min(1.0, (-0.66 - z) / 0.4)))
	cb.side_window(0.02, 0.98, "F", top_gap=0.05)
	cb.side_window(-1.10, -0.20, "B", top_gap=0.05, top_fn=c_pillar)
	cb.blackout(-0.2, 0.02, top_gap=0.05, belt_gap=0.02)
	# Chrome belt moulding under the side glass.
	belt = []
	for i in range(31):
		z = lerp(-1.12, 0.98, i / 30)
		info = b.section_info(z)
		belt.append((z, b.at_s(info, b.belt_s(info) + 0.012)[1]))
	cb.strip_side(belt, 0.014, 0.004, "Chrome")

	# --- front: headlights, grille, bumper intake, fog lamps
	hit, nrm = b.front_point(0.6, -0.01)
	n = (nrm + Vector((0, 0.0, 0.5))).normalized()
	poly = [(-0.21, -0.06), (0.17, -0.07), (0.23, -0.02), (0.21, 0.06), (-0.2, 0.06)]
	cb.lamp(poly, hit, n, "Glass",
		[("disc", (0.09, 0.0), 0.04, "Headlight"), ("disc", (-0.02, 0.0), 0.034, "Headlight"),
			("bar", (-0.03, -0.045), (0.3, 0.01), "Headlight"), ("bar", (0.17, 0.0), (0.03, 0.06), "Indicator")],
		depth=0.08, housing="Chrome", back_mat="Trim", round_r=0.03)
	hit, nrm = b.front_point(0.0, -0.075)
	cb.grille(parts.rect(0.66, 0.14), hit, Vector((0, 0.1, 1)), "bars", "Chrome", 4, 0.06, 0.008, vertical=0, round_r=0.035, reveal="Chrome")
	hit, nrm = b.front_point(0.0, -0.38)
	cb.grille(parts.rect(0.86, 0.11), hit, Vector((0, -0.1, 1)), "mesh", "Trim", 4, 0.05, round_r=0.04)
	hit, nrm = b.front_point(0.66, -0.37)
	cb.lamp(parts.ellipse(0.045, 0.035, 16), hit, (nrm + Vector((0, 0, 0.8))).normalized(), "Glass",
		[("disc", (0.0, 0.0), 0.03, "Headlight")], depth=0.05, housing="Chrome", back_mat="Trim")
	cb.plate(b.front_point(0.0, -0.245)[0] + Vector((0, 0, 0.006)), (0, 0, 1), "CRZ 482")

	# --- rear: tail light clusters, plate, exhaust
	hit, nrm = b.front_point(0.62, 0.155, front=False)
	n = (nrm + Vector((0, 0, -0.6))).normalized()
	cb.lamp([(-0.2, -0.065), (0.19, -0.065), (0.23, 0.0), (0.2, 0.065), (-0.2, 0.065)], hit, n, "Taillight",
		[("bar", (0.0, 0.0), (0.3, 0.08), "Taillight")], depth=0.05, housing="Chrome", back_mat="Taillight", round_r=0.025)
	hit, nrm = b.front_point(0.34, 0.155, front=False)
	cb.lamp(parts.rect(0.1, 0.11), hit, (nrm + Vector((0, 0, -0.6))).normalized(), "Glass",
		[("bar", (0.0, 0.0), (0.06, 0.07), "Chrome")], depth=0.04, housing="Chrome", round_r=0.02)
	cb.plate(b.front_point(0.0, 0.03, front=False)[0] + Vector((0, 0, -0.006)), (0, 0, -1), "CRZ 482")
	cb.exhaust(-0.55, -0.62, -2.36, 0.038, 0.3, dual=True, spacing=0.1)

	# --- bumpers and side mouldings
	cb.bumper(True, -0.49, -0.17, 0.05, "Paint", theta=76.0, back=0.75)
	cb.bumper(True, -0.535, -0.47, 0.035, "Trim", theta=66.0, back=0.75)
	cb.bumper(False, -0.47, -0.09, 0.05, "Paint", theta=74.0, back=0.7)
	cb.bumper(False, -0.53, -0.45, 0.035, "Trim", theta=62.0, back=0.7)
	cb.strip_side([(-1.0, -0.2), (0.98, -0.2)], 0.035, 0.008, "Trim")
	cb.strip_side([(-1.0, -0.2), (0.98, -0.2)], 0.008, 0.0095, "Chrome")

	# --- panel gaps
	door_bot = -0.62
	cb.gap_side([(0.99, 0.15), (0.99, door_bot)])
	cb.gap_side([(0.99, door_bot), (-1.0, door_bot)])
	cb.gap_side([(-0.09, 0.2), (-0.09, door_bot)])
	cb.gap_side([(-1.0, 0.225), (-1.0, door_bot)])
	cb.gap_side([(1.97, 0.05), (1.99, -0.45)])
	cb.gap_side([(-1.98, 0.17), (-2.0, -0.42)])
	cb.gap_top([(-0.79, 1.08), (-0.80, 2.0), (-0.70, 2.3), (0.70, 2.3), (0.80, 2.0), (0.79, 1.08), (-0.79, 1.08)], n=90)
	cb.gap_top([(-0.76, -1.6), (-0.78, -2.25), (-0.6, -2.36), (0.6, -2.36), (0.78, -2.25), (0.76, -1.6), (-0.76, -1.6)], n=90)
	cb.gap_dir([(-0.62, -0.02, -2.4), (0.62, -0.02, -2.4)], (0, 0, 1))
	cb.gap_dir([(-0.75, -0.13, 2.4), (0.75, -0.13, 2.4)], (0, 0, -1))
	# Fuel filler door on the right rear wing.
	for side in (-1.0,):
		s = parts.project_side(b, parts.superellipse(0.075, 0.065, 4.0, 24, -1.78, 0.03), side)
		cb.add(parts.ribbon(s, 0.005, "Gap", closed=True))

	# --- bolt-ons
	cb.mirror(0.86, 0.19, out=0.04, rise=0.06)
	cb.handle(0.3, 0.07, 0.14)
	cb.handle(-0.66, 0.09, 0.14)
	cb.wipers(ws, [0.32, -0.28], 0.55, 8.0)
	# Rocker panel trim and a roof aerial.
	cb.stripe_side(([(-1.05, -0.63), (1.04, -0.63)], [(-1.05, -0.72), (1.04, -0.72)]), "Trim")
	cb.add(core.superquadric((0.0, 0.715, -0.75), (0.035, 0.03, 0.09), 0.5, 0.5, 10, 6, "Trim",
		deform=lambda p: Vector((p.x * (1.0 - 0.5 * max(p.z, 0)), p.y * (1.0 - 0.6 * max(p.z, 0)), p.z))))

	# --- inside and underneath
	cb.interior(0.66, 0.06, 0.78, 0.16, -0.30, 0.38, rear_z=-0.62, rear_w=1.45, floor_y=-0.72, wheel_x=0.38)
	cb.underbody(-0.70, -1.9, 1.9, 0.5, -0.4, -2.2, tank_z=-0.95, axle_y=wy, axle_z=(wz, -wz), axle_x=0.72, diff_z=-wz, muffler_z=-1.9)
	return cb
