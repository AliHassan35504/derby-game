"""Bulldog Muscle: a 70s style American muscle coupe with a long bonnet,
hood scoop, quad headlights, chrome bumpers, coke-bottle hips and a
pillarless hardtop."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (2.0, 1.25, 4.9)
WHEEL = dict(r=0.38, w=0.34, x=0.881, y=-0.589, z=1.568)

BODY = dict(
	z=(-2.45, 2.45),
	yt=[(-2.45, -0.24), (-2.42, -0.12), (-2.35, -0.07), (-1.75, -0.06), (-1.55, -0.03), (-1.42, 0.03), (-1.15, 0.3),
		(-0.85, 0.46), (-0.5, 0.5), (-0.15, 0.495), (-0.05, 0.47), (0.5, 0.06), (0.58, 0.0), (0.75, -0.012),
		(1.6, -0.03), (2.3, -0.05), (2.41, -0.08), (2.45, -0.14)],
	dip=[(0.6, 0.0), (0.9, 0.012), (2.2, 0.012), (2.45, 0.0)],
	yb=[(-2.45, -0.6), (-2.38, -0.7), (-2.0, -0.76), (-1.6, -0.79), (-1.0, -0.8), (1.0, -0.8), (1.7, -0.78), (2.3, -0.72), (2.45, -0.62)],
	ysl=[(-2.45, -0.55), (-2.0, -0.66), (-1.0, -0.69), (1.0, -0.69), (2.0, -0.66), (2.45, -0.56)],
	ym=[(-2.45, -0.38), (0.0, -0.4), (2.45, -0.4)],
	ys=[(-2.45, -0.25), (-2.38, -0.1), (-1.7, -0.075), (-1.2, -0.085), (0.0, -0.11), (0.6, -0.12), (1.6, -0.1),
		(2.36, -0.1), (2.45, -0.18)],
	w=[(-2.45, 0.955), (-1.75, 0.98), (-1.4, 0.975), (-0.6, 0.965), (1.0, 0.965), (1.6, 0.97), (2.45, 0.96)],
	wsh=[(-2.45, 0.94), (-1.7, 0.962), (-0.6, 0.945), (1.6, 0.95), (2.45, 0.945)],
	wg=[(-2.45, 0.935), (-1.78, 0.95), (-1.52, 0.84), (0.45, 0.83), (0.62, 0.94), (2.45, 0.94)],
	wr=[(-2.45, 0.86), (-1.72, 0.88), (-1.3, 0.72), (-0.85, 0.65), (-0.1, 0.65), (0.5, 0.84), (0.7, 0.87), (2.45, 0.87)],
	tuck=0.03,
	rb=0.04,
	nu=[(-1.6, 3.6), (-1.4, 3.0), (0.5, 3.0), (0.65, 3.6)],
	cr=0.1,
	bulge=0.02,
	ledge_h=0.02,
	front=dict(R=0.22, k=3.4, rake=0.08, yref=-0.5),
	rear=dict(R=0.22, k=3.2, rake=-0.04, yref=-0.5),
	fenders=[dict(z=1.568, y=-0.57, r0=0.47, r1=0.78, amount=0.06, top=-0.16, top_w=0.2, kz=0.8),
		dict(z=-1.568, y=-0.57, r0=0.5, r1=1.15, amount=0.07, top=-0.09, top_w=0.2, kz=0.6)],
	stations=100,
	nc=20,
)


def build():
	cb = CarBuilder("muscle", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.02, wr + 0.045, flare=dict(width=0.02, height=0.007, mat="Chrome", angles=(-4.0, 184.0)))

	# --- glass: pillarless hardtop
	ws = cb.top_window(-0.04, 0.5, "Front", side_gap=0.045, reveal="Chrome")
	cb.top_window(-1.42, -0.88, "Rear", side_gap=0.09, reveal="Chrome")

	def quarter(z, info, st):
		return st - lerp(0.0, 0.3, max(0.0, min(1.0, (-0.62 - z) / 0.36)))
	cb.side_window(-1.0, 0.46, "S", top_gap=0.045, belt_gap=0.02, top_fn=quarter, reveal="Chrome")

	# --- front: full-width grille with quad round headlights, chrome blade bumper
	hit, nrm = b.front_point(0.0, -0.28)
	cb.grille(parts.rect(0.66, 0.18), hit, Vector((0, 0, 1)), "bars", "Chrome", 4, 0.08, 0.008, vertical=5, reveal="Chrome", round_r=0.03)
	for x in (0.47, 0.71):
		hit, nrm = b.front_point(x, -0.28)
		cb.lamp(parts.ellipse(0.082, 0.082, 24), hit + Vector((0, 0, 0.03)), Vector((0, 0, 1)), "HeadLens",
			[("bulb", (0.0, 0.0), 0.035, "Headlight"), ("outline", (0.0, 1.0), (0.008, 0.012), "Chrome")], depth=0.05, reveal="Chrome", housing="Chrome",
			marker="Headlight" if x > 0.6 else None)
	cb.bumper(True, -0.5, -0.4, kind="blade", mat="Chrome", theta=70.0, back=0.75, gap=0.02, thick=0.06)
	for side in (1.0, -1.0):
		hit, nrm = b.front_point(side * 0.55, -0.57)
		cb.add(core.prism(core.round_polygon(parts.rect(0.16, 0.05), 0.012, 2), hit, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 0.0, 0.01, "Indicator"))
	cb.plate(b.front_point(0.0, -0.45)[0] + Vector((0, 0, 0.09)), (0, 0, 1), "BLD 455", size=(0.5, 0.12))

	# --- rear: wide tail lights in a chrome-trimmed panel, chrome bumper
	hit, nrm = b.front_point(0.52, -0.22, front=False)
	cb.lamp(parts.rect(0.66, 0.11), hit, Vector((0, 0, -1)), "TailLens",
		[("bar", (0.0, 0.0), (0.6, 0.08), "Taillight"), ("bar", (-0.22, 0.0), (0.1, 0.06), "Chrome")], depth=0.04,
		reveal="Chrome", housing="Chrome", back_mat="Taillight", round_r=0.015, marker="Taillight")
	hit, nrm = b.front_point(0.0, -0.22, front=False)
	cb.lamp(parts.rect(0.24, 0.07), hit, Vector((0, 0, -1)), "HeadLens", [("bar", (0.0, 0.0), (0.18, 0.04), "Chrome")], depth=0.03,
		reveal="Chrome", housing="Chrome", mirror=False, round_r=0.01)
	cb.bumper(False, -0.52, -0.41, kind="blade", mat="Chrome", theta=68.0, back=0.75, gap=0.02, thick=0.06)
	cb.plate(b.front_point(0.0, -0.34, front=False)[0] + Vector((0, 0, -0.008)), (0, 0, -1), "BLD 455", size=(0.5, 0.12))
	for x in (0.6, -0.6):
		cb.exhaust(x, -0.72, -2.47, 0.045, 0.3)

	# --- bonnet scoop and stripes
	top, _ = b.top_point(0.0, 1.3)
	prof = [(-0.66, -0.04), (0.44, -0.04), (0.44, 0.12), (0.37, 0.135), (-0.2, 0.075), (-0.66, 0.0)]
	cb.add(core.prism(core.round_polygon(prof, 0.025, 3), top, Vector((0, 0, 1)), Vector((0, 1, 0)), Vector((1, 0, 0)), -0.26, 0.26, "Trim"))
	mouth_c = top + Vector((0, 0.045, 0.44))
	cb.add(core.prism(core.round_polygon(parts.rect(0.46, 0.13), 0.03, 2), mouth_c, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), -0.004, 0.003, "Chrome"))
	cb.add(core.prism(core.round_polygon(parts.rect(0.4, 0.085), 0.02, 2), mouth_c, Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), 0.0, 0.006, "Gap"))
	for z0, z1 in ((0.6, 2.4), (-0.86, -0.08), (-2.38, -1.56)):
		for xs in ((0.3, 0.42), (-0.42, -0.3)):
			cb.stripe_top(xs, z0, z1, "Decal", n=max(8, int((z1 - z0) * 24)))

	# --- gaps and detachable panels
	door_bot = -0.68
	cb.gap_side([(0.5, -0.1), (0.52, door_bot), (-0.75, door_bot), (-0.76, -0.07)], n=80)
	cb.gap_top([(-0.84, 2.36), (-0.84, 0.64), (0.84, 0.64), (0.84, 2.36), (-0.84, 2.36)], n=100)
	cb.gap_top([(-0.82, -1.62), (-0.84, -2.36), (0.84, -2.36), (0.82, -1.62), (-0.82, -1.62)], n=80)
	cb.panel_box("Part_Hood", -0.84, 0.84, -0.13, 1.0, 0.64, 2.36)
	cb.panel_box("Part_BumperFront", -1.2, 1.2, -1.0, -0.37, 2.2, 2.9)
	cb.panel_box("Part_BumperRear", -1.2, 1.2, -1.0, -0.37, -2.9, -2.2)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.72, 1.3) if sx > 0 else (-1.3, -0.72)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.75, 0.51, extra=[((0, -0.09, 0.0), (0, -1, 0.0))])
	cb.mirror(0.4, -0.08, out=0.02, rise=0.04, size=(0.07, 0.045, 0.06), mat="Chrome", arm_mat="Chrome")
	cb.handle(-0.45, -0.15, 0.13, "Chrome")
	cb.wipers(ws, [0.32, -0.26], 0.5, 6.0)
	belt = []
	for i in range(31):
		z = lerp(-1.02, 0.48, i / 30)
		info = b.section_info(z)
		belt.append((z, b.at_s(info, b.belt_s(info) + 0.01)[1]))
	cb.strip_side(belt, 0.012, 0.004, "Chrome")
	cb.strip_side([(-2.3, -0.66), (2.3, -0.66)], 0.012, 0.004, "Chrome")

	# --- inside and underneath
	cb.engine_bay(0.8, 2.2, -0.66, -0.16, 0.66)
	cb.interior(0.36, -0.06, 0.8, -0.15, -0.46, 0.4, rear_z=-0.62, rear_w=1.45, floor_y=-0.72, wheel_x=0.4)
	cb.underbody(-0.72, -2.0, 2.0, 0.5, 0.0, -2.2, tank_z=-1.95, axle_y=wy, axle_z=(wz, -wz), axle_x=0.72, diff_z=-wz, muffler_z=-1.3)
	return cb
