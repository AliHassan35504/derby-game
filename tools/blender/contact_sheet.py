"""Tiles the preview renders of every car into one contact sheet.

Run after build_cars.py --preview:
	python tools/blender/contact_sheet.py [--views front34,side,rear34] [--scale 0.5]

Rows are cars (in build_cars.STYLES order), columns are views. Writes
/tmp/claude-0/car-previews/contact_sheet.png.
"""

import argparse
import os
import sys

import bpy
import numpy as np

PREVIEW_DIR = "/tmp/claude-0/car-previews"
STYLES = ["van", "sports", "sedan", "pickup", "muscle", "rally", "monster"]


def load(path):
	img = bpy.data.images.load(path)
	w, h = img.size
	px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
	bpy.data.images.remove(img)
	return px


def shrink(px, scale):
	step = max(1, int(round(1.0 / scale)))
	h, w = px.shape[0] // step * step, px.shape[1] // step * step
	px = px[:h, :w]
	return px.reshape(h // step, step, w // step, step, 4).mean(axis=(1, 3))


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--views", default="front34,side,rear34")
	ap.add_argument("--scale", type=float, default=0.5)
	argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
	args = ap.parse_args(argv)
	views = args.views.split(",")
	rows = []
	for style in STYLES:
		tiles = []
		for view in views:
			path = os.path.join(PREVIEW_DIR, "%s_%s.png" % (style, view))
			if not os.path.exists(path):
				print("missing", path)
				continue
			tiles.append(shrink(load(path), args.scale))
		if tiles:
			h = min(t.shape[0] for t in tiles)
			rows.append(np.concatenate([t[:h] for t in tiles], axis=1))
	width = max(r.shape[1] for r in rows)
	rows = [np.pad(r, ((0, 0), (0, width - r.shape[1]), (0, 0)), constant_values=1.0) for r in rows]
	# Rows were loaded bottom-up (Blender images start at the bottom left).
	sheet = np.concatenate(rows[::-1], axis=0)
	h, w = sheet.shape[:2]
	out = bpy.data.images.new("contact_sheet", w, h, alpha=True)
	out.pixels[:] = sheet.ravel()
	out.filepath_raw = os.path.join(PREVIEW_DIR, "contact_sheet.png")
	out.file_format = "PNG"
	out.save()
	print("wrote", out.filepath_raw, w, h)


if __name__ == "__main__":
	main()
