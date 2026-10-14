"""Builds every Derby Game car procedurally with Blender and exports glTF.

Run with Blender's Python module:
	python tools/blender/build_cars.py [--only sedan,van] [--preview] [--no-export]

Writes assets/cars/<style>.glb (body, glass panels and marker empties) and
assets/cars/<style>_wheel.glb (one wheel centred at the origin, axle along X).
With --preview it also renders Cycles previews to /tmp/claude-0/car-previews/.
"""

import argparse
import importlib
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

from carlib import core, preview, wheels  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "cars")
PREVIEW_DIR = "/tmp/claude-0/car-previews"

STYLES = ["van", "sports", "sedan", "pickup", "muscle", "rally", "monster", "super", "police", "hatch"]
# Settled ride height: distance from the body origin down to the road, as
# measured in Godot with the car resting on flat ground.
GROUND = {"van": -1.368, "sports": -0.806, "sedan": -1.017, "pickup": -1.378, "muscle": -0.936, "rally": -1.046, "monster": -2.233,
	"super": -0.779, "police": -1.022, "hatch": -0.992}
# Preview camera distance scale and target height shift for tall vehicles.
PREVIEW_FRAMING = {"monster": (1.3, -0.55)}
PREVIEW_COLOURS = {
	"van": (0.62, 0.22, 0.05), "sports": (0.75, 0.04, 0.03), "sedan": (0.06, 0.16, 0.45), "pickup": (0.5, 0.52, 0.5),
	"muscle": (0.85, 0.5, 0.02), "rally": (0.03, 0.22, 0.6), "monster": (0.08, 0.35, 0.12),
	"super": (0.9, 0.42, 0.02), "police": (0.02, 0.02, 0.025), "hatch": (0.55, 0.62, 0.05),
}

# Livery/decal colours the game picks per car (CarVisuals.build_body).
PREVIEW_DECALS = {"police": {"Livery": (0.85, 0.85, 0.83), "Decal": (0.03, 0.03, 0.035)}}


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	core._materials.clear()


def build_style(style):
	mod = importlib.import_module("cars." + style)
	cb = mod.build()
	body, glass, markers = cb.finish()
	extra = getattr(cb, "extra_objects", []) + cb.panel_objs
	wheel = wheels.build_wheel(style, cb.wheel)
	return cb, body, glass, markers, extra, wheel


def export(objs, path):
	for o in bpy.context.scene.objects:
		o.select_set(False)
	for o in objs:
		o.select_set(True)
	bpy.ops.export_scene.gltf(
		filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
		export_texcoords=False, export_normals=True, export_materials="EXPORT", export_cameras=False,
		export_lights=False, export_animations=False, export_extras=False,
	)


def place_preview_wheels(style, wheel_objs, w):
	copies = []
	for sx in (1.0, -1.0):
		for sz in (1.0, -1.0):
			for src in wheel_objs:
				c = src.copy()
				c.data = src.data
				bpy.context.scene.collection.objects.link(c)
				rot = Matrix.Rotation(0.0 if sx > 0 else math.pi, 4, "Z")
				c.matrix_world = Matrix.Translation(core.g2b((sx * w["x"], w["y"], sz * w["z"]))) @ rot
				copies.append(c)
	return copies


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--only", default="")
	ap.add_argument("--preview", action="store_true")
	ap.add_argument("--views", default="front34,side,rear34")
	ap.add_argument("--samples", type=int, default=40)
	ap.add_argument("--no-export", action="store_true")
	ap.add_argument("--debug-normals", action="store_true")
	ap.add_argument("--res", default="640x400")
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
	args = ap.parse_args(argv)
	styles = [s for s in args.only.split(",") if s] or STYLES
	os.makedirs(OUT_DIR, exist_ok=True)
	os.makedirs(PREVIEW_DIR, exist_ok=True)
	stats = {}
	for style in styles:
		t0 = time.time()
		reset()
		cb, body, glass, markers, extra, wheel = build_style(style)
		tris = core.tri_count(body) + sum(core.tri_count(g) for g in glass) + sum(core.tri_count(e) for e in extra if e.type == "MESH")
		wtris = sum(core.tri_count(o) for o in wheel)
		empties = []
		for name, pos in markers.items():
			e = bpy.data.objects.new(name, None)
			bpy.context.scene.collection.objects.link(e)
			e.location = pos
			empties.append(e)
		all_body = [body] + glass + extra + empties
		core.bake_to_blender(all_body + wheel)
		if not args.no_export:
			export(all_body, os.path.join(OUT_DIR, style + ".glb"))
			export(wheel, os.path.join(OUT_DIR, style + "_wheel.glb"))
		print("[%s] body %d tris, wheel %d tris, built in %.1fs" % (style, tris, wtris, time.time() - t0))
		stats[style] = {"body_tris": tris, "wheel_tris": wtris}
		if args.preview:
			core.set_paint_colour(PREVIEW_COLOURS[style])
			for mat_name, rgb in PREVIEW_DECALS.get(style, {}).items():
				core.set_paint_colour(rgb, mat_name)
			copies = place_preview_wheels(style, wheel, cb.wheel)
			for o in wheel:
				o.hide_render = True
			preview.setup_scene(GROUND[style], samples=args.samples, res=tuple(int(v) for v in args.res.split("x")))
			if args.debug_normals:
				preview.debug_backfaces()
			scale, dy = PREVIEW_FRAMING.get(style, (1.0, 0.0))
			preview.render_views(os.path.join(PREVIEW_DIR, style), args.views.split(","), scale, GROUND[style], dy)
	if not args.no_export:
		with open(os.path.join(HERE, "last_build_stats.json"), "w") as f:
			json.dump(stats, f, indent=1)


if __name__ == "__main__":
	main()
