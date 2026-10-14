"""Vortex: a mid-engine wedge supercar. Knife-edge nose with slit headlights,
a cab-forward glass canopy squeezed between huge rear haunches, side intakes
feeding the engine under a glass cover, a fixed wing and a big diffuser."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (2.05, 0.9, 4.6)
WHEEL = dict(r=0.37, w=0.36, x=0.899, y=-0.438, z=1.518)

BODY = dict(
	z=(-2.3, 2.3),
	yt=[(-2.3, -0.22), (-2.26, -0.04), (-2.18, 0.05), (-2.0, 0.07), (-1.6, 0.12), (-1.1, 0.21), (-0.6, 0.33),
		(-0.3, 0.36), (0.0, 0.345), (0.15, 0.31), (0.8, 0.04), (0.95, 0.05), (1.3, 0.07), (1.6, 0.06), (1.9, 0.0),
		(2.15, -0.18), (2.3, -0.38)],
	dip=[(0.75, 0.0), (0.95, 0.1), (1.3, 0.19), (1.7, 0.19), (2.0, 0.14), (2.2, 0.05), (2.3, 0.0)],
	yb=[(-2.3, -0.5), (-2.2, -0.6), (-1.9, -0.65), (-1.0, -0.66), (1.0, -0.66), (1.9, -0.65), (2.2, -0.6), (2.3, -0.52)],
	ysl=[(-2.3, -0.47), (-1.9, -0.57), (-1.0, -0.58), (1.0, -0.58), (1.9, -0.57), (2.3, -0.48)],
	ym=[(-2.3, -0.34), (0.0, -0.38), (2.3, -0.42)],
	ys=[(-2.3, -0.24), (-2.2, -0.04), (-1.8, 0.0), (-1.5, 0.04), (-1.0, 0.0), (-0.4, -0.06), (0.4, -0.08), (1.0, -0.02),
		(1.5, 0.03), (1.85, -0.04), (2.15, -0.2), (2.3, -0.4)],
	w=[(-2.3, 0.92), (-1.5, 0.95), (-0.8, 0.93), (0.0, 0.9), (1.0, 0.93), (1.5, 0.94), (2.3, 0.9)],
	wsh=[(-2.3, 0.89), (-1.5, 0.92), (-0.8, 0.9), (0.0, 0.87), (1.0, 0.9), (1.5, 0.91), (2.3, 0.87)],
	wg=[(-2.3, 0.88), (-1.9, 0.86), (-1.45, 0.68), (0.7, 0.68), (0.95, 0.86), (2.3, 0.86)],
	wr=[(-2.3, 0.76), (-1.6, 0.7), (-1.0, 0.54), (-0.5, 0.52), (0.2, 0.52), (0.85, 0.76), (2.3, 0.72)],
	tuck=0.04,
	rb=0.04,
	nu=2.8,
	cr=0.09,
	bulge=0.02,
	ledge_h=0.05,
	front=dict(R=0.42, k=2.2, rake=-0.3, yref=-0.56),
	rear=dict(R=0.3, k=2.6, rake=0.05, yref=-0.56),
	fenders=[dict(z=1.518, y=-0.42, r0=0.45, r1=0.8, amount=0.1, top=0.02, top_w=0.2, kz=0.9),
		dict(z=-1.518, y=-0.42, r0=0.47, r1=1.05, amount=0.13, top=0.05, top_w=0.22, kz=0.7)],
	stations=100,
	nc=20,
)


def build():
	cb = CarBuilder("super", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.012, wr + 0.035)

	# --- glass canopy
	ws = cb.top_window(0.12, 0.8, "Front", side_gap=0.04)
	cb.top_window(-1.42, -0.58, "Rear", side_gap=0.07, radius=0.05)

	def quarter(z, info, st):
		return st - lerp(0.0, 0.25, max(0.0, min(1.0, (-0.1 - z) / 0.4)))
	cb.side_window(-0.5, 0.74, "S", top_gap=0.035, belt_gap=0.02, top_fn=quarter)

	# --- front: slit headlights, three big intakes, splitter
	hit, nrm = b.front_point(0.62, -0.32)
	n = (nrm + Vector((0.0, 0.8, 0.25))).normalized()
	cb.lamp([(-0.24, -0.022), (0.16, -0.035), (0.27, 0.0), (0.2, 0.028), (-0.2, 0.028)], hit, n, "HeadLens",
		[("disc", (0.1, -0.004), 0.018, "Headlight"), ("disc", (0.04, -0.004), 0.018, "Headlight"), ("disc", (-0.02, -0.004), 0.018, "Headlight"),
			("outline", (0.4, 0.98), (0.009, 0.008), "Headlight"), ("bar", (0.22, 0.0), (0.03, 0.02), "Indicator")],
		depth=0.05, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.015, marker="Headlight")
	hit, nrm = b.front_point(0.0, -0.49)
	cb.grille([(-0.3, -0.05), (0.3, -0.05), (0.36, 0.04), (-0.36, 0.04)], hit, Vector((0, -0.1, 1)), "mesh", "Trim", 4, 0.06, round_r=0.02)
	for side in (1.0, -1.0):
		hit, nrm = b.front_point(side * 0.66, -0.49)
		cb.grille([(-0.17, -0.05), (0.15, -0.06), (0.2, 0.06), (-0.17, 0.04)] if side > 0 else [(-0.15, -0.06), (0.17, -0.05), (0.17, 0.04), (-0.2, 0.06)],
			hit, (nrm + Vector((0, 0, 1.0))).normalized(), "bars", "Trim", 3, 0.06, 0.008, round_r=0.02)
	cb.bumper(True, -0.6, -0.57, 0.06, "Trim", theta=68.0, back=0.9, p=2.0)
	# Bonnet vents between the wings.
	for side in (1.0, -1.0):
		top, _ = b.top_point(side * 0.28, 1.75)
		pts = parts.project_top(b, [(side * 0.18, 1.62), (side * 0.4, 1.62), (side * 0.4, 1.9), (side * 0.2, 1.9)], 0.002)
		if len(pts) == 4:
			mb = core.MeshBuilder()
			mb.f([mb.v(p) for p, _n in pts][:: (1 if side > 0 else -1)], "Gap", False)
			cb.add(mb)

	# --- rear: LED light blade, diffuser, centre exhausts, fixed wing
	hit, nrm = b.front_point(0.0, -0.05, front=False)
	cb.lamp(parts.rect(1.5, 0.03), hit, (0, 0.15, -1), "TailLens", [("bar", (0.0, 0.0), (1.44, 0.012), "Taillight")], depth=0.03,
		housing="Trim", reveal="Trim", mirror=False, round_r=0.012)
	for side in (1.0, -1.0):
		hit, nrm = b.front_point(side * 0.7, -0.1, front=False)
		cb.lamp([(-0.12, -0.04), (0.12, -0.02), (0.12, 0.03), (-0.12, 0.03)] if side > 0 else [(-0.12, -0.02), (0.12, -0.04), (0.12, 0.03), (-0.12, 0.03)],
			hit, (nrm + Vector((0, 0, -0.6))).normalized(), "TailLens", [("outline", (0.0, 1.0), (0.01, 0.01), "Taillight")], depth=0.04,
			housing="Trim", reveal="Trim", mirror=False, round_r=0.01, marker="Taillight" if side > 0 else None)
	hit, nrm = b.front_point(0.0, -0.3, front=False)
	cb.grille(parts.rect(1.3, 0.12), hit, (0, 0, -1), "bars", "Trim", 2, 0.06, 0.008, round_r=0.03)
	cb.bumper(False, -0.6, -0.42, 0.05, "Trim", theta=62.0, back=0.8, p=3.0)
	for k in range(6):
		x = lerp(-0.55, 0.55, k / 5)
		cb.add(core.box((x, -0.56, b.z0 + 0.05), (0.006, 0.07, 0.2), "Trim"))
	for x in (0.12, -0.12):
		cb.exhaust(x, -0.36, -2.3, 0.045, 0.25, shape="square")
	cb.plate(b.front_point(0.0, -0.2, front=False)[0] + Vector((0, 0, -0.02)), (0, 0, -1), "VTX 01", size=(0.46, 0.1))
	wing_y = 0.25
	cb.add(core.superquadric((0.0, wing_y, -2.05), (0.86, 0.018, 0.16), 0.2, 0.25, 16, 6, "Trim",
		deform=lambda p: Vector((p.x, p.y + 0.5 * max(0.0, -p.z) * 0.8, p.z))))
	for x in (0.82, -0.82):
		cb.add(core.superquadric((x, wing_y - 0.02, -2.05), (0.012, 0.06, 0.17), 0.3, 0.3, 6, 6, "Trim"))
	for x in (0.42, -0.42):
		top, _ = b.top_point(x, -2.0)
		cb.add(core.superquadric(Vector((x, (top.y + wing_y) * 0.5, -2.02)), (0.012, (wing_y - top.y) * 0.5 + 0.02, 0.05), 0.3, 0.3, 6, 6, "Trim"))

	# --- side intakes in the haunches
	for side in (1.0, -1.0):
		s = parts.project_side(b, [(-0.58, -0.08), (-1.08, 0.0), (-1.06, -0.3), (-0.7, -0.34)], side, 0.003)
		if len(s) == 4:
			mb = core.MeshBuilder()
			mb.f([mb.v(p) for p, _n in s][:: (1 if side < 0 else -1)], "Gap", False)
			cb.add(mb)
	cb.strip_side([(-0.56, -0.07), (-0.68, -0.34)], 0.02, 0.006, "Trim")
	cb.stripe_side(([(-1.0, -0.52), (1.0, -0.52)], [(-1.0, -0.62), (1.0, -0.62)]), "Trim")

	# --- gaps and detachable panels
	door_bot = -0.53
	cb.gap_side([(0.75, -0.06), (0.76, door_bot), (-0.52, door_bot), (-0.54, -0.06)], n=70)
	cb.gap_top([(-0.55, 2.0), (-0.55, 1.0), (0.55, 1.0), (0.55, 2.0), (-0.55, 2.0)], n=80)
	cb.gap_dir([(-0.9, -0.42, 2.8), (0.9, -0.42, 2.8)], (0, 0, -1))
	cb.gap_side([(2.02, -0.42), (2.02, -0.6)])
	cb.gap_dir([(-0.9, -0.2, -2.8), (0.9, -0.2, -2.8)], (0, 0, 1))
	cb.gap_side([(-2.06, -0.2), (-2.06, -0.6)])
	cb.panel_box("Part_Hood", -0.55, 0.55, -0.3, 1.0, 1.0, 2.0)
	cb.panel_box("Part_BumperFront", -1.3, 1.3, -1.0, -0.42, 2.02, 2.9)
	cb.panel_box("Part_BumperRear", -1.3, 1.3, -1.0, -0.2, -2.9, -2.06)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.66, 1.3) if sx > 0 else (-1.3, -0.66)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.53, 0.76, extra=[((0, -0.07, 0.0), (0, -1, 0.0))])
	cb.mirror(0.66, -0.07, out=0.06, rise=0.06, size=(0.085, 0.045, 0.055), mat="Paint")
	cb.handle(-0.3, -0.14, 0.11, "Trim", recess=True)
	cb.wipers(ws, [0.0], 0.62, 4.0)

	# --- inside and underneath: engine behind the cabin
	cb.engine_bay(-1.85, -0.75, -0.6, 0.02, 0.62)
	cb.interior(0.55, -0.24, 0.62, -0.12, -0.52, 0.36, floor_y=-0.62, wheel_x=0.36)
	cb.underbody(-0.6, -1.9, 1.9, 0.45, 0.0, -2.1, axle_y=wy, axle_z=(wz, -wz), axle_x=0.74, diff_z=-wz)
	return cb
