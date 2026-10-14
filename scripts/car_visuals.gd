class_name CarVisuals
extends RefCounted
## Builds the visible model for each car type from the generated glTF models
## in assets/cars (see tools/blender/build_cars.py), restyles their materials
## by name, and dents the body where the car gets hit. Bumpers, bonnet and
## front doors (Part_* nodes) break off as debris after enough hits near them.
## Returns the paint material so the car can darken it as it takes damage.
## Falls back to simple box bodies when a model is missing.

const MODEL_DIR := "res://assets/cars/"
const MODEL_NODE := "CarModel"
## Furthest a body vertex can be pushed in from its original place (m).
const MAX_DENT := 0.2
## Spatial hash cell size for finding vertices near an impact (m).
const DENT_CELL := 0.4
## Accumulated hit strength (m/s, weighted by distance) that tears a panel off.
const PART_BREAK := 15.0
## Hits further than this from a panel's bounds do not count against it (m).
const PART_REACH := 0.7
## Panels that can come off one car, and how long the debris lasts (s).
const MAX_DEBRIS := 3
const DEBRIS_LIFE := 8.0
## Debris lives on its own physics layer and only collides with the world
## (layer 1), so cars (layer 2) drive through it instead of tripping on it.
const DEBRIS_LAYER := 4
const LIGHT_MATERIALS := ["Headlight", "HeadLens", "Taillight", "TailLens"]

const RIM_COLORS := {
	"sedan": Color(0.72, 0.73, 0.75), "sports": Color(0.16, 0.16, 0.17), "muscle": Color(0.9, 0.9, 0.92),
	"van": Color(0.88, 0.88, 0.9), "pickup": Color(0.3, 0.3, 0.32), "rally": Color(0.92, 0.92, 0.9),
	"monster": Color(0.07, 0.07, 0.075), "super": Color(0.1, 0.1, 0.11), "police": Color(0.05, 0.05, 0.055),
	"hatch": Color(0.82, 0.82, 0.84),
}
const CALIPER_COLORS := {
	"sports": Color(0.8, 0.06, 0.04), "rally": Color(0.95, 0.75, 0.05), "muscle": Color(0.12, 0.12, 0.13),
	"monster": Color(0.85, 0.08, 0.05), "super": Color(0.95, 0.72, 0.05), "police": Color(0.2, 0.2, 0.22),
	"hatch": Color(0.85, 0.1, 0.06),
}

static var _scenes := {}
static var _materials := {}
static var _crack_texture: ImageTexture


static func build_body(car: Node3D, style: String, size: Vector3, color: Color) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.metallic = 0.45
	paint.metallic_specular = 0.6
	paint.roughness = 0.3
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	paint.clearcoat_roughness = 0.08

	var scene := _load_scene(style)
	if scene == null:
		_build_box_body(car, style, size, paint)
		return paint
	var model: Node3D = scene.instantiate()
	model.name = MODEL_NODE
	car.add_child(model)
	var decal := _decal_material(color, false)
	var livery := _decal_material(color, true)
	if style == "police":
		# Black-and-white: white doors and roof on dark paint, or the other
		# way round on a light car, with contrasting lettering.
		var light := color.get_luminance() > 0.45
		livery.albedo_color = Color(0.06, 0.06, 0.07) if light else Color(0.94, 0.94, 0.92)
		decal.albedo_color = Color(0.94, 0.94, 0.92) if light else Color(0.05, 0.05, 0.06)
	var flasher: LightbarFlasher
	for mi in _mesh_instances(model):
		var names := _surface_names(mi)
		for i in names.size():
			var mat_name: String = names[i]
			match mat_name:
				"Paint":
					mi.set_surface_override_material(i, paint)
				"Decal":
					mi.set_surface_override_material(i, decal)
				"Livery":
					mi.set_surface_override_material(i, livery)
				"LightbarRed", "LightbarBlue":
					# Own material per car so each light bar flashes on its own.
					var lamp := _shared_material(mat_name, style).duplicate() as StandardMaterial3D
					mi.set_surface_override_material(i, lamp)
					if flasher == null:
						flasher = LightbarFlasher.new()
						flasher.name = "LightbarFlasher"
						flasher.car = car
					if mat_name == "LightbarRed":
						flasher.red.append(lamp)
					else:
						flasher.blue.append(lamp)
				_:
					mi.set_surface_override_material(i, _shared_material(mat_name, style))
	if flasher:
		car.add_child(flasher)
	if style == "monster":
		var rig := SuspensionRig.new()
		rig.name = "SuspensionRig"
		rig.model = model
		car.add_child(rig)
	return paint


static func build_wheel(radius: float, width: float, style: String) -> Node3D:
	var scene := _load_scene(style + "_wheel")
	if scene == null:
		return _build_box_wheel(radius, width, style)
	var root := WheelVisual.new()
	var model: Node3D = scene.instantiate()
	root.add_child(model)
	var aabb := AABB()
	var wheel_mesh: MeshInstance3D = model.get_node_or_null("Wheel")
	if wheel_mesh:
		aabb = wheel_mesh.mesh.get_aabb()
	var size := aabb.size
	var s := Vector3.ONE
	if size.y > 0.01 and size.x > 0.01:
		s = Vector3(width / size.x, 2.0 * radius / size.y, 2.0 * radius / size.y)
	model.scale = s
	for mi in _mesh_instances(model):
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			mi.set_surface_override_material(i, _shared_material(src.resource_name if src else "", style))
	var caliper := model.get_node_or_null("Caliper") as Node3D
	if caliper:
		root.caliper = caliper
	return root


static func build_nitro_flames(car: Node3D, size: Vector3) -> GPUParticles3D:
	var flames := GPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.25
	flames.emitting = false
	flames.local_coords = false
	flames.position = Vector3(0, -size.y * 0.15, -size.z * 0.5 - 0.1)
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 0, -1)
	proc.spread = 8.0
	proc.initial_velocity_min = 6.0
	proc.initial_velocity_max = 9.0
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.5
	proc.scale_max = 1.0
	# Shoot the flames out of the model's exhaust tips when it has them.
	var tips: Array[Vector3] = []
	var model := car.get_node_or_null(MODEL_NODE)
	if model:
		for child in model.get_children():
			if child is Node3D and not child is MeshInstance3D and String(child.name).begins_with("Exhaust"):
				tips.append((child as Node3D).position)
	if tips.size() == 1:
		flames.position = tips[0]
	elif tips.size() > 1:
		var centre := Vector3.ZERO
		for tip in tips:
			centre += tip
		centre /= tips.size()
		flames.position = centre
		var img := Image.create(tips.size(), 1, false, Image.FORMAT_RGBF)
		for i in tips.size():
			var p := tips[i] - centre
			img.set_pixel(i, 0, Color(p.x, p.y, p.z))
		proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINTS
		proc.emission_point_texture = ImageTexture.create_from_image(img)
		proc.emission_point_count = tips.size()
		flames.amount = 30 * tips.size()
	flames.process_material = proc
	var puff := SphereMesh.new()
	puff.radius = 0.12 if tips.size() > 0 else 0.16
	puff.height = puff.radius * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.55, 1.0)
	mat.emission_energy_multiplier = 6.0
	puff.material = mat
	flames.draw_pass_1 = puff
	car.add_child(flames)
	return flames


## Called on a damaging car-to-car hit. dv is the car's change in velocity
## (global). Dents the body at the contact point, cracks the nearest window on
## heavy hits and knocks out the lights at the struck end.
static func apply_impact(car: RigidBody3D, dv: Vector3) -> void:
	var model := car.get_node_or_null(MODEL_NODE) as Node3D
	if model == null:
		return
	var strength := dv.length()
	var push := car.global_basis.inverse() * dv.normalized()
	var point := _contact_point(car, -push)
	dent(car, point, push, strength)
	_damage_parts(car, model, model.transform.affine_inverse() * point, strength)


## Push the body in around local_point (car space) along push, harder for
## larger strength (m/s of impact).
static func dent(car: Node3D, local_point: Vector3, push: Vector3, strength: float) -> void:
	var model := car.get_node_or_null(MODEL_NODE) as Node3D
	if model == null or strength < 1.0:
		return
	var radius := clampf(0.3 + strength * 0.035, 0.3, 0.75)
	var depth := clampf((strength - 1.5) * 0.014, 0.006, 0.11)
	var dir := push.normalized()
	var to_model := model.transform.affine_inverse()
	var p := to_model * local_point
	var d := (to_model.basis * dir).normalized()
	for mi in _mesh_instances(model):
		_dent_mesh(mi, mi.transform.affine_inverse() * p, (mi.transform.basis.inverse() * d).normalized(), radius, depth)
	if strength > 7.0:
		_crack_glass(model, p)
	if strength > 6.0:
		_break_lights(model, p)


# --- denting -----------------------------------------------------------------


static func _dent_mesh(mi: MeshInstance3D, p: Vector3, dir: Vector3, radius: float, depth: float) -> void:
	var data := _dent_data(mi)
	var aabbs: Array = data["aabbs"]
	var grids: Array = data["grids"]
	var surfaces: Array = data["arrays"]
	var originals: Array = data["orig"]
	var changed := false
	for s in surfaces.size():
		var box: AABB = aabbs[s]
		if not box.grow(radius).has_point(p):
			continue
		var arrays: Array = surfaces[s]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var orig: PackedVector3Array = originals[s]
		var grid: Dictionary = grids[s]
		var c0 := Vector3i(((p - Vector3.ONE * radius) / DENT_CELL).floor())
		var c1 := Vector3i(((p + Vector3.ONE * radius) / DENT_CELL).floor())
		for cx in range(c0.x, c1.x + 1):
			for cy in range(c0.y, c1.y + 1):
				for cz in range(c0.z, c1.z + 1):
					var key := Vector3i(cx, cy, cz)
					if not grid.has(key):
						continue
					for i: int in grid[key]:
						var v := verts[i]
						var dist := v.distance_to(p)
						if dist >= radius:
							continue
						var u := 1.0 - dist / radius
						var f := u * u * (3.0 - 2.0 * u)
						var moved := v + dir * depth * f
						var off := moved - orig[i]
						if off.length() > MAX_DENT:
							moved = orig[i] + off.normalized() * MAX_DENT
						verts[i] = moved
						# Tilt the normal down the slope of the dent.
						var n := norms[i]
						var into := -dir.dot(n)
						var t := moved - p
						t -= n * t.dot(n)
						if into > 0.0 and t.length_squared() > 1e-8:
							var slope := depth * 6.0 * u * (1.0 - u) / radius
							norms[i] = (n - t.normalized() * slope * into).normalized()
						changed = true
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
	if not changed:
		return
	var mesh: ArrayMesh = data["mesh"]
	var mats: Array = data["mats"]
	mesh.clear_surfaces()
	for s in surfaces.size():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s])
		mi.set_surface_override_material(s, mats[s])


## Per-instance copy of the mesh arrays, made on the first dent so cars only
## pay for a private mesh once they are actually hit.
static func _dent_data(mi: MeshInstance3D) -> Dictionary:
	if mi.has_meta("dent_data"):
		return mi.get_meta("dent_data")
	var src: Mesh = mi.mesh
	var surfaces := []
	var originals := []
	var aabbs := []
	var grids := []
	var mats := []
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		# Keep positions, normals and indices; drop tangents and the rest.
		var keep := []
		keep.resize(Mesh.ARRAY_MAX)
		keep[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
		keep[Mesh.ARRAY_NORMAL] = arrays[Mesh.ARRAY_NORMAL]
		keep[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		surfaces.append(keep)
		var verts: PackedVector3Array = keep[Mesh.ARRAY_VERTEX]
		originals.append(verts.duplicate())
		var grid := {}
		var box := AABB(verts[0] if verts.size() > 0 else Vector3.ZERO, Vector3.ZERO)
		for i in verts.size():
			var key := Vector3i((verts[i] / DENT_CELL).floor())
			if not grid.has(key):
				grid[key] = PackedInt32Array()
			var cell: PackedInt32Array = grid[key]
			cell.append(i)
			grid[key] = cell
			box = box.expand(verts[i])
		grids.append(grid)
		aabbs.append(box)
		mats.append(mi.get_surface_override_material(s))
	var mesh := ArrayMesh.new()
	for s in surfaces.size():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[s])
	mi.mesh = mesh
	for s in mats.size():
		mi.set_surface_override_material(s, mats[s])
	var data := {"mesh": mesh, "arrays": surfaces, "orig": originals, "aabbs": aabbs, "grids": grids, "mats": mats}
	mi.set_meta("dent_data", data)
	return data


static func _contact_point(car: RigidBody3D, towards: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(car.get_rid())
	if state:
		var best := Vector3.ZERO
		var count := 0
		for i in state.get_contact_count():
			if state.get_contact_collider_object(i) is VehicleBody3D:
				best += car.to_local(state.get_contact_local_position(i))
				count += 1
		if count > 0:
			return best / count
	# No contact reported: aim at the box face pointing towards the hitter.
	var size := Vector3(2, 1.4, 4.6)
	var shape := car.get_node_or_null("CollisionShape3D") as CollisionShape3D
	for child in car.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			size = (child.shape as BoxShape3D).size
			break
	var t := INF
	for axis in 3:
		if absf(towards[axis]) > 1e-4:
			t = minf(t, size[axis] * 0.5 / absf(towards[axis]))
	return towards * (t if t < INF else 1.0)


static func _crack_glass(model: Node3D, p: Vector3) -> void:
	var best: MeshInstance3D
	var best_d := 1.4
	for mi in _mesh_instances(model):
		if not String(mi.name).begins_with("Glass") or mi.has_meta("cracked"):
			continue
		var d := mi.mesh.get_aabb().get_center().distance_to(p)
		if d < best_d:
			best_d = d
			best = mi
	if best:
		best.set_meta("cracked", true)
		best.set_surface_override_material(0, _shared_material("CrackedGlass", ""))
		if best.has_meta("dent_data"):
			var mats: Array = best.get_meta("dent_data")["mats"]
			mats[0] = best.get_surface_override_material(0)


static func _break_lights(model: Node3D, p: Vector3) -> void:
	var body := model.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var aabb: AABB = body.get_meta("rest_aabb", body.mesh.get_aabb())
	body.set_meta("rest_aabb", aabb)
	var front := p.z > aabb.get_center().z + aabb.size.z * 0.3
	var rear := p.z < aabb.get_center().z - aabb.size.z * 0.3
	if not front and not rear:
		return
	var targets := ["Headlight", "HeadLens"] if front else ["Taillight", "TailLens"]
	for mi in _mesh_instances(model):
		var names := _surface_names(mi)
		for i in names.size():
			if names[i] in targets:
				_set_surface_material(mi, i, _shared_material("Broken" + names[i], ""))
	if front:
		var car := model.get_parent()
		for beam_name in ["HeadBeam_L", "HeadBeam_R"]:
			var beam := car.get_node_or_null(beam_name) if car else null
			if beam:
				beam.queue_free()
		if car:
			car.set_meta("headlights_broken", true)


static func _set_surface_material(mi: MeshInstance3D, i: int, mat: Material) -> void:
	mi.set_surface_override_material(i, mat)
	if mi.has_meta("dent_data"):
		var mats: Array = mi.get_meta("dent_data")["mats"]
		if i < mats.size():
			mats[i] = mat


## Material names of a mesh's surfaces as imported, remembered before denting
## swaps the mesh for an unnamed copy.
static func _surface_names(mi: MeshInstance3D) -> PackedStringArray:
	if mi.has_meta("surface_names"):
		return mi.get_meta("surface_names")
	var names := PackedStringArray()
	for i in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(i)
		names.append(src.resource_name if src else "")
	mi.set_meta("surface_names", names)
	return names


# --- lights -----------------------------------------------------------------


## Headlights for night maps: brightens the lamp lenses and adds a pair of
## headlight beams (no shadows). Lamps already smashed stay dark.
static func set_lights(car: Node3D, on: bool) -> void:
	car.set_meta("lights_on", on)
	var model := car.get_node_or_null(MODEL_NODE) as Node3D
	var meshes: Array[MeshInstance3D] = []
	if model:
		meshes = _mesh_instances(model)
	for mi in meshes:
		var names := _surface_names(mi)
		for i in names.size():
			if not names[i] in LIGHT_MATERIALS:
				continue
			var current := mi.get_surface_override_material(i)
			if current and current.resource_name.begins_with("Broken"):
				continue
			_set_surface_material(mi, i, _shared_material(names[i] + (":on" if on else ""), ""))
	for beam_name in ["HeadBeam_L", "HeadBeam_R"]:
		var old := car.get_node_or_null(beam_name)
		if old:
			old.free()
	if not on or car.get_meta("headlights_broken", false):
		return
	var spots: Array[Vector3] = []
	if model:
		for marker in ["Headlight_L", "Headlight_R"]:
			var node := model.get_node_or_null(marker) as Node3D
			if node:
				spots.append(model.transform * node.position)
	if spots.size() < 2:
		var size := Vector3(2, 1.4, 4.6)
		for child in car.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				size = (child.shape as BoxShape3D).size
		spots = [Vector3(size.x * 0.32, 0.0, size.z * 0.5), Vector3(-size.x * 0.32, 0.0, size.z * 0.5)]
	for i in 2:
		var beam := SpotLight3D.new()
		beam.name = "HeadBeam_L" if i == 0 else "HeadBeam_R"
		beam.light_color = Color(1.0, 0.95, 0.85)
		beam.light_energy = 3.0
		beam.spot_range = 22.0
		beam.spot_angle = 30.0
		beam.spot_attenuation = 0.8
		beam.shadow_enabled = false
		beam.position = spots[i] + Vector3(0, 0, 0.05)
		beam.basis = Basis.looking_at(Vector3(spots[i].x * 0.15, -0.12, 1.0))
		car.add_child(beam)


# --- detachable panels ---------------------------------------------------------


## Adds this hit (model space point, m/s strength) to every panel near it and
## tears off the ones that have had enough.
static func _damage_parts(car: Node3D, model: Node3D, p: Vector3, strength: float) -> void:
	if strength < 2.0:
		return
	var torn: int = car.get_meta("debris_count", 0)
	if torn >= MAX_DEBRIS:
		return
	for child in model.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not String(mi.name).begins_with("Part_"):
			continue
		var box: AABB = mi.get_meta("rest_aabb", mi.mesh.get_aabb())
		mi.set_meta("rest_aabb", box)
		var d := p.clamp(box.position, box.end).distance_to(p)
		if d > PART_REACH:
			continue
		var damage: float = mi.get_meta("part_damage", 0.0) + strength * (1.0 - d / PART_REACH)
		mi.set_meta("part_damage", damage)
		if damage >= PART_BREAK and torn < MAX_DEBRIS:
			torn += 1
			car.set_meta("debris_count", torn)
			_detach_part(car, model, mi, box)


static func _detach_part(car: Node3D, model: Node3D, mi: MeshInstance3D, box: AABB) -> void:
	var world := car.get_parent() as Node3D
	if world == null:
		return
	var debris := Debris.new()
	debris.collision_layer = DEBRIS_LAYER
	debris.collision_mask = 1
	debris.mass = clampf(box.size.x * box.size.y * box.size.z * 60.0, 8.0, 30.0)
	debris.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	debris.center_of_mass = box.get_center()
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = box.size.max(Vector3.ONE * 0.06)
	shape.shape = cube
	shape.position = box.get_center()
	debris.add_child(shape)
	var xform := mi.global_transform
	# Door glass goes with its door.
	var riders: Array[MeshInstance3D] = [mi]
	if String(mi.name).begins_with("Part_Door"):
		for other in _mesh_instances(model):
			if not String(other.name).begins_with("Glass_"):
				continue
			var c := other.mesh.get_aabb().get_center()
			if signf(c.x) == signf(box.get_center().x) and c.z > box.position.z and c.z < box.end.z:
				riders.append(other)
	world.add_child(debris)
	debris.global_transform = xform
	for rider in riders:
		var local := xform.affine_inverse() * rider.global_transform
		rider.get_parent().remove_child(rider)
		debris.add_child(rider)
		rider.transform = local
	var out := Vector3(signf(box.get_center().x) * 0.6, 0.6, signf(box.get_center().z) * 0.8)
	var body := car as RigidBody3D
	var base_velocity := body.linear_velocity if body else Vector3.ZERO
	debris.linear_velocity = base_velocity + car.global_basis * out * 3.0
	debris.angular_velocity = Vector3(randf_range(-4, 4), randf_range(-3, 3), randf_range(-4, 4))



# --- materials -----------------------------------------------------------------


static func _load_scene(model_name: String) -> PackedScene:
	if _scenes.has(model_name):
		return _scenes[model_name]
	var path := MODEL_DIR + model_name + ".glb"
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	_scenes[model_name] = scene
	return scene


static func _mesh_instances(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for child in root.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh:
			out.append(child)
		out.append_array(_mesh_instances(child))
	return out


## Stripes and livery: white on dark paint, near-black on light paint.
static func _decal_material(paint: Color, second: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var light := paint.get_luminance() > 0.45
	if second:
		mat.albedo_color = Color(0.85, 0.08, 0.06) if light else Color(0.95, 0.78, 0.1)
	else:
		mat.albedo_color = Color(0.06, 0.06, 0.07) if light else Color(0.93, 0.93, 0.9)
	mat.metallic = 0.2
	mat.roughness = 0.3
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.5
	return mat


static func _shared_material(mat_name: String, style: String) -> Material:
	var key := mat_name
	if mat_name == "Rim" or mat_name == "Caliper":
		key = mat_name + ":" + style
	if _materials.has(key):
		return _materials[key]
	var mat := StandardMaterial3D.new()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	match mat_name:
		"Glass":
			mat.albedo_color = Color(0.03, 0.045, 0.05, 0.5)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.6
			mat.metallic_specular = 1.0
			mat.roughness = 0.04
		"CrackedGlass":
			mat.albedo_texture = _crack_texture_get()
			mat.uv1_triplanar = true
			mat.uv1_world_triplanar = false
			mat.uv1_scale = Vector3(1.4, 1.4, 1.4)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic = 0.3
			mat.roughness = 0.25
		"Chrome":
			mat.albedo_color = Color(0.86, 0.86, 0.88)
			mat.metallic = 1.0
			mat.roughness = 0.1
		"Trim":
			mat.albedo_color = Color(0.035, 0.035, 0.04)
			mat.roughness = 0.45
		"Gap":
			mat.albedo_color = Color(0.008, 0.008, 0.008)
			mat.roughness = 0.9
		"Headlight":
			mat.albedo_color = Color(1.0, 1.0, 0.95)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.96, 0.88)
			mat.emission_energy_multiplier = 2.2
		"Taillight":
			mat.albedo_color = Color(0.55, 0.02, 0.02)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.06, 0.03)
			mat.emission_energy_multiplier = 1.4
			mat.roughness = 0.2
		"Indicator":
			mat.albedo_color = Color(0.95, 0.45, 0.05)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.45, 0.05)
			mat.emission_energy_multiplier = 0.5
			mat.roughness = 0.2
		"Headlight:on":
			mat.albedo_color = Color(1.0, 1.0, 0.96)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.96, 0.88)
			mat.emission_energy_multiplier = 6.0
		"Taillight:on":
			mat.albedo_color = Color(0.7, 0.03, 0.03)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.05, 0.03)
			mat.emission_energy_multiplier = 3.5
		"HeadLens", "HeadLens:on":
			# Clear lens over the reflectors and projectors.
			mat.albedo_color = Color(0.85, 0.9, 0.95, 0.16)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic_specular = 1.0
			mat.roughness = 0.03
			if mat_name.ends_with(":on"):
				mat.emission_enabled = true
				mat.emission = Color(1.0, 0.96, 0.88)
				mat.emission_energy_multiplier = 0.6
		"TailLens", "TailLens:on":
			mat.albedo_color = Color(0.55, 0.02, 0.025, 0.72)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.metallic_specular = 0.9
			mat.roughness = 0.06
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.05, 0.03)
			mat.emission_energy_multiplier = 1.6 if mat_name.ends_with(":on") else 0.35
		"Indicator:on":
			mat.albedo_color = Color(0.95, 0.45, 0.05)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.45, 0.05)
			mat.emission_energy_multiplier = 0.5
		"LightbarRed", "LightbarBlue":
			var red := mat_name == "LightbarRed"
			mat.albedo_color = Color(0.5, 0.03, 0.03) if red else Color(0.03, 0.06, 0.5)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.04, 0.03) if red else Color(0.08, 0.25, 1.0)
			mat.emission_energy_multiplier = 0.2
			mat.roughness = 0.15
		"BrokenHeadlight", "BrokenTaillight", "BrokenHeadLens", "BrokenTailLens":
			mat.albedo_color = Color(0.2, 0.02, 0.02) if mat_name.contains("Tail") else Color(0.12, 0.11, 0.1)
			mat.roughness = 0.7
			if mat_name.contains("Lens"):
				mat.albedo_texture = _crack_texture_get()
				mat.uv1_triplanar = true
				mat.uv1_scale = Vector3(4, 4, 4)
				mat.albedo_color.a = 0.85
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		"Interior":
			mat.albedo_color = Color(0.085, 0.08, 0.075)
			mat.roughness = 0.85
		"Seat":
			mat.albedo_color = Color(0.13, 0.12, 0.11)
			mat.roughness = 0.8
		"Tyre":
			mat.albedo_color = Color(0.035, 0.035, 0.036)
			mat.roughness = 0.85
		"Rim":
			mat.albedo_color = RIM_COLORS.get(style, Color(0.7, 0.7, 0.72))
			mat.metallic = 0.85
			mat.roughness = 0.22
		"Brake":
			mat.albedo_color = Color(0.32, 0.31, 0.3)
			mat.metallic = 0.8
			mat.roughness = 0.45
		"Caliper":
			mat.albedo_color = CALIPER_COLORS.get(style, Color(0.28, 0.28, 0.3))
			mat.metallic = 0.3
			mat.roughness = 0.35
		"Plate":
			mat.albedo_color = Color(0.92, 0.92, 0.88)
			mat.roughness = 0.4
		"Underbody":
			mat.albedo_color = Color(0.04, 0.04, 0.042)
			mat.roughness = 0.95
		"Frame":
			mat.albedo_color = Color(0.9, 0.62, 0.04)
			mat.metallic = 0.3
			mat.roughness = 0.35
		_:
			mat.albedo_color = Color(0.5, 0.5, 0.5)
	mat.resource_name = mat_name
	_materials[key] = mat
	return mat


## Spider-web cracks, drawn once and used with triplanar mapping.
static func _crack_texture_get() -> ImageTexture:
	if _crack_texture:
		return _crack_texture
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.24, 0.26, 0.62))
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var centre := Vector2(n * 0.5, n * 0.5)
	var crack := Color(0.9, 0.93, 0.95, 0.95)
	for i in 14:
		var ang := TAU * i / 14.0 + rng.randf_range(-0.2, 0.2)
		var pos := centre
		for step in 40:
			ang += rng.randf_range(-0.25, 0.25)
			var next := pos + Vector2(cos(ang), sin(ang)) * rng.randf_range(3.0, 6.0)
			_draw_line(img, pos, next, crack)
			pos = next
	for ring in [18.0, 40.0, 70.0, 105.0]:
		var segs := int(ring * 0.6)
		for k in segs:
			if rng.randf() < 0.35:
				continue
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var r0: float = ring * rng.randf_range(0.9, 1.1)
			var r1: float = ring * rng.randf_range(0.9, 1.1)
			_draw_line(img, centre + Vector2(cos(a0), sin(a0)) * r0, centre + Vector2(cos(a1), sin(a1)) * r1, crack)
	_crack_texture = ImageTexture.create_from_image(img)
	return _crack_texture


static func _draw_line(img: Image, a: Vector2, b: Vector2, color: Color) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y))) + 1
	var n := img.get_width()
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		var x := posmod(int(p.x), n)
		var y := posmod(int(p.y), n)
		img.set_pixel(x, y, color)


# --- moving parts ----------------------------------------------------------------


## Root of a wheel model. Turns the rim to face outwards on the right-hand
## wheels and keeps the brake caliper from spinning with the wheel.
class WheelVisual:
	extends Node3D

	var caliper: Node3D
	var _mirror := false

	func _ready() -> void:
		var wheel := get_parent() as Node3D
		if wheel and wheel.position.x < 0.0:
			_mirror = true
			rotation.y = PI

	func _process(_delta: float) -> void:
		if caliper == null:
			return
		var wheel := get_parent() as VehicleWheel3D
		if wheel == null:
			return
		var car := wheel.get_parent() as Node3D
		if car == null:
			return
		var s: Vector3 = (caliper.get_parent() as Node3D).global_basis.get_scale()
		var b := car.global_basis * Basis(Vector3.UP, wheel.steering)
		if _mirror:
			b = b * Basis(Vector3.UP, PI)
		caliper.global_basis = b * Basis.from_scale(s)


## Flashes the police light bar (red and blue lamps in turn, with a quick
## double blink) while its car is alive; at night it also throws coloured
## light around.
class LightbarFlasher:
	extends Node

	var car: Node
	var red: Array[StandardMaterial3D] = []
	var blue: Array[StandardMaterial3D] = []
	var _t := 0.0
	var _glow: OmniLight3D

	func _process(delta: float) -> void:
		_t += delta
		var alive: bool = car != null and car.get("alive") != false
		var phase := fmod(_t, 0.8) / 0.8
		var r_on := alive and (phase < 0.12 or (phase > 0.2 and phase < 0.32))
		var b_on := alive and ((phase > 0.5 and phase < 0.62) or (phase > 0.7 and phase < 0.82))
		for m in red:
			m.emission_energy_multiplier = 7.0 if r_on else 0.15
		for m in blue:
			m.emission_energy_multiplier = 7.0 if b_on else 0.15
		var night: bool = car != null and car.get_meta("lights_on", false)
		if night and alive and _glow == null and car is Node3D:
			_glow = OmniLight3D.new()
			_glow.omni_range = 7.0
			_glow.shadow_enabled = false
			_glow.position = Vector3(0, 1.0, 0)
			car.add_child(_glow)
		if _glow:
			_glow.visible = night and alive and (r_on or b_on)
			_glow.light_color = Color(1.0, 0.1, 0.08) if r_on else Color(0.15, 0.3, 1.0)
			_glow.light_energy = 2.5


## A panel torn off a car: tumbles away on its own physics layer and
## disappears after a while.
class Debris:
	extends RigidBody3D

	var life := DEBRIS_LIFE

	func _physics_process(delta: float) -> void:
		life -= delta
		if life < 0.0:
			queue_free()


## Moves the monster truck's solid axles and coil-over shocks with the
## wheels. The model has Axle_F / Axle_R (origin on the axle line, X along
## the axle, as wide as the track) and Shock_<end><side> (origin at the top
## mount, hanging straight down) nodes.
class SuspensionRig:
	extends Node3D

	var model: Node3D
	var _axles := {}
	var _shocks := []
	var _set_up := false

	func _process(_delta: float) -> void:
		var car := get_parent() as Node3D
		if car == null or model == null:
			return
		var wheels := {}
		for child in car.get_children():
			if child is VehicleWheel3D:
				var key := ("F" if child.position.z > 0.0 else "R") + ("L" if child.position.x > 0.0 else "R")
				wheels[key] = car.to_local(child.global_position)
		if wheels.size() < 4:
			return
		if not _set_up:
			_setup()
		var frames := {}
		for end: String in _axles:
			var axle: Dictionary = _axles[end]
			var left: Vector3 = wheels[end + "L"]
			var right: Vector3 = wheels[end + "R"]
			var x_axis := (left - right).normalized()
			var y_axis := (Vector3.UP - x_axis * x_axis.dot(Vector3.UP)).normalized()
			var stretch := left.distance_to(right) / float(axle["track"])
			var frame := Transform3D(Basis(x_axis * stretch, y_axis, x_axis.cross(y_axis)), (left + right) * 0.5)
			(axle["node"] as Node3D).transform = frame
			frames[end] = frame
		for shock: Dictionary in _shocks:
			if not frames.has(shock["end"]):
				continue
			var bottom: Vector3 = (frames[shock["end"]] as Transform3D) * (shock["bottom"] as Vector3)
			var top: Vector3 = shock["top"]
			var up := top - bottom
			var length := up.length()
			if length < 0.01:
				continue
			var y_axis := up / length
			var x_axis := (Vector3.RIGHT - y_axis * y_axis.x).normalized()
			(shock["node"] as Node3D).transform = Transform3D(Basis(x_axis, y_axis * (length / float(shock["length"])), x_axis.cross(y_axis)), top)

	func _setup() -> void:
		_set_up = true
		var rest := {}
		for end in ["F", "R"]:
			var node := model.get_node_or_null("Axle_" + end) as MeshInstance3D
			if node == null or node.mesh == null:
				continue
			_axles[end] = {"node": node, "track": maxf(node.mesh.get_aabb().size.x, 0.1)}
			rest[end] = node.transform
		for child in model.get_children():
			var child_name := String(child.name)
			if not child_name.begins_with("Shock_") or not child is MeshInstance3D:
				continue
			var end := child_name.substr(6, 1)
			if not rest.has(end):
				continue
			var node := child as MeshInstance3D
			var length := maxf(-node.mesh.get_aabb().position.y, 0.1)
			var top := node.position
			var bottom := (rest[end] as Transform3D).affine_inverse() * (top + Vector3.DOWN * length)
			_shocks.append({"node": node, "end": end, "top": top, "length": length, "bottom": bottom})


# --- fallback box models ------------------------------------------------------------


static func _build_box_wheel(radius: float, width: float, style: String) -> Node3D:
	var root := Node3D.new()
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.05, 0.05, 0.05)
	tire_mat.roughness = 0.92
	var tire := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = radius
	tire_mesh.bottom_radius = radius
	tire_mesh.height = width
	tire_mesh.radial_segments = 24
	tire_mesh.material = tire_mat
	tire.mesh = tire_mesh
	tire.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(tire)

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.75, 0.76, 0.78) if style != "monster" else Color(0.15, 0.15, 0.16)
	rim_mat.metallic = 0.9
	rim_mat.roughness = 0.25
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = radius * 0.62
	rim_mesh.bottom_radius = radius * 0.62
	rim_mesh.height = width * 1.04
	rim_mesh.radial_segments = 16
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(rim)

	# Spokes so you can see the wheels turning.
	for i in 5:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(width * 1.08, radius * 1.15, radius * 0.12)
		spoke_mesh.material = rim_mat
		spoke.mesh = spoke_mesh
		spoke.rotation = Vector3(TAU * i / 5.0, 0, 0)
		root.add_child(spoke)
	return root


static func _build_box_body(car: Node3D, style: String, size: Vector3, paint: StandardMaterial3D) -> void:
	match style:
		"van":
			_build_van(car, size, paint)
		"sports":
			_build_sports(car, size, paint)
		"monster":
			_build_monster(car, size, paint)
		_:
			_box(car, size, Vector3.ZERO, paint)


static func _build_van(car: Node3D, s: Vector3, paint: StandardMaterial3D) -> void:
	# Tall boxy van: body, slightly narrower upper cabin, windows and a roof rack.
	_box(car, Vector3(s.x, s.y * 0.55, s.z), Vector3(0, -s.y * 0.2, 0), paint)
	_box(car, Vector3(s.x * 0.97, s.y * 0.48, s.z * 0.97), Vector3(0, s.y * 0.3, -s.z * 0.01), paint)
	var glass := _glass()
	_box(car, Vector3(s.x * 0.92, s.y * 0.32, 0.06), Vector3(0, s.y * 0.32, s.z * 0.475), glass)
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.05, s.y * 0.26, s.z * 0.55), Vector3(side * s.x * 0.487, s.y * 0.34, s.z * 0.12), glass)
	var trim := _trim()
	_box(car, Vector3(s.x * 0.8, 0.08, s.z * 0.55), Vector3(0, s.y * 0.58, -s.z * 0.05), trim)
	_bumpers(car, s, trim)
	_lights(car, s, s.y * -0.12)
	_stripe(car, s, Color(0.95, 0.95, 0.9), -s.y * 0.05)


static func _build_sports(car: Node3D, s: Vector3, paint: StandardMaterial3D) -> void:
	# Low wedge: long body, sloped glass cabin set back, rear wing.
	_box(car, Vector3(s.x, s.y * 0.7, s.z), Vector3(0, -s.y * 0.15, 0), paint)
	var hood := MeshInstance3D.new()
	var hood_mesh := PrismMesh.new()
	hood_mesh.left_to_right = 1.0
	hood_mesh.size = Vector3(s.z * 0.35, s.y * 0.28, s.x * 0.98)
	hood_mesh.material = paint
	hood.mesh = hood_mesh
	hood.rotation_degrees = Vector3(0, 90, 0)
	hood.position = Vector3(0, s.y * 0.33, s.z * 0.3)
	car.add_child(hood)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := PrismMesh.new()
	cabin_mesh.left_to_right = 0.45
	cabin_mesh.size = Vector3(s.z * 0.5, s.y * 0.55, s.x * 0.84)
	cabin_mesh.material = _glass()
	cabin.mesh = cabin_mesh
	cabin.rotation_degrees = Vector3(0, 90, 0)
	cabin.position = Vector3(0, s.y * 0.47, -s.z * 0.06)
	car.add_child(cabin)
	var trim := _trim()
	# Rear wing on two posts.
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.08, s.y * 0.35, 0.12), Vector3(side * s.x * 0.32, s.y * 0.38, -s.z * 0.44), trim)
	_box(car, Vector3(s.x * 0.95, 0.05, 0.42), Vector3(0, s.y * 0.56, -s.z * 0.45), trim)
	_bumpers(car, s, trim)
	_lights(car, s, -s.y * 0.05)
	for side in [-1.0, 1.0]:
		var pipe := MeshInstance3D.new()
		var pipe_mesh := CylinderMesh.new()
		pipe_mesh.top_radius = 0.06
		pipe_mesh.bottom_radius = 0.07
		pipe_mesh.height = 0.25
		pipe_mesh.material = trim
		pipe.mesh = pipe_mesh
		pipe.rotation_degrees = Vector3(90, 0, 0)
		pipe.position = Vector3(side * 0.25, -s.y * 0.35, -s.z * 0.5)
		car.add_child(pipe)


static func _build_monster(car: Node3D, s: Vector3, paint: StandardMaterial3D) -> void:
	# Pickup body perched on a visible frame, with a roll bar and roof lights.
	var trim := _trim()
	_box(car, Vector3(s.x * 0.55, s.y * 0.2, s.z * 0.95), Vector3(0, -s.y * 0.35, 0), trim)
	_box(car, Vector3(s.x * 0.92, s.y * 0.4, s.z * 0.96), Vector3(0, s.y * 0.0, 0), paint)
	_box(car, Vector3(s.x * 0.88, s.y * 0.42, s.z * 0.32), Vector3(0, s.y * 0.4, s.z * 0.06), paint)
	var glass := _glass()
	_box(car, Vector3(s.x * 0.8, s.y * 0.28, 0.06), Vector3(0, s.y * 0.43, s.z * 0.225), glass)
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.05, s.y * 0.24, s.z * 0.22), Vector3(side * s.x * 0.442, s.y * 0.43, s.z * 0.06), glass)
		_box(car, Vector3(0.1, s.y * 0.5, 0.1), Vector3(side * s.x * 0.38, s.y * 0.45, -s.z * 0.15), trim)
	_box(car, Vector3(s.x * 0.86, 0.1, 0.1), Vector3(0, s.y * 0.7, -s.z * 0.15), trim)
	# Bed floor.
	_box(car, Vector3(s.x * 0.84, 0.05, s.z * 0.4), Vector3(0, s.y * 0.2, -s.z * 0.28), trim)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1, 0.95, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.92, 0.75)
	lamp.emission_energy_multiplier = 2.5
	for i in 4:
		var bulb := MeshInstance3D.new()
		var bulb_mesh := CylinderMesh.new()
		bulb_mesh.top_radius = 0.09
		bulb_mesh.bottom_radius = 0.09
		bulb_mesh.height = 0.08
		bulb_mesh.material = lamp
		bulb.mesh = bulb_mesh
		bulb.rotation_degrees = Vector3(90, 0, 0)
		bulb.position = Vector3((i - 1.5) * s.x * 0.2, s.y * 0.66, s.z * 0.12)
		car.add_child(bulb)
	_bumpers(car, s, trim)
	_lights(car, s, s.y * 0.05)
	_stripe(car, s, Color(0.95, 0.95, 0.95), s.y * 0.05)


static func _bumpers(car: Node3D, s: Vector3, mat: Material) -> void:
	_box(car, Vector3(s.x * 1.02, s.y * 0.16, 0.18), Vector3(0, -s.y * 0.32, s.z * 0.5 + 0.06), mat)
	_box(car, Vector3(s.x * 1.02, s.y * 0.16, 0.18), Vector3(0, -s.y * 0.32, -s.z * 0.5 - 0.06), mat)


static func _lights(car: Node3D, s: Vector3, y: float) -> void:
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 1, 0.95)
	head.emission_enabled = true
	head.emission = Color(1, 0.97, 0.9)
	head.emission_energy_multiplier = 3.0
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.8, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(1, 0.1, 0.05)
	tail.emission_energy_multiplier = 2.0
	for side in [-1.0, 1.0]:
		_box(car, Vector3(s.x * 0.22, s.y * 0.1, 0.05), Vector3(side * s.x * 0.36, y, s.z * 0.5 + 0.01), head)
		_box(car, Vector3(s.x * 0.2, s.y * 0.09, 0.05), Vector3(side * s.x * 0.37, y, -s.z * 0.5 - 0.01), tail)


static func _stripe(car: Node3D, s: Vector3, color: Color, y: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.02, s.y * 0.07, s.z * 0.8), Vector3(side * (s.x * 0.5 + 0.005), y, 0), mat)


static func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.09, 0.12)
	glass.metallic = 0.2
	glass.roughness = 0.05
	return glass


static func _trim() -> StandardMaterial3D:
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.1, 0.1, 0.11)
	trim.metallic = 0.6
	trim.roughness = 0.4
	return trim


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	parent.add_child(mesh)
	return mesh
