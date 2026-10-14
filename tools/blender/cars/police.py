"""Interceptor: a full-size police cruiser. An upright, square-shouldered
four-door with a long bonnet and boot, a push bar, a pillar spotlight and a
roof light bar.

The light bar lenses are separate objects, LightbarRed and LightbarBlue, each
with its own material of the same name, so the game can flash them
(CarVisuals.LightbarFlasher). The doors and roof are painted with the Livery
material and the lettering uses Decal, so the game picks the black-and-white
scheme to suit the body colour."""

import math

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import MeshBuilder, lerp

SIZE = (1.95, 1.45, 4.9)
WHEEL = dict(r=0.37, w=0.29, x=0.874, y=-0.685, z=1.519)

BODY = dict(
	z=(-2.45, 2.45),
	yt=[(-2.45, -0.1), (-2.41, 0.04), (-2.33, 0.1), (-2.15, 0.12), (-1.75, 0.13), (-1.55, 0.14), (-1.45, 0.17),
		(-1.2, 0.37), (-0.95, 0.52), (-0.7, 0.565), (-0.2, 0.578), (0.15, 0.57), (0.3, 0.55), (0.95, 0.09),
		(1.02, 0.07), (1.2, 0.06), (1.9, 0.03), (2.2, -0.01), (2.36, -0.08), (2.45, -0.2)],
	yb=[(-2.45, -0.54), (-2.36, -0.68), (-2.05, -0.77), (-1.6, -0.82), (-1.0, -0.84), (1.0, -0.84), (1.75, -0.8),
		(2.25, -0.73), (2.45, -0.58)],
	ysl=[(-2.45, -0.48), (-2.05, -0.65), (-1.0, -0.72), (1.0, -0.72), (2.05, -0.65), (2.45, -0.5)],
	ym=[(-2.45, -0.38), (0.0, -0.42), (2.45, -0.42)],
	ys=[(-2.45, -0.13), (-2.36, 0.04), (-2.0, 0.06), (-1.0, 0.03), (0.0, 0.0), (1.0, -0.02), (1.9, -0.04),
		(2.35, -0.1), (2.45, -0.2)],
	w=[(-2.45, 0.935), (-1.6, 0.955), (0, 0.955), (1.6, 0.955), (2.45, 0.935)],
	wsh=[(-2.45, 0.92), (0.0, 0.925), (2.45, 0.915)],
	wg=[(-2.45, 0.905), (-1.6, 0.905), (-1.45, 0.85), (0.95, 0.85), (1.1, 0.905), (2.45, 0.9)],
	wr=[(-2.45, 0.8), (-1.6, 0.84), (-1.3, 0.75), (-0.95, 0.69), (0.28, 0.69), (0.95, 0.83), (1.2, 0.84), (2.45, 0.8)],
	tuck=0.035,
	rb=0.05,
	nu=3.4,
	cr=0.09,
	bulge=0.012,
	ledge_h=0.03,
	front=dict(R=0.42, k=2.6, rake=-0.22, yref=-0.6),
	rear=dict(R=0.3, k=2.8, rake=-0.1, yref=-0.6),
	fenders=[dict(z=1.519, y=-0.66, r0=0.47, r1=0.8, amount=0.06, top=-0.1, top_w=0.25, kz=0.85),
		dict(z=-1.519, y=-0.66, r0=0.47, r1=0.85, amount=0.06, top=-0.06, top_w=0.25, kz=0.8)],
	stations=100,
	nc=20,
	extra_z=[0.02, -0.2],
)

BAR_Z = -0.32


def build():
	cb = CarBuilder("police", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.015, wr + 0.045)

	# --- glass
	ws = cb.top_window(0.36, 0.93, "Front", side_gap=0.05)
	cb.top_window(-1.42, -0.98, "Rear", side_gap=0.09)

	def c_pillar(z, info, st):
		return st - lerp(0.0, 0.3, max(0.0, min(1.0, (-0.78 - z) / 0.38)))
	cb.side_window(0.02, 0.9, "F", top_gap=0.05)
	cb.side_window(-1.18, -0.2, "B", top_gap=0.05, top_fn=c_pillar)
	cb.blackout(-0.2, 0.02, top_gap=0.05, belt_gap=0.02)
	belt = []
	for i in range(31):
		z = lerp(-1.2, 0.92, i / 30)
		info = b.section_info(z)
		belt.append((z, b.at_s(info, b.belt_s(info) + 0.014)[1]))
	cb.strip_side(belt, 0.012, 0.004, "Trim")

	# --- livery: white doors and roof, lettering on the front doors
	door_bot = -0.68
	cb.stripe_side(([(-1.22, -0.02), (1.02, -0.035)], [(-1.22, -0.66), (1.02, -0.66)]), "Livery", n=44, nv=12, lift=0.003)
	cb.stripe_top((-0.6, 0.6), -0.86, 0.22, "Livery", n=40)
	for side in (1.0, -1.0):
		cen, cn = b.side_point(-0.3, 0.46, side)
		cb.add(core.text_mesh("POLICE", 0.115, 0.002, "Decal", cen + cn * 0.007, Vector((0, 0, -side)), Vector((0, 1, 0)), cn))
		cen, cn = b.side_point(-0.24, -0.62, side)
		cb.add(core.text_mesh("UNIT 07", 0.07, 0.002, "Decal", cen + cn * 0.007, Vector((0, 0, -side)), Vector((0, 1, 0)), cn))

	# --- front: square headlights, chrome grille, push bar
	hit, nrm = b.front_point(0.6, -0.16)
	n = (nrm + Vector((0, 0.2, 0.5))).normalized()
	cb.lamp([(-0.2, -0.06), (0.22, -0.06), (0.27, 0.0), (0.24, 0.06), (-0.2, 0.06)], hit, n, "HeadLens",
		[("disc", (0.08, 0.0), 0.04, "Headlight"), ("disc", (-0.06, 0.0), 0.036, "Headlight"),
			("outline", (0.44, 0.98), (0.01, 0.01), "Headlight"), ("bar", (0.22, 0.0), (0.03, 0.06), "Indicator")],
		depth=0.08, housing="Trim", reveal="Chrome", back_mat="Trim", round_r=0.02, marker="Headlight")
	hit, nrm = b.front_point(0.0, -0.18)
	cb.grille([(-0.33, -0.08), (0.33, -0.08), (0.36, 0.07), (-0.36, 0.07)], hit, Vector((0, 0.15, 1)), "bars", "Trim", 4, 0.06, 0.008,
		vertical=1, round_r=0.03, reveal="Chrome")
	hit, nrm = b.front_point(0.0, -0.55)
	cb.grille(parts.rect(0.9, 0.1), hit, Vector((0, -0.1, 1)), "mesh", "Trim", 4, 0.05, round_r=0.03)
	cb.bumper(True, -0.66, -0.36, 0.04, "Trim", theta=72.0, back=0.75, p=2.0)
	cb.plate(b.front_point(0.0, -0.44)[0] + Vector((0, 0, 0.04)), (0, 0, 1), "PD 0417", size=(0.48, 0.11))
	push_bar(cb, b)

	# --- rear: wide tail lights, boot lid, twin exhausts
	hit, nrm = b.front_point(0.6, -0.02, front=False)
	n = (nrm + Vector((0, 0.0, -0.5))).normalized()
	cb.lamp([(-0.25, -0.06), (0.24, -0.06), (0.28, 0.0), (0.24, 0.06), (-0.25, 0.06)], hit, n, "TailLens",
		[("outline", (0.0, 1.0), (0.014, 0.016), "Taillight"), ("bar", (0.06, 0.0), (0.24, 0.04), "Taillight"),
			("bar", (-0.17, 0.0), (0.07, 0.05), "Chrome")],
		depth=0.06, housing="Trim", back_mat="Trim", round_r=0.02, marker="Taillight")
	cb.plate(b.front_point(0.0, -0.14, front=False)[0] + Vector((0, 0, -0.006)), (0, 0, -1), "PD 0417", size=(0.48, 0.11))
	cb.bumper(False, -0.62, -0.44, 0.04, "Trim", theta=62.0, back=0.7, p=3.0)
	for x in (0.55, -0.55):
		cb.exhaust(x, -0.62, -2.42, 0.038, 0.3)

	# --- panel gaps (the doors, bonnet and bumpers are detachable panels)
	cb.gap_side([(0.99, 0.0), (0.99, door_bot)])
	cb.gap_side([(0.99, door_bot), (-1.06, door_bot)])
	cb.gap_side([(-0.09, 0.03), (-0.09, door_bot)])
	cb.gap_side([(-1.06, 0.06), (-1.06, door_bot)])
	cb.gap_side([(2.04, -0.3), (2.04, -0.64)])
	cb.gap_side([(-2.04, -0.3), (-2.04, -0.62)])
	cb.gap_top([(-0.8, 2.25), (-0.8, 1.0), (0.8, 1.0), (0.8, 2.25)], n=90)
	cb.gap_dir([(-0.8, -0.1, 2.8), (0.8, -0.1, 2.8)], (0, 0, -1))
	cb.gap_top([(-0.72, -2.3), (-0.8, -2.2), (-0.8, -1.56), (0.8, -1.56), (0.8, -2.2), (0.72, -2.3), (-0.72, -2.3)], n=90)
	cb.gap_dir([(-0.95, -0.3, 2.8), (0.95, -0.3, 2.8)], (0, 0, -1))
	cb.gap_dir([(-0.95, -0.3, -2.8), (0.95, -0.3, -2.8)], (0, 0, 1))
	s = parts.project_side(b, parts.superellipse(0.075, 0.065, 4.0, 24, -1.84, -0.06), -1.0)
	cb.add(parts.ribbon(s, 0.005, "Gap", closed=True))
	cb.panel_box("Part_Hood", -0.8, 0.8, -0.1, 1.0, 1.0, 2.8)
	cb.panel_box("Part_BumperFront", -1.2, 1.2, -1.0, -0.3, 2.04, 2.9)
	cb.panel_box("Part_BumperRear", -1.2, 1.2, -1.0, -0.3, -2.9, -2.04)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (0.72, 1.3) if sx > 0 else (-1.3, -0.72)
		cb.panel_box(name, x0, x1, door_bot, 0.5, -0.09, 0.99, extra=[((0, -0.035, 0.0), (0, -1, 0.03))])

	# --- bolt-ons: mirrors, handles, wipers, pillar spotlight, antennas
	cb.mirror(0.86, 0.02, out=0.04, rise=0.06, mat="Trim")
	cb.handle(0.3, -0.1, 0.14, "Trim")
	cb.handle(-0.7, -0.08, 0.14, "Trim")
	cb.wipers(ws, [0.32, -0.28], 0.55, 8.0)
	top, tn = b.side_point(0.12, 0.82, 1.0)
	if top is not None:
		c = top + tn * 0.07 + Vector((0, 0.0, 0.0))
		cb.add(core.cylinder(top + tn * 0.01, c, 0.012, 0.012, 8, "Chrome"))
		cb.spotlamp(c + Vector((0, 0, 0.02)), (0.1, 0.0, 1.0), 0.05, 0.08, housing="Chrome", lens="Headlight", bezel="Chrome", guard=False)
	for z, h in ((-1.25, 0.32), (-1.65, 0.0)):
		t, _ = b.top_point(0.0, z)
		if t is not None:
			cb.add(core.cylinder(t, t + Vector((0, 0.04 + h, -0.02 - h * 0.15)), 0.004, 0.003, 6, "Trim"))
	cb.extra_objects = light_bar(cb, b)

	# --- inside: cabin, partition cage behind the front seats, laptop
	cb.engine_bay(1.15, 2.1, -0.62, -0.16, 0.64)
	cb.interior(0.66, -0.1, 0.8, 0.16, -0.42, 0.38, rear_z=-0.72, rear_w=1.45, floor_y=-0.74, wheel_x=0.38)
	for k in range(9):
		x = lerp(-0.7, 0.7, k / 8)
		cb.add(core.cylinder((x, -0.25, -0.3), (x * 0.92, 0.47, -0.3), 0.008, 0.008, 4, "Frame"))
	for y in (-0.25, 0.1, 0.46):
		cb.add(core.cylinder((-0.74, y, -0.3), (0.74, y, -0.3), 0.01, 0.01, 4, "Frame"))
	cb.add(core.box((0.0, 0.02, 0.62), (0.13, 0.008, 0.09), "Trim"))
	cb.underbody(-0.74, -1.95, 1.95, 0.5, -0.45, -2.25, tank_z=-1.0, axle_y=wy, axle_z=(wz, -wz), axle_x=0.72, diff_z=-wz, muffler_z=-1.95)
	return cb


def push_bar(cb, b):
	"""Black steel push bar bolted through the front bumper."""
	zf = b.front_point(0.0, -0.4)[0].z + 0.1
	for x in (0.3, -0.3):
		top = Vector((x, -0.06, zf))
		bot = Vector((x, -0.62, zf - 0.02))
		cb.add(core.cylinder(bot, top, 0.028, 0.028, 10, "Trim"))
		cb.add(core.cylinder(top, top + Vector((-0.02 * math.copysign(1, x), 0.0, -0.12)), 0.026, 0.026, 8, "Trim"))
		for y in (-0.2, -0.5):
			cb.add(core.box((x, y, zf - 0.07), (0.02, 0.035, 0.07), "Trim"))
	for y in (-0.16, -0.48):
		cb.add(core.cylinder((-0.36, y, zf), (0.36, y, zf), 0.022, 0.022, 10, "Trim"))


def light_bar(cb, b):
	"""Roof light bar: a black base on two feet (part of the body) plus the
	red (car's left) and blue (car's right) lens objects."""
	top, _ = b.top_point(0.0, BAR_Z)
	y0 = top.y + 0.035
	cb.add(core.superquadric((0.0, y0, BAR_Z), (0.62, 0.022, 0.13), 0.25, 0.4, 16, 6, "Trim"))
	for x in (0.42, -0.42):
		t, _ = b.top_point(x, BAR_Z)
		cb.add(core.box((x, (t.y + y0) * 0.5, BAR_Z), (0.04, (y0 - t.y) * 0.5 + 0.005, 0.1), "Trim"))
	# Centre module: takedown light and a siren speaker grille.
	cb.add(core.superquadric((0.0, y0 + 0.05, BAR_Z), (0.08, 0.035, 0.11), 0.3, 0.4, 10, 6, "Chrome"))
	cb.add(core.box((0.0, y0 + 0.05, BAR_Z + 0.111), (0.05, 0.022, 0.002), "Headlight"))
	objs = []
	for name, sx in (("LightbarRed", 1.0), ("LightbarBlue", -1.0)):
		mb = MeshBuilder()
		for k in range(3):
			x0 = lerp(0.095, 0.6, k / 3) + 0.004
			x1 = lerp(0.095, 0.6, (k + 1) / 3) - 0.004
			cx = (x0 + x1) * 0.5
			taper = 1.0 - 0.25 * (k / 2)
			mb.add(core.superquadric((sx * cx, 0.05, 0.0), ((x1 - x0) * 0.5, 0.042 * taper + 0.006, 0.115), 0.35, 0.45, 10, 6, name))
		obj = mb.build(name, sharp_angle=38.0)
		obj.data.shade_smooth()
		obj.data.set_sharp_from_angle(angle=math.radians(38.0))
		obj.location = Vector((0.0, y0, BAR_Z))
		objs.append(obj)
	return objs
