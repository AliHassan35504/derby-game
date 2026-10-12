class_name FrozenPeaksMap
extends DerbyMap
## An icy mountain pass at dawn: glassy ice roads on natural rock bridges
## between snowy summits. A six-pointed star of peaks rings a frozen lake far
## below, and three long ice bridges run in from it to a high summit in the
## middle. The star's inner corners are gentle bends and its points are
## right angles, so there is room to slide.

## Radius of the star's inner corners. Its points sit 1.366 times further
## out, which makes each point a right angle.
const STAR_RADIUS := 80.0
const SUMMIT := 44.0
const LAKE := -62.0

var _rng := RandomNumberGenerator.new()
var _rock: ShaderMaterial
var _ice_side: ShaderMaterial


func build() -> void:
	map_name = "Frozen Peaks"
	car_type = "rally"
	rule_text = "Black ice: a third less grip, so brake early"
	kill_height = 10.0
	road_width = 5.5
	plain_stilts = false
	grip_multiplier = 0.65
	_rng.seed = 808

	make_environment(Color(0.3, 0.44, 0.72), Color(1.0, 0.74, 0.62), Color(0.62, 0.66, 0.76),
			Color(0.84, 0.78, 0.86), 0.0018, Vector3(-9, 70, 0), 1.75)
	sun.light_color = Color(1.0, 0.72, 0.52)
	environment.ambient_light_energy = 0.5
	environment.fog_sun_scatter = 0.3
	var sky_mat: ProceduralSkyMaterial = environment.sky.sky_material
	sky_mat.sun_angle_max = 9.0
	sky_mat.sky_curve = 0.15

	_rock = make_shader_material("snow_rock")
	set_materials(make_shader_material("ice", {"road_width": road_width}), _rock)

	add_pad("summit", Vector3(0, SUMMIT, 0), Vector2(15, 15))
	for i in 6:
		var angle := TAU * i / 6.0
		var corner := Vector3(cos(angle), 0, sin(angle)) * STAR_RADIUS
		add_pad("d%d" % i, corner + Vector3.UP * (34.0 if i % 2 == 0 else 38.0), Vector2(13, 13))
		var tip_angle := angle + PI / 6.0
		var tip := Vector3(cos(tip_angle), 0, sin(tip_angle)) * STAR_RADIUS * 1.366
		add_pad("t%d" % i, tip + Vector3.UP * 32.0, Vector2(13, 13))
	for i in 6:
		add_road("d%d" % i, "t%d" % i)
		add_road("t%d" % i, "d%d" % ((i + 1) % 6))
		if i % 2 == 0:
			add_road("summit", "d%d" % i)

	_dress_pads()
	_dress_roads()
	_build_range()
	add_weather(2600, 0.11, Color(1, 1, 1, 0.85), 2.2, 2.5)

	for i in 6:
		# Corners face along the star toward the next point.
		add_spawn("d%d" % i, "t%d" % i)
	add_spawn("summit", "d0", 3.0)
	add_spawn("t3", "d4")


## Pads are the flattened tops of snowy peaks that run all the way down to
## the lake.
func _dress_pads() -> void:
	var pad_ice := make_shader_material("ice", {"road_width": 13.0})
	var index := 0
	for id in pad_ids():
		var body := pad_body(id)
		piece_mesh(body).material_override = pad_ice
		var top := pad_position(id) + Vector3.DOWN * 0.35
		var kit := MeshKit.new()
		var flare := _rng.randf_range(26.0, 40.0)
		kit.shell(make_rock_rings(top, pad_half(id) * 1.04, LAKE - 6.0, 70 + index, 0.22, flare, 0.12), true, body.transform.affine_inverse())
		kit.instance(body, _rock)
		index += 1


## Each road rides on a natural rock rib, thick where it meets the peaks and
## thin in the middle like an arch, hung with icicles.
func _dress_roads() -> void:
	var icicle_mat := StandardMaterial3D.new()
	icicle_mat.albedo_color = Color(0.75, 0.88, 1.0, 0.75)
	icicle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	icicle_mat.roughness = 0.05
	icicle_mat.metallic_specular = 0.9
	for road in roads():
		var body: StaticBody3D = road["body"]
		var start: Vector3 = road["start"]
		var end: Vector3 = road["end"]
		var thickness: float = road["thickness"]
		var forward := (end - start).normalized()
		var right := Vector3.UP.cross(forward).normalized()
		var down := right.cross(forward).normalized()
		var to_local := body.transform.affine_inverse()
		var length := start.distance_to(end)
		var stations := maxi(int(length / 3.0), 4)
		var rings := []
		var noise := FastNoiseLite.new()
		noise.seed = _rng.randi()
		noise.frequency = 0.15
		var points := 14
		for s in stations + 1:
			var t := s / float(stations)
			# Run a little into the peaks at both ends.
			var centre := start.lerp(end, t) + forward * lerpf(-3.0, 3.0, t) + Vector3.DOWN * (thickness - 0.05)
			var depth := 3.0 + 12.0 * pow(absf(t - 0.5) * 2.0, 2.0) + noise.get_noise_1d(s * 3.0) * 1.2
			var half_w := road_width * 0.5 - 0.15 + absf(t - 0.5) * 2.0
			var ring := PackedVector3Array()
			for k in points:
				var a := TAU * k / float(points)
				var c := cos(a)
				var sn := sin(a)
				var bump := 1.0 + noise.get_noise_2d(s * 2.0, k * 3.0) * 0.25
				var below := sn * depth * bump if sn > 0.0 else sn * 0.3
				var across := c * half_w * (bump if sn > 0.2 else 1.0)
				ring.append(centre + right * across + down * below)
			rings.append(ring)
		var kit := MeshKit.new()
		kit.shell(rings, false, to_local)
		kit.instance(body, _rock)

		# Icicles hanging from the thin middle of the rib.
		var ice := MeshKit.new()
		var count := int(length / 2.0)
		for k in count:
			var t := _rng.randf_range(0.2, 0.8)
			var span := absf(t - 0.5) * 2.0
			var depth := 3.0 + 12.0 * span * span
			var side := _rng.randf_range(-0.6, 0.6)
			var top := start.lerp(end, t) + right * side * road_width * 0.4 + down * (depth * (1.0 - absf(side) * 0.5) - 0.4)
			var drop := _rng.randf_range(0.8, 2.6)
			ice.tube(to_local * top, to_local * (top + Vector3.DOWN * drop), _rng.randf_range(0.08, 0.18), 0.0, 5)
		ice.instance(body, icicle_mat, false)


## The mountains all round, the frozen lake in the bowl, and snowy pines on
## the lower slopes.
func _build_range() -> void:
	var lake := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(900, 900)
	plane.material = make_shader_material("ice", {"world_mode": true, "snow_patches": 0.6})
	lake.mesh = plane
	lake.position.y = LAKE
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)

	var ridges := FastNoiseLite.new()
	ridges.seed = 21
	ridges.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.frequency = 0.0026
	ridges.fractal_octaves = 5
	ridges.domain_warp_enabled = true
	ridges.domain_warp_amplitude = 60.0
	ridges.domain_warp_frequency = 0.004
	var hills := FastNoiseLite.new()
	hills.seed = 4
	hills.frequency = 0.01
	var massif := FastNoiseLite.new()
	massif.seed = 12
	massif.frequency = 0.0012
	var height_at := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length()
		# Lake bowl, a shore, then the range rising all round, in massifs
		# with ridges and gullies rather than an even wall of spikes.
		var rise := smoothstep(190.0, 560.0, d)
		var bulk := 110.0 + massif.get_noise_2d(x, z) * 90.0
		var h := LAKE - 4.0 + rise * (bulk + ridges.get_noise_2d(x, z) * 170.0)
		h += hills.get_noise_2d(x, z) * 10.0 * smoothstep(150.0, 260.0, d)
		return maxf(h, LAKE - 4.0)
	var colour_at := func(_x: float, _z: float, _h: float, _n: Vector3) -> Color:
		return Color(1, 1, 1)
	var terrain := MeshInstance3D.new()
	terrain.mesh = make_terrain(260, 2600.0, height_at, colour_at)
	terrain.material_override = make_shader_material("snow_rock", {"snow_amount": 0.42})
	add_child(terrain)

	# A few lone spires standing in the lake.
	var spires := MeshKit.new()
	for i in 9:
		var angle := _rng.randf() * TAU
		var r := _rng.randf_range(150.0, 230.0)
		var top := Vector3(cos(angle) * r, _rng.randf_range(-10.0, 45.0), sin(angle) * r)
		spires.shell(make_rock_rings(top, Vector2.ONE * _rng.randf_range(5.0, 12.0), LAKE - 4.0, 500 + i, 0.25, _rng.randf_range(18.0, 40.0), 0.12, 24))
	spires.instance(self, _rock)

	_build_forest(height_at)


func _build_forest(height_at: Callable) -> void:
	var tree := MeshKit.new()
	tree.color = Color(0.25, 0.17, 0.1)
	tree.tube(Vector3.ZERO, Vector3.UP * 2.0, 0.25, 0.2, 6)
	var tiers := 4
	for k in tiers:
		var y := 1.2 + k * 2.1
		var r := 2.6 - k * 0.55
		tree.color = Color(0.07, 0.17, 0.11)
		tree.cone(Vector3.UP * y, r, 3.2, 8)
		# Snow lying on each tier.
		tree.color = Color(0.92, 0.94, 0.98)
		tree.cone(Vector3.UP * (y + 0.9), r * 0.82, 2.3, 8)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	var mesh := tree.commit(mat)
	var transforms := []
	var tries := 0
	while transforms.size() < 1800 and tries < 12000:
		tries += 1
		var angle := _rng.randf() * TAU
		var r := _rng.randf_range(200.0, 700.0)
		var x := cos(angle) * r
		var z := sin(angle) * r
		var h: float = height_at.call(x, z)
		var slope := absf(float(height_at.call(x + 3.0, z)) - h) + absf(float(height_at.call(x, z + 3.0)) - h)
		if slope > 3.5 or h > 90.0:
			continue
		var s := _rng.randf_range(0.8, 1.7)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.9, 1.3), s)), Vector3(x, h - 0.3, z)))
	add_multimesh(mesh, transforms)
