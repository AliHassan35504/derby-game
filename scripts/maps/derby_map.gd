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
var road_width := 4.0
## How far below each road its stilts reach.
var stilt_bottom := -5.0
## Stilts within this distance of the map centre are skipped so they don't
## poke through crossing roads.
var stilt_clear_radius := 0.0

var environment: Environment
var sun: DirectionalLight3D

var _road_material: Material
var _stilt_material: Material
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
	var pad := _make_slab(Vector3(size.x, thickness, size.y), _road_material)
	pad.name = "Pad_" + id
	pad.position = pos - Vector3(0, thickness * 0.5, 0)
	add_child(pad)
	_pads[id] = {"pos": pos, "half": size * 0.5}
	_links[id] = []
	_pieces.append(pad)
	var offsets := [Vector3(size.x * 0.35, 0, 0), Vector3(-size.x * 0.35, 0, 0), Vector3(0, 0, size.y * 0.35), Vector3(0, 0, -size.y * 0.35)]
	for offset in offsets:
		_add_stilt(pad, offset + Vector3(0, -thickness * 0.5, 0), pos + offset)
	return pad


## Lays a road from one pad to another, trimmed to start and end at the pads'
## edges.
func add_road(from_id: String, to_id: String, thickness := 0.45) -> StaticBody3D:
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
	_links[from_id].append(to_id)
	_links[to_id].append(from_id)
	return add_road_between(start, end, thickness, from_id + "-" + to_id)


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


func add_ocean(height: float, deep: Color, shallow: Color) -> void:
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1800, 1800)
	plane.subdivide_width = 220
	plane.subdivide_depth = 220
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/ocean.gdshader")
	mat.set_shader_parameter("deep_color", deep)
	mat.set_shader_parameter("shallow_color", shallow)
	plane.material = mat
	sea.mesh = plane
	sea.position.y = height
	sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sea)


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
