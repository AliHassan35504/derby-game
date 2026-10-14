class_name MountainSpiralMap
extends DerbyMap
## A dark asphalt road spiralling up around a rock pillar, high above a foggy
## pine valley, to a summit platform. Knocked cars can land on the turn below.

const RADIUS := 36.0
const NODES_PER_TURN := 9
const NODE_COUNT := 20
const BOTTOM := 12.0
const TOP := 56.0


func build() -> void:
	map_name = "Mountain Spiral"
	car_type = "monster"
	rule_text = "Big suspension: hops go much higher"
	kill_height = -12.0
	road_width = 5.4
	stilt_bottom = -75.0
	stilt_clear_radius = 0.0
	hop_multiplier = 1.5

	make_environment(Color(0.35, 0.48, 0.66), Color(0.74, 0.78, 0.82), Color(0.25, 0.3, 0.28),
			Color(0.72, 0.76, 0.8), 0.006, Vector3(-28, 60, 0), 1.2)

	var stilt := StandardMaterial3D.new()
	stilt.albedo_color = Color(0.42, 0.42, 0.42)
	stilt.roughness = 0.85
	set_materials(make_asphalt_material(), stilt)

	for i in NODE_COUNT:
		var angle := TAU * i / float(NODES_PER_TURN)
		var y := lerpf(BOTTOM, TOP, i / float(NODE_COUNT - 1))
		# The top pad is where the road turns in to the summit, so it is larger.
		var size := Vector2(14, 14) if i == NODE_COUNT - 1 else Vector2(10, 10)
		add_pad(str(i), Vector3(cos(angle) * RADIUS, y, sin(angle) * RADIUS), size)
	add_pad("summit", Vector3(0, TOP + 5.0, 0), Vector2(16, 16))
	for i in NODE_COUNT - 1:
		add_road(str(i), str(i + 1))
	add_road(str(NODE_COUNT - 1), "summit")

	_build_pillar()
	_build_valley()

	for i in [0, 3, 6, 9, 12, 15, 18, 1]:
		add_spawn(str(i), str(i + 1))


func _build_pillar() -> void:
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.36, 0.34, 0.32)
	rock.roughness = 1.0
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	rock.normal_enabled = true
	rock.normal_texture = tex
	rock.uv1_scale = Vector3(6, 10, 1)
	var pillar := CylinderMesh.new()
	pillar.top_radius = 7.0
	pillar.bottom_radius = 13.0
	pillar.height = TOP + 4.4 + 60.0
	pillar.radial_segments = 20
	var shape := CylinderShape3D.new()
	shape.radius = 9.0
	shape.height = pillar.height
	add_obstacle(pillar, shape, Vector3(0, (TOP + 4.4 - 60.0) * 0.5, 0), rock)


func _build_valley() -> void:
	# Hilly terrain far below, coloured by height, with a pine forest.
	var noise := FastNoiseLite.new()
	noise.frequency = 0.004
	noise.fractal_octaves = 5
	var cells := 120
	var extent := 1400.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var heights := []
	for z in cells + 1:
		var row := []
		for x in cells + 1:
			var px := (x / float(cells) - 0.5) * extent
			var pz := (z / float(cells) - 0.5) * extent
			var dist := Vector2(px, pz).length()
			var h := noise.get_noise_2d(px, pz) * 70.0 - 55.0 + smoothstep(120.0, 600.0, dist) * 90.0
			row.append(h)
		heights.append(row)
	for z in cells:
		for x in cells:
			var quad := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x + 1, z + 1), Vector2i(x, z), Vector2i(x + 1, z + 1), Vector2i(x, z + 1)]
			for c in quad:
				var h: float = heights[c.y][c.x]
				var col := Color(0.2, 0.3, 0.16).lerp(Color(0.42, 0.4, 0.36), smoothstep(-10.0, 40.0, h))
				col = col.lerp(Color(0.92, 0.94, 0.96), smoothstep(55.0, 75.0, h))
				st.set_color(col)
				st.add_vertex(Vector3((c.x / float(cells) - 0.5) * extent, h, (c.y / float(cells) - 0.5) * extent))
	st.generate_normals()
	var ground_mat := StandardMaterial3D.new()
	ground_mat.vertex_color_use_as_albedo = true
	ground_mat.roughness = 1.0
	var terrain := MeshInstance3D.new()
	terrain.mesh = st.commit()
	terrain.material_override = ground_mat
	add_child(terrain)

	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 3.2
	pine.height = 14.0
	pine.radial_segments = 7
	var pine_mat := StandardMaterial3D.new()
	pine_mat.albedo_color = Color(0.08, 0.17, 0.1)
	pine_mat.roughness = 1.0
	pine.material = pine_mat
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = pine
	var count := 900
	multi.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in count:
		var px := rng.randf_range(-extent * 0.45, extent * 0.45)
		var pz := rng.randf_range(-extent * 0.45, extent * 0.45)
		var gx := clampi(int((px / extent + 0.5) * cells), 0, cells)
		var gz := clampi(int((pz / extent + 0.5) * cells), 0, cells)
		var h: float = heights[gz][gx]
		var s := rng.randf_range(0.7, 1.4)
		multi.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), Vector3(px, h + 6.0 * s, pz)))
	var forest := MultiMeshInstance3D.new()
	forest.multimesh = multi
	add_child(forest)
