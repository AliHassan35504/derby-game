"""Ranger Pickup: a lifted full-size crew-cab pickup with an open bed."""

from mathutils import Vector

from carlib import core, parts
from carlib.builder import CarBuilder
from carlib.core import lerp

SIZE = (2.1, 1.8, 5.2)
WHEEL = dict(r=0.44, w=0.34, x=0.931, y=-0.978, z=1.664)

CAB = dict(
	z=(-0.64, 2.6),
	yt=[(-0.64, 0.7), (-0.62, 0.84), (-0.57, 0.875), (0.7, 0.885), (0.8, 0.86), (1.28, 0.33), (1.34, 0.295),
		(1.5, 0.285), (2.3, 0.27), (2.5, 0.235), (2.6, 0.1)],
	yb=[(-0.64, -0.7), (-0.6, -0.86), (2.2, -0.86), (2.5, -0.76), (2.6, -0.55)],
	ym=[(-0.64, -0.3), (2.6, -0.3)],
	ys=[(-0.64, 0.24), (-0.58, 0.31), (0.8, 0.31), (1.3, 0.265), (2.3, 0.24), (2.6, 0.05)],
	w=[(-0.64, 1.04), (-0.5, 1.05), (2.2, 1.05), (2.6, 1.03)],
	wsh=[(-0.64, 1.03), (-0.5, 1.04), (2.2, 1.04), (2.6, 1.02)],
	wg=[(-0.64, 0.99), (-0.5, 0.985), (1.2, 0.985), (1.36, 1.03), (2.6, 1.01)],
	wr=[(-0.64, 0.9), (-0.5, 0.9), (0.8, 0.9), (1.3, 0.96), (2.6, 0.96)],
	nb=5.0,
	nu=[(-0.6, 4.0), (1.2, 4.0), (1.4, 4.5)],
	cr=0.13,
	bulge=0.01,
	ledge_h=0.018,
	front=dict(R=0.16, k=3.6, rake=-0.04, yref=-0.55),
	rear=dict(R=0.06, k=4.0),
	stations=80,
	extra_z=[0.02, 0.14],
)

BED = dict(
	z=(-2.6, -0.68),
	yt=[(-2.6, 0.27), (-2.58, 0.305), (-0.7, 0.305), (-0.68, 0.27)],
	yb=[(-2.6, -0.62), (-2.54, -0.82), (-0.72, -0.82), (-0.68, -0.7)],
	ym=-0.3,
	ys=0.27,
	w=1.05,
	wsh=1.045,
	wg=1.04,
	wr=1.0,
	nb=5.0,
	nu=4.0,
	cr=0.04,
	bulge=0.0,
	front=dict(R=0.05, k=4.0),
	rear=dict(R=0.07, k=4.0),
	stations=56,
	nc=10,
)


def build():
	cb = CarBuilder("pickup", SIZE, WHEEL, CAB)
	cab = cb.body
	bed = cb.add_shell(BED, "Bed")
	wy, wz, wr = WHEEL["y"], WHEEL["z"], WHEEL["r"]
	flare = dict(width=0.1, height=0.045, mat="Trim", angles=(-4.0, 184.0))
	cb.arch(wz, wy + 0.06, wr + 0.065, n_exp=2.3, flare=flare, shell=cab)
	cb.arch(-wz, wy + 0.06, wr + 0.065, n_exp=2.3, flare=flare, shell=bed)

	# --- bed
	cb.box_cut(-0.975, 0.975, -0.4, 1.5, -2.53, -0.75, reveal="Paint", shell=bed)
	cb.bed_tub(0.972, -0.4, 0.285, -2.528, -0.752)
	for side in (1.0, -1.0):
		cb.add(core.box((side * 1.01, 0.315, -1.64), (0.045, 0.012, 0.9), "Trim"))
	cb.add(core.box((0.0, 0.315, -2.565), (1.04, 0.012, 0.04), "Trim"))

	# --- glass
	ws = cb.top_window(0.84, 1.28, "Front", side_gap=0.06, radius=0.05)
	cb.side_window(0.14, 1.26, "F", top_gap=0.06, belt_gap=0.025)
	cb.side_window(-0.52, 0.02, "B", top_gap=0.06, belt_gap=0.025)
	cb.blackout(0.02, 0.14, top_gap=0.06, belt_gap=0.025)
	hit, nrm = cab.front_point(0.0, 0.6, front=False)
	cb.flat_window(core.round_polygon(parts.rect(1.5, 0.36), 0.06, 3), hit, (0, 0, -1), "Back", reveal="Trim", round_r=0.0)

	# --- front: big grille, headlights, steel bumper, fog lamps
	hit, nrm = cab.front_point(0.0, -0.06)
	cb.grille(parts.rect(1.18, 0.42), hit, Vector((0, 0, 1)), "egg", "Chrome", 4, 0.08, 0.016, reveal="Chrome", round_r=0.05)
	for x in (0.83,):
		hit, nrm = cab.front_point(x, 0.06)
		cb.lamp([(-0.14, -0.1), (0.15, -0.1), (0.17, 0.0), (0.15, 0.1), (-0.14, 0.1)], hit, (nrm + Vector((0, 0, 1))).normalized(), "Glass",
			[("disc", (-0.04, 0.02), 0.055, "Headlight"), ("bar", (0.05, -0.065), (0.2, 0.025), "Indicator")],
			depth=0.08, reveal="Chrome", housing="Chrome", back_mat="Trim", round_r=0.03)
	cb.bumper(True, -0.62, -0.38, kind="blade", mat="Trim", theta=70.0, back=0.6, gap=0.03, thick=0.1)
	for x in (0.72, -0.72):
		cb.spotlamp((x, -0.5, cab.z1 + 0.14), (0, 0, 1), 0.055, 0.05)
	cb.plate(Vector((0.0, -0.5, cab.z1 + 0.135)), (0, 0, 1), "RNG 350", size=(0.5, 0.12))
	for x in (0.42, -0.42):
		cb.add(core.superquadric((x, -0.66, cab.z1 + 0.1), (0.035, 0.035, 0.06), 0.4, 0.4, 8, 6, "Caliper"))

	# --- rear: vertical tail lights on the bed, tailgate, step bumper, hitch
	for x in (0.97,):
		hit, nrm = bed.front_point(x, 0.0, front=False)
		cb.lamp(parts.rect(0.12, 0.4), hit, (nrm + Vector((0, 0, -1.2))).normalized(), "Taillight",
			[("bar", (0.0, 0.08), (0.08, 0.18), "Taillight"), ("bar", (0.0, -0.12), (0.08, 0.1), "Chrome")],
			depth=0.04, reveal="Chrome", housing="Chrome", back_mat="Taillight", round_r=0.015, shell=bed)
	cb.gap_dir([(-0.86, 0.28, -2.7), (-0.86, -0.56, -2.7), (0.86, -0.56, -2.7), (0.86, 0.28, -2.7)], (0, 0, 1), shell=bed, n=60)
	cb.add(core.superquadric((0.0, 0.05, -2.615), (0.1, 0.04, 0.01), 0.3, 0.3, 8, 4, "Trim"))
	cb.bumper(False, -0.66, -0.48, kind="blade", mat="Chrome", theta=60.0, back=0.5, gap=0.03, thick=0.08, shell=bed)
	cb.plate(Vector((0.0, -0.36, bed.z0 - 0.012)), (0, 0, -1), "RNG 350", size=(0.5, 0.12))
	cb.add(core.box((0.0, -0.66, bed.z0 - 0.2), (0.05, 0.05, 0.14), "Trim"))
	cb.add(core.superquadric((0.0, -0.58, bed.z0 - 0.3), (0.035, 0.035, 0.035), 1.0, 1.0, 10, 6, "Chrome"))
	cb.exhaust(-0.6, -0.86, -2.3, 0.05, 0.3)

	# --- gaps, roof marker lights, bolt-ons
	door_bot = -0.74
	cb.gap_side([(1.3, 0.27), (1.3, door_bot), (-0.56, door_bot), (-0.56, 0.3)], shell=cab, n=80)
	cb.gap_side([(0.08, 0.31), (0.08, door_bot)], shell=cab)
	cb.gap_top([(-0.92, 1.36), (-0.94, 2.45), (0.94, 2.45), (0.92, 1.36), (-0.92, 1.36)], shell=cab, n=80)
	for k in range(5):
		x = lerp(-0.45, 0.45, k / 4)
		top, _ = cab.top_point(x, 0.66)
		cb.add(core.superquadric(top + Vector((0, 0.012, 0)), (0.04, 0.015, 0.02), 0.4, 0.4, 8, 4, "Indicator"))
	cb.mirror(1.22, 0.33, out=0.07, rise=0.08, size=(0.1, 0.12, 0.05), mat="Trim")
	cb.handle(0.95, 0.2, 0.14, "Trim", shell=cab)
	cb.handle(-0.15, 0.22, 0.14, "Trim", shell=cab)
	cb.wipers(ws, [0.38, -0.32], 0.55, 5.0)
	for side in (1.0, -1.0):
		cb.add(core.box((side * 1.0, -0.94, 0.42), (0.11, 0.02, 0.78), "Trim"))
		for z in (-0.1, 0.9):
			cb.add(core.box((side * 0.94, -0.9, z), (0.03, 0.04, 0.03), "Trim"))
	cb.strip_side([(-0.55, -0.55), (1.28, -0.55)], 0.04, 0.008, "Trim", shell=cab)

	# --- inside and underneath
	cb.interior(1.08, 0.18, 0.9, 0.42, -0.2, 0.45, rear_z=-0.18, rear_w=1.6, floor_y=-0.75, wheel_x=0.45)
	cb.underbody(-0.83, -2.4, 2.3, 0.55, -0.5, -2.3, tank_z=-0.3, axle_y=wy, axle_z=(wz, -wz), axle_x=0.78, diff_z=-wz, muffler_z=-1.2)
	return cb
