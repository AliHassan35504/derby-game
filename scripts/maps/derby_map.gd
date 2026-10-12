class_name DerbyMap
extends Node3D
## Base for every derby map. A map is a set of flat pads (junctions) joined by
## narrow sloped roads, all floating in the air on stilts. Subclasses set the
## map's name, car and look, then lay out pads and roads in build().
##
## Late in a round the map collapses piece by piece, from the outside in, so
## the fight keeps getting tighter.

## Physics layer used by roads and pads. Cars are on layer 2, and the bots'
## ground probes only look at this layer.
const ROAD_LAYER := 1

var map_name := "Map"
## Key into DerbyCar.CAR_TYPES. Every player gets this car on this map.
var car_type := "van"
## One-line twist shown on the Next Derby screen.
var rule_text := ""
## Cars below this height are out.
var kill_height := 0.0
## Height of the sea surface for splashes, or NAN when the map has no water.
var water_height := NAN
var nitro_refill_multiplier := 1.0
var hop_multiplier := 1.0
## Tyre grip on this map's roads, e.g. below 1 on ice.
var grip_multiplier := 1.0
var road_width := 4.0
## How far below each road its stilts reach.
var stilt_bottom := -5.0
## Stilts within this distance of the map centre are skipped so they don't
## poke through crossing roads.
var stilt_clear_radius := 0.0

## When false, pads and roads get no plain round stilts and the map builds
## its own supports (see deck_below() and roads()).
var plain_stilts := true
## Material for pads. When null, pads use the road material.
var pad_material: Material

var environment: Environment
var sun: DirectionalLight3D

var _road_material: Material
var _stilt_material: Material
## Every road built so far: body, start, end, thickness, sag and the pads it
## joins (empty for roads laid with add_road_between directly).
var _roads: Array[Dictionary] = []
var _weather: GPUParticles3D
var _pads := {}
## Pad id -> ids of the pads its roads lead to. Bots navigate with this.
var _links := {}
var _pieces: Array[Node3D] = []
var _spawns: Array[Transform3D] = []
var _collapse_queue: Array[Node3D] = []


## Subclasses lay out the map here.
func build() -> void:
	pass


func _ready() -> void:
	build()
	_collapse_queue = _pieces.duplicate()
	# Furthest from the middle collapses first; the hub goes last.
	_collapse_queue.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return _flat_distance(a.global_position) > _flat_distance(b.global_position))


func get_spawn_points(count: int) -> Array[Transform3D]:
	var points: Array[Transform3D] = []
	for i in count:
		var base := _spawns[i % _spawns.size()]
		# Extra cars beyond the spawn list queue up behind earlier ones.
		var row := i / _spawns.size()
		base.origin -= base.basis.z * 7.0 * row
		points.append(base)
	return points


func pieces_left() -> int:
	return _collapse_queue.size()


## Drops the next outermost piece. Returns false when nothing is left.
func collapse_next() -> bool:
	if _collapse_queue.is_empty():
		return false
	var piece: Node3D = _collapse_queue.pop_front()
	var start := piece.position
	var tween := piece.create_tween()
	# Shake as a warning, then fall away.
	for i in 8:
		var jitter := Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.02), randf_range(-0.12, 0.12))
		tween.tween_property(piece, "position", start + jitter, 0.1)
	tween.tween_callback(func() -> void:
		if piece is CollisionObject3D:
			piece.collision_layer = 0)
	tween.set_parallel()
	tween.tween_property(piece, "position", start + Vector3.DOWN * 80.0, 3.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(piece, "rotation", piece.rotation + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6)), 3.0)
	tween.chain().tween_callback(piece.queue_free)
	return true


func is_over_water() -> bool:
	return not is_nan(water_height)


# --- Navigation (used by bots) -----------------------------------------------

func pad_position(id: String) -> Vector3:
	return _pads[id]["pos"]


func pad_radius(id: String) -> float:
	var half: Vector2 = _pads[id]["half"]
	return minf(half.x, half.y)


func pad_links(id: String) -> Array:
	return _links.get(id, [])


## The pad closest to a position, weighting height so a road passing above
## or below doesn't count.
func nearest_pad(pos: Vector3) -> String:
	var best := ""
	var best_dist := INF
	for id in _pads:
		var p: Vector3 = _pads[id]["pos"]
		var d := Vector2(p.x - pos.x, p.z - pos.z).length() + absf(p.y - pos.y) * 3.0
		if d < best_dist:
			best_dist = d
			best = id
	return best


## Shortest list of pads from one pad to another (both included).
func route(from_id: String, to_id: String) -> Array:
	if from_id == to_id:
		return [from_id]
	var came_from := {from_id: ""}
	var queue := [from_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next in _links.get(current, []):
			if came_from.has(next):
				continue
			came_from[next] = current
			if next == to_id:
				var path := [to_id]
				while path[0] != from_id:
					path.push_front(came_from[path[0]])
				return path
			queue.append(next)
	return [from_id]


# --- Building helpers -------------------------------------------------------

func add_pad(id: String, pos: Vector3, size: Vector2, thickness := 0.6) -> StaticBody3D:
	var pad := _make_slab(Vector3(size.x, thickness, size.y), pad_material if pad_material else _road_material)
	pad.name = "Pad_" + id
	pad.position = pos - Vector3(0, thickness * 0.5, 0)
	add_child(pad)
	_pads[id] = {"pos": pos, "half": size * 0.5, "body": pad, "thickness": thickness}
	_links[id] = []
	_pieces.append(pad)
	if not plain_stilts:
		return pad
	var offsets := [Vector3(size.x * 0.35, 0, 0), Vector3(-size.x * 0.35, 0, 0), Vector3(0, 0, size.y * 0.35), Vector3(0, 0, -size.y * 0.35)]
	for offset in offsets:
		_add_stilt(pad, offset + Vector3(0, -thickness * 0.5, 0), pos + offset)
	return pad


## Lays a road from one pad to another, trimmed to start and end at the pads'
## edges.
func add_road(from_id: String, to_id: String, thickness := 0.45) -> StaticBody3D:
	var ends := _road_ends(from_id, to_id)
	_links[from_id].append(to_id)
	_links[to_id].append(from_id)
	var road := add_road_between(ends[0], ends[1], thickness, from_id + "-" + to_id)
	_roads[-1]["from"] = from_id
	_roads[-1]["to"] = to_id
	return road


## Like add_road, but the deck hangs in a shallow curve like a rope bridge,
## dipping by sag metres in the middle. It is built from short straight
## sections that share one body, so it collapses as one piece. Never gets
## plain stilts.
func add_sagging_road(from_id: String, to_id: String, sag: float, sections := 10, thickness := 0.45) -> StaticBody3D:
	var ends := _road_ends(from_id, to_id)
	_links[from_id].append(to_id)
	_links[to_id].append(from_id)
	var start: Vector3 = ends[0]
	var end: Vector3 = ends[1]
	var along := end - start
	var forward := along.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	var road := StaticBody3D.new()
	road.collision_layer = ROAD_LAYER
	road.collision_mask = 0
	road.name = "Road_" + from_id + "-" + to_id
	road.transform = Transform3D(Basis(right, up, forward), (start + end) * 0.5 - up * thickness * 0.5)
	add_child(road)
	var to_local := road.transform.affine_inverse()
	var kit := MeshKit.new()
	for i in sections:
		var p0 := sag_point(start, end, sag, i / float(sections))
		var p1 := sag_point(start, end, sag, (i + 1) / float(sections))
		var seg := p1 - p0
		# Sections overlap a little so the joints have no gaps.
		var extra := 0.0 if i == 0 or i == sections - 1 else 0.15
		var basis := Basis(right, seg.normalized().cross(right).normalized(), seg.normalized())
		var centre := (p0 + p1) * 0.5 - basis.y * thickness * 0.5
		var local := to_local * Transform3D(basis, centre)
		var size := Vector3(road_width, thickness, seg.length() + extra * 2.0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		shape.transform = local
		road.add_child(shape)
		kit.box(local, size)
	kit.instance(road, _road_material)
	_pieces.append(road)
	_roads.append({"body": road, "start": start, "end": end, "thickness": thickness, "sag": sag, "from": from_id, "to": to_id})
	return road


## A point on a sagging road's deck, t from 0 at the start to 1 at the end.
static func sag_point(start: Vector3, end: Vector3, sag: float, t: float) -> Vector3:
	return start.lerp(end, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)


## All roads built so far, as dictionaries with body, start, end, thickness,
## sag, from and to.
func roads() -> Array[Dictionary]:
	return _roads


## The pad's body, or null.
func pad_body(id: String) -> StaticBody3D:
	return _pads[id].get("body") if _pads.has(id) else null


func pad_ids() -> Array:
	return _pads.keys()


func pad_half(id: String) -> Vector2:
	return _pads[id]["half"]


## Height of the highest deck (pad or road) under a point, closer than
## margin to its edge sideways and lower than the point, or -INF when there
## is none. Maps use it to stop supports from poking through roads below.
func deck_below(point: Vector3, margin := 1.0, ignore: Node = null) -> float:
	var best := -INF
	for id in _pads:
		var pad: Dictionary = _pads[id]
		if pad.get("body") == ignore and ignore != null:
			continue
		var p: Vector3 = pad["pos"]
		var half: Vector2 = pad["half"]
		if absf(point.x - p.x) < half.x + margin and absf(point.z - p.z) < half.y + margin and p.y < point.y - 0.3:
			best = maxf(best, p.y)
	for road in _roads:
		if road["body"] == ignore and ignore != null:
			continue
		var a: Vector3 = road["start"]
		var b: Vector3 = road["end"]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var t := clampf(Vector2(point.x - a.x, point.z - a.z).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var closest := Vector2(a.x, a.z) + ab * t
		if closest.distance_to(Vector2(point.x, point.z)) > road_width * 0.5 + margin:
			continue
		var y := sag_point(a, b, float(road.get("sag", 0.0)), t).y
		if y < point.y - 0.3:
			best = maxf(best, y)
	return best


func add_road_between(start: Vector3, end: Vector3, thickness := 0.45, label := "") -> StaticBody3D:
	var along := end - start
	var length := along.length()
	var forward := along / length
	var right := Vector3.UP.cross(forward).normalized()
	var up := forward.cross(right).normalized()
	var road := _make_slab(Vector3(road_width, thickness, length), _road_material)
	road.name = "Road_" + label
	road.transform = Transform3D(Basis(right, up, forward), (start + end) * 0.5 - up * thickness * 0.5)
	add_child(road)
	_pieces.append(road)
	_roads.append({"body": road, "start": start, "end": end, "thickness": thickness, "sag": 0.0, "from": "", "to": ""})
	if not plain_stilts:
		return road

	var stations := maxi(int(length / 11.0), 1)
	for i in stations + 1:
		var t := (i + 0.5) / float(stations + 1)
		var local_z := (t - 0.5) * length
		var world := start.lerp(end, t)
		for side in [-1.0, 1.0]:
			var local := Vector3(side * road_width * 0.42, -thickness * 0.5, local_z)
			_add_stilt(road, local, world + right * side * road_width * 0.42)
	return road


## Adds a spawn on a pad, facing toward another pad.
func add_spawn(pad_id: String, face_id: String, offset := 0.0) -> void:
	var pos: Vector3 = _pads[pad_id]["pos"]
	var target: Vector3 = _pads[face_id]["pos"]
	var dir := Vector3(target.x - pos.x, 0, target.z - pos.z).normalized()
	# looking_at aims -Z and cars drive along +Z, so aim -Z away from the target.
	var basis := Basis.looking_at(-dir, Vector3.UP)
	_spawns.append(Transform3D(basis, pos + dir * offset + Vector3.UP * 2.8))


func set_materials(road: Material, stilt: Material) -> void:
	_road_material = road
	_stilt_material = stilt


func make_plank_material(light: Color, dark: Color, weathering := 0.35) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planks.gdshader")
	mat.set_shader_parameter("wood_light", light)
	mat.set_shader_parameter("wood_dark", dark)
	mat.set_shader_parameter("weathering", weathering)
	return mat


func make_asphalt_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/asphalt.gdshader")
	mat.set_shader_parameter("road_width", road_width)
	return mat


func make_environment(sky_top: Color, horizon: Color, ground: Color, fog_color: Color, fog_density: float, sun_angles: Vector3, sun_energy := 1.3) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = horizon
	sky_mat.ground_horizon_color = horizon
	sky_mat.ground_bottom_color = ground
	sky_mat.sun_angle_max = 20.0
	sky_mat.sky_curve = 0.12
	var sky := Sky.new()
	sky.sky_material = sky_mat
	environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.0
	environment.tonemap_white = 6.0
	environment.fog_enabled = true
	environment.fog_light_color = fog_color
	environment.fog_density = fog_density
	environment.fog_aerial_perspective = 0.6
	environment.fog_sky_affect = 0.3
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.05
	environment.glow_hdr_threshold = 1.2
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.1
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = sun_angles
	sun.light_energy = sun_energy
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 180.0
	sun.directional_shadow_blend_splits = true
	add_child(sun)


## Graphics quality: 0 = Low, 1 = Medium, 2 = High.
func apply_quality(level: int) -> void:
	if environment == null:
		return
	environment.ssao_enabled = level >= 1
	environment.ssao_intensity = 1.6
	environment.ssil_enabled = level >= 2
	environment.ssr_enabled = level >= 2
	environment.sdfgi_enabled = level >= 2
	environment.sdfgi_use_occlusion = true
	environment.volumetric_fog_enabled = level >= 2
	environment.volumetric_fog_density = 0.004
	environment.volumetric_fog_albedo = environment.fog_light_color
	environment.glow_enabled = level >= 1
	if sun:
		sun.shadow_enabled = level >= 1
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if level >= 2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS


func add_ocean(height: float, deep: Color, shallow: Color, wave_height := 0.9) -> MeshInstance3D:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1800, 1800)
	plane.subdivide_width = 220
	plane.subdivide_depth = 220
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ocean.gdshader")
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("shallow_color", shallow)
	mat.set_shader_parameter("wave_height", wave_height)
	plane.material = mat
	sea.mesh = plane
	sea.position.y = height
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)
	return sea


func add_cloud_layer(height: float) -> void:
	for i in 2:
		var layer := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(3000, 3000)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/clouds.gdshader")
		mat.set_shader_parameter("scale", 0.012 if i == 0 else 0.007)
		plane.material = mat
		layer.mesh = plane
		layer.position.y = height - i * 6.0
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(layer)


## Adds a solid prop. When attached to a pad it falls with that pad.
func add_obstacle(mesh: PrimitiveMesh, shape: Shape3D, pos: Vector3, mat: Material, attach_to := "") -> void:
	var body := StaticBody3D.new()
	body.collision_layer = ROAD_LAYER
	body.collision_mask = 0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)
	var visual := MeshInstance3D.new()
	mesh.material = mat
	visual.mesh = mesh
	body.add_child(visual)
	if attach_to != "" and has_node("Pad_" + attach_to):
		get_node("Pad_" + attach_to).add_child(body)
		body.global_position = pos
	else:
		body.position = pos
		add_child(body)


## A ShaderMaterial for one of the shaders in res://shaders, with its
## parameters set from a dictionary.
func make_shader_material(shader_name: String, params := {}) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/%s.gdshader" % shader_name)
	for key in params:
		mat.set_shader_parameter(key, params[key])
	return mat


## The visible mesh of a pad or road body, e.g. to give one pad its own
## material.
func piece_mesh(piece: Node3D) -> MeshInstance3D:
	for child in piece.get_children():
		if child is MeshInstance3D:
			return child
	return null


## Weather that follows the camera: snowflakes, dust motes or rain. The
## particles live in world space, so they drift past as the camera moves.
## flake is the size of each particle, fall its speed (down is positive).
func add_weather(amount: int, flake: float, tint: Color, fall: float, drift: float, extent := Vector3(70, 35, 70)) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "Weather"
	particles.amount = amount
	particles.lifetime = extent.y * 2.0 / maxf(fall, 0.5)
	particles.preprocess = particles.lifetime
	particles.local_coords = false
	particles.visibility_aabb = AABB(-extent * 1.5, extent * 3.0)
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = extent
	proc.direction = Vector3.DOWN
	proc.spread = 15.0
	proc.initial_velocity_min = fall * 0.7
	proc.initial_velocity_max = fall * 1.3
	proc.gravity = Vector3(drift * 0.3, 0, drift * 0.2)
	proc.turbulence_enabled = drift > 0.0
	proc.turbulence_noise_strength = drift
	proc.turbulence_noise_scale = 6.0
	proc.turbulence_influence_min = 0.05
	proc.turbulence_influence_max = 0.15
	proc.scale_min = 0.5
	proc.scale_max = 1.3
	particles.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(flake, flake)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = tint
	mat.vertex_color_use_as_albedo = true
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 32
	dot.height = 32
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = fade
	mat.albedo_texture = dot
	quad.material = mat
	particles.draw_pass_1 = quad
	add_child(particles)
	_weather = particles
	return particles


func _process(_delta: float) -> void:
	if _weather == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera:
		_weather.global_position = camera.global_position + Vector3.UP * 8.0


## A smooth heightfield mesh, cells x cells quads over a square extent
## centred on the origin. height_at(x, z) gives the height and colour_at(x,
## z, height, normal) the vertex colour.
func make_terrain(cells: int, extent: float, height_at: Callable, colour_at: Callable) -> ArrayMesh:
	var side := cells + 1
	var step := extent / cells
	var heights := PackedFloat32Array()
	heights.resize(side * side)
	for z in side:
		for x in side:
			heights[z * side + x] = height_at.call((x * step) - extent * 0.5, (z * step) - extent * 0.5)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colours := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(side * side)
	normals.resize(side * side)
	colours.resize(side * side)
	uvs.resize(side * side)
	for z in side:
		for x in side:
			var i := z * side + x
			var h := heights[i]
			var hl := heights[z * side + maxi(x - 1, 0)]
			var hr := heights[z * side + mini(x + 1, cells)]
			var hd := heights[maxi(z - 1, 0) * side + x]
			var hu := heights[mini(z + 1, cells) * side + x]
			var n := Vector3(hl - hr, 2.0 * step, hd - hu).normalized()
			var px := x * step - extent * 0.5
			var pz := z * step - extent * 0.5
			verts[i] = Vector3(px, h, pz)
			normals[i] = n
			colours[i] = colour_at.call(px, pz, h, n)
			uvs[i] = Vector2(px, pz) * 0.05
	var indices := PackedInt32Array()
	indices.resize(cells * cells * 6)
	var k := 0
	for z in cells:
		for x in cells:
			var i := z * side + x
			indices[k] = i
			indices[k + 1] = i + 1
			indices[k + 2] = i + side
			indices[k + 3] = i + 1
			indices[k + 4] = i + side + 1
			indices[k + 5] = i + side
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Copies of one mesh with per-copy transforms (and optional colours and
## custom data) as a single MultiMeshInstance3D.
func add_multimesh(mesh: Mesh, transforms: Array, colours: Array = [], custom: Array = [], parent: Node = null) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = not colours.is_empty()
	multi.use_custom_data = not custom.is_empty()
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
		if multi.use_colors:
			multi.set_instance_color(i, colours[i])
		if multi.use_custom_data:
			multi.set_instance_custom_data(i, custom[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	(parent if parent else self).add_child(instance)
	return instance


## Rings of points for a rock pillar under a pad, for MeshKit.shell(). The
## top ring hugs the pad's square edge so the rock top and the pad's
## collision match; further down the outline loosens into a rough, ledged
## column that flares out by flare metres at the bottom.
func make_rock_rings(top: Vector3, half: Vector2, bottom_y: float, seed_value: int, roughness := 0.15, flare := 0.0, ledges := 0.08, points := 32) -> Array:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.08
	noise.fractal_octaves = 3
	var rings := []
	var height := top.y - bottom_y
	var ring_count := clampi(int(height / 2.5), 3, 48)
	for r in ring_count + 1:
		# Bottom ring first.
		var k := ring_count - r
		var depth := height * k / float(ring_count)
		var y := top.y - depth
		# Within the first metres keep the square; then loosen.
		var loose := smoothstep(0.0, 6.0, depth)
		var widen := flare * pow(depth / maxf(height, 1.0), 1.6) + loose * 0.4
		# Ledges: the outline steps in and out with the rock layers.
		var step := floorf(y / 3.4)
		var ledge := 1.0 + ledges * (fmod(absf(step) * 0.618, 1.0) - 0.5) * loose
		var ring := PackedVector3Array()
		for i in points:
			var a := TAU * i / float(points)
			var c := cos(a)
			var s := sin(a)
			# Rounded square (superellipse) at the top, rounder lower down.
			var power := lerpf(0.18, 0.7, loose)
			var sx := signf(c) * pow(absf(c), power)
			var sz := signf(s) * pow(absf(s), power)
			var bump := 1.0 + noise.get_noise_3d(c * 20.0, y * 0.6, s * 20.0) * roughness * 2.0 * loose
			var rx := (half.x * ledge * bump + widen) * sx
			var rz := (half.y * ledge * bump + widen) * sz
			ring.append(Vector3(top.x + rx, y, top.z + rz))
		rings.append(ring)
	return rings


func _road_ends(from_id: String, to_id: String) -> Array:
	var a: Dictionary = _pads[from_id]
	var b: Dictionary = _pads[to_id]
	var a_pos: Vector3 = a["pos"]
	var b_pos: Vector3 = b["pos"]
	var flat := Vector3(b_pos.x - a_pos.x, 0, b_pos.z - a_pos.z)
	var dir := flat.normalized()
	var start := a_pos + Vector3(dir.x, 0, dir.z) * (_pad_reach(a["half"], dir) - 0.4)
	var end := b_pos - Vector3(dir.x, 0, dir.z) * (_pad_reach(b["half"], dir) - 0.4)
	start.y = a_pos.y
	end.y = b_pos.y
	return [start, end]


func _make_slab(size: Vector3, mat: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = ROAD_LAYER
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = size
	box_mesh.material = mat
	mesh.mesh = box_mesh
	body.add_child(mesh)
	return body


func _add_stilt(parent: Node3D, local_top: Vector3, world_top: Vector3) -> void:
	if _flat_distance(world_top) < stilt_clear_radius:
		return
	var length := world_top.y - stilt_bottom
	if length <= 0.5:
		return
	var stilt := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.16
	cylinder.bottom_radius = 0.2
	cylinder.height = length
	cylinder.radial_segments = 8
	cylinder.material = _stilt_material
	stilt.mesh = cylinder
	parent.add_child(stilt)
	# Stilts hang straight down even when the road above is sloped.
	stilt.global_basis = Basis.IDENTITY
	stilt.global_position = parent.global_transform * local_top + Vector3.DOWN * length * 0.5


func _pad_reach(half: Vector2, dir: Vector3) -> float:
	var reach_x := half.x / absf(dir.x) if absf(dir.x) > 0.001 else INF
	var reach_z := half.y / absf(dir.z) if absf(dir.z) > 0.001 else INF
	return minf(reach_x, reach_z)


func _flat_distance(pos: Vector3) -> float:
	return Vector2(pos.x, pos.z).length()
