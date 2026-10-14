"""Cruiser Sedan: a full-size four-door saloon."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (1.9, 1.45, 4.8)
WHEEL = dict(r=0.36, w=0.28, x=0.852, y=-0.692, z=1.488)

BODY = dict(
	z=(-2.40, 2.40),
	yt=[(-2.40, -0.12), (-2.36, 0.02), (-2.28, 0.085), (-2.10, 0.11), (-1.75, 0.122), (-1.55, 0.135), (-1.42, 0.17),
		(-1.15, 0.36), (-0.85, 0.5), (-0.55, 0.548), (-0.1, 0.562), (0.2, 0.55), (0.32, 0.525), (0.95, 0.075),
		(1.02, 0.052), (1.2, 0.038), (1.8, -0.005), (2.12, -0.05), (2.3, -0.12), (2.40, -0.24)],
	yb=[(-2.40, -0.56), (-2.3, -0.70), (-2.0, -0.78), (-1.6, -0.82), (-1.0, -0.84), (1.0, -0.84), (1.75, -0.8), (2.2, -0.74), (2.40, -0.6)],
	ysl=[(-2.4, -0.5), (-2.0, -0.66), (-1.0, -0.72), (1.0, -0.72), (2.0, -0.66), (2.4, -0.52)],
	ym=[(-2.4, -0.4), (0.0, -0.44), (2.4, -0.44)],
	ys=[(-2.40, -0.17), (-2.3, 0.0), (-2.0, 0.02), (-1.0, 0.0), (0.0, -0.03), (1.0, -0.055), (1.8, -0.09), (2.3, -0.16), (2.40, -0.26)],
	w=[(-2.4, 0.92), (-1.6, 0.935), (0, 0.935), (1.6, 0.935), (2.4, 0.915)],
	wsh=[(-2.4, 0.895), (0.0, 0.9), (2.4, 0.89)],
	wg=[(-2.4, 0.885), (-1.62, 0.885), (-1.45, 0.83), (0.95, 0.83), (1.1, 0.885), (2.4, 0.88)],
	wr=[(-2.4, 0.78), (-1.6, 0.82), (-1.35, 0.72), (-0.9, 0.64), (0.25, 0.645), (0.95, 0.81), (1.2, 0.82), (2.4, 0.78)],
	tuck=0.04,
	rb=0.05,
	nu=3.0,
	cr=0.11,
	bulge=0.02,
	ledge_h=0.025,
	front=dict(R=0.5, k=2.2, rake=-0.35, yref=-0.6),
	rear=dict(R=0.36, k=2.4, rake=-0.16, yref=-0.6),
	fenders=[dict(z=1.488, y=-0.67, r0=0.46, r1=0.8, amount=0.045, top=-0.12, top_w=0.25, kz=0.85),
		dict(z=-1.488, y=-0.67, r0=0.46, r1=0.85, amount=0.05, top=-0.06, top_w=0.25, kz=0.8)],
	stations=100,
	nc=20,
	extra_z=[0.02, -0.2],
)


def build():
	cb = CarBuilder("sedan", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.015, wr + 0.045)

	# --- glass
	ws = cb.top_window(0.36, 0.93, "Front", side_gap=0.05)
	cb.top_window(-1.40, -0.86, "Rear", side_gap=0.09)

	def c_pillar(z, info, st):
		# Slant the back edge of the rear door glass along the C-pillar.
		return st - lerp(0.0, 0.42, max(0.0, min(1.0, (-0.66 - z) / 0.4)))
	cb.side_window(0.02, 0.9, "F", top_gap=0.05)
	cb.side_window(-1.10, -0.20, "B", top_gap=0.05, top_fn=c_pillar)
	cb.blackout(-0.2, 0.02, top_gap=0.05, belt_gap=0.02)
	belt = []
	for i in range(31):
		z = lerp(-1.12, 0.92, i / 30)
		info = b.section_info(z)
		belt.append((z, b.at_s(info, b.belt_s(info) + 0.014)[1]))
	cb.strip_side(belt, 0.012, 0.004, "Chrome")

	# --- front: swept headlights with LED light guides, grille, intakes
	hit, nrm = b.front_point(0.6, -0.17)
	n = (nrm + Vector((0, 0.35, 0.3))).normalized()
	poly = [(-0.24, -0.05), (0.16, -0.07), (0.3, -0.01), (0.27, 0.06), (-0.22, 0.06)]
	cb.lamp(poly, hit, n, "HeadLens",
		[("disc", (0.07, -0.005), 0.038, "Headlight"), ("disc", (-0.04, -0.005), 0.034, "Headlight"),
			("outline", (0.42, 0.98), (0.012, 0.012), "Headlight"), ("bar", (0.2, 0.0), (0.035, 0.05), "Indicator")],
		depth=0.08, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.03, marker="Headlight")
	hit, nrm = b.front_point(0.0, -0.35)
	cb.grille([(-0.3, -0.07), (0.3, -0.07), (0.36, 0.06), (-0.36, 0.06)], hit, Vector((0, 0.3, 1)), "bars", "Chrome", 5, 0.06, 0.008,
		round_r=0.03, reveal="Chrome")
	hit, nrm = b.front_point(0.0, -0.585)
	cb.grille(parts.rect(0.7, 0.08), hit, Vector((0, -0.1, 1)), "mesh", "Trim", 4, 0.05, round_r=0.03)
	for x in (0.66,):
		hit, nrm = b.front_point(x, -0.55)
		cb.grille(core.round_polygon(parts.rect(0.2, 0.12), 0.03, 2), hit, (nrm + Vector((0, 0, 1.2))).normalized(), "bars", "Trim", 3, 0.05, 0.008)
	for side in (1.0, -1.0):
		hit, nrm = b.front_point(side * 0.66, -0.55)
		cb.spotlamp(hit + Vector((side * 0.02, 0.0, -0.035)), (side * 0.3, 0.0, 1.0), 0.032, 0.03, housing="Trim", lens="Headlight", bezel="Chrome", guard=False)
	cb.bumper(True, -0.66, -0.63, 0.035, "Trim", theta=70.0, back=0.75, p=2.0)
	cb.plate(b.front_point(0.0, -0.48)[0] + Vector((0, 0, 0.004)), (0, 0, 1), "CRZ 482", size=(0.48, 0.11))

	# --- rear: wrap-round tail lights, plate, diffuser, exhausts
	hit, nrm = b.front_point(0.6, -0.02, front=False)
	n = (nrm + Vector((0, 0.0, -0.5))).normalized()
	cb.lamp([(-0.25, -0.045), (0.2, -0.06), (0.27, 0.0), (0.22, 0.06), (-0.25, 0.05)], hit, n, "TailLens",
		[("outline", (0.0, 1.0), (0.014, 0.016), "Taillight"), ("bar", (0.02, 0.0), (0.26, 0.035), "Taillight"),
			("bar", (-0.17, 0.0), (0.06, 0.04), "Chrome")],
		depth=0.06, housing="Trim", back_mat="Trim", round_r=0.025, marker="Taillight")
	cb.plate(b.front_point(0.0, -0.17, front=False)[0] + Vector((0, 0, -0.006)), (0, 0, -1), "CRZ 482", size=(0.48, 0.11))
	cb.bumper(False, -0.62, -0.5, 0.03, "Trim", theta=60.0, back=0.7, p=3.0)
	for x in (0.52, -0.52):
		cb.exhaust(x, -0.6, -2.37, 0.04, 0.3, shape="oval")

	# --- panel gaps (the doors, bonnet and bumpers are detachable panels)
	door_bot = -0.68
	cb.gap_side([(0.99, 0.0), (0.99, door_bot)])
	cb.gap_side([(0.99, door_bot), (-1.0, door_bot)])
	cb.gap_side([(-0.09, 0.03), (-0.09, door_bot)])
	cb.gap_side([(-1.0, 0.05), (-1.0, door_bot)])
	cb.gap_side([(1.95, -0.26), (1.95, -0.62)])
	cb.gap_side([(-1.95, -0.26), (-1.95, -0.6)])
	cb.gap_top([(-0.78, 2.16), (-0.78, 1.0), (0.78, 1.0), (0.78, 2.16)], n=90)
	cb.gap_dir([(-0.78, -0.1, 2.8), (0.78, -0.1, 2.8)], (0, 0, -1))
	cb.gap_top([(-0.62, -2.22), (-0.74, -2.12), (-0.76, -1.55), (0.76, -1.55), (0.74, -2.12), (0.62, -2.22), (-0.62, -2.22)], n=90)
	cb.gap_dir([(-0.9, -0.26, 2.6), (0.9, -0.26, 2.6)], (0, 0, -1))
	cb.gap_dir([(-0.9, -0.26, -2.6), (0.9, -0.26, -2.6)], (0, 0, 1))
	for side in (-1.0,):
		s = parts.project_side(b, parts.superellipse(0.075, 0.065, 4.0, 24, -1.78, -0.08), side)
		cb.add(parts.ribbon(s, 0.005, "Gap", closed=True))
	cb.panel_box("Part_Hood", -0.78, 0.78, -0.1, 1.0, 1.0, 2.8)
	cb.panel_box("Part_BumperFront", -1.2, 1.2, -1.0, -0.26, 1.95, 2.8)
	cb.panel_box("Part_BumperRear", -1.2, 1.2, -1.0, -0.26, -2.8, -1.95)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.72, 1.3) if sx > 0 else (-1.3, -0.72)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.09, 0.99, extra=[((0, -0.045, 0.0), (0, -1, 0.03))])

	# --- bolt-ons
	cb.mirror(0.86, 0.0, out=0.04, rise=0.06)
	cb.handle(0.3, -0.11, 0.14)
	cb.handle(-0.66, -0.08, 0.14)
	cb.wipers(ws, [0.32, -0.28], 0.55, 8.0)
	cb.stripe_side(([(-1.05, -0.69), (1.04, -0.69)], [(-1.05, -0.78), (1.04, -0.78)]), "Trim")
	cb.add(core.superquadric((0.0, 0.565, -0.75), (0.035, 0.03, 0.09), 0.5, 0.5, 10, 6, "Trim",
		deform=lambda p: Vector((p.x * (1.0 - 0.5 * max(p.z, 0)), p.y * (1.0 - 0.6 * max(p.z, 0)), p.z))))

	# --- inside and underneath
	cb.engine_bay(1.15, 2.05, -0.62, -0.18, 0.62)
	cb.interior(0.66, -0.12, 0.78, 0.16, -0.42, 0.38, rear_z=-0.62, rear_w=1.45, floor_y=-0.74, wheel_x=0.38)
	cb.underbody(-0.74, -1.9, 1.9, 0.5, -0.4, -2.2, tank_z=-0.95, axle_y=wy, axle_z=(wz, -wz), axle_x=0.72, diff_z=-wz, muffler_z=-1.9)
	return cb
