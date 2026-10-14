"""Pocket: a small three-door hot hatch. Short overhangs, a tall rounded
cabin pushed to the corners, a steep tailgate with a roof spoiler, wide
arches over big wheels, a honeycomb front end and twin centre exhausts."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (1.75, 1.4, 3.7)
WHEEL = dict(r=0.33, w=0.25, x=0.788, y=-0.694, z=1.184)

BODY = dict(
	z=(-1.85, 1.85),
	yt=[(-1.85, -0.16), (-1.82, -0.05), (-1.78, 0.04), (-1.72, 0.14), (-1.62, 0.27), (-1.52, 0.35), (-1.42, 0.385),
		(-1.2, 0.405), (-0.5, 0.42), (-0.1, 0.42), (0.08, 0.4), (0.2, 0.36), (0.86, -0.02), (0.93, -0.035),
		(1.2, -0.05), (1.5, -0.09), (1.7, -0.15), (1.8, -0.23), (1.85, -0.33)],
	dip=[(0.88, 0.0), (1.05, 0.012), (1.4, 0.02), (1.7, 0.01), (1.85, 0.0)],
	yb=[(-1.85, -0.58), (-1.78, -0.72), (-1.55, -0.8), (-1.0, -0.84), (1.0, -0.84), (1.55, -0.8), (1.78, -0.72), (1.85, -0.6)],
	ysl=[(-1.85, -0.52), (-1.6, -0.67), (-1.0, -0.72), (1.0, -0.72), (1.6, -0.67), (1.85, -0.54)],
	ym=[(-1.85, -0.42), (0.0, -0.44), (1.85, -0.44)],
	ys=[(-1.85, -0.22), (-1.8, -0.07), (-1.6, -0.03), (-1.0, -0.04), (0.0, -0.07), (0.8, -0.09), (1.5, -0.12),
		(1.78, -0.18), (1.85, -0.28)],
	w=[(-1.85, 0.835), (-1.3, 0.86), (0.0, 0.85), (1.3, 0.855), (1.85, 0.83)],
	wsh=[(-1.85, 0.8), (-1.3, 0.83), (0.0, 0.81), (1.3, 0.82), (1.85, 0.795)],
	wg=[(-1.85, 0.8), (-1.62, 0.82), (-1.5, 0.75), (0.85, 0.74), (0.98, 0.81), (1.85, 0.79)],
	wr=[(-1.85, 0.69), (-1.6, 0.71), (-1.45, 0.62), (-0.2, 0.6), (0.2, 0.61), (0.92, 0.79), (1.85, 0.69)],
	tuck=0.035,
	rb=0.05,
	nu=2.6,
	cr=0.12,
	bulge=0.025,
	ledge_h=0.02,
	front=dict(R=0.4, k=2.1, rake=-0.32, yref=-0.6),
	rear=dict(R=0.28, k=2.6, rake=-0.04, yref=-0.6),
	fenders=[dict(z=1.184, y=-0.67, r0=0.42, r1=0.72, amount=0.075, top=-0.1, top_w=0.22, kz=0.85),
		dict(z=-1.184, y=-0.67, r0=0.42, r1=0.78, amount=0.08, top=-0.06, top_w=0.22, kz=0.8)],
	stations=90,
	nc=20,
)


def build():
	cb = CarBuilder("hatch", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.015, wr + 0.04)

	# --- glass: steep screen, one long door window, small rear quarter, tailgate glass
	ws = cb.top_window(0.2, 0.84, "Front", side_gap=0.05)
	rw = cb.top_window(-1.7, -1.53, "Rear", side_gap=0.08, radius=0.04)

	def quarter(z, info, st):
		return st - lerp(0.0, 0.3, max(0.0, min(1.0, (-1.12 - z) / 0.3)))
	cb.side_window(-0.42, 0.8, "F", top_gap=0.045)
	cb.side_window(-1.42, -0.52, "B", top_gap=0.045, top_fn=quarter)
	cb.blackout(-0.52, -0.42, top_gap=0.045, belt_gap=0.02)

	# --- front: big round-cornered headlights, slot grille, honeycomb intake
	hit, nrm = b.front_point(0.55, -0.2)
	n = (nrm + Vector((0, 0.3, 0.4))).normalized()
	poly = core.round_polygon([(-0.18, -0.06), (0.15, -0.065), (0.24, 0.0), (0.18, 0.07), (-0.16, 0.06)], 0.03, 3)
	cb.lamp(poly, hit, n, "HeadLens",
		[("disc", (0.06, 0.0), 0.045, "Headlight"), ("disc", (-0.07, 0.0), 0.03, "Headlight"),
			("outline", (0.5, 0.98), (0.01, 0.01), "Headlight"), ("bar", (0.19, -0.01), (0.03, 0.04), "Indicator")],
		depth=0.07, housing="Trim", reveal="Trim", back_mat="Trim", round_r=0.03, marker="Headlight")
	hit, nrm = b.front_point(0.0, -0.25)
	cb.grille([(-0.3, -0.06), (0.3, -0.06), (0.34, 0.045), (-0.34, 0.045)], hit, Vector((0, 0.25, 1)), "mesh", "Trim", 3, 0.05,
		round_r=0.02, reveal="Trim")
	hit, nrm = b.front_point(0.0, -0.56)
	cb.grille([(-0.46, -0.07), (0.46, -0.07), (0.52, 0.06), (-0.52, 0.06)], hit, Vector((0, -0.05, 1)), "mesh", "Trim", 4, 0.06,
		round_r=0.04)
	for side in (1.0, -1.0):
		hit, nrm = b.front_point(side * 0.66, -0.52)
		cb.spotlamp(hit + Vector((0.0, 0.0, -0.025)), (side * 0.3, 0.0, 1.0), 0.03, 0.03, housing="Trim", lens="Headlight", bezel="Chrome", guard=False)
	cb.bumper(True, -0.67, -0.64, 0.035, "Trim", theta=70.0, back=0.75, p=2.0)
	cb.plate(b.front_point(0.0, -0.42)[0] + Vector((0, 0, 0.004)), (0, 0, 1), "PKT 55", size=(0.44, 0.1))

	# --- rear: tall corner tail lights, tailgate, spoiler, diffuser, twin pipes
	hit, nrm = b.front_point(0.64, 0.02, front=False)
	n = (nrm + Vector((0.3, 0.0, -0.6))).normalized()
	cb.lamp([(-0.12, -0.15), (0.09, -0.15), (0.12, 0.08), (0.07, 0.15), (-0.12, 0.13)], hit, n, "TailLens",
		[("outline", (0.0, 1.0), (0.012, 0.014), "Taillight"), ("bar", (0.0, 0.08), (0.17, 0.035), "Taillight"),
			("bar", (0.0, 0.0), (0.15, 0.012), "Taillight"), ("bar", (0.0, -0.08), (0.15, 0.045), "Chrome")],
		depth=0.06, housing="Trim", back_mat="Trim", round_r=0.03, marker="Taillight")
	cb.plate(b.front_point(0.0, -0.06, front=False)[0] + Vector((0, 0, -0.006)), (0, 0, -1), "PKT 55", size=(0.44, 0.1))
	cb.bumper(False, -0.62, -0.44, 0.035, "Trim", theta=62.0, back=0.7, p=3.0)
	hit, nrm = b.front_point(0.0, -0.62, front=False)
	cb.grille(parts.rect(0.8, 0.07), hit, (0, -0.3, -1), "bars", "Trim", 2, 0.05, 0.008, round_r=0.03)
	for x in (0.1, -0.1):
		cb.exhaust(x, -0.62, -1.83, 0.042, 0.26)
	# Roof spoiler over the tailgate glass, with a brake light.
	t, _ = b.top_point(0.0, -1.5)
	cb.add(core.superquadric((0.0, t.y + 0.012, -1.56), (0.66, 0.018, 0.12), 0.25, 0.3, 14, 6, "Paint",
		deform=lambda p: Vector((p.x, p.y - 0.25 * max(0.0, -p.z), p.z))))
	cb.add(core.box((0.0, t.y + 0.004, -1.672), (0.22, 0.008, 0.003), "Taillight"))
	cb.wipers(rw, [0.0], 0.34, 0.0)

	# --- panel gaps and detachable panels
	door_bot = -0.68
	cb.gap_side([(0.86, -0.04), (0.86, door_bot), (-0.48, door_bot), (-0.5, 0.0)], n=70)
	cb.gap_side([(1.63, -0.2), (1.63, -0.62)])
	cb.gap_side([(-1.63, -0.24), (-1.63, -0.6)])
	cb.gap_top([(-0.7, 1.62), (-0.7, 0.9), (0.7, 0.9), (0.7, 1.62)], n=80)
	cb.gap_dir([(-0.7, -0.15, 2.4), (0.7, -0.15, 2.4)], (0, 0, -1))
	cb.gap_dir([(-0.9, -0.24, 2.4), (0.9, -0.24, 2.4)], (0, 0, -1))
	cb.gap_dir([(-0.9, -0.28, -2.4), (0.9, -0.28, -2.4)], (0, 0, 1))
	cb.gap_top([(-0.7, -1.7), (-0.74, -1.5), (0.74, -1.5), (0.7, -1.7)], n=60)
	s = parts.project_side(b, parts.superellipse(0.065, 0.055, 4.0, 24, -1.36, -0.08), -1.0)
	cb.add(parts.ribbon(s, 0.005, "Gap", closed=True))
	cb.panel_box("Part_Hood", -0.7, 0.7, -0.15, 1.0, 0.9, 2.4)
	cb.panel_box("Part_BumperFront", -1.2, 1.2, -1.0, -0.24, 1.63, 2.4)
	cb.panel_box("Part_BumperRear", -1.2, 1.2, -1.0, -0.28, -2.4, -1.63)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.66, 1.3) if sx > 0 else (-1.3, -0.66)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.49, 0.86, extra=[((0, -0.06, 0.0), (0, -1, 0.03))])

	# --- bolt-ons and a pair of side stripes
	cb.mirror(0.68, 0.02, out=0.04, rise=0.06, size=(0.09, 0.06, 0.05))
	cb.handle(-0.36, -0.08, 0.13, "Trim")
	cb.wipers(ws, [0.26, -0.24], 0.48, 8.0)
	cb.stripe_side(([(-1.5, -0.6), (1.5, -0.6)], [(-1.5, -0.66), (1.5, -0.66)]), "Decal", n=60)
	cb.strip_side([(-1.5, -0.69), (1.5, -0.69)], 0.02, 0.006, "Trim")
	t, _ = b.top_point(0.0, -1.2)
	if t is not None:
		cb.add(core.cylinder(t, t + Vector((0, 0.18, -0.06)), 0.004, 0.003, 6, "Trim"))

	# --- inside and underneath
	cb.engine_bay(0.85, 1.6, -0.62, -0.18, 0.58)
	cb.interior(0.5, -0.12, 0.68, -0.08, -0.44, 0.34, rear_z=-0.88, rear_w=1.25, floor_y=-0.74, wheel_x=0.34)
	cb.underbody(-0.74, -1.5, 1.5, 0.42, 0.0, -1.7, tank_z=-0.85, axle_y=wy, axle_z=(wz, -wz), axle_x=0.64, diff_z=wz, muffler_z=-1.5)
	return cb
