class_name VolcanoCoreMap
extends DerbyMap
## Inside a smoking caldera: obsidian bridges on basalt columns over a lake
## of lava. An outer ring of six pads runs round a low inner triangle
## close to the vent, and one long bridge runs straight over the crater,
## passing above two of the inner roads.
##
## Twist: eruptions. The vent rumbles and glows, red rings mark where lava
## bombs will land, then it blows: cars near the vent are flung outward and
## the bombs blast anyone still standing in a ring.

const OUTER_R := 72.0
const INNER_R := 30.0
const OUTER_LOW := 34.0
const OUTER_HIGH := 40.0
const INNER := 24.0
const LAVA := 0.0
const VENT := Vector3(0, 28, 0)
const RUMBLE_TIME := 3.2
## Cars this close to the vent (sideways) get the blast; full strength at
## the middle.
const BLAST_RADIUS := 30.0
const BLAST_DV := 9.0
const BOMBS := 5
const BOMB_RADIUS := 5.5
const BOMB_DV := 7.5
const BOMB_DAMAGE := 12.0

var _rng := RandomNumberGenerator.new()
var _rock: ShaderMaterial
var _deck: ShaderMaterial
var _pad_deck: ShaderMaterial
var _lava: ShaderMaterial
var _cinder: ShaderMaterial
var _vent_light: OmniLight3D
var _lava_lights: Array[OmniLight3D] = []
var _smoke: GPUParticles3D
var _fountain: GPUParticles3D
var _embers: GPUParticles3D

var _erupt_timer := 16.0
var _rumbling := false
var _heat := 0.0
## Lava bombs waiting to launch or in flight: target, marker, from, time, flight.
var _bombs: Array = []
var _ring_mat: StandardMaterial3D
var _bomb_mat: StandardMaterial3D
var _boom: AudioStream


func build() -> void:
	map_name = "Volcano Core"
	car_type = "super"
	rule_text = "Eruptions: when the vent rumbles, get clear of it and out of the red rings"
	kill_height = 12.0
	road_width = 5.0
	plain_stilts = false
	night = true
	_rng.seed = 6660

	make_environment(Color(0.09, 0.06, 0.06), Color(0.36, 0.17, 0.09), Color(0.2, 0.06, 0.02),
			Color(0.22, 0.12, 0.08), 0.0035, Vector3(-24, -60, 0), 1.0)
	sun.light_color = Color(1.0, 0.55, 0.35)
	var sky_mat: ProceduralSkyMaterial = environment.sky.sky_material
	sky_mat.sun_angle_max = 4.0
	sky_mat.sky_curve = 0.25
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.38, 0.32)
	environment.ambient_light_energy = 0.95
	environment.fog_height = 8.0
	environment.fog_height_density = 0.01
	environment.fog_sky_affect = 0.5
	environment.glow_intensity = 0.9
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 0.9

	_rock = make_shader_material("basalt", {"heat_height": 12.0})
	_deck = make_shader_material("basalt", {"deck": true, "road_width": road_width})
	_pad_deck = make_shader_material("basalt", {"deck": true, "pad": true, "pad_size": 13.0})
	_lava = make_shader_material("lava")
	set_materials(_deck, _rock)
	pad_material = _pad_deck

	for k in 6:
		var a := TAU * k / 6.0
		add_pad("o%d" % k, Vector3(cos(a), 0, sin(a)) * OUTER_R + Vector3.UP * (OUTER_LOW if k % 2 == 0 else OUTER_HIGH), Vector2(13, 13))
	for k in 3:
		var a := deg_to_rad(30.0 + 120.0 * k)
		add_pad("i%d" % k, Vector3(cos(a), 0, sin(a)) * INNER_R + Vector3.UP * INNER, Vector2(13, 13))
	for k in 6:
		add_road("o%d" % k, "o%d" % ((k + 1) % 6))
	for k in 3:
		add_road("i%d" % k, "i%d" % ((k + 1) % 3))
	# Spokes from the inner triangle out to the ring, and the crater bridge.
	add_road("i0", "o0")
	add_road("i1", "o3")
	add_road("i2", "o5")
	add_road("o1", "o4")

	_dress_pads()
	_dress_roads()
	_build_vent()
	_build_caldera()
	_build_air()
	_ring_mat = _emissive(Color(1.0, 0.12, 0.04), 4.0)
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bomb_mat = _emissive(Color(1.0, 0.45, 0.1), 6.0)
	_boom = load("res://assets/audio/sfx/explosion.ogg")

	add_spawn("o0", "o1")
	add_spawn("o3", "o4")
	add_spawn("o2", "o3")
	add_spawn("o5", "o0")
	add_spawn("o1", "o2")
	add_spawn("o4", "o5")
	add_spawn("i0", "i1")
	add_spawn("i2", "i0")


func apply_quality(level: int) -> void:
	super(level)
	for i in _lava_lights.size():
		_lava_lights[i].visible = level >= 1 or i % 2 == 0


## Each pad is an obsidian cap on a cluster of hexagonal basalt columns
## rising out of the lava, the outer columns lower.
func _dress_pads() -> void:
	for id in pad_ids():
		var body := pad_body(id)
		var pos := pad_position(id)
		var half := pad_half(id)
		var to_local := body.transform.affine_inverse()
		var kit := MeshKit.new()
		var column := 1.7
		var span := int((half.x + 6.0) / column)
		for gx in range(-span, span + 1):
			for gz in range(-span, span + 1):
				var c := Vector3(gx * column * 1.5, 0, (gz + (0.5 if gx % 2 != 0 else 0.0)) * column * 1.732)
				var out := maxf(absf(c.x) - half.x + 1.0, absf(c.z) - half.y + 1.0)
				if c.length() > half.x + 6.0:
					continue
				var top := pos.y - 0.55
				if out > 0.0:
					top -= 1.5 + out * _rng.randf_range(1.0, 2.6)
				var radius := column * _rng.randf_range(0.92, 1.0)
				var rings := []
				for y in [LAVA - 3.0, top]:
					var ring := PackedVector3Array()
					for k in 6:
						var a := TAU * k / 6.0
						ring.append(Vector3(pos.x + c.x + cos(a) * radius, y, pos.z + c.z + sin(a) * radius))
					rings.append(ring)
				kit.shell(rings, true, to_local)
		kit.instance(body, _rock)


## Each road rides a natural basalt rib, deep where it meets the columns
## and thin in the middle.
func _dress_roads() -> void:
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
		var noise := FastNoiseLite.new()
		noise.seed = _rng.randi()
		noise.frequency = 0.15
		var rings := []
		for s in stations + 1:
			var t := s / float(stations)
			var centre := start.lerp(end, t) + forward * lerpf(-2.0, 2.0, t) + Vector3.DOWN * (thickness - 0.05)
			var span := absf(t - 0.5) * 2.0
			var depth := 2.2 + 9.0 * pow(span, 2.5) + noise.get_noise_1d(s * 3.0) * 0.8
			var half_w := road_width * 0.5 - 0.1 + span * span * 1.5
			var ring := PackedVector3Array()
			for k in 12:
				var a := TAU * k / 12.0
				var c := cos(a)
				var sn := sin(a)
				var bump := 1.0 + noise.get_noise_2d(s * 2.0, k * 3.0) * 0.25
				var below := sn * depth * bump if sn > 0.0 else sn * 0.3
				ring.append(centre + right * c * half_w * (bump if sn > 0.2 else 1.0) + down * below)
			rings.append(ring)
		var kit := MeshKit.new()
		kit.shell(rings, false, to_local)
		kit.instance(body, _rock)


## The vent: a cinder cone in the middle of the lake with a churning crater,
## its glow, and the smoke column above it.
func _build_vent() -> void:
	var kit := MeshKit.new()
	var rings := []
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.3
	for r in 9:
		var t := r / 8.0
		var y := lerpf(LAVA - 3.0, VENT.y, t)
		var radius := lerpf(30.0, 7.5, pow(t, 0.75))
		var ring := PackedVector3Array()
		for k in 28:
			var a := TAU * k / 28.0
			var bump := 1.0 + noise.get_noise_2d(cos(a) * 4.0, r * 1.3 + sin(a) * 4.0) * 0.18
			ring.append(Vector3(cos(a) * radius * bump, y, sin(a) * radius * bump))
		rings.append(ring)
	# The rim turns in and down into the crater.
	var lip := PackedVector3Array()
	for k in 28:
		var a := TAU * k / 28.0
		lip.append(Vector3(cos(a) * 5.5, VENT.y - 2.0, sin(a) * 5.5))
	rings.append(lip)
	kit.shell(rings, false)
	_cinder = make_shader_material("basalt", {"heat_height": 10.0, "rock": Color(0.17, 0.08, 0.06), "rock_light": Color(0.32, 0.14, 0.09)})
	kit.instance(self, _cinder)
	var pool := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 6.0
	disc.bottom_radius = 6.0
	disc.height = 0.5
	disc.material = _lava
	pool.mesh = disc
	pool.position = VENT + Vector3.DOWN * 2.2
	add_child(pool)
	_vent_light = OmniLight3D.new()
	_vent_light.light_color = Color(1.0, 0.45, 0.12)
	_vent_light.light_energy = 6.0
	_vent_light.omni_range = 90.0
	_vent_light.omni_attenuation = 1.0
	add_child(_vent_light)
	_vent_light.position = VENT + Vector3.UP * 4.0

	_smoke = GPUParticles3D.new()
	_smoke.amount = 70
	_smoke.lifetime = 16.0
	_smoke.preprocess = 16.0
	_smoke.visibility_aabb = AABB(Vector3(-120, -10, -120), Vector3(240, 260, 240))
	_smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 4.0
	proc.direction = Vector3.UP
	proc.spread = 10.0
	proc.initial_velocity_min = 7.0
	proc.initial_velocity_max = 11.0
	proc.gravity = Vector3(1.2, 0.4, 0.5)
	proc.damping_min = 0.3
	proc.damping_max = 0.5
	proc.scale_min = 0.6
	proc.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.3))
	grow.add_point(Vector2(1, 3.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	proc.scale_curve = grow_tex
	var fade := Gradient.new()
	fade.set_color(0, Color(0.9, 0.5, 0.3, 0.0))
	fade.add_point(0.08, Color(0.2, 0.15, 0.14, 0.6))
	fade.set_color(1, Color(0.1, 0.09, 0.09, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	proc.color_ramp = fade_tex
	_smoke.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(16, 16)
	var smoke_mat := _soft_sprite(Color(1, 1, 1, 1), false)
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	quad.material = smoke_mat
	_smoke.draw_pass_1 = quad
	add_child(_smoke)
	_smoke.position = VENT + Vector3.UP * 2.0

	# Lava spurting out of the crater all the time; more as it heats up.
	_fountain = GPUParticles3D.new()
	_fountain.amount = 80
	_fountain.lifetime = 2.2
	_fountain.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 80, 80))
	_fountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spurt := ParticleProcessMaterial.new()
	spurt.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	spurt.emission_sphere_radius = 3.0
	spurt.direction = Vector3.UP
	spurt.spread = 18.0
	spurt.initial_velocity_min = 8.0
	spurt.initial_velocity_max = 15.0
	spurt.gravity = Vector3(0, -12, 0)
	spurt.scale_min = 0.5
	spurt.scale_max = 1.4
	_fountain.process_material = spurt
	var blob := SphereMesh.new()
	blob.radius = 0.8
	blob.height = 1.6
	blob.radial_segments = 6
	blob.rings = 3
	blob.material = _emissive(Color(1.0, 0.5, 0.12), 5.0)
	_fountain.draw_pass_1 = blob
	add_child(_fountain)
	_fountain.position = VENT + Vector3.DOWN * 2.0


## The caldera walls all round, lava lights under the bridges and a few
## basalt stacks standing in the lake.
func _build_caldera() -> void:
	var lake := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, 1400)
	plane.subdivide_width = 120
	plane.subdivide_depth = 120
	plane.material = _lava
	lake.mesh = plane
	lake.position.y = LAVA
	lake.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lake)

	var ridges := FastNoiseLite.new()
	ridges.seed = 66
	ridges.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridges.frequency = 0.004
	ridges.fractal_octaves = 4
	var height_at := func(x: float, z: float) -> float:
		var d := Vector2(x, z).length()
		var rise := smoothstep(170.0, 420.0, d)
		return LAVA - 6.0 + rise * (150.0 + ridges.get_noise_2d(x, z) * 90.0) - (1.0 - rise) * 4.0
	var colour_at := func(_x: float, _z: float, _h: float, _n: Vector3) -> Color:
		return Color(1, 1, 1)
	var terrain := MeshInstance3D.new()
	terrain.mesh = make_terrain(150, 1500.0, height_at, colour_at)
	terrain.material_override = make_shader_material("basalt", {"heat_height": 8.0, "crack_amount": 0.6})
	add_child(terrain)

	var stacks := MeshKit.new()
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(95.0, 170.0)
		var c := Vector3(cos(a) * r, 0, sin(a) * r)
		var top := _rng.randf_range(4.0, 26.0)
		for j in 5:
			var off := Vector3(_rng.randf_range(-4.0, 4.0), 0, _rng.randf_range(-4.0, 4.0))
			var rad := _rng.randf_range(1.4, 2.4)
			var h := top - _rng.randf_range(0.0, 6.0)
			var ring_lo := PackedVector3Array()
			var ring_hi := PackedVector3Array()
			for k in 6:
				var b := TAU * k / 6.0
				ring_lo.append(c + off + Vector3(cos(b) * rad, LAVA - 3.0, sin(b) * rad))
				ring_hi.append(c + off + Vector3(cos(b) * rad, h, sin(b) * rad))
			stacks.shell([ring_lo, ring_hi])
	stacks.instance(self, _rock)

	# Orange light welling up from the lava onto the undersides.
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.4, 0.1)
		light.light_energy = 3.0
		light.omni_range = 60.0
		light.omni_attenuation = 1.0
		add_child(light)
		light.position = Vector3(cos(a) * 55.0, 6.0, sin(a) * 55.0)
		_lava_lights.append(light)


## Embers drifting up round the camera.
func _build_air() -> void:
	_embers = GPUParticles3D.new()
	_embers.amount = 500
	_embers.lifetime = 9.0
	_embers.preprocess = 9.0
	_embers.local_coords = false
	_embers.visibility_aabb = AABB(Vector3(-90, -50, -90), Vector3(180, 100, 180))
	_embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(60, 25, 60)
	proc.direction = Vector3.UP
	proc.spread = 30.0
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 4.0
	proc.gravity = Vector3(0.4, 0.6, 0.2)
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 2.0
	proc.turbulence_noise_scale = 5.0
	proc.scale_min = 0.4
	proc.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1.0, 0.6, 0.2, 0.0))
	fade.add_point(0.15, Color(1.0, 0.5, 0.15, 1.0))
	fade.set_color(1, Color(0.6, 0.15, 0.05, 0.0))
	var fade_tex := GradientTexture1D.new()
	fade_tex.gradient = fade
	proc.color_ramp = fade_tex
	_embers.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	quad.material = _soft_sprite(Color(3.0, 1.4, 0.5, 1.0), true)
	_embers.draw_pass_1 = quad
	add_child(_embers)


func _process(delta: float) -> void:
	super(delta)
	var camera := get_viewport().get_camera_3d()
	if camera and _embers:
		_embers.global_position = camera.global_position + Vector3.UP * 5.0


func _physics_process(delta: float) -> void:
	super(delta)
	_update_bombs(delta)
	var live := live_cars().filter(func(c: DerbyCar) -> bool: return c.controls_enabled)
	if live.is_empty():
		_set_heat(move_toward(_heat, 0.0, delta * 0.3))
		return
	_erupt_timer -= delta
	if not _rumbling and _erupt_timer <= 0.0:
		_start_rumble(live)
	elif _rumbling:
		_set_heat(minf(_heat + delta / RUMBLE_TIME, 1.0))
		var camera := get_viewport().get_camera_3d()
		if camera and camera.has_method("add_trauma"):
			camera.add_trauma(delta * 0.3)
		if _erupt_timer <= 0.0:
			_blast(live)
	else:
		_set_heat(move_toward(_heat, 0.0, delta * 0.25))


## The warning: the vent rumbles and glows, and rings mark where bombs land.
func _start_rumble(live: Array) -> void:
	_rumbling = true
	_erupt_timer = RUMBLE_TIME
	Sfx.play_at(_boom, VENT, 6.0, 120.0, 0.32)
	var space := get_world_3d().direct_space_state
	var tries := 0
	while _bombs.size() < BOMBS and tries < 40:
		tries += 1
		var aim := Vector3.ZERO
		if _rng.randf() < 0.6:
			var car: DerbyCar = live[_rng.randi() % live.size()]
			aim = car.global_position + car.linear_velocity * 1.5 + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
		else:
			var road: Dictionary = roads()[_rng.randi() % roads().size()]
			aim = (road["start"] as Vector3).lerp(road["end"], _rng.randf_range(0.2, 0.8))
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(aim + Vector3.UP * 6.0, aim + Vector3.DOWN * 12.0, ROAD_LAYER))
		if hit.is_empty():
			continue
		var at: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		var too_close := false
		for b in _bombs:
			if (b["to"] as Vector3).distance_to(at) < BOMB_RADIUS * 1.5:
				too_close = true
		if too_close:
			continue
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = BOMB_RADIUS - 0.5
		torus.outer_radius = BOMB_RADIUS
		torus.rings = 32
		torus.ring_segments = 6
		torus.material = _ring_mat
		ring.mesh = torus
		ring.scale = Vector3(1.0, 0.15, 1.0)
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		ring.global_transform = Transform3D(MeshKit.frame(normal.cross(Vector3.RIGHT).normalized(), normal), at + normal * 0.08)
		ring.scale = Vector3(1.0, 0.15, 1.0)
		var tween := ring.create_tween().set_loops()
		tween.tween_property(ring, "scale", Vector3(0.85, 0.15, 0.85), 0.35)
		tween.tween_property(ring, "scale", Vector3(1.0, 0.15, 1.0), 0.35)
		_bombs.append({"to": at, "ring": ring, "time": -1.0, "flight": 0.0, "node": null})


## The eruption: shove cars near the vent outward and launch the bombs.
func _blast(live: Array) -> void:
	_rumbling = false
	_erupt_timer = _rng.randf_range(17.0, 23.0)
	Sfx.play_at(_boom, VENT, 10.0, 150.0, 0.55)
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("add_trauma"):
		camera.add_trauma(0.6)
	for car: DerbyCar in live:
		var flat := Vector3(car.global_position.x - VENT.x, 0, car.global_position.z - VENT.z)
		var d := flat.length()
		if d > BLAST_RADIUS or car.global_position.y > VENT.y + 35.0:
			continue
		var out := flat / maxf(d, 0.1) if d > 0.5 else Vector3.RIGHT
		var strength := sqrt(1.0 - d / BLAST_RADIUS)
		car.apply_central_impulse((out * 0.8 + Vector3.UP * 0.6).normalized() * car.mass * BLAST_DV * strength)
	_burst(VENT + Vector3.UP * 2.0, 3.0, 40)
	for bomb in _bombs:
		if bomb["time"] < 0.0:
			var dist := VENT.distance_to(bomb["to"])
			bomb["time"] = 0.0
			bomb["flight"] = 1.8 + dist / 45.0
			var ball := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 0.9
			sphere.height = 1.8
			sphere.radial_segments = 10
			sphere.rings = 5
			sphere.material = _bomb_mat
			ball.mesh = sphere
			ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ball)
			ball.global_position = VENT
			bomb["node"] = ball


func _update_bombs(delta: float) -> void:
	for i in range(_bombs.size() - 1, -1, -1):
		var bomb: Dictionary = _bombs[i]
		if bomb["time"] < 0.0:
			continue
		bomb["time"] += delta
		var t: float = bomb["time"] / bomb["flight"]
		var to: Vector3 = bomb["to"]
		var ball: MeshInstance3D = bomb["node"]
		var arc := 22.0 + VENT.distance_to(to) * 0.35
		ball.global_position = VENT.lerp(to, t) + Vector3.UP * arc * 4.0 * t * (1.0 - t)
		if t < 1.0:
			continue
		_bombs.remove_at(i)
		ball.queue_free()
		(bomb["ring"] as Node).queue_free()
		Sfx.play_at(_boom, to, 2.0, 30.0, 0.9)
		_burst(to, 1.4, 24)
		for car in live_cars():
			var offset: Vector3 = car.global_position - to
			var d := offset.length()
			if d > BOMB_RADIUS + 1.0:
				continue
			var strength := clampf(1.0 - d / (BOMB_RADIUS + 1.0), 0.2, 1.0)
			var away := Vector3(offset.x, 0, offset.z).normalized() if Vector2(offset.x, offset.z).length() > 0.3 else Vector3.ZERO
			car.apply_central_impulse((away * 0.7 + Vector3.UP * 0.7).normalized() * car.mass * BOMB_DV * strength)
			car.take_damage(BOMB_DAMAGE * strength)


## A flash and a spray of glowing lava.
func _burst(at: Vector3, size: float, count: int) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.5, 0.15)
	flash.light_energy = 10.0 * size
	flash.omni_range = 12.0 * size
	add_child(flash)
	flash.global_position = at + Vector3.UP * 2.0
	var tween := flash.create_tween()
	tween.tween_property(flash, "light_energy", 0.0, 0.8)
	tween.tween_callback(flash.queue_free)
	var spray := GPUParticles3D.new()
	spray.amount = count
	spray.lifetime = 1.6
	spray.one_shot = true
	spray.explosiveness = 0.95
	spray.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 50.0
	proc.initial_velocity_min = 6.0 * size
	proc.initial_velocity_max = 12.0 * size
	proc.gravity = Vector3(0, -14, 0)
	proc.scale_min = 0.5
	proc.scale_max = 1.5
	spray.process_material = proc
	var blob := SphereMesh.new()
	blob.radius = 0.25 * size
	blob.height = 0.5 * size
	blob.radial_segments = 6
	blob.rings = 3
	blob.material = _bomb_mat
	spray.draw_pass_1 = blob
	add_child(spray)
	spray.global_position = at
	spray.emitting = true
	get_tree().create_timer(2.5, false).timeout.connect(spray.queue_free)


func _set_heat(value: float) -> void:
	_heat = value
	for mat in [_lava, _rock, _deck, _pad_deck, _cinder]:
		mat.set_shader_parameter("heat", _heat)
	_vent_light.light_energy = 6.0 + _heat * 22.0
	_vent_light.omni_range = 90.0 + _heat * 40.0
	_smoke.amount_ratio = 0.6 + _heat * 0.4
	_fountain.amount_ratio = 0.35 + _heat * 0.65
	(_fountain.process_material as ParticleProcessMaterial).initial_velocity_max = 15.0 + _heat * 12.0


func _soft_sprite(tint: Color, glow: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = tint
	if glow:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	var dot := GradientTexture2D.new()
	dot.fill = GradientTexture2D.FILL_RADIAL
	dot.fill_from = Vector2(0.5, 0.5)
	dot.fill_to = Vector2(1.0, 0.5)
	dot.width = 64
	dot.height = 64
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	dot.gradient = fade
	mat.albedo_texture = dot
	return mat


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
