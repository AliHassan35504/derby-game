class_name OrbitalRingMap
extends DerbyMap
## A space station in low orbit, the Earth curving away far below. Truss
## roads join the station's modules: three high spokes run out from the
## docking hub and pass over a low triangle of roads between the three
## lower modules, and a ring of ramps joins the two levels round the
## outside. The station's great habitat ring turns slowly round it all.
##
## Twist: low gravity. Cars fall slowly, so hops go high and big hits send
## cars floating off the deck.

const HUB := 52.0
const HIGH := 52.0
const LOW := 43.0
const HIGH_R := 80.0
const LOW_R := 60.0
const RING_RADIUS := 165.0
const RING_Y := 30.0
const EARTH_RADIUS := 3500.0
const EARTH_CENTRE := Vector3(0, -4050, 0)

var _rng := RandomNumberGenerator.new()
var _hull: ShaderMaterial
var _frame: ShaderMaterial
var _ring: Node3D
var _beacons: Array[MeshInstance3D] = []
var _clock := 0.0


func build() -> void:
	map_name = "Orbital Ring"
	car_type = "monster"
	rule_text = "Low gravity: once your wheels leave the deck you float, so hops fly high and big hits carry"
	kill_height = 28.0
	road_width = 5.4
	plain_stilts = false
	gravity_multiplier = 0.45
	_rng.seed = 1969

	make_environment(Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), 0.0, Vector3(-16, -35, 0), 2.1)
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/space_sky.gdshader")
	environment.sky.sky_material = sky_mat
	environment.fog_enabled = false
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.55, 0.75)
	environment.ambient_light_energy = 0.55
	environment.glow_intensity = 0.8
	environment.glow_bloom = 0.1
	environment.glow_hdr_threshold = 1.1
	environment.adjustment_contrast = 1.12
	sun.light_color = Color(1.0, 0.98, 0.94)
	sun.directional_shadow_max_distance = 220.0

	_hull = make_shader_material("hull", {"world_mode": true})
	_frame = make_shader_material("steel", {"paint": Color(0.72, 0.72, 0.7), "rust_amount": 0.0, "grime_height": -100.0, "metallic": 0.7, "roughness": 0.35})
	set_materials(make_shader_material("hull", {"road_width": road_width}), _frame)
	pad_material = make_shader_material("hull", {"pad": true, "pad_size": 16.0})

	add_pad("hub", Vector3(0, HUB, 0), Vector2(20, 20))
	for k in 3:
		var a := TAU * k / 3.0
		add_pad("low%d" % k, Vector3(cos(a), 0, sin(a)) * LOW_R + Vector3.UP * LOW, Vector2(18, 18))
		var b := a + PI / 3.0
		add_pad("high%d" % k, Vector3(cos(b), 0, sin(b)) * HIGH_R + Vector3.UP * HIGH, Vector2(16, 16))
	for k in 3:
		add_road("hub", "high%d" % k)
		add_road("low%d" % k, "low%d" % ((k + 1) % 3))
		add_road("low%d" % k, "high%d" % k)
		add_road("high%d" % k, "low%d" % ((k + 1) % 3))
	piece_mesh(pad_body("hub")).material_override = make_shader_material("hull", {"pad": true, "pad_size": 20.0})
	var low_deck := make_shader_material("hull", {"pad": true, "pad_size": 18.0})
	for k in 3:
		piece_mesh(pad_body("low%d" % k)).material_override = low_deck

	_dress_pads()
	_dress_roads()
	_build_ring()
	_build_earth()

	add_spawn("low0", "low1")
	add_spawn("low1", "low2")
	add_spawn("low2", "low0")
	add_spawn("high0", "low1")
	add_spawn("high1", "low2")
	add_spawn("high2", "low0")
	add_spawn("hub", "high0", 3.0)
	add_spawn("hub", "high2", 3.0)


## Each pad is the roof of a station module: a deck block with lit windows,
## a pressurised can hanging below, radiator fins and blinking beacons. The
## high modules carry solar wings, the hub a long spindle down to the
## habitat ring's spokes.
func _dress_pads() -> void:
	var windows := _emissive(Color(0.75, 0.88, 1.0), 3.0)
	var red := _emissive(Color(1.0, 0.1, 0.05), 8.0)
	var green := _emissive(Color(0.1, 1.0, 0.3), 8.0)
	var cells := StandardMaterial3D.new()
	cells.albedo_color = Color(0.05, 0.08, 0.2)
	cells.metallic = 0.8
	cells.roughness = 0.25
	cells.emission_enabled = true
	cells.emission = Color(0.05, 0.12, 0.35)
	cells.emission_energy_multiplier = 0.4
	for id in pad_ids():
		var body := pad_body(id)
		var pos := pad_position(id)
		var half := pad_half(id)
		var to_local := body.transform.affine_inverse()
		var kit := MeshKit.new()
		var glow := MeshKit.new()
		var block_top := pos.y - 0.6
		kit.cube(to_local * Vector3(pos.x, block_top - 1.6, pos.z), Vector3(half.x * 2.0 - 0.6, 3.2, half.y * 2.0 - 0.6))
		for k in 8:
			var a := TAU * k / 8.0
			var d := Vector3(cos(a), 0, sin(a))
			glow.box(to_local * Transform3D(MeshKit.frame(d), Vector3(pos.x, block_top - 1.6, pos.z) + d * (half.x - 0.25)), Vector3(half.x * 0.5, 0.35, 0.1))
		var can_len := 16.0 if id == "hub" else 9.0
		kit.tube(to_local * Vector3(pos.x, block_top - 3.2, pos.z), to_local * Vector3(pos.x, block_top - 3.2 - can_len, pos.z), half.x * 0.42, half.x * 0.42, 16, true)
		for r in 3:
			var y := block_top - 5.0 - r * can_len * 0.3
			kit.tube(to_local * Vector3(pos.x, y, pos.z), to_local * Vector3(pos.x, y - 0.6, pos.z), half.x * 0.46, half.x * 0.46, 16)
		# Radiator fins.
		for side in [-1.0, 1.0]:
			kit.box(to_local * Transform3D(Basis.IDENTITY, Vector3(pos.x + side * (half.x * 0.42 + 3.0), block_top - 3.2 - can_len * 0.5, pos.z)), Vector3(5.5, can_len * 0.8, 0.15))
		if id == "hub":
			# The spindle down to the habitat ring's spokes.
			kit.tube(to_local * Vector3(pos.x, block_top - 3.2 - can_len, pos.z), to_local * Vector3(pos.x, RING_Y - 25.0, pos.z), 2.5, 2.5, 12, true)
			kit.tube(to_local * Vector3(pos.x, RING_Y + 2.0, pos.z), to_local * Vector3(pos.x, RING_Y - 6.0, pos.z), 9.0, 9.0, 20, true)
		elif id.begins_with("high"):
			var out := Vector3(pos.x, 0, pos.z).normalized()
			var side := Vector3.UP.cross(out)
			var root := Vector3(pos.x, block_top - 2.0, pos.z) + out * half.x
			kit.beam(to_local * root, to_local * (root + out * 46.0), 0.6, 0.6)
			var wings := MeshKit.new()
			for w in 3:
				var c := root + out * (12.0 + w * 12.0)
				for s in [-1.0, 1.0]:
					wings.box(to_local * Transform3D(MeshKit.frame(out), c + side * s * 8.5), Vector3(14.0, 0.15, 10.0))
			wings.instance(body, cells)
		kit.instance(body, _frame)
		glow.instance(body, windows, false)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var beacon := MeshInstance3D.new()
				var bulb := SphereMesh.new()
				bulb.radius = 0.22
				bulb.height = 0.44
				bulb.radial_segments = 8
				bulb.rings = 4
				bulb.material = red if sx * sz > 0.0 else green
				beacon.mesh = bulb
				body.add_child(beacon)
				beacon.global_position = Vector3(pos.x + sx * (half.x + 0.2), pos.y - 0.9, pos.z + sz * (half.y + 0.2))
				_beacons.append(beacon)


## Box trusses under the decks: four longerons, zig-zag bracing on every
## face and frames at each bay, with blue running lights along the sides.
func _dress_roads() -> void:
	var lights := _emissive(Color(0.2, 0.55, 1.0), 4.0)
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
		var strip := MeshKit.new()
		var a := start - forward * 0.5
		var b := end + forward * 0.5
		var w := road_width * 0.5 - 0.3
		var corners := [right * w + down * (thickness + 0.2), -right * w + down * (thickness + 0.2),
				-right * w * 0.55 + down * (thickness + 2.8), right * w * 0.55 + down * (thickness + 2.8)]
		for c in corners:
			kit.tube(to_local * (a + c), to_local * (b + c), 0.16, 0.16, 6)
		var bays := maxi(int(length / 3.5), 2)
		for i in bays + 1:
			var p := a.lerp(b, i / float(bays))
			for k in 4:
				kit.tube(to_local * (p + corners[k]), to_local * (p + corners[(k + 1) % 4]), 0.1, 0.1, 5)
			if i < bays:
				var q := a.lerp(b, (i + 1) / float(bays))
				for k in 4:
					var c0: Vector3 = corners[k]
					var c1: Vector3 = corners[(k + 1) % 4]
					if i % 2 == 0:
						kit.tube(to_local * (p + c0), to_local * (q + c1), 0.07, 0.07, 4)
					else:
						kit.tube(to_local * (p + c1), to_local * (q + c0), 0.07, 0.07, 4)
		for side in [-1.0, 1.0]:
			strip.cube(to_local * ((start + end) * 0.5 + right * side * (road_width * 0.5 + 0.04) + down * 0.15), Vector3(0.06, 0.1, length - 0.5))
		kit.instance(body, _frame)
		strip.instance(body, lights, false)


## The station's habitat ring, turning slowly round the arena below the
## decks, joined to the hub spindle by three spokes.
func _build_ring() -> void:
	_ring = Node3D.new()
	_ring.position = Vector3(0, RING_Y, 0)
	add_child(_ring)
	var torus := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = RING_RADIUS - 9.0
	mesh.outer_radius = RING_RADIUS + 9.0
	mesh.rings = 160
	mesh.ring_segments = 20
	mesh.material = _hull
	torus.mesh = mesh
	_ring.add_child(torus)
	var kit := MeshKit.new()
	var glow := MeshKit.new()
	for k in 3:
		var a := TAU * (k + 0.25) / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		kit.tube(d * 9.0 + Vector3.DOWN * 2.0, d * (RING_RADIUS - 8.0), 2.2, 2.2, 10)
		kit.tube(d * 9.0 + Vector3.UP * 0.5, d * (RING_RADIUS - 8.0) + Vector3.UP * 0.5, 0.8, 0.8, 6)
	# Window bands on the inner and outer faces, and docking lights.
	for k in 180:
		var a := TAU * k / 180.0
		var d := Vector3(cos(a), 0, sin(a))
		for r in [RING_RADIUS - 8.6, RING_RADIUS + 8.6]:
			glow.box(Transform3D(MeshKit.frame(Vector3.UP.cross(d)), d * r + Vector3.UP * 1.5), Vector3(0.12, 0.9, 3.2))
		if k % 15 == 0:
			kit.tube(d * RING_RADIUS + Vector3.UP * 8.0, d * RING_RADIUS + Vector3.UP * 13.0, 3.0, 2.2, 10, true)
	kit.instance(_ring, _hull)
	glow.instance(_ring, _emissive(Color(1.0, 0.85, 0.6), 3.0), false)


func _build_earth() -> void:
	var earth := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = EARTH_RADIUS
	sphere.height = EARTH_RADIUS * 2.0
	sphere.radial_segments = 160
	sphere.rings = 80
	sphere.material = make_shader_material("earth", {"centre": EARTH_CENTRE})
	earth.mesh = sphere
	earth.position = EARTH_CENTRE
	earth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(earth)


func _process(delta: float) -> void:
	super(delta)
	_clock += delta
	_ring.rotate_y(delta * 0.02)
	var on := fmod(_clock, 1.6) < 0.2
	for beacon in _beacons:
		beacon.visible = on


func _emissive(colour: Color, energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.emission_enabled = true
	mat.emission = colour
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
