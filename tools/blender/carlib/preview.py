"""Cycles preview renders of a built car (CPU, small, denoised)."""

import math

import bpy
from mathutils import Matrix, Vector

from . import core


def setup_scene(ground_y, samples=40, res=(640, 400)):
	sc = bpy.context.scene
	sc.render.engine = "CYCLES"
	sc.cycles.device = "CPU"
	sc.cycles.samples = samples
	sc.cycles.use_denoising = True
	try:
		sc.cycles.denoiser = "OPENIMAGEDENOISE"
	except TypeError:
		pass
	sc.cycles.max_bounces = 6
	sc.cycles.transmission_bounces = 6
	sc.cycles.glossy_bounces = 3
	sc.render.resolution_x, sc.render.resolution_y = res
	sc.render.resolution_percentage = 100
	sc.render.film_transparent = False
	try:
		sc.view_settings.view_transform = "AgX"
		sc.view_settings.look = "AgX - Medium High Contrast"
	except TypeError:
		pass

	world = bpy.data.worlds.new("Sky") if not sc.world else sc.world
	sc.world = world
	world.use_nodes = True
	nt = world.node_tree
	nt.nodes.clear()
	out = nt.nodes.new("ShaderNodeOutputWorld")
	bg = nt.nodes.new("ShaderNodeBackground")
	tc = nt.nodes.new("ShaderNodeTexCoord")
	sep = nt.nodes.new("ShaderNodeSeparateXYZ")
	ramp = nt.nodes.new("ShaderNodeValToRGB")
	nt.links.new(tc.outputs["Generated"], sep.inputs[0])
	maprange = nt.nodes.new("ShaderNodeMapRange")
	maprange.inputs["From Min"].default_value = -1.0
	maprange.inputs["From Max"].default_value = 1.0
	nt.links.new(sep.outputs["Z"], maprange.inputs["Value"])
	nt.links.new(maprange.outputs["Result"], ramp.inputs["Fac"])
	cr = ramp.color_ramp
	cr.elements[0].position = 0.0
	cr.elements[0].color = (0.05, 0.05, 0.05, 1)
	cr.elements[1].position = 0.49
	cr.elements[1].color = (0.32, 0.3, 0.28, 1)
	e = cr.elements.new(0.505)
	e.color = (0.95, 0.97, 1.0, 1)
	e = cr.elements.new(0.6)
	e.color = (0.55, 0.68, 0.9, 1)
	e = cr.elements.new(1.0)
	e.color = (0.18, 0.35, 0.75, 1)
	nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
	bg.inputs["Strength"].default_value = 1.0
	nt.links.new(bg.outputs[0], out.inputs["Surface"])

	# Ground: a large asphalt-ish plane plus a faint grid of paint lines.
	mb = core.MeshBuilder()
	s = 60.0
	mb.f((mb.v((-s, ground_y, -s)), mb.v((-s, ground_y, s)), mb.v((s, ground_y, s)), mb.v((s, ground_y, -s))), "PreviewGround", False)
	ground = mb.build("PreviewGround")
	gm = core.material("PreviewGround")
	bsdf = gm.node_tree.nodes["Principled BSDF"]
	bsdf.inputs["Base Color"].default_value = (0.16, 0.16, 0.165, 1.0)
	bsdf.inputs["Roughness"].default_value = 0.55
	core.bake_to_blender([ground])

	sun_data = bpy.data.lights.new("Sun", "SUN")
	sun_data.energy = 3.2
	sun_data.angle = math.radians(3.0)
	sun = bpy.data.objects.new("Sun", sun_data)
	sc.collection.objects.link(sun)
	sun.rotation_euler = Vector((0.0, 0.0, 1.0)).rotation_difference(Vector((0.55, -0.45, 0.7)).normalized()).to_euler()

	area_data = bpy.data.lights.new("Soft", "AREA")
	area_data.energy = 900.0
	area_data.size = 6.0
	area = bpy.data.objects.new("Soft", area_data)
	sc.collection.objects.link(area)
	area.location = core.g2b((-3.0, ground_y + 6.0, 5.0))
	area.rotation_euler = (Vector((0, 0, -1))).rotation_difference((core.g2b((0, ground_y, 0)) - area.location).normalized()).to_euler()
	return ground


def camera(name, pos, target, lens=50.0):
	cam_data = bpy.data.cameras.new(name)
	cam_data.lens = lens
	cam_data.clip_start = 0.05
	cam = bpy.data.objects.new(name, cam_data)
	bpy.context.scene.collection.objects.link(cam)
	p = core.g2b(pos)
	t = core.g2b(target)
	cam.location = p
	d = (t - p).normalized()
	cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
	return cam


def render(cam, path):
	sc = bpy.context.scene
	sc.camera = cam
	sc.render.filepath = path
	bpy.ops.render.render(write_still=True)


STANDARD_VIEWS = {
	# name: (camera position offset from car centre, target offset, lens)
	"front34": ((5.2, 1.3, 6.4), (0.0, -0.2, 0.15), 42.0),
	"side": ((11.0, 0.1, 0.0), (0.0, -0.15, 0.0), 58.0),
	"rear34": ((-5.2, 1.6, -6.2), (0.0, -0.2, -0.1), 42.0),
	"low": ((3.6, -0.55, 4.6), (0.0, -0.3, 0.0), 30.0),
	"top": ((4.0, 6.0, 4.0), (0.0, -0.3, 0.0), 40.0),
	"front": ((0.0, 0.4, 9.0), (0.0, -0.2, 0.0), 50.0),
	"rear": ((0.0, 0.6, -9.0), (0.0, -0.2, 0.0), 50.0),
	"interior": ((1.8, 0.6, 0.6), (0.0, 0.0, -0.1), 28.0),
}


def render_views(prefix, views, scale=1.0, ground_y=-1.0, target_dy=0.0):
	paths = []
	for name in views:
		pos, tgt, lens = STANDARD_VIEWS[name]
		pos = Vector(pos) * scale + Vector((0.0, target_dy, 0.0))
		tgt = Vector(tgt) + Vector((0.0, target_dy, 0.0))
		pos.y = max(pos.y, ground_y + 0.25 - 0.0)
		cam = camera("Cam_" + name, pos, Vector(tgt), lens)
		path = "%s_%s.png" % (prefix, name)
		render(cam, path)
		paths.append(path)
	return paths


def debug_backfaces():
	"""Show back faces in bright red so wrong winding is easy to spot."""
	for mat in bpy.data.materials:
		if not mat.use_nodes or mat.name.startswith("PreviewGround"):
			continue
		nt = mat.node_tree
		out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None)
		bsdf = nt.nodes.get("Principled BSDF")
		if out is None or bsdf is None:
			continue
		geo = nt.nodes.new("ShaderNodeNewGeometry")
		em = nt.nodes.new("ShaderNodeEmission")
		em.inputs["Color"].default_value = (1.0, 0.0, 0.0, 1.0)
		em.inputs["Strength"].default_value = 2.0
		mix = nt.nodes.new("ShaderNodeMixShader")
		nt.links.new(geo.outputs["Backfacing"], mix.inputs[0])
		nt.links.new(bsdf.outputs[0], mix.inputs[1])
		nt.links.new(em.outputs[0], mix.inputs[2])
		nt.links.new(mix.outputs[0], out.inputs["Surface"])
		bsdf.inputs["Transmission Weight"].default_value = 0.0
