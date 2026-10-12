class_name NeonOverpassMap
extends DerbyMap
## A stacked highway interchange in a city at night, after the rain. A high
## level of ramps runs north-south and a low level east-west, crossing over
## and under each other five times, joined by a ring of ramps round the
## outside. Skyscrapers with lit windows and neon signs rise between the
## ramps; the streets and their traffic are far below.

const HIGH := 32.0
const LOW := 20.0
const CORNER := 26.0
## Made-up names for the neon signs.
const SIGNS := [
	"KAIJU RAMEN", "HOTEL ORBIT", "NIGHT OWL", "PIXEL DINER", "ZENITH", "LUMEN CLUB",
	"MOONLIGHT MOTEL", "HYPERDRIVE", "NOODLE BAR 24H", "ARCADIA", "VELVET LOUNGE", "NOVA TAXI",
	"KARAOKE", "SUSHI GO-GO", "CYBER CAFE", "STARLINE", "TOKYO DRIFT INN", "GOLDEN DRAGON",
]
const NEON_COLOURS := [
	Color(1.0, 0.1, 0.55), Color(0.1, 0.8, 1.0), Color(1.0, 0.55, 0.05), Color(0.5, 0.2, 1.0),
	Color(0.2, 1.0, 0.4), Color(1.0, 0.15, 0.1), Color(1.0, 0.9, 0.2),
]

var _rng := RandomNumberGenerator.new()
var _concrete: ShaderMaterial
var _steel: ShaderMaterial
var _lamps: Array[Light3D] = []
## Footprints (centre, half size) of the towers inside the arena.
var _towers: Array = []


func build() -> void:
	map_name = "Neon Overpass"
	car_type = "sedan"
	rule_text = "Rain-slick asphalt: grip is down 15%"
	kill_height = 10.0
	road_width = 5.2
	plain_stilts = false
	grip_multiplier = 0.85
	_rng.seed = 2088

	make_environment(Color(0.01, 0.015, 0.04), Color(0.16, 0.08, 0.2), Color(0.02, 0.02, 0.03),
			Color(0.09, 0.06, 0.13), 0.0035, Vector3(-38, -120, 0), 0.22)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/night_sky.gdshader")
	environment.sky.sky_material = sky_mat
	sun.light_color = Color(0.62, 0.7, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.3, 0.28, 0.42)
	environment.ambient_light_energy = 0.9
	environment.fog_aerial_perspective = 0.2
	environment.fog_sky_affect = 0.15
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.12
	environment.glow_hdr_threshold = 0.9
	environment.adjustment_saturation = 1.2

	_concrete = make_shader_material("concrete", {"tint": Color(0.5, 0.5, 0.52), "wetness": 0.35})
	_steel = make_shader_material("steel", {"paint": Color(0.3, 0.31, 0.33), "rust_amount": 0.1, "grime_height": -10.0, "metallic": 0.6, "roughness": 0.4})
	set_materials(make_shader_material("wet_road", {"road_width": road_width}), _concrete)

	# Ring of ramps round the outside; ends of the high and low levels.
	add_pad("c_nw", Vector3(-75, CORNER, -75), Vector2(11, 11))
	add_pad("c_ne", Vector3(75, CORNER, -75), Vector2(11, 11))
	add_pad("c_se", Vector3(75, CORNER, 75), Vector2(11, 11))
	add_pad("c_sw", Vector3(-75, CORNER, 75), Vector2(11, 11))
	add_pad("h_nw", Vector3(-25, HIGH, -75), Vector2(12, 12))
	add_pad("h_ne", Vector3(25, HIGH, -75), Vector2(12, 12))
	add_pad("h_sw", Vector3(-25, HIGH, 75), Vector2(12, 12))
	add_pad("h_se", Vector3(25, HIGH, 75), Vector2(12, 12))
	add_pad("l_wn", Vector3(-75, LOW, -25), Vector2(12, 12))
	add_pad("l_ws", Vector3(-75, LOW, 25), Vector2(12, 12))
	add_pad("l_en", Vector3(75, LOW, -25), Vector2(12, 12))
	add_pad("l_es", Vector3(75, LOW, 25), Vector2(12, 12))
	# Junctions in the middle of each level.
	add_pad("m_w", Vector3(-25, HIGH, 0), Vector2(12, 12))
	add_pad("m_e", Vector3(25, HIGH, 0), Vector2(12, 12))
	add_pad("m_n", Vector3(0, LOW, -25), Vector2(12, 12))
	add_pad("m_s", Vector3(0, LOW, 25), Vector2(12, 12))

	var ring := ["c_nw", "h_nw", "h_ne", "c_ne", "l_en", "l_es", "c_se", "h_se", "h_sw", "c_sw", "l_ws", "l_wn", "c_nw"]
	for i in ring.size() - 1:
		add_road(ring[i], ring[i + 1])
	for pair in [["h_nw", "m_w"], ["m_w", "h_sw"], ["h_ne", "m_e"], ["m_e", "h_se"],
			["l_wn", "m_n"], ["m_n", "l_en"], ["l_ws", "m_s"], ["m_s", "l_es"],
			["m_w", "m_e"], ["m_n", "m_s"]]:
		add_road(pair[0], pair[1])

	_dress_pads()
	_dress_roads()
	_build_city()

	add_spawn("h_nw", "m_w")
	add_spawn("h_se", "m_e")
	add_spawn("l_wn", "m_n")
	add_spawn("l_es", "m_s")
	add_spawn("m_e", "m_w", 2.0)
	add_spawn("m_n", "m_s", 2.0)
	add_spawn("c_ne", "h_ne")
	add_spawn("c_sw", "h_sw")


func apply_quality(level: int) -> void:
	super(level)
	# Street lights are cheap without shadows, but trim them on Low.
	for i in _lamps.size():
		_lamps[i].visible = level >= 1 or i % 2 == 0


## Pads get the box-junction hatch and a concrete pier with a capital.
func _dress_pads() -> void:
	var junction := {}
	for id in pad_ids():
		var body := pad_body(id)
		var half := pad_half(id)
		var size := half.x * 2.0
		if not junction.has(size):
			junction[size] = make_shader_material("wet_road", {"junction": true, "pad_size": size})
		piece_mesh(body).material_override = junction[size]
		var pos := pad_position(id)
		var kit := MeshKit.new()
		var to_local := body.transform.affine_inverse()
		var bottom := -1.0
		kit.cube(to_local * Vector3(pos.x, pos.y - 1.4, pos.z), Vector3(half.x * 1.6, 1.6, half.y * 1.6))
		kit.box(to_local * Transform3D(Basis.IDENTITY, Vector3(pos.x, (pos.y - 2.2 + bottom) * 0.5, pos.z)), Vector3(3.2, pos.y - 2.2 - bottom, 3.2))
		kit.instance(body, _concrete)


## Box girders, piers, edge light strips and street lamps for every road.
func _dress_roads() -> void:
	var strip_high := _emissive(Color(0.1, 0.75, 1.0), 4.0)
	var strip_low := _emissive(Color(1.0, 0.15, 0.6), 4.0)
	var lamp_glass := _emissive(Color(1.0, 0.85, 0.65), 6.0)
	var lamp_index := 0
	for road in roads():
		var body: StaticBody3D = road["body"]
		var start: Vector3 = road["start"]
		var end: Vector3 = road["end"]
		var thickness: float = road["thickness"]
		var length := start.distance_to(end)
		var forward := (end - start).normalized()
		var right := Vector3.UP.cross(forward).normalized()
		var to_local := body.transform.affine_inverse()
		var high := minf(start.y, end.y) > LOW + 3.0
		var kit := MeshKit.new()
		var under := -thickness * 0.5
		# Box girder under the deck.
		kit.cube(Vector3(0, under - 0.75, 0), Vector3(road_width * 0.7, 1.5, length))
		kit.cube(Vector3(0, under - 0.12, 0), Vector3(road_width + 0.3, 0.25, length))
		# Piers: a column with a hammerhead cap every 18 m, standing on the
		# street, skipped where they would go through a road below.
		var piers := maxi(int(length / 18.0), 1)
		for i in piers:
			var t := (i + 0.5) / float(piers)
			var top := start.lerp(end, t) + Vector3.DOWN * (thickness + 1.5)
			if deck_below(top, 2.5, body) > -INF:
				continue
			kit.box(to_local * Transform3D(Basis(Vector3.UP, atan2(forward.x, forward.z)), top + Vector3.DOWN * 0.6), Vector3(road_width * 0.9, 1.2, 2.2))
			kit.tube(to_local * (top + Vector3.DOWN * 1.2), to_local * Vector3(top.x, -1.0, top.z), 1.1, 1.3, 14)
		kit.instance(body, _concrete)

		# Light strips along both edges of the deck.
		var strips := MeshKit.new()
		for side in [-1.0, 1.0]:
			strips.cube(Vector3(side * (road_width * 0.5 + 0.16), under - 0.05, 0), Vector3(0.04, 0.07, length - 0.4))
		strips.instance(body, strip_high if high else strip_low, false)

		# Street lamps on brackets outside the deck edge, alternating sides.
		var poles := MeshKit.new()
		var heads := MeshKit.new()
		var count := maxi(int(length / 24.0), 1)
		for i in count:
			var t := (i + 0.5) / float(count)
			var side := 1.0 if (i + lamp_index) % 2 == 0 else -1.0
			var base := start.lerp(end, t)
			var foot := base + right * side * (road_width * 0.5 + 0.45) + Vector3.DOWN * 1.2
			var mast := base + right * side * (road_width * 0.5 + 0.45) + Vector3.UP * 8.0
			var head := base + right * side * (road_width * 0.5 - 1.3) + Vector3.UP * 8.3
			poles.tube(to_local * foot, to_local * mast, 0.14, 0.1, 8)
			poles.tube(to_local * mast, to_local * head, 0.08, 0.07, 6)
			poles.beam(to_local * (foot + Vector3.UP * 0.6), to_local * (base + right * side * (road_width * 0.5 - 0.1) + Vector3.DOWN * 0.6), 0.25, 0.25)
			heads.box(to_local * Transform3D(MeshKit.frame(right * -side), head + Vector3.DOWN * 0.15), Vector3(0.45, 0.18, 1.1))
			var light := SpotLight3D.new()
			light.light_color = Color(1.0, 0.68, 0.38) if not high else Color(0.85, 0.9, 1.0)
			light.light_energy = 9.0
			light.spot_range = 22.0
			light.spot_angle = 58.0
			light.spot_attenuation = 0.8
			light.light_specular = 0.9
			body.add_child(light)
			light.transform = to_local * Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), head + Vector3.DOWN * 0.4)
			_lamps.append(light)
		lamp_index += 1
		poles.instance(body, _steel)
		heads.instance(body, lamp_glass, false)


## Towers between the ramps, the city all round, neon signs, screens and
## the streets below.
func _build_city() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2400, 2400)
	plane.material = make_shader_material("city_ground")
	ground.mesh = plane
	ground.position.y = -1.0
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	var tower_mesh := BoxMesh.new()
	tower_mesh.size = Vector3.ONE
	tower_mesh.material = make_shader_material("windows", {"night": 1.0, "shop_glow": 1.0})
	var transforms := []
	var custom := []
	# Inside the arena: the eight cells between the ramps.
	for cx in [-50.0, 0.0, 50.0]:
		for cz in [-50.0, 0.0, 50.0]:
			if cx == 0.0 and cz == 0.0:
				continue
			var half := Vector2(_rng.randf_range(9.0, 11.5), _rng.randf_range(9.0, 11.5))
			var h := _rng.randf_range(55.0, 150.0)
			var centre := Vector3(cx, h * 0.5 - 1.0, cz)
			transforms.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.0, h, half.y * 2.0)), centre))
			custom.append(Color(_rng.randf(), _rng.randf_range(0.25, 0.5), 1.0 if _rng.randf() < 0.5 else 0.0, _rng.randf()))
			_towers.append([centre, half, h])
	# The rest of the city, denser near the arena and taller downtown.
	var placed := 0
	while placed < 420:
		var p := Vector2(_rng.randf_range(-900.0, 900.0), _rng.randf_range(-900.0, 900.0))
		if absf(p.x) < 110.0 and absf(p.y) < 110.0:
			continue
		# Keep to city blocks: streets run every 96 m.
		var block_off := Vector2(fposmod(p.x + 48.0, 96.0) - 48.0, fposmod(p.y + 48.0, 96.0) - 48.0)
		var w := _rng.randf_range(16.0, 34.0)
		var d := _rng.randf_range(16.0, 34.0)
		if absf(block_off.x) < 13.0 + w * 0.5 or absf(block_off.y) < 13.0 + d * 0.5:
			continue
		var dist := p.length()
		var h := _rng.randf_range(20.0, 70.0) + maxf(0.0, 260.0 - dist * 0.35) * _rng.randf()
		transforms.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), Vector3(p.x, h * 0.5 - 1.0, p.y)))
		custom.append(Color(_rng.randf(), _rng.randf_range(0.15, 0.5), 1.0 if _rng.randf() < 0.4 else 0.0, _rng.randf()))
		placed += 1
	add_multimesh(tower_mesh, transforms, [], custom)

	_build_signs()
	_build_rooftops()


## Neon signs and screens on the arena towers, facing the ramps.
func _build_signs() -> void:
	var names := SIGNS.duplicate()
	var frame_kit := {}
	var sign_index := 0
	for tower in _towers:
		var centre: Vector3 = tower[0]
		var half: Vector2 = tower[1]
		var h: float = tower[2]
		# Faces looking toward the middle of the map.
		var faces := []
		if absf(centre.x) > 1.0:
			faces.append(Vector3(-signf(centre.x), 0, 0))
		if absf(centre.z) > 1.0:
			faces.append(Vector3(0, 0, -signf(centre.z)))
		for normal in faces:
			var colour: Color = NEON_COLOURS[sign_index % NEON_COLOURS.size()]
			var text: String = names[sign_index % names.size()]
			var face_half := half.y if absf(normal.x) > 0.5 else half.x
			var surface: Vector3 = centre + normal * ((half.x if absf(normal.x) > 0.5 else half.y) + 0.35)
			var along := Vector3.UP.cross(normal).normalized()
			var y := _rng.randf_range(LOW + 8.0, minf(h - 8.0, HIGH + 20.0))
			var vertical := sign_index % 3 == 2
			var label := Label3D.new()
			label.text = "\n".join(text.split("")) if vertical else text
			label.font_size = 64 if vertical else 96
			# Big letters, but never wider than the tower face.
			var pixel := minf(0.04, face_half * 1.7 / (text.length() * 0.62 * 96.0))
			label.pixel_size = pixel if not vertical else 0.034
			label.outline_size = 18
			label.modulate = Color(colour.r * 2.2, colour.g * 2.2, colour.b * 2.2)
			label.outline_modulate = Color(colour.r, colour.g, colour.b, 0.45)
			label.double_sided = false
			label.line_spacing = -18.0 if vertical else 0.0
			add_child(label)
			var offset: Vector3 = along * _rng.randf_range(-face_half * 0.3, face_half * 0.3) if not vertical else along * (face_half - 2.0)
			label.global_transform = Transform3D(Basis(along, Vector3.UP, normal), Vector3(surface.x, y, surface.z) + offset)
			# Backing panel and a glowing frame tube round the sign.
			var size := Vector2(text.length() * 0.62 * 96.0 * pixel + 2.0, 96.0 * pixel * 1.3) if not vertical else Vector2(3.6, text.length() * 64.0 * 0.034 * 0.95 + 1.5)
			var key := colour.to_html()
			if not frame_kit.has(key):
				frame_kit[key] = [MeshKit.new(), colour]
			var kit: MeshKit = frame_kit[key][0]
			var c: Vector3 = Vector3(surface.x, y, surface.z) + offset - normal * 0.2
			var hx := along * size.x * 0.5
			var hy := Vector3.UP * size.y * 0.5
			for edge in [[-hx - hy, hx - hy], [-hx + hy, hx + hy], [-hx - hy, -hx + hy], [hx - hy, hx + hy]]:
				kit.tube(c + edge[0], c + edge[1], 0.07, 0.07, 6)
			var panel := MeshKit.new()
			panel.color = Color(0.03, 0.03, 0.04)
			panel.box(Transform3D(Basis(along, Vector3.UP, normal), c - normal * 0.15), Vector3(size.x, size.y, 0.25))
			panel.instance(self, _steel, false)
			# A soft coloured light spilling from the sign onto the ramps.
			var spill := OmniLight3D.new()
			spill.light_color = colour
			spill.light_energy = 2.5
			spill.omni_range = 22.0
			spill.omni_attenuation = 1.5
			add_child(spill)
			spill.global_position = c + normal * 3.0
			_lamps.append(spill)
			sign_index += 1
		# A video screen high up on some towers.
		if sign_index % 2 == 0 and h > 70.0:
			var normal: Vector3 = faces[0]
			var along := Vector3.UP.cross(normal).normalized()
			var face_d := half.x if absf(normal.x) > 0.5 else half.y
			var screen := MeshInstance3D.new()
			var quad := QuadMesh.new()
			quad.size = Vector2(14.0, 8.0)
			var mat := make_shader_material("neon_screen", {"seed": _rng.randf(),
					"colour_a": NEON_COLOURS[_rng.randi() % NEON_COLOURS.size()],
					"colour_b": NEON_COLOURS[_rng.randi() % NEON_COLOURS.size()]})
			quad.material = mat
			screen.mesh = quad
			screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(screen)
			screen.global_transform = Transform3D(Basis(along, Vector3.UP, normal), Vector3(centre.x, h - 14.0, centre.z) + normal * (face_d + 0.3))
	for key in frame_kit:
		var entry: Array = frame_kit[key]
		var colour: Color = entry[1]
		entry[0].instance(self, _emissive(colour, 5.0), false)


## Red aircraft warning lights and rooftop billboards on the arena towers.
func _build_rooftops() -> void:
	var red := MeshKit.new()
	for tower in _towers:
		var centre: Vector3 = tower[0]
		var half: Vector2 = tower[1]
		var h: float = tower[2]
		var roof := h - 1.0
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				red.cube(Vector3(centre.x + sx * (half.x - 0.5), roof + 0.4, centre.z + sz * (half.y - 0.5)), Vector3(0.5, 0.5, 0.5))
		# Rooftop plant room and mast.
		var plant := MeshKit.new()
		plant.color = Color(0.5, 0.5, 0.52)
		plant.cube(Vector3(centre.x, roof + 2.0, centre.z), Vector3(half.x, 4.0, half.y))
		plant.tube(Vector3(centre.x, roof + 4.0, centre.z), Vector3(centre.x, roof + 18.0, centre.z), 0.4, 0.15, 6)
		plant.instance(self, _concrete)
		red.cube(Vector3(centre.x, roof + 18.3, centre.z), Vector3(0.6, 0.6, 0.6))
	red.instance(self, _emissive(Color(1.0, 0.05, 0.03), 8.0), false)


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
