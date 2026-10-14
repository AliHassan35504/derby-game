class_name StadiumJumpsMap
extends DerbyMap
## A floodlit stadium at night, packed to the roof. An elevated track on
## steel scaffolding runs round the infield with a gap to jump in the middle
## of each long side, and a long straight down the middle jumps clean over
## the low road that crosses under it. Fall short and you land on the grass.

const LOW := 10.0
const CORNER := 17.0
const HIGH := 22.0
const HALF_X := 95.0
const HALF_Z := 60.0
## Inner edge of the stands (a rounded rectangle) and how they rise.
const STAND_X := 128.0
const STAND_Z := 92.0
const STAND_CORNER := 40.0
const TIERS := 16
const TIER_DEPTH := 1.6
const TIER_RISE := 1.05
const STAND_FOOT := 4.0
const SEGMENTS := 160
const ADS := ["NITRO COLA", "SMASH TV", "BUMPER BURGER", "TURBO TYRES", "DENT-B-GONE", "CRASH INSURANCE?", "HOP SHOP", "SCRAPYARD FM"]

var _rng := RandomNumberGenerator.new()
var _steel: ShaderMaterial
var _concrete: ShaderMaterial
var _lamps: Array[Light3D] = []


func build() -> void:
	map_name = "Stadium Jumps"
	car_type = "hatch"
	rule_text = "Jump track: hit the kickers flat out (nitro helps) or drop onto the grass"
	kill_height = 4.0
	road_width = 5.0
	plain_stilts = false
	night = true
	_rng.seed = 4242

	make_environment(Color(0.01, 0.015, 0.04), Color(0.1, 0.1, 0.16), Color(0.02, 0.02, 0.03),
			Color(0.16, 0.17, 0.22), 0.0022, Vector3(-62, 25, 0), 1.25)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("horizon", Color(0.1, 0.1, 0.16))
	sky_mat.set_shader_parameter("city_glow", Color(0.3, 0.26, 0.22))
	sky_mat.set_shader_parameter("cloud_tint", Color(0.14, 0.14, 0.18))
	environment.sky.sky_material = sky_mat
	# The "sun" is the floodlight rig: a cold white key light from high up.
	sun.light_color = Color(0.9, 0.95, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.32, 0.34, 0.42)
	environment.ambient_light_energy = 0.8
	environment.fog_aerial_perspective = 0.1
	environment.fog_sky_affect = 0.1
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.0

	_steel = make_shader_material("steel", {"paint": Color(0.36, 0.38, 0.42), "rust_amount": 0.05, "grime_height": 2.0, "metallic": 0.6, "roughness": 0.45})
	_concrete = make_shader_material("concrete", {"tint": Color(0.5, 0.5, 0.52)})
	set_materials(make_shader_material("race_track", {"road_width": road_width}), _steel)
	pad_material = make_shader_material("race_track", {"pad": true, "pad_size": 14.0})

	# Corners, the middle of each long side (low) and of each short side (high).
	add_pad("nw", Vector3(-HALF_X, CORNER, -HALF_Z), Vector2(14, 14))
	add_pad("ne", Vector3(HALF_X, CORNER, -HALF_Z), Vector2(14, 14))
	add_pad("se", Vector3(HALF_X, CORNER, HALF_Z), Vector2(14, 14))
	add_pad("sw", Vector3(-HALF_X, CORNER, HALF_Z), Vector2(14, 14))
	add_pad("n", Vector3(0, LOW, -HALF_Z), Vector2(14, 14))
	add_pad("s", Vector3(0, LOW, HALF_Z), Vector2(14, 14))
	add_pad("w", Vector3(-HALF_X, HIGH, 0), Vector2(14, 14))
	add_pad("e", Vector3(HALF_X, HIGH, 0), Vector2(14, 14))

	for pair in [["nw", "n"], ["n", "ne"], ["se", "s"], ["s", "sw"]]:
		add_jump_road(pair[0], pair[1], 0.5, 6.5, 1.1, 5.5)
	for pair in [["ne", "e"], ["e", "se"], ["sw", "w"], ["w", "nw"]]:
		add_road(pair[0], pair[1])
	# The low road down the middle, and the long straight that jumps over it.
	add_road("n", "s")
	add_jump_road("w", "e", 0.5, 7.0, 1.2, 6.0)

	_dress_pads()
	_dress_roads()
	_build_pitch()
	_build_stands()
	_build_floodlights()
	_build_screens()

	add_spawn("nw", "n")
	add_spawn("se", "s")
	add_spawn("w", "e", 2.0)
	add_spawn("e", "w", 2.0)
	add_spawn("n", "s", 1.5)
	add_spawn("s", "n", 1.5)
	add_spawn("ne", "e")
	add_spawn("sw", "w")


func apply_quality(level: int) -> void:
	super(level)
	for i in _lamps.size():
		_lamps[i].visible = level >= 1 or i % 2 == 0


## Each pad stands on a steel lattice tower down to the grass.
func _dress_pads() -> void:
	for id in pad_ids():
		var body := pad_body(id)
		var pos := pad_position(id)
		var half := pad_half(id) * 0.8
		var to_local := body.transform.affine_inverse()
		var kit := MeshKit.new()
		var top := pos.y - 0.6
		var corners := [Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y)]
		for c in corners:
			kit.beam(to_local * (pos + c + Vector3.DOWN * 0.6), to_local * Vector3(pos.x + c.x, 0.0, pos.z + c.z), 0.5, 0.5)
		var rings := maxi(int(top / 4.0), 1)
		for r in rings + 1:
			var y := top - r * (top / rings)
			for k in 4:
				var a: Vector3 = corners[k]
				var b: Vector3 = corners[(k + 1) % 4]
				kit.beam(to_local * Vector3(pos.x + a.x, y, pos.z + a.z), to_local * Vector3(pos.x + b.x, y, pos.z + b.z), 0.22, 0.22)
				if r < rings:
					var y2 := y - top / rings
					kit.beam(to_local * Vector3(pos.x + a.x, y, pos.z + a.z), to_local * Vector3(pos.x + b.x, y2, pos.z + b.z), 0.14, 0.14)
		# A deep edge beam under the pad.
		kit.cube(to_local * Vector3(pos.x, pos.y - 0.9, pos.z), Vector3(pad_half(id).x * 2.0 - 0.4, 0.6, pad_half(id).y * 2.0 - 0.4))
		kit.instance(body, _steel)


## Scaffold bents under the roads, skipped over a road below and in the
## gaps, with an extra tall pair holding up each kicker.
func _dress_roads() -> void:
	var lamp_mat := _emissive(Color(1.0, 0.85, 0.5), 5.0)
	for road in roads():
		var body: StaticBody3D = road["body"]
		var start: Vector3 = road["start"]
		var end: Vector3 = road["end"]
		var thickness: float = road["thickness"]
		var length := start.distance_to(end)
		var forward := (end - start) / length
		var right := Vector3.UP.cross(forward).normalized()
		var to_local := body.transform.affine_inverse()
		var gap: Array = road.get("gap", [])
		var kit := MeshKit.new()
		var lights := MeshKit.new()
		# Side girders under both deck edges (not across the gap).
		var spans := [[0.0, length]]
		if not gap.is_empty():
			spans = [[0.0, length * 0.5 + gap[0]], [length * 0.5 + gap[1], length]]
		for span in spans:
			for side in [-1.0, 1.0]:
				var a: Vector3 = start + forward * span[0] + right * side * (road_width * 0.5 - 0.25) + Vector3.DOWN * (thickness + 0.4)
				var b: Vector3 = start + forward * span[1] + right * side * (road_width * 0.5 - 0.25) + Vector3.DOWN * (thickness + 0.4)
				kit.i_beam(to_local * a, to_local * b, 0.35, 0.8)
		var stations := maxi(int(length / 10.0), 1)
		var points := []
		for i in stations + 1:
			points.append(lerpf(3.0, length - 3.0, i / float(stations)))
		if not gap.is_empty():
			points = points.filter(func(d: float) -> bool: return d < length * 0.5 + gap[0] - 1.5 or d > length * 0.5 + gap[1] + 1.5)
			points.append(length * 0.5 + gap[0] - 0.6)
			points.append(length * 0.5 + gap[1] + 0.6)
		for d in points:
			var top: Vector3 = start + forward * d + Vector3.DOWN * (thickness + 0.8)
			if deck_below(top, 1.5, body) > -INF:
				continue
			var foot := Vector3(top.x, 0.0, top.z)
			for side in [-1.0, 1.0]:
				var off: Vector3 = right * side * (road_width * 0.5 - 0.25)
				kit.beam(to_local * (top + off), to_local * (foot + off * 1.3), 0.32, 0.32)
			kit.beam(to_local * (top - right * road_width * 0.5), to_local * (top + right * road_width * 0.5), 0.3, 0.3)
			var levels := maxi(int(top.y / 5.0), 1)
			for k in levels:
				var y0 := top.y * (1.0 - k / float(levels))
				var y1 := top.y * (1.0 - (k + 1) / float(levels))
				var s := 1.0 if k % 2 == 0 else -1.0
				var w0 := (road_width * 0.5 - 0.25) * lerpf(1.3, 1.0, y0 / top.y)
				var w1 := (road_width * 0.5 - 0.25) * lerpf(1.3, 1.0, y1 / top.y)
				kit.beam(to_local * Vector3(top.x, y0, top.z) + to_local.basis * (right * s * w0), to_local * Vector3(top.x, y1, top.z) - to_local.basis * (right * s * w1), 0.12, 0.12)
		# Little amber marker lights along the deck edges.
		for i in int(length / 4.0):
			var d := 2.0 + i * 4.0
			if not gap.is_empty() and d > length * 0.5 + gap[0] - 0.5 and d < length * 0.5 + gap[1] + 0.5:
				continue
			for side in [-1.0, 1.0]:
				lights.cube(to_local * (start + forward * d + right * side * (road_width * 0.5 + 0.06) + Vector3.DOWN * 0.15), Vector3(0.12, 0.12, 0.3))
		kit.instance(body, _steel)
		lights.instance(body, lamp_mat, false)


func _build_pitch() -> void:
	var field := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(STAND_X * 2.0 + 20.0, STAND_Z * 2.0 + 20.0)
	plane.material = make_shader_material("pitch", {"half_size": Vector2(HALF_X + 12.0, HALF_Z + 12.0)})
	field.mesh = plane
	field.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(field)
	var outside := MeshInstance3D.new()
	var ground := PlaneMesh.new()
	ground.size = Vector2(3000, 3000)
	ground.material = make_shader_material("city_ground", {"traffic": 0.6})
	outside.mesh = ground
	outside.position.y = -0.3
	outside.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outside)

	# Advertising hoardings round the pitch, lit from inside.
	var boards := MeshKit.new()
	var index := 0
	for side in [-1.0, 1.0]:
		for i in 6:
			var x := -HALF_X - 5.0 + i * (HALF_X * 2.0 + 10.0) / 5.0
			var z: float = side * (HALF_Z + 16.0)
			_ad_board(boards, Vector3(x, 0.0, z), Vector3(0, 0, -side), ADS[index % ADS.size()], index)
			index += 1
		for i in 3:
			var z := -HALF_Z + 5.0 + i * (HALF_Z * 2.0 - 10.0) / 2.0
			var x: float = side * (HALF_X + 18.0)
			_ad_board(boards, Vector3(x, 0.0, z), Vector3(-side, 0, 0), ADS[index % ADS.size()], index)
			index += 1
	boards.instance(self, _steel)


func _ad_board(kit: MeshKit, at: Vector3, facing: Vector3, text: String, index: int) -> void:
	var along := Vector3.UP.cross(facing).normalized()
	kit.color = Color(0.2, 0.2, 0.22)
	kit.box(Transform3D(Basis(along, Vector3.UP, facing), at + Vector3.UP * 1.1), Vector3(22.0, 2.2, 0.4))
	var colours := [Color(1.0, 0.25, 0.1), Color(0.1, 0.7, 1.0), Color(1.0, 0.85, 0.1), Color(0.3, 1.0, 0.4), Color(1.0, 0.2, 0.6)]
	var colour: Color = colours[index % colours.size()]
	var panel := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(21.4, 1.8)
	quad.material = _emissive(colour, 1.2)
	panel.mesh = quad
	panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(panel)
	panel.global_transform = Transform3D(Basis(along, Vector3.UP, facing), at + Vector3.UP * 1.1 + facing * 0.21)
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = 0.014
	label.modulate = Color(1.6, 1.6, 1.6)
	label.outline_size = 12
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.double_sided = false
	add_child(label)
	label.global_transform = Transform3D(Basis(along, Vector3.UP, facing), at + Vector3.UP * 1.1 + facing * 0.24)


## A point on the stands' inner edge, a rounded rectangle, u from 0 to 1
## of the way round (starting halfway along the east end), pushed out by
## offset metres.
func _stand_point(u: float, offset: float) -> Vector3:
	var sx := STAND_X - STAND_CORNER
	var sz := STAND_Z - STAND_CORNER
	var arc := PI * 0.5 * STAND_CORNER
	var pieces := [sz, arc, sx * 2.0, arc, sz * 2.0, arc, sx * 2.0, arc, sz]
	var d := fposmod(u, 1.0) * (sx * 4.0 + sz * 4.0 + arc * 4.0)
	var i := 0
	while i < pieces.size() - 1 and d > pieces[i]:
		d -= pieces[i]
		i += 1
	var r := STAND_CORNER + offset
	match i:
		0, 8:
			return Vector3(STAND_X + offset, 0, d if i == 0 else -sz + d)
		2:
			return Vector3(sx - d, 0, STAND_Z + offset)
		4:
			return Vector3(-STAND_X - offset, 0, sz - d)
		6:
			return Vector3(-sx + d, 0, -STAND_Z - offset)
	# Corners: quarter circles, in order NE... round to SE.
	var k := (i - 1) / 2
	var centre: Vector3 = [Vector3(sx, 0, sz), Vector3(-sx, 0, sz), Vector3(-sx, 0, -sz), Vector3(sx, 0, -sz)][k]
	var angle := PI * 0.5 * k + d / STAND_CORNER
	return centre + Vector3(cos(angle), 0, sin(angle)) * r


## Tiered stands all the way round, a roof over the top rows, and the crowd.
func _build_stands() -> void:
	var kit := MeshKit.new()
	var people_t := []
	var people_c := []
	var people_d := []
	var shirts := [Color(0.85, 0.1, 0.1), Color(0.1, 0.3, 0.85), Color(0.95, 0.8, 0.1), Color(0.95, 0.95, 0.95),
			Color(0.1, 0.1, 0.1), Color(0.1, 0.6, 0.25), Color(0.95, 0.45, 0.1), Color(0.5, 0.2, 0.7)]
	var seats := [Color(0.65, 0.08, 0.08), Color(0.1, 0.22, 0.6)]
	var roof := MeshKit.new()
	var roof_lights := MeshKit.new()
	for k in SEGMENTS:
		var a0 := k / float(SEGMENTS)
		var a1 := (k + 1) / float(SEGMENTS)
		# Sections in alternating seat colours, with stairs between them.
		var section := (k / 10) % 2
		for t in TIERS:
			var d0 := t * TIER_DEPTH
			var p0 := _stand_point(a0, d0 + TIER_DEPTH * 0.5)
			var p1 := _stand_point(a1, d0 + TIER_DEPTH * 0.5)
			var y := STAND_FOOT + t * TIER_RISE
			var along := p1 - p0
			var frame := MeshKit.frame(along.normalized())
			var mid := (p0 + p1) * 0.5
			kit.color = seats[section] if k % 10 != 0 else Color(0.45, 0.45, 0.47)
			kit.box(Transform3D(frame, Vector3(mid.x, y * 0.5, mid.z)), Vector3(TIER_DEPTH + 0.05, y, along.length() + 0.25))
			if k % 10 == 0:
				continue
			# Fans along the step, facing the pitch.
			var facing := -frame.x if frame.x.dot(mid) > 0.0 else frame.x
			var count := int(along.length() / 0.95)
			for i in count:
				if _rng.randf() > 0.82:
					continue
				var f := (i + 0.5) / float(count)
				var at := p0.lerp(p1, f) + Vector3.UP * (y + 0.55) - facing * 0.15
				var turn := Basis(Vector3.UP, atan2(facing.x, facing.z) + _rng.randf_range(-0.3, 0.3))
				people_t.append(Transform3D(turn.scaled(Vector3.ONE * _rng.randf_range(0.9, 1.1)), at))
				people_c.append(shirts[_rng.randi() % shirts.size()])
				people_d.append(Color(_rng.randf(), 1.0 if _rng.randf() < 0.03 else 0.0, _rng.randf(), 0.0))
		# Front wall, back wall and the roof over the upper tiers.
		var f0 := _stand_point(a0, -0.2)
		var f1 := _stand_point(a1, -0.2)
		kit.color = Color(0.25, 0.25, 0.28)
		kit.box(Transform3D(MeshKit.frame((f1 - f0).normalized()), (f0 + f1) * 0.5 + Vector3.UP * STAND_FOOT * 0.5), Vector3(0.4, STAND_FOOT + 1.0, f0.distance_to(f1) + 0.3))
		var back := TIERS * TIER_DEPTH
		var b0 := _stand_point(a0, back + 0.3)
		var b1 := _stand_point(a1, back + 0.3)
		var top_y := STAND_FOOT + TIERS * TIER_RISE
		kit.box(Transform3D(MeshKit.frame((b1 - b0).normalized()), (b0 + b1) * 0.5 + Vector3.UP * (top_y + 9.0) * 0.5), Vector3(0.6, top_y + 9.0, b0.distance_to(b1) + 0.3))
		var r_out0 := b0 + Vector3.UP * (top_y + 9.0)
		var r_out1 := b1 + Vector3.UP * (top_y + 9.0)
		var r_in0 := _stand_point(a0, back - 16.0) + Vector3.UP * (top_y + 6.5)
		var r_in1 := _stand_point(a1, back - 16.0) + Vector3.UP * (top_y + 6.5)
		roof.quad(r_out0, r_out1, r_in1, r_in0)
		roof.quad(r_in0, r_in1, r_out1, r_out0)
		roof_lights.cube((r_in0 + r_in1) * 0.5 + Vector3.DOWN * 0.3, Vector3(0.6, 0.25, 0.6))
		if k % 4 == 0:
			roof.tube(b0 + Vector3.UP * (top_y + 9.0), r_in0 + Vector3.UP * 0.1, 0.25, 0.25, 6)
	var stand_mat := StandardMaterial3D.new()
	stand_mat.vertex_color_use_as_albedo = true
	stand_mat.roughness = 0.85
	kit.instance(self, stand_mat)
	roof.instance(self, _steel)
	roof_lights.instance(self, _emissive(Color(1.0, 0.95, 0.85), 6.0), false)

	var person := MeshKit.new()
	person.cube(Vector3(0, -0.3, 0), Vector3(0.36, 0.4, 0.26))
	person.cube(Vector3(0, 0.1, 0), Vector3(0.46, 0.42, 0.3))
	person.cube(Vector3(0, 0.43, 0), Vector3(0.24, 0.24, 0.24))
	var crowd := add_multimesh(person.commit(make_shader_material("crowd")), people_t, people_c, people_d)
	crowd.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Four floodlight towers over the corners of the stands, each with a bank
## of lamps, a beam you can see in the haze, and a spot light on the track.
func _build_floodlights() -> void:
	var masts := MeshKit.new()
	var lamps := MeshKit.new()
	for i in 4:
		var corner := Vector3(STAND_X - STAND_CORNER, 0, STAND_Z - STAND_CORNER) * Vector3(1 if i % 3 == 0 else -1, 0, 1 if i < 2 else -1)
		var base := corner + corner.normalized() * (STAND_CORNER + TIERS * TIER_DEPTH + 8.0)
		var head := base + Vector3.UP * 72.0
		masts.tube(base, head, 1.6, 0.9, 10)
		var to_centre := (Vector3(0, 12, 0) - head).normalized()
		var frame := MeshKit.frame(to_centre)
		masts.box(Transform3D(frame, head - to_centre * 0.8), Vector3(16.0, 9.0, 1.0))
		for gx in 6:
			for gy in 4:
				var p := head + frame.x * (gx - 2.5) * 2.5 + frame.y * (gy - 1.5) * 2.0
				lamps.box(Transform3D(frame, p), Vector3(2.0, 1.6, 0.3))
		var light := SpotLight3D.new()
		light.light_color = Color(0.92, 0.95, 1.0)
		light.light_energy = 6.0
		light.spot_range = 320.0
		light.spot_angle = 26.0
		light.spot_attenuation = 0.5
		add_child(light)
		light.global_transform = Transform3D(MeshKit.frame(-to_centre), head + to_centre * 1.0)
		_lamps.append(light)
		add_light_beam(head + to_centre * 1.5, to_centre, 110.0, 5.0, 24.0, Color(0.85, 0.9, 1.0), 0.05)
	masts.instance(self, _steel)
	lamps.instance(self, _emissive(Color(1.0, 0.98, 0.92), 9.0), false)


## Big screens over both ends and the name over the main stand.
func _build_screens() -> void:
	var frames := MeshKit.new()
	for side in [-1.0, 1.0]:
		var at := _stand_point(0.0 if side > 0.0 else 0.5, TIERS * TIER_DEPTH + 2.0) + Vector3.UP * (STAND_FOOT + TIERS * TIER_RISE + 22.0)
		var facing := Vector3(-side, 0, 0)
		var basis := Basis(Vector3.UP.cross(facing).normalized(), Vector3.UP, facing)
		frames.box(Transform3D(basis, at - facing * 0.6), Vector3(34.0, 17.0, 1.0))
		frames.tube(at + Vector3.DOWN * 8.0 - facing * 0.5, Vector3(at.x, 0, at.z) - facing * 0.5, 0.8, 0.8, 8)
		var screen := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(32.0, 15.0)
		quad.material = make_shader_material("neon_screen", {"seed": 0.3 if side > 0.0 else 0.7,
				"colour_a": Color(1.0, 0.3, 0.05), "colour_b": Color(0.1, 0.4, 1.0), "brightness": 1.6})
		screen.mesh = quad
		screen.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(screen)
		screen.global_transform = Transform3D(basis, at)
		var label := Label3D.new()
		label.text = "STADIUM\nJUMPS" if side > 0.0 else "LAST CAR\nSTANDING"
		label.font_size = 160
		label.pixel_size = 0.035
		label.outline_size = 24
		label.modulate = Color(1.6, 1.6, 1.6)
		label.outline_modulate = Color(0, 0, 0, 0.8)
		label.double_sided = false
		add_child(label)
		label.global_transform = Transform3D(basis, at + facing * 0.1)
	frames.instance(self, _steel)


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
