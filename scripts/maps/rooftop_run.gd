class_name RooftopRunMap
extends DerbyMap
## Downtown at night, high above the streets. Steel girder roads span
## between skyscraper rooftops: four high girders run out from a helipad
## on the central tower, and pass over a diamond of low girders between
## four other rooftops. Searchlights sweep the sky and a police helicopter
## circles, spotlighting the cars.
##
## Twist: crosswinds. Every so often a gust howls between the towers and
## shoves every car sideways for a few seconds. Wind streaks pick up just
## before it hits.

const HUB := 60.0
const HIGH := 60.0
const LOW := 48.0
const HIGH_R := 60.0
const LOW_R := 62.0
## Sideways push of a full gust, in m/s².
const GUST_ACCEL := 3.2
const WARNING_TIME := 2.5
const GUST_TIME := 3.2

var _rng := RandomNumberGenerator.new()
var _steel: ShaderMaterial
var _lamps: Array[Light3D] = []
var _clock := 0.0
## Footprints (centre, half size) of buildings already placed.
var _footprints: Array = []

var _searchlights: Array = []
var _heli: Node3D
var _rotor: Node3D
var _heli_light: SpotLight3D
var _heli_beam: MeshInstance3D
var _heli_aim := Vector3(0, HUB, 0)
var _heli_target: Node3D
var _heli_retarget := 0.0
var _nav_lights: Array[MeshInstance3D] = []

var _wind_dir := Vector3.RIGHT
## 0 calm, 1 picking up (warning), 2 gust.
var _wind_phase := 0
var _wind_timer := 14.0
var _wind := 0.0
var _streaks: GPUParticles3D
var _wind_sound: AudioStreamPlayer


func build() -> void:
	map_name = "Rooftop Run"
	car_type = "police"
	rule_text = "Crosswinds: gusts shove cars sideways on the girders; wind streaks warn you first"
	kill_height = 36.0
	road_width = 4.6
	plain_stilts = false
	night = true
	_rng.seed = 911

	make_environment(Color(0.01, 0.015, 0.045), Color(0.12, 0.1, 0.2), Color(0.02, 0.02, 0.03),
			Color(0.07, 0.07, 0.12), 0.0026, Vector3(-34, 150, 0), 0.55)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/night_sky.gdshader")
	sky_mat.set_shader_parameter("horizon", Color(0.14, 0.1, 0.18))
	sky_mat.set_shader_parameter("city_glow", Color(0.6, 0.35, 0.22))
	environment.sky.sky_material = sky_mat
	sun.light_color = Color(0.6, 0.68, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.3, 0.32, 0.45)
	environment.ambient_light_energy = 0.9
	environment.fog_aerial_perspective = 0.2
	environment.fog_sky_affect = 0.1
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.1
	environment.glow_hdr_threshold = 0.9

	_steel = make_shader_material("steel", {"paint": Color(0.72, 0.26, 0.12), "rust_amount": 0.3, "grime_height": -10.0, "metallic": 0.55, "roughness": 0.5})
	set_materials(make_shader_material("grating", {"road_width": road_width, "steel": Color(0.36, 0.37, 0.38),
			"edge_paint": Color(0.95, 0.72, 0.08), "rust_amount": 0.25}), _steel)
	pad_material = make_shader_material("helipad", {"pad_size": 14.0, "helipad": false})

	add_pad("hub", Vector3(0, HUB, 0), Vector2(18, 18))
	var highs := ["h_ne", "h_se", "h_sw", "h_nw"]
	var lows := ["l_e", "l_s", "l_w", "l_n"]
	for i in 4:
		var a := PI * 0.25 * (2 * i - 1)
		add_pad(highs[i], Vector3(cos(a), 0, sin(a)) * HIGH_R * sqrt(2.0) + Vector3.UP * HIGH, Vector2(14, 14))
		var b := PI * 0.5 * i
		add_pad(lows[i], Vector3(cos(b), 0, sin(b)) * LOW_R + Vector3.UP * LOW, Vector2(14, 14))
	for i in 4:
		add_road("hub", highs[i])
		add_road(lows[i], lows[(i + 1) % 4])
		add_road(lows[i], highs[i])
		add_road(highs[i], lows[(i + 3) % 4])
	var hub_mesh := piece_mesh(pad_body("hub"))
	hub_mesh.material_override = make_shader_material("helipad", {"pad_size": 18.0})

	_build_towers()
	_dress_roads()
	_build_city()
	_build_searchlights()
	_build_helicopter()
	_build_wind()

	add_spawn("l_e", "l_s")
	add_spawn("l_w", "l_n")
	add_spawn("h_ne", "hub")
	add_spawn("h_sw", "hub")
	add_spawn("l_s", "l_w")
	add_spawn("l_n", "l_e")
	add_spawn("h_se", "hub")
	add_spawn("h_nw", "hub")


func apply_quality(level: int) -> void:
	super(level)
	for i in _lamps.size():
		_lamps[i].visible = level >= 1 or i % 2 == 0


## The rooftops are the tops of skyscrapers running down to the street,
## with red aircraft lights on their corners.
func _build_towers() -> void:
	var tower_mesh := BoxMesh.new()
	tower_mesh.size = Vector3.ONE
	tower_mesh.material = make_shader_material("windows", {"night": 1.0, "shop_glow": 1.0})
	var transforms := []
	var custom := []
	var red := MeshKit.new()
	for id in pad_ids():
		var pos := pad_position(id)
		var half := pad_half(id)
		var top := pos.y - 0.6
		transforms.append(Transform3D(Basis.from_scale(Vector3(half.x * 2.0 - 0.1, top, half.y * 2.0 - 0.1)), Vector3(pos.x, top * 0.5, pos.z)))
		custom.append(Color(_rng.randf(), _rng.randf_range(0.35, 0.6), 1.0 if id != "hub" else 0.0, _rng.randf()))
		_footprints.append([Vector2(pos.x, pos.z), half])
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				red.cube(Vector3(pos.x + sx * (half.x + 0.1), top - 0.6, pos.z + sz * (half.y + 0.1)), Vector3(0.35, 0.35, 0.35))
	add_multimesh(tower_mesh, transforms, [], custom)
	red.instance(self, _emissive(Color(1.0, 0.05, 0.03), 8.0), false)
	# Work lights over every rooftop so the decks read at night.
	for id in pad_ids():
		if id == "hub":
			continue
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.78, 0.5)
		lamp.light_energy = 2.2
		lamp.omni_range = 22.0
		lamp.omni_attenuation = 0.8
		add_child(lamp)
		lamp.position = pad_position(id) + Vector3.UP * 7.0
		_lamps.append(lamp)

	# Edge lights round the helipad.
	var edge := MeshKit.new()
	var hub := pad_position("hub")
	for i in 16:
		var t := (i + 0.5) / 16.0 * 4.0
		var side := int(t)
		var f := (t - side) * 2.0 - 1.0
		var p: Vector3 = [Vector3(f * 8.8, 0, -8.8), Vector3(8.8, 0, f * 8.8), Vector3(-f * 8.8, 0, 8.8), Vector3(-8.8, 0, -f * 8.8)][side]
		edge.cube(hub + p + Vector3.UP * 0.03, Vector3(0.35, 0.06, 0.35))
	edge.instance(self, _emissive(Color(0.2, 1.0, 0.45), 6.0), false)
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.5, 1.0, 0.6)
	glow.light_energy = 2.5
	glow.omni_range = 24.0
	add_child(glow)
	glow.position = hub + Vector3.UP * 3.0


## Girders: I-beam stringers under the deck edges, a Warren truss below,
## and a light strip along each edge (blue on the high girders).
func _dress_roads() -> void:
	var blue := _emissive(Color(0.15, 0.4, 1.0), 5.0)
	var white := _emissive(Color(0.9, 0.9, 1.0), 3.0)
	for road in roads():
		var body: StaticBody3D = road["body"]
		var start: Vector3 = road["start"]
		var end: Vector3 = road["end"]
		var thickness: float = road["thickness"]
		var length := start.distance_to(end)
		var forward := (end - start) / length
		var right := Vector3.UP.cross(forward).normalized()
		var down := right.cross(forward).normalized()
		var to_local := body.transform.affine_inverse()
		var kit := MeshKit.new()
		var lights := MeshKit.new()
		var depth := 2.4
		var half := road_width * 0.5 - 0.2
		var a := start - forward * 0.5
		var b := end + forward * 0.5
		for side in [-1.0, 1.0]:
			var off: Vector3 = right * side * half
			kit.i_beam(to_local * (a + off + down * (thickness + 0.4)), to_local * (b + off + down * (thickness + 0.4)), 0.4, 0.8)
			kit.beam(to_local * (a + off + down * (thickness + depth)), to_local * (b + off + down * (thickness + depth)), 0.3, 0.3)
			var panels := maxi(int(length / 3.0), 2)
			for i in panels:
				var p0 := a.lerp(b, i / float(panels)) + off
				var p1 := a.lerp(b, (i + 1) / float(panels)) + off
				var top0 := p0 + down * (thickness + 0.8)
				var bot1 := p1 + down * (thickness + depth)
				var bot0 := p0 + down * (thickness + depth)
				var top1 := p1 + down * (thickness + 0.8)
				if i % 2 == 0:
					kit.beam(to_local * top0, to_local * bot1, 0.14, 0.14)
				else:
					kit.beam(to_local * bot0, to_local * top1, 0.14, 0.14)
				kit.beam(to_local * top0, to_local * bot0, 0.12, 0.12)
			lights.cube(to_local * ((start + end) * 0.5 + right * side * (road_width * 0.5 + 0.05) + down * 0.12), Vector3(0.06, 0.08, length - 0.6))
		# Cross members under the bottom chords.
		for i in maxi(int(length / 6.0), 1):
			var p := a.lerp(b, (i + 0.5) / maxf(int(length / 6.0), 1.0)) + down * (thickness + depth)
			kit.beam(to_local * (p - right * half), to_local * (p + right * half), 0.2, 0.2)
		kit.instance(body, _steel)
		var high := minf(start.y, end.y) > LOW + 4.0
		lights.instance(body, blue if high else white, false)


## The city all round: low blocks under the arena, taller ones further out,
## and the streets with their traffic far below.
func _build_city() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2600, 2600)
	plane.material = make_shader_material("city_ground", {"block": 64.0, "street": 14.0})
	ground.mesh = plane
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	var tower_mesh := BoxMesh.new()
	tower_mesh.size = Vector3.ONE
	tower_mesh.material = make_shader_material("windows", {"night": 1.0, "shop_glow": 1.0})
	var transforms := []
	var custom := []
	var tries := 0
	while transforms.size() < 520 and tries < 8000:
		tries += 1
		var p := Vector2(_rng.randf_range(-950.0, 950.0), _rng.randf_range(-950.0, 950.0))
		if tries < 2500:
			p *= 0.18
		var block := Vector2(fposmod(p.x + 32.0, 64.0) - 32.0, fposmod(p.y + 32.0, 64.0) - 32.0)
		var w := _rng.randf_range(12.0, 26.0)
		var d := _rng.randf_range(12.0, 26.0)
		if absf(block.x) < 7.0 + w * 0.5 or absf(block.y) < 7.0 + d * 0.5:
			continue
		var clear := true
		for fp in _footprints:
			var c: Vector2 = fp[0]
			var h: Vector2 = fp[1]
			if absf(p.x - c.x) < h.x + w * 0.5 + 2.0 and absf(p.y - c.y) < h.y + d * 0.5 + 2.0:
				clear = false
				break
		if not clear:
			continue
		var dist := p.length()
		var height := 0.0
		if dist < 150.0:
			# Under the arena: keep well below the girders.
			height = _rng.randf_range(12.0, 30.0)
		elif dist < 280.0:
			height = _rng.randf_range(25.0, 75.0)
		else:
			height = _rng.randf_range(50.0, 110.0) + maxf(0.0, 160.0 - dist * 0.12) * _rng.randf()
		_footprints.append([p, Vector2(w, d) * 0.5])
		transforms.append(Transform3D(Basis.from_scale(Vector3(w, height, d)), Vector3(p.x, height * 0.5, p.y)))
		custom.append(Color(_rng.randf(), _rng.randf_range(0.15, 0.55), 1.0 if _rng.randf() < 0.45 else 0.0, _rng.randf()))
	add_multimesh(tower_mesh, transforms, [], custom)


## Searchlights on far rooftops, sweeping the sky.
func _build_searchlights() -> void:
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		var at := Vector3(cos(a), 0, sin(a)) * _rng.randf_range(180.0, 260.0) + Vector3.UP * _rng.randf_range(40.0, 70.0)
		var beam := add_light_beam(at, Vector3.UP, 320.0, 0.8, 12.0, Color(0.85, 0.9, 1.0), 0.05)
		_searchlights.append([beam, at, _rng.randf() * TAU, _rng.randf_range(0.15, 0.3)])


## A police helicopter circling the towers, its spotlight hunting a car.
func _build_helicopter() -> void:
	_heli = Node3D.new()
	add_child(_heli)
	var body := MeshKit.new()
	body.color = Color(0.1, 0.12, 0.2)
	body.box(Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)), Vector3(2.2, 2.0, 4.6))
	body.box(Transform3D(Basis.IDENTITY, Vector3(0, 0.35, -5.0)), Vector3(0.5, 0.6, 6.0))
	body.box(Transform3D(Basis.IDENTITY, Vector3(0, 1.0, -7.8)), Vector3(0.2, 1.6, 0.9))
	body.color = Color(0.9, 0.9, 0.92)
	body.box(Transform3D(Basis.IDENTITY, Vector3(0, -0.2, 0.2)), Vector3(2.25, 0.5, 4.0))
	for side in [-1.0, 1.0]:
		body.color = Color(0.2, 0.2, 0.22)
		body.beam(Vector3(side * 1.1, -1.4, -1.8), Vector3(side * 1.1, -1.4, 1.8), 0.15, 0.15)
		body.beam(Vector3(side * 0.9, -0.9, -1.0), Vector3(side * 1.1, -1.4, -1.0), 0.1, 0.1)
		body.beam(Vector3(side * 0.9, -0.9, 1.0), Vector3(side * 1.1, -1.4, 1.0), 0.1, 0.1)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.5
	mat.roughness = 0.4
	body.instance(_heli, mat)
	var glass := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 1.0
	dome.height = 1.6
	var glass_mat := _emissive(Color(0.9, 0.75, 0.4), 0.8)
	dome.material = glass_mat
	glass.mesh = dome
	glass.position = Vector3(0, 0.2, 2.1)
	_heli.add_child(glass)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 1.25, 0)
	_heli.add_child(_rotor)
	var blades := MeshKit.new()
	blades.color = Color(0.08, 0.08, 0.08)
	blades.box(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(11.0, 0.08, 0.4))
	blades.box(Transform3D(Basis.IDENTITY, Vector3.ZERO), Vector3(0.4, 0.08, 11.0))
	blades.instance(_rotor, mat, false)
	for i in 2:
		var nav := MeshInstance3D.new()
		var bulb := SphereMesh.new()
		bulb.radius = 0.25
		bulb.height = 0.5
		bulb.material = _emissive(Color(1.0, 0.05, 0.05) if i == 0 else Color(0.1, 0.3, 1.0), 10.0)
		nav.mesh = bulb
		nav.position = Vector3(-1.2 if i == 0 else 1.2, 0.9, 0.0)
		_heli.add_child(nav)
		_nav_lights.append(nav)
	_heli_light = SpotLight3D.new()
	_heli_light.light_color = Color(0.95, 0.97, 1.0)
	_heli_light.light_energy = 14.0
	_heli_light.spot_range = 140.0
	_heli_light.spot_angle = 7.0
	_heli_light.spot_attenuation = 0.4
	add_child(_heli_light)
	_lamps.append(_heli_light)
	_heli_beam = add_light_beam(Vector3.ZERO, Vector3.DOWN, 70.0, 0.4, 7.0, Color(0.9, 0.95, 1.0), 0.07)
	_update_helicopter(0.0)


func _build_wind() -> void:
	_streaks = GPUParticles3D.new()
	_streaks.amount = 260
	_streaks.lifetime = 1.4
	_streaks.preprocess = 1.4
	_streaks.local_coords = false
	_streaks.amount_ratio = 0.0
	_streaks.visibility_aabb = AABB(Vector3(-80, -40, -80), Vector3(160, 80, 160))
	_streaks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(40, 14, 40)
	proc.direction = _wind_dir
	proc.spread = 4.0
	proc.initial_velocity_min = 30.0
	proc.initial_velocity_max = 45.0
	proc.gravity = Vector3.ZERO
	proc.particle_flag_align_y = true
	proc.scale_min = 0.6
	proc.scale_max = 1.4
	_streaks.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 3.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.45)
	quad.material = mat
	_streaks.draw_pass_1 = quad
	add_child(_streaks)
	_wind_sound = AudioStreamPlayer.new()
	_wind_sound.stream = load("res://assets/audio/sfx/wind_loop.wav")
	_wind_sound.bus = Sfx.bus(Sfx.SFX_BUS)
	_wind_sound.volume_db = -40.0
	add_child(_wind_sound)


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	for s in _searchlights:
		var beam: MeshInstance3D = s[0]
		var yaw: float = s[2] + _clock * float(s[3])
		var tilt := 0.45 + 0.25 * sin(_clock * float(s[3]) * 1.7 + float(s[2]))
		var dir := Vector3(cos(yaw) * cos(tilt), sin(tilt) + 0.6, sin(yaw) * cos(tilt)).normalized()
		beam.global_transform = Transform3D(MeshKit.frame(-dir), s[1])
	_update_helicopter(delta)
	var camera := get_viewport().get_camera_3d()
	if camera and _streaks:
		_streaks.global_position = camera.global_position - _wind_dir * 25.0


func _update_helicopter(delta: float) -> void:
	var t := _clock * 0.12
	var pos := Vector3(cos(t) * 85.0, 96.0 + sin(_clock * 0.5) * 2.0, sin(t) * 85.0)
	var tangent := Vector3(-sin(t), 0, cos(t))
	_heli.global_transform = Transform3D(MeshKit.frame(tangent).rotated(tangent.cross(Vector3.UP).normalized(), -0.12), pos)
	_rotor.rotate_y(delta * 28.0)
	for i in _nav_lights.size():
		_nav_lights[i].visible = fmod(_clock * 1.5 + i * 0.5, 1.0) < 0.5
	# Pick a car to follow now and then, and swing the light after it.
	_heli_retarget -= delta
	if _heli_retarget <= 0.0 or (_heli_target != null and not is_instance_valid(_heli_target)):
		_heli_retarget = 7.0
		var cars := live_cars()
		_heli_target = cars[_rng.randi() % cars.size()] if not cars.is_empty() else null
	var goal := Vector3(sin(_clock * 0.3) * 30.0, HUB, cos(_clock * 0.23) * 30.0)
	if _heli_target != null and is_instance_valid(_heli_target):
		goal = _heli_target.global_position
	_heli_aim = _heli_aim.lerp(goal, clampf(delta * 1.5, 0.0, 1.0)) if delta > 0.0 else goal
	var from := pos + Vector3.DOWN * 1.2
	var dir := (_heli_aim - from).normalized()
	_heli_light.global_transform = Transform3D(MeshKit.frame(-dir), from)
	_heli_beam.global_transform = Transform3D(MeshKit.frame(-dir), from)


func _physics_process(delta: float) -> void:
	super(delta)
	var cars := live_cars()
	var live := cars.filter(func(c: DerbyCar) -> bool: return c.controls_enabled)
	if live.is_empty():
		_wind = move_toward(_wind, 0.0, delta)
		_update_wind_fx()
		return
	_wind_timer -= delta
	if _wind_timer <= 0.0:
		_wind_phase = (_wind_phase + 1) % 3
		match _wind_phase:
			1:
				var a := _rng.randf() * TAU
				_wind_dir = Vector3(cos(a), 0, sin(a))
				(_streaks.process_material as ParticleProcessMaterial).direction = _wind_dir
				_wind_timer = WARNING_TIME
			2:
				_wind_timer = GUST_TIME
			_:
				_wind_timer = _rng.randf_range(11.0, 16.0)
	var target: float = [0.0, 0.2, 1.0][_wind_phase]
	_wind = move_toward(_wind, target, delta * (0.8 if target > _wind else 0.6))
	_update_wind_fx()
	if _wind_phase == 0 and _wind < 0.05:
		return
	var push := 0.0 if _wind_phase == 1 else _wind
	for car: DerbyCar in live:
		car.apply_central_force(_wind_dir * car.mass * GUST_ACCEL * push)


func _update_wind_fx() -> void:
	_streaks.amount_ratio = clampf(_wind * 1.1, 0.0, 1.0)
	_wind_sound.volume_db = lerpf(-40.0, -2.0, sqrt(_wind))
	if _wind > 0.02 and not _wind_sound.playing:
		_wind_sound.play()
	elif _wind <= 0.02 and _wind_sound.playing:
		_wind_sound.stop()


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
