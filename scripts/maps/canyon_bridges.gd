class_name CanyonBridgesMap
extends DerbyMap
## A red-rock desert canyon at midday. The roads are plank bridges strung
## between the flat tops of sandstone mesas: sagging rope spans and tall
## timber trestles, at different heights. Two long bridges cross in the
## middle, one over the other, making a figure eight. A river winds along
## the canyon floor far below.

const FLOOR := -52.0
const RIVER := -55.0
## Bridges laid as sagging rope spans (sag in metres); the rest are trestles.
const ROPE_SPANS := {"d-c": 2.6, "a-b": 1.4, "e-f": 1.4, "n-d": 1.2, "c-s": 1.2}

var _rng := RandomNumberGenerator.new()
var _rock: ShaderMaterial
var _timber: ShaderMaterial
var _rope: StandardMaterial3D


func build() -> void:
	map_name = "Canyon Bridges"
	car_type = "muscle"
	rule_text = "Desert drag strip: nitro refills 50% faster"
	kill_height = 2.0
	road_width = 5.0
	plain_stilts = false
	nitro_refill_multiplier = 1.5
	_rng.seed = 1977

	make_environment(Color(0.2, 0.42, 0.76), Color(0.8, 0.74, 0.64), Color(0.42, 0.28, 0.18),
			Color(0.86, 0.68, 0.5), 0.0012, Vector3(-62, 35, 0), 1.35)
	sun.light_color = Color(1.0, 0.94, 0.84)
	environment.ambient_light_energy = 0.6
	environment.fog_sun_scatter = 0.15
	environment.fog_height = 10.0
	environment.fog_height_density = 0.004
	var sky_mat: ProceduralSkyMaterial = environment.sky.sky_material
	sky_mat.sun_angle_max = 6.0
	sky_mat.sky_curve = 0.18
	var river := add_ocean(RIVER, Color(0.06, 0.16, 0.14), Color(0.22, 0.32, 0.24), 0.12)
	(river.mesh.material as ShaderMaterial).set_shader_parameter("foam_amount", 0.25)

	_rock = make_shader_material("sandstone")
	_timber = make_shader_material("timber")
	_rope = StandardMaterial3D.new()
	_rope.albedo_color = Color(0.56, 0.47, 0.34)
	_rope.roughness = 1.0
	set_materials(make_plank_material(Color(0.6, 0.45, 0.3), Color(0.36, 0.25, 0.16), 0.3), _timber)
	pad_material = _rock

	add_pad("a", Vector3(-45, 22, -40), Vector2(12, 12))
	add_pad("f", Vector3(45, 22, 40), Vector2(12, 12))
	add_pad("d", Vector3(45, 34, -40), Vector2(12, 12))
	add_pad("c", Vector3(-45, 34, 40), Vector2(12, 12))
	add_pad("b", Vector3(-80, 28, 0), Vector2(11, 11))
	add_pad("e", Vector3(80, 28, 0), Vector2(11, 11))
	add_pad("n", Vector3(0, 28, -85), Vector2(11, 11))
	add_pad("s", Vector3(0, 28, 85), Vector2(11, 11))

	for pair in [["a", "f"], ["d", "c"], ["a", "b"], ["b", "c"], ["d", "e"], ["e", "f"],
			["a", "n"], ["n", "d"], ["c", "s"], ["s", "f"]]:
		var key: String = pair[0] + "-" + pair[1]
		if ROPE_SPANS.has(key):
			add_sagging_road(pair[0], pair[1], ROPE_SPANS[key], 12)
		else:
			add_road(pair[0], pair[1])

	_build_mesas()
	_dress_bridges()
	_build_canyon()
	add_weather(500, 0.06, Color(1.0, 0.9, 0.75, 0.5), 0.4, 1.5, Vector3(40, 15, 40))

	add_spawn("a", "f")
	add_spawn("f", "a")
	add_spawn("d", "c")
	add_spawn("c", "d")
	add_spawn("b", "a")
	add_spawn("e", "f")
	add_spawn("n", "d")
	add_spawn("s", "c")


## Each pad is the flat cap of a sandstone mesa rising from the canyon floor.
func _build_mesas() -> void:
	var i := 0
	for id in pad_ids():
		var body := pad_body(id)
		piece_mesh(body).visible = false
		var top := pad_position(id)
		var kit := MeshKit.new()
		var rings := make_rock_rings(top, pad_half(id) * 1.02, FLOOR - 4.0, 300 + i, 0.16, 9.0, 0.1)
		kit.shell(rings, true, body.transform.affine_inverse())
		kit.instance(body, _rock)
		i += 1


## Rope spans get edge ropes, hangers and anchor stakes; the others stand on
## timber trestle bents down to the rocks.
func _dress_bridges() -> void:
	for road in roads():
		var body: StaticBody3D = road["body"]
		var start: Vector3 = road["start"]
		var end: Vector3 = road["end"]
		var sag: float = road["sag"]
		var to_local := body.transform.affine_inverse()
		var forward := (end - start).normalized()
		var right := Vector3.UP.cross(forward).normalized()
		if sag > 0.0:
			_rope_span(body, to_local, start, end, sag, right)
		else:
			_trestle(body, to_local, start, end, right, road["thickness"])


func _rope_span(body: StaticBody3D, to_local: Transform3D, start: Vector3, end: Vector3, sag: float, right: Vector3) -> void:
	var ropes := MeshKit.new()
	var wood := MeshKit.new()
	var steps := 24
	for side in [-1.0, 1.0]:
		var offset: Vector3 = right * side * (road_width * 0.5 + 0.05)
		for i in steps:
			var p0 := sag_point(start, end, sag, i / float(steps)) + offset + Vector3.DOWN * 0.2
			var p1 := sag_point(start, end, sag, (i + 1) / float(steps)) + offset + Vector3.DOWN * 0.2
			ropes.tube(to_local * p0, to_local * p1, 0.09, 0.09, 6)
		# Anchor stakes driven into the rock at both ends.
		for end_point in [start, end]:
			var stake: Vector3 = end_point + offset
			wood.tube(to_local * (stake + Vector3.DOWN * 1.2), to_local * (stake + Vector3.UP * 0.45), 0.16, 0.13, 7, true)
	# Under-deck stringer logs.
	for side: float in [-0.6, 0.6]:
		for i in steps:
			var p0 := sag_point(start, end, sag, i / float(steps)) + right * side + Vector3.DOWN * 0.6
			var p1 := sag_point(start, end, sag, (i + 1) / float(steps)) + right * side + Vector3.DOWN * 0.6
			wood.tube(to_local * p0, to_local * p1, 0.14, 0.14, 6)
	ropes.instance(body, _rope)
	wood.instance(body, _timber)


## Timber trestle: bents every few metres, each a pair of battered legs with
## cross girts and X bracing, standing on the rock far below.
func _trestle(body: StaticBody3D, to_local: Transform3D, start: Vector3, end: Vector3, right: Vector3, thickness: float) -> void:
	var kit := MeshKit.new()
	var length := start.distance_to(end)
	var flat := Vector3(end.x - start.x, 0, end.z - start.z).normalized()
	# Stringers under the deck.
	for side in [-1.6, 0.0, 1.6]:
		kit.beam(to_local * (start + right * side + Vector3.DOWN * (thickness + 0.3)),
				to_local * (end + right * side + Vector3.DOWN * (thickness + 0.3)), 0.35, 0.6)
	var bents := maxi(int(length / 7.5), 2)
	var bottom := FLOOR + 2.0
	for i in bents:
		var t := (i + 0.5) / float(bents)
		var cap := start.lerp(end, t) + Vector3.DOWN * (thickness + 0.65)
		if deck_below(cap, 1.5, body) > -INF:
			continue
		var height := cap.y - bottom
		# Cap beam across the top.
		kit.beam(to_local * (cap - right * 2.4), to_local * (cap + right * 2.4), 0.4, 0.4, Vector3.UP)
		var legs := []
		for side in [-1.0, 1.0]:
			var top_p: Vector3 = cap + right * side * 1.9
			var foot: Vector3 = Vector3(top_p.x, bottom, top_p.z) + right * side * height * 0.12
			legs.append([top_p, foot])
			kit.beam(to_local * top_p, to_local * foot, 0.42, 0.42, flat)
		# Storeys: a girt across and X braces in each.
		var storey := 7.0
		var levels := int(height / storey)
		for k in levels + 1:
			var f0 := k * storey / height
			var f1 := minf((k + 1) * storey / height, 1.0)
			var l0: Vector3 = legs[0][0].lerp(legs[0][1], f0)
			var r0: Vector3 = legs[1][0].lerp(legs[1][1], f0)
			var l1: Vector3 = legs[0][0].lerp(legs[0][1], f1)
			var r1: Vector3 = legs[1][0].lerp(legs[1][1], f1)
			kit.beam(to_local * l0, to_local * r0, 0.28, 0.32, Vector3.UP)
			if f1 > f0 + 0.01:
				kit.beam(to_local * l0, to_local * r1, 0.18, 0.22, flat)
				kit.beam(to_local * r0, to_local * l1, 0.18, 0.22, flat)
		# Longitudinal ties to the next bent.
		if i < bents - 1:
			var next_cap := start.lerp(end, (i + 1.5) / float(bents)) + Vector3.DOWN * (thickness + 0.65)
			if deck_below(next_cap, 1.5, body) == -INF:
				for side in [-1.0, 1.0]:
					for k in range(1, int(height / 14.0) + 1):
						var y := k * 14.0
						var a: Vector3 = cap + right * side * (1.9 + y * 0.12) + Vector3.DOWN * y
						var b: Vector3 = next_cap + right * side * (1.9 + (next_cap.y - cap.y + y) * 0.12) + Vector3.DOWN * (next_cap.y - cap.y + y)
						b.y = a.y
						kit.beam(to_local * a, to_local * b, 0.2, 0.25, Vector3.UP)
	kit.instance(body, _timber)


## Canyon walls stepping up in ledges, the floor with its river and green
## banks, distant buttes and hoodoos, and scrub.
func _build_canyon() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 5
	noise.frequency = 0.006
	noise.fractal_octaves = 4
	var detail := FastNoiseLite.new()
	detail.seed = 9
	detail.frequency = 0.03
	var height_at := func(x: float, z: float) -> float:
		# The canyon is a long winding basin: walls all round, far away
		# along its length so the ends fade into the haze.
		var centre := sin(x / 210.0) * 32.0 + sin(x / 90.0 + 1.0) * 10.0
		var half_width := 150.0 + noise.get_noise_2d(x * 0.5, 100.0) * 35.0
		var dz := z - centre
		var d := sqrt(pow(x / 3.4, 2.0) + dz * dz) + noise.get_noise_2d(x, z) * 30.0
		var t := clampf((d - half_width) / 105.0, 0.0, 1.0)
		# Terraces: flat ledges joined by steep cliffs.
		var steps := 6.0
		var s := t * steps
		var stepped := (floorf(s) + smoothstep(0.55, 0.95, s - floorf(s))) / steps
		var h := FLOOR + stepped * 118.0 + detail.get_noise_2d(x, z) * 2.5
		if t >= 1.0:
			h += noise.get_noise_2d(x * 2.0, z * 2.0) * 8.0
		# River channel in the floor.
		var river_z := centre + sin(x / 70.0) * 22.0
		var r := absf(z - river_z)
		h -= (1.0 - smoothstep(9.0, 18.0, r)) * 5.0 * (1.0 - t)
		return h
	var colour_at := func(x: float, z: float, h: float, n: Vector3) -> Color:
		var c := Color(1, 1, 1)
		if h < FLOOR + 3.0 and n.y > 0.8:
			# Green willow and tamarisk along the river.
			var lush := 1.0 - smoothstep(FLOOR - 2.0, FLOOR + 3.0, h)
			c = c.lerp(Color(0.5, 0.62, 0.36), lush * 0.8)
		return c
	var terrain := MeshInstance3D.new()
	terrain.mesh = make_terrain(300, 2400.0, height_at, colour_at)
	terrain.material_override = _rock
	add_child(terrain)

	# Free-standing buttes and hoodoos on the canyon floor, clear of the arena.
	var spires := MeshKit.new()
	for i in 14:
		var angle := _rng.randf() * TAU
		var r := _rng.randf_range(115.0, 165.0)
		var p := Vector3(cos(angle) * r * 1.6, 0, sin(angle) * r)
		var top_y := _rng.randf_range(-5.0, 40.0)
		var half := Vector2(_rng.randf_range(5.0, 16.0), _rng.randf_range(5.0, 16.0))
		spires.shell(make_rock_rings(Vector3(p.x, top_y, p.z), half, FLOOR - 4.0, 900 + i, 0.2, _rng.randf_range(6.0, 20.0), 0.14, 24))
	spires.instance(self, _rock)

	# Scrub and junipers on the ledges and the plateau, cottonwoods by the river.
	var bush := MeshKit.new()
	bush.color = Color(0.36, 0.4, 0.22)
	bush.shell([_ring(0.0, 0.9, 7), _ring(0.6, 1.2, 7), _ring(1.3, 0.8, 7), _ring(1.7, 0.2, 7)])
	var bush_mat := StandardMaterial3D.new()
	bush_mat.vertex_color_use_as_albedo = true
	bush_mat.roughness = 1.0
	var bush_mesh := bush.commit(bush_mat)
	var transforms := []
	var colours := []
	var placed := 0
	var tries := 0
	while placed < 1400 and tries < 9000:
		tries += 1
		var x := _rng.randf_range(-800.0, 800.0)
		var z := _rng.randf_range(-800.0, 800.0)
		if absf(x) < 100.0 and absf(z) < 95.0:
			continue
		var h: float = height_at.call(x, z)
		var hx: float = height_at.call(x + 2.0, z)
		var hz: float = height_at.call(x, z + 2.0)
		if absf(hx - h) > 1.2 or absf(hz - h) > 1.2:
			continue
		var s := _rng.randf_range(0.6, 1.8) * (2.2 if h < FLOOR + 2.0 else 1.0)
		transforms.append(Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.7, 1.3), s)), Vector3(x, h - 0.2, z)))
		colours.append(Color(0.75, 0.85, 0.6).lerp(Color(1.1, 1.0, 0.8), _rng.randf()) if h > FLOOR + 2.0 else Color(0.7, 1.15, 0.6))
		placed += 1
	var scrub := add_multimesh(bush_mesh, transforms, colours)
	scrub.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A ring of points round the vertical axis, for small shells.
func _ring(y: float, radius: float, points: int) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for i in points:
		var a := TAU * i / float(points)
		ring.append(Vector3(cos(a) * radius, y, sin(a) * radius))
	return ring
