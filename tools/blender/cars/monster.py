"""Big Foot: a monster truck. A regular-cab pickup body sits high on a tube
chassis over huge mud tyres, with solid axles, twin coil-over shocks per
corner, a supercharger through the bonnet and a roof light bar.

The axles and shocks are separate objects (Axle_F, Axle_R, Shock_<F|R><L|R>_n)
so the game can move them with the wheels (CarVisuals.SuspensionRig):
- Axle_*: origin on the axle line, X along the axle, X extent = the track.
- Shock_*: origin at the top mount, the mesh hanging straight down along -Y
  to the lower mount on the axle.
"""

import math

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import MeshBuilder, lerp

SIZE = (2.5, 1.5, 4.6)
WHEEL = dict(r=0.95, w=0.75, x=0.988, y=-1.348, z=1.656)

CAB = dict(
	z=(-0.6, 2.3),
	yt=[(-0.6, 0.6), (-0.58, 0.71), (-0.53, 0.745), (0.4, 0.75), (0.5, 0.72), (0.98, 0.17), (1.04, 0.14), (1.3, 0.13),
		(2.1, 0.11), (2.24, 0.07), (2.3, -0.06)],
	yb=[(-0.6, -0.62), (-0.56, -0.75), (2.15, -0.75), (2.3, -0.6)],
	ym=-0.42,
	ys=[(-0.6, 0.06), (-0.55, 0.14), (0.5, 0.14), (1.0, 0.12), (2.1, 0.1), (2.3, -0.06)],
	w=[(-0.6, 1.22), (-0.45, 1.235), (2.1, 1.235), (2.3, 1.215)],
	wsh=[(-0.6, 1.21), (-0.45, 1.225), (2.1, 1.225), (2.3, 1.205)],
	wg=[(-0.6, 1.16), (-0.45, 1.155), (0.9, 1.155), (1.06, 1.21), (2.3, 1.19)],
	wr=[(-0.6, 1.04), (-0.45, 1.05), (0.5, 1.05), (1.0, 1.12), (2.3, 1.12)],
	tuck=0.025,
	rb=0.06,
	nu=[(-0.6, 4.0), (0.9, 4.0), (1.1, 4.5)],
	cr=0.14,
	bulge=0.01,
	ledge_h=0.02,
	front=dict(R=0.18, k=3.6, rake=-0.04, yref=-0.6),
	rear=dict(R=0.06, k=4.0),
	stations=72,
	nc=18,
	extra_z=[-0.12, 0.0],
)

BED = dict(
	z=(-2.3, -0.64),
	yt=[(-2.3, 0.13), (-2.28, 0.165), (-0.66, 0.165), (-0.64, 0.13)],
	yb=[(-2.3, -0.6), (-2.25, -0.75), (-0.68, -0.75), (-0.64, -0.62)],
	ym=-0.42,
	ys=0.13,
	w=1.235,
	wsh=1.23,
	wg=1.225,
	wr=1.19,
	tuck=0.025,
	rb=0.06,
	nu=4.0,
	cr=0.04,
	bulge=0.0,
	front=dict(R=0.05, k=4.0),
	rear=dict(R=0.07, k=4.0),
	stations=50,
	nc=10,
)

SHOCK_X = 0.54
SHOCK_TOP = -0.6
SHOCK_DZ = (0.21, -0.21)
SHOCK_LOW = 0.09


def build():
	cb = CarBuilder("monster", SIZE, WHEEL, CAB)
	cab = cb.body
	bed = cb.add_shell(BED, "Bed")
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	flare = dict(width=0.15, height=0.06, mat="Trim", angles=(-8.0, 188.0))
	cb.arch(wz, wy + 0.07, wr + 0.1, n_exp=2.2, flare=flare, shell=cab)
	cb.arch(-wz, wy + 0.07, wr + 0.1, n_exp=2.2, flare=flare, shell=bed)

	# --- bed
	cb.box_cut(-1.155, 1.155, -0.2, 1.5, -2.22, -0.72, reveal="Paint", shell=bed)
	cb.bed_tub(1.152, -0.2, 0.165, -2.218, -0.722)
	for side in (1.0, -1.0):
		cb.add(core.box((side * 1.195, 0.172, -1.47), (0.045, 0.01, 0.8), "Trim"))
	cb.add(core.box((0.0, 0.172, -2.26), (1.235, 0.01, 0.04), "Trim"))

	# --- glass
	ws = cb.top_window(0.54, 0.96, "Front", side_gap=0.07, radius=0.05)
	cb.side_window(0.0, 0.94, "F", top_gap=0.06, belt_gap=0.025)
	cb.side_window(-0.5, -0.14, "B", top_gap=0.06, belt_gap=0.025)
	cb.blackout(-0.14, 0.0, top_gap=0.06, belt_gap=0.025)
	hit, nrm = cab.front_point(0.0, 0.43, front=False)
	cb.flat_window(core.round_polygon(parts.rect(1.6, 0.4), 0.06, 3), hit, (0, 0, -1), "Back", reveal="Trim", round_r=0.0)

	# --- front: chrome grille between stacked square headlights
	hit, nrm = cab.front_point(0.0, -0.2)
	cb.grille(parts.rect(1.0, 0.34), hit, Vector((0, 0, 1)), "bars", "Chrome", 5, 0.08, 0.016, vertical=3, reveal="Chrome", round_r=0.03)
	for x in (0.83,):
		hit, nrm = cab.front_point(x, -0.2)
		cb.lamp(parts.rect(0.26, 0.32), hit, (nrm + Vector((0, 0, 1))).normalized(), "HeadLens",
			[("bar", (0.0, 0.075), (0.21, 0.12), "Headlight"), ("bar", (0.0, -0.075), (0.21, 0.12), "Headlight")],
			depth=0.07, reveal="Chrome", housing="Chrome", back_mat="Trim", round_r=0.02, marker="Headlight")
		hit, nrm = cab.front_point(1.08, -0.2)
		cb.lamp(parts.rect(0.07, 0.24), hit, (nrm + Vector((0, 0, 1))).normalized(), "Indicator", [], depth=0.03,
			reveal="Chrome", housing="Chrome", round_r=0.01)
	cb.add(core.superquadric((0.0, -0.53, 2.31), (1.15, 0.06, 0.02), 0.2, 0.3, 14, 4, "Chrome"))
	cb.plate(Vector((0.0, -0.84, 2.425)), (0, 0, 1), "BFT 66", size=(0.46, 0.11))

	# --- rear: tail lights on the bed corners, tailgate, exhausts
	for x in (1.15,):
		hit, nrm = bed.front_point(x, -0.03, front=False)
		cb.lamp(parts.rect(0.13, 0.3), hit, (nrm + Vector((0, 0, -1.2))).normalized(), "TailLens",
			[("bar", (0.0, 0.05), (0.09, 0.16), "Taillight"), ("bar", (0.0, -0.1), (0.09, 0.06), "Chrome")],
			depth=0.04, reveal="Chrome", housing="Chrome", back_mat="Trim", round_r=0.015, shell=bed, marker="Taillight")
	cb.gap_dir([(-1.06, 0.15, -2.4), (-1.06, -0.5, -2.4), (1.06, -0.5, -2.4), (1.06, 0.15, -2.4)], (0, 0, 1), shell=bed, n=60)
	cb.add(core.superquadric((0.0, -0.05, -2.31), (0.12, 0.04, 0.012), 0.3, 0.3, 8, 4, "Trim"))
	for x in (0.3, -0.3):
		cb.exhaust(x, -0.86, -2.42, 0.06, 0.35)

	# --- bonnet: supercharger poking through a hole
	cb.box_cut(-0.3, 0.3, 0.0, 1.0, 1.18, 1.68, reveal="Trim", shell=cab)
	blower(cb)

	# --- gaps, roof light bar, bolt-ons
	door_bot = -0.62
	cb.gap_side([(0.98, 0.12), (0.98, door_bot), (-0.5, door_bot), (-0.5, 0.14)], shell=cab, n=80)
	cb.gap_top([(-1.08, 1.08), (-1.1, 2.2), (1.1, 2.2), (1.08, 1.08), (-1.08, 1.08)], shell=cab, n=80)
	cb.panel_box("Part_Hood", -1.1, 1.1, 0.0, 1.5, 1.08, 2.2)
	cb.panel_box("Part_BumperFront", -1.4, 1.4, -1.3, -0.45, 2.28, 3.0)
	cb.panel_box("Part_BumperRear", -1.4, 1.4, -1.3, -0.4, -3.0, -2.28)
	for name, sx in (("Part_DoorL", 1.0), ("Part_DoorR", -1.0)):
		x0, x1 = (1.0, 1.6) if sx > 0 else (-1.6, -1.0)
		cb.panel_box(name, x0, x1, door_bot, 0.13, -0.5, 0.98)
	top, _ = cab.top_point(0.0, 0.25)
	bar_y = top.y + 0.07
	cb.add(core.cylinder((-0.85, bar_y, 0.3), (0.85, bar_y, 0.3), 0.025, 0.025, 10, "Trim"))
	for x in (-0.8, 0.8):
		cb.add(core.cylinder((x, bar_y, 0.3), (x * 1.05, top.y - 0.02, 0.15), 0.018, 0.018, 8, "Trim"))
	for k in range(5):
		x = lerp(-0.64, 0.64, k / 4)
		cb.spotlamp((x, bar_y + 0.07, 0.4), (0, 0, 1), 0.085, 0.09)
		cb.add(core.cylinder((x, bar_y, 0.3), (x, bar_y + 0.05, 0.33), 0.015, 0.015, 6, "Trim"))
	for k in range(3):
		x = lerp(-0.25, 0.25, k / 2)
		top, _ = cab.top_point(x, 0.47)
		cb.add(core.superquadric(top + Vector((0, 0.012, 0)), (0.05, 0.016, 0.02), 0.4, 0.4, 8, 4, "Indicator"))
	cb.mirror(0.88, 0.2, out=0.08, rise=0.1, size=(0.11, 0.14, 0.05), mat="Trim")
	cb.handle(-0.36, 0.05, 0.15, "Chrome", shell=cab)
	cb.wipers(ws, [0.42, -0.36], 0.6, 5.0)
	cb.strip_side([(-0.5, -0.66), (0.98, -0.66)], 0.05, 0.01, "Trim", shell=cab)
	# Bold side graphics: a band that sweeps up into a point at the front.
	band_top = [(-2.2, -0.08), (-0.6, -0.02), (0.4, 0.02), (1.2, 0.07), (2.2, 0.06)]
	band_bot = [(-2.2, -0.3), (-0.6, -0.26), (0.4, -0.2), (1.2, -0.06), (2.2, 0.0)]
	cb.stripe_side((band_top, band_bot), "Livery", n=70)
	cb.stripe_side(([(z, y - 0.04) for z, y in band_bot], [(z, y - 0.07) for z, y in band_bot]), "Decal", n=70)

	# --- inside: dash, race seats, roll cage
	cb.interior(0.95, 0.06, 1.0, 0.25, -0.32, 0.45, floor_y=-0.7, wheel_x=0.45)
	cage = [Vector((0.95, -0.7, -0.45)), Vector((0.93, 0.55, -0.45)), Vector((0.8, 0.66, -0.45)), Vector((-0.8, 0.66, -0.45)),
		Vector((-0.93, 0.55, -0.45)), Vector((-0.95, -0.7, -0.45))]
	for p0, p1 in zip(cage[:-1], cage[1:]):
		cb.add(core.cylinder(p0, p1, 0.03, 0.03, 8, "Frame"))
	for side in (1.0, -1.0):
		cb.add(core.cylinder((side * 0.8, 0.66, -0.45), (side * 0.88, 0.62, 0.42), 0.03, 0.03, 8, "Frame"))
		cb.add(core.cylinder((side * 0.88, 0.62, 0.42), (side * 0.95, 0.0, 0.92), 0.03, 0.03, 8, "Frame"))
	cb.add(core.cylinder((0.93, 0.2, -0.45), (-0.93, 0.55, -0.45), 0.028, 0.028, 8, "Frame"))

	chassis(cb)
	cb.extra_objects = suspension()
	return cb


def blower(cb):
	"""Supercharger, intake hat and belt drive sticking up out of the bonnet."""
	cb.add(core.superquadric((0.0, -0.08, 1.4), (0.36, 0.1, 0.36), 0.25, 0.25, 12, 6, "Brake"))
	for side in (1.0, -1.0):
		cb.add(core.superquadric((side * 0.24, 0.02, 1.36), (0.06, 0.05, 0.32), 0.25, 0.35, 8, 6, "Chrome"))
	cb.add(core.superquadric((0.0, 0.13, 1.42), (0.21, 0.13, 0.27), 0.3, 0.2, 14, 8, "Chrome"))
	for k in range(5):
		cb.add(core.box((0.0, 0.13 + lerp(-0.08, 0.08, k / 4), 1.42 - 0.272), (0.19, 0.008, 0.004), "Gap"))
	cb.add(core.box((0.0, 0.272, 1.42), (0.22, 0.014, 0.28), "Brake"))
	cb.add(core.superquadric((0.0, 0.34, 1.42), (0.14, 0.055, 0.2), 0.25, 0.25, 12, 6, "Chrome"))
	cb.add(core.superquadric((0.0, 0.42, 1.42), (0.1, 0.03, 0.17), 0.2, 0.2, 10, 4, "Chrome"))
	for k in range(3):
		z = lerp(1.3, 1.54, k / 2)
		cb.add(core.box((0.0, 0.452, z), (0.075, 0.002, 0.025), "Gap"))
	# Belt drive at the front of the blower.
	cb.add(core.cylinder((0.0, 0.08, 1.72), (0.0, 0.08, 1.76), 0.08, 0.08, 16, "Chrome"))
	cb.add(core.cylinder((0.0, -0.12, 1.72), (0.0, -0.12, 1.76), 0.1, 0.1, 16, "Chrome"))
	for side in (1.0, -1.0):
		cb.add(core.box((side * 0.085, -0.02, 1.74), (0.012, 0.1, 0.022), "Trim"))


def chassis(cb):
	"""Static tube chassis: rails, cross members, body mounts, shock hoops,
	drivetrain and push bars."""
	wy, wz = WHEEL["y"], WHEEL["z"]
	ry = -0.98
	cb.frame_rails(0.42, ry, -2.25, 2.25, h=0.14, w=0.08, mat="Frame")
	for z in (-2.2, -1.0, 0.0, 1.0, 2.2):
		cb.add(core.cylinder((-0.42, ry, z), (0.42, ry, z), 0.04, 0.04, 10, "Frame"))
	for z in (-1.9, -0.65, 0.5, 2.0):
		for side in (1.0, -1.0):
			cb.add(core.cylinder((side * 0.42, ry + 0.07, z), (side * 0.42, -0.74, z), 0.032, 0.032, 8, "Frame"))
			cb.add(core.box((side * 0.42, -0.755, z), (0.06, 0.01, 0.06), "Trim"))
	# Shock hoops: a tube along each corner the shocks hang from, on two legs.
	for ez in (1.0, -1.0):
		for side in (1.0, -1.0):
			zc = ez * wz
			x = side * (SHOCK_X + 0.0)
			top = SHOCK_TOP + 0.035
			cb.add(core.cylinder((x, top, zc - 0.36), (x, top, zc + 0.36), 0.035, 0.035, 10, "Frame"))
			for dz in (-0.36, 0.36):
				cb.add(core.cylinder((x, top, zc + dz), (side * 0.42, ry + 0.07, zc + dz * 1.4), 0.035, 0.035, 10, "Frame"))
			for dz in SHOCK_DZ:
				cb.add(core.box((x, SHOCK_TOP + 0.01, zc + dz), (0.035, 0.03, 0.025), "Frame"))
	# Engine, gearbox, transfer case and drive shafts.
	cb.add(core.superquadric((0.0, -0.62, 1.35), (0.3, 0.24, 0.45), 0.3, 0.3, 12, 8, "Brake"))
	cb.add(core.superquadric((0.0, -0.86, 0.55), (0.16, 0.13, 0.42), 0.4, 0.4, 10, 6, "Brake"))
	cb.add(core.box((0.0, -1.02, 0.0), (0.16, 0.14, 0.16), "Brake"))
	cb.add(core.cylinder((0.0, -1.06, 0.15), (0.18, wy + 0.06, wz - 0.3), 0.04, 0.04, 10, "Chrome"))
	cb.add(core.cylinder((0.0, -1.06, -0.15), (0.18, wy + 0.06, -wz + 0.3), 0.04, 0.04, 10, "Chrome"))
	# Fuel cell and battery boxes under the bed.
	cb.add(core.superquadric((0.0, -0.6, -1.6), (0.32, 0.12, 0.3), 0.2, 0.2, 10, 6, "Trim"))
	# Tubular push bars front and rear.
	for ez in (1.0, -1.0):
		z = ez * 2.38
		for y in (-0.72, -0.98):
			cb.add(core.cylinder((-0.56, y, z), (0.56, y, z), 0.045, 0.045, 12, "Frame"))
		for x in (-0.5, 0.5):
			cb.add(core.cylinder((x, -0.66, z), (x, -1.06, z), 0.045, 0.045, 12, "Frame"))
			cb.add(core.cylinder((x, -0.98, z), (x * 0.84, ry, ez * 2.2), 0.04, 0.04, 10, "Frame"))
			# Tow hooks.
			cb.add(core.box((x * 0.6, -1.06, z + ez * 0.03), (0.02, 0.06, 0.04), "Caliper"))
	cb.add(core.superquadric((0.0, -1.08, 2.0), (0.45, 0.02, 0.36), 0.25, 0.25, 10, 4, "Brake"))


def _mesh_object(name, mb, location):
	obj = mb.build(name, sharp_angle=38.0)
	obj.data.shade_smooth()
	obj.data.set_sharp_from_angle(angle=math.radians(38.0))
	obj.location = Vector(location)
	return obj


def suspension():
	"""Axle and shock objects, each in its own local frame (see module doc)."""
	wy, wz, wx = WHEEL["y"], WHEEL["z"], WHEEL["x"]
	objs = []
	for end, ez in (("F", 1.0), ("R", -1.0)):
		mb = MeshBuilder()
		# Axle tube, knuckles out to the wheel centres (the X extent = track).
		mb.add(core.cylinder((-0.8, 0, 0), (0.8, 0, 0), 0.075, 0.075, 14, "Brake"))
		for sx in (1.0, -1.0):
			mb.add(core.cylinder((sx * 0.62, 0, 0), (sx * 0.8, 0, 0), 0.12, 0.09, 14, "Brake"))
			mb.add(core.cylinder((sx * 0.8, 0, 0), (sx * wx, 0, 0), 0.14, 0.14, 16, "Brake"))
			mb.add(core.cylinder((sx * 0.62, -0.02, 0), (sx * 0.62, 0.2, 0), 0.07, 0.06, 10, "Brake"))
			# Lower shock mounts.
			for dz in SHOCK_DZ:
				mb.add(core.box((sx * SHOCK_X, SHOCK_LOW * 0.5, ez * dz), (0.03, SHOCK_LOW * 0.5, 0.03), "Frame"))
			# Trailing links towards the middle of the chassis.
			for ly in (0.06, -0.08):
				mb.add(core.cylinder((sx * 0.36, ly, 0.0), (sx * 0.42, 0.3 + ly * 0.3, -ez * 0.9), 0.028, 0.028, 8, "Frame"))
		# Differential pumpkin with its cover facing out.
		mb.add(core.superquadric((0.12, 0, 0), (0.2, 0.18, 0.18), 0.7, 0.7, 14, 10, "Brake"))
		mb.add(core.cylinder((0.12, 0, ez * 0.15), (0.12, 0, ez * 0.2), 0.16, 0.13, 18, "Chrome"))
		mb.add(core.cylinder((0.12, 0, 0), (0.12, 0, -ez * 0.26), 0.07, 0.06, 12, "Brake"))
		if end == "F":
			# Tie rod ahead of the axle and steering arms.
			mb.add(core.cylinder((-0.84, -0.06, 0.2), (0.84, -0.06, 0.2), 0.025, 0.025, 8, "Chrome"))
			for sx in (1.0, -1.0):
				mb.add(core.cylinder((sx * 0.84, -0.06, 0.2), (sx * 0.86, 0.0, 0.0), 0.022, 0.022, 6, "Brake"))
			mb.add(core.cylinder((0.3, 0.0, 0.2), (0.3, 0.12, 0.42), 0.03, 0.03, 8, "Chrome"))
		objs.append(_mesh_object("Axle_" + end, mb, (0.0, wy, ez * wz)))
		for side_name, sx in (("L", 1.0), ("R", -1.0)):
			for k, dz in enumerate(SHOCK_DZ):
				top = Vector((sx * SHOCK_X, SHOCK_TOP, ez * (wz + dz)))
				length = top.y - (wy + SHOCK_LOW)
				objs.append(_mesh_object("Shock_%s%s_%d" % (end, side_name, k), shock(length, coil=(k == 0)), top))
	return objs


def shock(length, coil=True):
	"""Coil-over shock hanging from its top mount at the origin, bottom at -length."""
	mb = MeshBuilder()
	L = length
	mb.add(core.cylinder((-0.03, -0.03, 0), (0.03, -0.03, 0), 0.03, 0.03, 10, "Brake"))
	mb.add(core.cylinder((0, -0.05, 0), (0, -0.42 * L, 0), 0.055, 0.055, 14, "Chrome"))
	mb.add(core.cylinder((0, -0.42 * L, 0), (0, -0.45 * L, 0), 0.06, 0.055, 14, "Trim"))
	mb.add(core.cylinder((0, -0.45 * L, 0), (0, -(L - 0.06), 0), 0.022, 0.022, 10, "Chrome"))
	mb.add(core.cylinder((-0.028, -(L - 0.028), 0), (0.028, -(L - 0.028), 0), 0.028, 0.028, 10, "Brake"))
	# Reservoir piggy-backed on the body.
	mb.add(core.cylinder((0.07, -0.08, 0), (0.07, -0.34 * L, 0), 0.03, 0.03, 10, "Trim"))
	if coil:
		turns, per = 6, 10
		y0, y1 = -0.1, -(L - 0.12)
		path = []
		for i in range(turns * per + 1):
			t = i / (turns * per)
			a = t * turns * 2.0 * math.pi
			path.append((math.cos(a) * 0.085, lerp(y0, y1, t), math.sin(a) * 0.085))
		prof = [(math.cos(a) * 0.014, math.sin(a) * 0.014) for a in [2 * math.pi * k / 5 for k in range(5)]]
		mb.add(core.sweep(path, prof, "Caliper"))
		for y in (y0, y1):
			mb.add(core.cylinder((0, y + 0.012, 0), (0, y - 0.012, 0), 0.1, 0.1, 14, "Trim"))
	return mb
