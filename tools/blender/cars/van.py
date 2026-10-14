"""Hot Rod Van: a lifted 70s custom van with porthole windows, side pipes,
chrome bumpers, a spare wheel on the back doors and wavy stripes."""

import math

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (2.1, 1.7, 4.6)
WHEEL = dict(r=0.42, w=0.32, x=0.938, y=-0.985, z=1.518)

BODY = dict(
	z=(-2.3, 2.3),
	yt=[(-2.3, 0.58), (-2.27, 0.74), (-2.2, 0.8), (-2.0, 0.82), (0.5, 0.83), (1.28, 0.82), (1.36, 0.79),
		(1.68, 0.21), (1.76, 0.15), (2.05, 0.09), (2.22, 0.03), (2.3, -0.08)],
	yb=[(-2.3, -0.6), (-2.24, -0.8), (-2.0, -0.88), (2.0, -0.88), (2.24, -0.8), (2.3, -0.6)],
	ym=[(-2.3, -0.3), (0.0, -0.3), (2.3, -0.32)],
	ys=[(-2.3, 0.08), (-2.2, 0.14), (1.3, 0.16), (1.66, 0.13), (2.1, 0.06), (2.3, -0.12)],
	w=[(-2.3, 1.03), (-2.0, 1.05), (1.5, 1.05), (2.3, 1.02)],
	wsh=[(-2.3, 1.02), (-2.0, 1.04), (1.5, 1.04), (2.3, 1.01)],
	wg=[(-2.3, 1.01), (-2.1, 1.0), (1.55, 1.0), (1.72, 1.03), (2.3, 1.0)],
	wr=[(-2.3, 0.93), (-2.1, 0.94), (1.3, 0.94), (1.7, 0.97), (2.3, 0.95)],
	nb=5.0,
	nu=[(-2.3, 4.5), (1.6, 4.5), (1.75, 3.2)],
	cr=0.14,
	bulge=0.0,
	ledge_h=0.02,
	front=dict(R=0.22, k=3.2, rake=-0.06, yref=-0.6),
	rear=dict(R=0.14, k=4.0),
	stations=100,
	extra_z=[0.82, 0.86],
)


def build():
	cb = CarBuilder("van", SIZE, WHEEL, BODY)
	b = cb.body
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	for z in (wz, -wz):
		cb.arch(z, wy + 0.06, wr + 0.06, n_exp=2.4, flare=dict(width=0.09, height=0.04, mat="Paint", angles=(-6.0, 186.0)))

	# --- glass: steep windscreen, cab door windows, portholes, rear door windows
	ws = cb.top_window(1.38, 1.67, "Front", side_gap=0.06, radius=0.05)
	cb.side_window(0.86, 1.64, "F", top_gap=0.06, belt_gap=0.03, reveal="Chrome")
	cb.side_window_poly(parts.ellipse(0.27, 0.27, 28, -0.75, 0.47), "Port", reveal="Chrome", radius=0.0)
	for x in (0.47,):
		hit, nrm = b.front_point(x, 0.47, front=False)
		cb.flat_window(core.round_polygon(parts.rect(0.66, 0.42), 0.06, 3), hit, (0, 0, -1), "Back", mirror=True, reveal="Chrome", round_r=0.0)

	# --- front: round headlights, chrome grille, chrome bumper
	hit, nrm = b.front_point(0.0, -0.18)
	cb.grille(parts.rect(0.94, 0.26), hit, Vector((0, 0, 1)), "bars", "Chrome", 7, 0.07, 0.01, reveal="Chrome", round_r=0.03)
	for x in (0.73,):
		hit, nrm = b.front_point(x, -0.18)
		cb.lamp(parts.ellipse(0.105, 0.105, 24), hit, (nrm + Vector((0, 0, 1))).normalized(), "Glass",
			[("bulb", (0.0, 0.0), 0.05, "Headlight")], depth=0.06, reveal="Chrome", housing="Chrome")
	for x in (0.73,):
		hit, nrm = b.front_point(x, -0.38)
		cb.lamp(parts.rect(0.14, 0.06), hit, (nrm + Vector((0, 0, 1))).normalized(), "Indicator", [], depth=0.03, reveal="Chrome", housing="Chrome", round_r=0.01)
	cb.bumper(True, -0.62, -0.47, kind="blade", mat="Chrome", theta=72.0, back=0.6, gap=0.03, thick=0.07)
	cb.plate(b.front_point(0.0, -0.66)[0] + Vector((0, 0, 0.1)), (0, 0, 1), "GRV 76", size=(0.5, 0.12))

	# --- rear: tail lights, back doors, spare wheel, ladder, chrome bumper
	for x in (0.93,):
		hit, nrm = b.front_point(x, -0.2, front=False)
		cb.lamp(parts.rect(0.11, 0.36), hit, (nrm + Vector((0, 0, -1))).normalized(), "Taillight",
			[("bar", (0.0, 0.05), (0.08, 0.2), "Taillight")], depth=0.04, reveal="Chrome", housing="Chrome", back_mat="Taillight", round_r=0.015)
	cb.bumper(False, -0.66, -0.52, kind="blade", mat="Chrome", theta=72.0, back=0.5, gap=0.03, thick=0.07)
	cb.plate(b.front_point(0.0, -0.42, front=False)[0] + Vector((0, 0, -0.008)), (0, 0, -1), "GRV 76", size=(0.5, 0.12))
	cb.gap_dir([(0.0, 0.7, -2.4), (0.0, -0.78, -2.4)], (0, 0, 1))
	cb.gap_dir([(-0.92, 0.7, -2.4), (-0.92, -0.78, -2.4)], (0, 0, 1))
	cb.gap_dir([(0.92, 0.7, -2.4), (0.92, -0.78, -2.4)], (0, 0, 1))
	cb.gap_dir([(-0.92, 0.7, -2.4), (0.92, 0.7, -2.4)], (0, 0, 1))
	# Spare wheel on the right back door.
	spare_c = Vector((-0.47, -0.16, b.front_point(-0.47, -0.16, front=False)[0].z - 0.15))
	cb.add(core.lathe([(0.2, 0.0), (0.3, 0.02), (0.36, 0.06), (0.36, 0.14), (0.3, 0.18), (0.2, 0.2)], 32, "Tyre", axis="z", centre=spare_c - Vector((0, 0, 0.05)), flip=True))
	cb.add(core.lathe([(0.0, 0.2), (0.15, 0.19), (0.2, 0.2)], 24, "Chrome", axis="z", centre=spare_c - Vector((0, 0, 0.05)), flip=False))
	cb.add(core.lathe([(0.0, -0.06), (0.21, -0.06)], 24, "Chrome", axis="z", centre=spare_c - Vector((0, 0, 0.05)), flip=True))
	# Ladder to the roof on the left back door.
	lz = b.front_point(0.62, 0.0, front=False)[0].z - 0.05
	for x in (0.5, 0.74):
		cb.add(core.cylinder((x, -0.6, lz), (x, 0.84, lz), 0.014, 0.014, 8, "Chrome"))
	for k in range(7):
		y = lerp(-0.45, 0.7, k / 6)
		cb.add(core.cylinder((0.5, y, lz), (0.74, y, lz), 0.011, 0.011, 6, "Chrome"))
	for y in (-0.5, 0.6):
		cb.add(core.cylinder((0.62, y, lz), (0.62, y, lz + 0.06), 0.01, 0.01, 6, "Chrome"))
	cb.exhaust(-0.55, -0.84, -2.32, 0.045, 0.3)

	# --- side pipes, stripes, gaps, bolt-ons
	for side in (1.0, -1.0):
		x = side * 1.09
		cb.add(core.cylinder((x, -0.82, -0.95), (x, -0.82, 0.95), 0.055, 0.055, 16, "Chrome", caps=False))
		cb.add(core.cylinder((x, -0.82, -0.95), (x, -0.82, -1.0), 0.055, 0.05, 16, "Chrome", caps=True, cap_mat="Gap"))
		cb.add(core.cylinder((x, -0.82, 0.95), (side * 0.98, -0.82, 1.05), 0.05, 0.05, 12, "Chrome"))
		# Perforated heat shield look: dark slots on top of the pipe.
		for k in range(10):
			z = lerp(-0.8, 0.8, k / 9)
			cb.add(core.box((x, -0.82 + 0.052, z), (0.022, 0.004, 0.05), "Gap"))
	wave_top = [(lerp(-2.25, 2.2, i / 40), 0.02 + 0.07 * math.sin(i / 40 * math.pi * 3.0)) for i in range(41)]
	wave_bot = [(z, y - 0.07) for z, y in wave_top]
	cb.stripe_side((wave_top, wave_bot), "Decal", n=80)
	wave2_top = [(z, y - 0.11) for z, y in wave_top]
	wave2_bot = [(z, y - 0.15) for z, y in wave_top]
	cb.stripe_side((wave2_top, wave2_bot), "Livery", n=80)
	door_bot = -0.72
	cb.gap_side([(1.66, 0.12), (1.66, door_bot), (0.84, door_bot), (0.84, 0.74)], n=80)
	cb.gap_side([(0.78, 0.74), (0.78, door_bot)])
	cb.gap_side([(-0.15, 0.74), (-0.15, door_bot), (0.78, door_bot)], both=False)
	cb.gap_side([(0.78, 0.74), (-0.15, 0.74)], both=False)
	cb.gap_top([(-0.94, 1.72), (-0.95, 2.2), (0.95, 2.2), (0.94, 1.72), (-0.94, 1.72)], n=60)
	cb.mirror(1.55, 0.28, out=0.1, rise=0.1, size=(0.09, 0.13, 0.04), mat="Chrome", arm_mat="Chrome")
	cb.handle(0.97, 0.06, 0.14)
	cb.wipers(ws, [0.36, -0.3], 0.55, 5.0)
	# Roof spoiler over the windscreen and a running board.
	cb.add(core.superquadric((0.0, 0.85, 1.22), (0.9, 0.03, 0.16), 0.25, 0.25, 16, 6, "Paint",
		deform=lambda p: Vector((p.x, p.y + 0.5 * max(0.0, p.z) * 0.06 / 0.03, p.z))))
	for side in (1.0, -1.0):
		cb.add(core.box((side * 1.02, -0.93, 1.2), (0.09, 0.015, 0.22), "Trim"))

	# --- inside and underneath
	cb.interior(1.28, 0.05, 0.9, 0.7, -0.28, 0.45, floor_y=-0.8, wheel_x=0.45)
	cb.seat(0.0, -0.3, -0.8, width=1.6, bench=True, recline=12.0)
	cb.underbody(-0.83, -1.9, 1.9, 0.55, -0.55, -2.2, tank_z=-0.6, axle_y=wy, axle_z=(wz, -wz), axle_x=0.78, diff_z=-wz, muffler_z=-1.7)
	return cb
