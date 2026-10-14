class_name HarbourCranesMap
extends DerbyMap
## A container port at sunset. Two gantry cranes hold their booms out over
## the water as long high steel roads; grated girder walkways ramp down from
## them to the tops of container stacks standing on barges, and a low
## walkway runs right across the harbour underneath both booms. Fall in the
## sea and you're out.

const CONTAINER := Vector3(2.44, 2.59, 12.19)
const CONTAINER_COLOURS := [
	Color(0.55, 0.12, 0.08), Color(0.12, 0.27, 0.5), Color(0.15, 0.36, 0.22),
	Color(0.62, 0.6, 0.56), Color(0.8, 0.38, 0.08), Color(0.85, 0.85, 0.82),
	Color(0.38, 0.1, 0.12), Color(0.05, 0.4, 0.42), Color(0.82, 0.62, 0.1),
	Color(0.2, 0.2, 0.22),
]
## Cranes: pad at each end of the boom, paint colour.
const CRANES := [
	["wn", "ws", Color(0.85, 0.22, 0.08)],
	["en", "es", Color(0.14, 0.34, 0.66)],
]
## Pads that are the tops of container stacks.
const STACKS := ["nw", "sw", "ne", "se", "lw", "lc", "le"]

var _container_mesh: ArrayMesh
var _steel: ShaderMaterial
var _rng := RandomNumberGenerator.new()


func build() -> void:
	map_name = "Harbour Cranes"
	car_type = "pickup"
	rule_text = "Steel decks over the sea: one splash and you're out"
	kill_height = 1.4
	water_height = 0.0
	road_width = 5.0
	plain_stilts = false
	_rng.seed = 41

	make_environment(Color(0.16, 0.2, 0.4), Color(0.98, 0.56, 0.3), Color(0.08, 0.1, 0.14),
			Color(0.86, 0.58, 0.42), 0.0016, Vector3(-7, 196, 0), 1.7)
	sun.light_color = Color(1.0, 0.64, 0.38)
	environment.ambient_light_energy = 0.8
	environment.fog_sun_scatter = 0.35
	var sky_mat: ProceduralSkyMaterial = environment.sky.sky_material
	sky_mat.sun_angle_max = 8.0
	sky_mat.sun_curve = 0.08
	sky_mat.sky_curve = 0.2
	sky_mat.sky_energy_multiplier = 1.1
	var sea := add_ocean(0.0, Color(0.03, 0.07, 0.1), Color(0.1, 0.17, 0.2), 0.7)
	(sea.mesh.material as ShaderMaterial).set_shader_parameter("foam_amount", 0.2)

	_steel = make_shader_material("steel", {"paint": Color(0.36, 0.38, 0.36), "rust_amount": 0.45, "grime_height": 5.0})
	var deck := make_shader_material("grating", {"road_width": road_width})
	set_materials(deck, _steel)
	var container_mat := make_shader_material("container")
	var kit := MeshKit.new()
	kit.cube(Vector3.ZERO, CONTAINER)
	_container_mesh = kit.commit(container_mat)

	# Crane booms (high), container stacks (middle) and the low walkway.
	var stack := Vector2(CONTAINER.x * 5.0, CONTAINER.z)
	add_pad("wn", Vector3(-35, 31, -55), Vector2(12, 12))
	add_pad("ws", Vector3(-35, 31, 55), Vector2(12, 12))
	add_pad("en", Vector3(35, 27, -55), Vector2(12, 12))
	add_pad("es", Vector3(35, 27, 55), Vector2(12, 12))
	add_pad("nw", Vector3(-85, 24, -55), stack)
	add_pad("sw", Vector3(-85, 23, 55), stack)
	add_pad("ne", Vector3(85, 21, -55), stack)
	add_pad("se", Vector3(85, 20, 55), stack)
	add_pad("lw", Vector3(-85, 16, 0), stack)
	add_pad("lc", Vector3(0, 15, 0), stack)
	add_pad("le", Vector3(85, 14, 0), stack)

	add_road("wn", "ws")
	add_road("en", "es")
	add_road("wn", "en")
	add_road("ws", "es")
	add_road("wn", "nw")
	add_road("ws", "sw")
	add_road("en", "ne")
	add_road("es", "se")
	add_road("nw", "lw")
	add_road("sw", "lw")
	add_road("ne", "le")
	add_road("se", "le")
	add_road("lw", "lc")
	add_road("lc", "le")

	_dress_pads()
	_dress_walkways()
	for crane in CRANES:
		_build_crane(crane[0], crane[1], crane[2])
	_build_port()

	add_spawn("wn", "ws")
	add_spawn("es", "en")
	add_spawn("en", "wn")
	add_spawn("ws", "es")
	add_spawn("nw", "lw")
	add_spawn("se", "le")
	add_spawn("lw", "lc", 2.0)
	add_spawn("le", "lc", 2.0)


## Container pads show the stack itself (the slab is hidden inside the top
## tier); crane pads are grated steel platforms.
func _dress_pads() -> void:
	var platform := make_shader_material("grating", {"road_width": 12.0, "edge_paint": Color(0.9, 0.7, 0.1)})
	for id in pad_ids():
		var body := pad_body(id)
		var pos := pad_position(id)
		if id in STACKS:
			piece_mesh(body).visible = false
			_build_stack(body, pos)
		else:
			piece_mesh(body).material_override = platform


## A stack of containers from the sea up to a pad, five abreast, on a barge.
func _build_stack(body: Node3D, top: Vector3) -> void:
	var transforms := []
	var colours := []
	var tiers := ceili(top.y / CONTAINER.y) + 1
	var to_local := body.transform.affine_inverse()
	for tier in tiers:
		var y := top.y - CONTAINER.y * (tier + 0.5)
		for i in 5:
			# Lower tiers sit a touch out of line, like a real stack.
			var jitter := Vector3(0, 0, _rng.randf_range(-0.12, 0.12)) if tier > 0 else Vector3.ZERO
			var world := Vector3(top.x + (i - 2) * CONTAINER.x, y, top.z) + jitter
			transforms.append(to_local * Transform3D(Basis.IDENTITY, world))
			colours.append(CONTAINER_COLOURS[_rng.randi() % CONTAINER_COLOURS.size()])
	add_multimesh(_container_mesh, transforms, colours, [], body)

	# Barge hull at the waterline.
	var hull := MeshKit.new()
	hull.color = Color(0.25, 0.08, 0.06)
	hull.cube(to_local * Vector3(top.x, 0.2, top.z), Vector3(15.5, 2.6, 15.0))
	hull.color = Color(0.12, 0.12, 0.12)
	hull.cube(to_local * Vector3(top.x, 1.6, top.z), Vector3(15.7, 0.3, 15.2))
	hull.instance(body, _steel)


## Girders, cross beams and lattice support towers under the walkways.
## Booms are dressed by their cranes.
func _dress_walkways() -> void:
	for road in roads():
		var from: String = road["from"]
		var to: String = road["to"]
		var is_boom := false
		for crane in CRANES:
			if (from == crane[0] and to == crane[1]) or (from == crane[1] and to == crane[0]):
				is_boom = true
		var body: StaticBody3D = road["body"]
		var start: Vector3 = road["start"]
		var end: Vector3 = road["end"]
		var thickness: float = road["thickness"]
		var length := start.distance_to(end)
		var kit := MeshKit.new()
		kit.color = Color(0.9, 0.9, 0.9)
		var under := -thickness * 0.5
		var depth := 2.4 if is_boom else 0.8
		for side in [-1.0, 1.0]:
			var x: float = side * (road_width * 0.5 - 0.25)
			kit.i_beam(Vector3(x, under - depth * 0.5, -length * 0.5), Vector3(x, under - depth * 0.5, length * 0.5), 0.35, depth)
		var beams := int(length / 3.0)
		for i in beams + 1:
			var z := -length * 0.5 + length * i / float(beams)
			kit.beam(Vector3(-road_width * 0.5 + 0.3, under - 0.2, z), Vector3(road_width * 0.5 - 0.3, under - 0.2, z), 0.18, 0.3)
		if not is_boom:
			_add_towers(kit, body, start, end, thickness)
		kit.instance(body, _steel)


## Steel lattice towers standing in the sea under a walkway, skipped
## wherever another road runs below.
func _add_towers(kit: MeshKit, body: StaticBody3D, start: Vector3, end: Vector3, thickness: float) -> void:
	var length := start.distance_to(end)
	var count := maxi(int((length - 8.0) / 17.0), 1)
	var to_local := body.transform.affine_inverse()
	var forward := (end - start).normalized()
	var right := Vector3.UP.cross(forward).normalized()
	var flat := Vector3(forward.x, 0, forward.z).normalized()
	for i in count:
		var t := (i + 0.5) / float(count)
		var top := start.lerp(end, t) + Vector3.DOWN * (thickness + 0.8)
		if deck_below(top, 2.0, body) > -INF or _near_crane(top):
			continue
		var legs := []
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				legs.append(Vector2(sx * 1.7, sz * 1.3))
		kit.color = Color(0.75, 0.75, 0.75)
		for leg in legs:
			var a: Vector3 = top + right * leg.x + flat * leg.y
			var b: Vector3 = Vector3(a.x, -1.5, a.z) + right * leg.x * 0.35 + flat * leg.y * 0.35
			kit.beam(to_local * a, to_local * b, 0.3, 0.3)
		# X-bracing panels every 5 m.
		var y := top.y - 1.0
		while y > 1.5:
			var y2 := maxf(y - 5.0, 0.5)
			for pair in [[0, 1], [2, 3], [0, 2], [1, 3]]:
				var l0: Vector2 = legs[pair[0]]
				var l1: Vector2 = legs[pair[1]]
				var spread := lerpf(1.35, 1.0, (y - 1.5) / maxf(top.y - 1.5, 1.0))
				var spread2 := lerpf(1.35, 1.0, (y2 - 1.5) / maxf(top.y - 1.5, 1.0))
				var p0 := Vector3(top.x, y, top.z) + (right * l0.x + flat * l0.y) * spread
				var p1 := Vector3(top.x, y2, top.z) + (right * l1.x + flat * l1.y) * spread2
				var p2 := Vector3(top.x, y, top.z) + (right * l1.x + flat * l1.y) * spread
				var p3 := Vector3(top.x, y2, top.z) + (right * l0.x + flat * l0.y) * spread2
				kit.beam(to_local * p0, to_local * p1, 0.12, 0.12)
				kit.beam(to_local * p2, to_local * p3, 0.12, 0.12)
			y = y2
		# Concrete pile cap at the waterline.
		kit.color = Color(0.5, 0.48, 0.45)
		kit.cube(to_local * Vector3(top.x, -0.2, top.z), Vector3(6.0, 2.2, 5.0))


## Whether a point is inside a crane's gantry, where towers would clash
## with its legs and beams.
func _near_crane(point: Vector3) -> bool:
	for crane in CRANES:
		var a := pad_position(crane[0])
		var b := pad_position(crane[1])
		if absf(point.x - a.x) < 11.0 and absf(point.z - (a.z + b.z) * 0.5) < 22.0:
			return true
	return false


## A ship-to-shore gantry crane carrying the boom from pad a to pad b: two
## portal frames with legs into the sea, an A-frame above the boom with a
## machinery house, stays to both ends and a trolley with an operator cab.
func _build_crane(a_id: String, b_id: String, paint: Color) -> void:
	var a := pad_position(a_id)
	var b := pad_position(b_id)
	var deck_y := a.y
	var x := a.x
	var mat := make_shader_material("steel", {"paint": Color(1, 1, 1), "rust_amount": 0.25, "grime_height": 6.0, "metallic": 0.35, "roughness": 0.5})
	var white := Color(0.9, 0.9, 0.88)
	var kit := MeshKit.new()
	var gauge := 6.4
	var portals := [-18.0, 18.0]
	var top_y := deck_y + 15.0
	for pz in portals:
		var z: float = (a.z + b.z) * 0.5 + pz
		kit.color = paint
		for side in [-1.0, 1.0]:
			var foot := Vector3(x + side * (gauge + 1.5), -1.0, z)
			var knee := Vector3(x + side * gauge, deck_y - 2.0, z)
			var head := Vector3(x + side * 3.6, top_y, z)
			kit.beam(foot, knee, 1.4, 1.4)
			kit.beam(knee, head, 1.1, 1.1)
			# Bogies on the rail at the foot.
			kit.color = Color(0.2, 0.2, 0.2)
			kit.cube(Vector3(foot.x, -0.6, z), Vector3(2.2, 1.6, 6.0))
			kit.color = paint
		# Portal beam under the boom and the top beam over it.
		kit.beam(Vector3(x - gauge - 0.6, deck_y - 3.2, z), Vector3(x + gauge + 0.6, deck_y - 3.2, z), 1.6, 1.8)
		kit.beam(Vector3(x - 4.2, top_y, z), Vector3(x + 4.2, top_y, z), 1.2, 1.2)
		# Low sill beam tying the legs.
		kit.beam(Vector3(x - gauge - 1.4, 6.0, z), Vector3(x + gauge + 1.4, 6.0, z), 0.9, 0.9)
	# Longitudinal beams between the portals.
	for side in [-1.0, 1.0]:
		var z0: float = (a.z + b.z) * 0.5 + portals[0]
		var z1: float = (a.z + b.z) * 0.5 + portals[1]
		kit.color = paint
		kit.beam(Vector3(x + side * (gauge + 0.9), 7.0, z0), Vector3(x + side * (gauge + 0.9), 7.0, z1), 1.0, 1.4)
		kit.beam(Vector3(x + side * 3.6, top_y, z0), Vector3(x + side * 3.6, top_y, z1), 1.0, 1.0)
		# Stays from the A-frame head out to both ends of the boom.
		kit.color = white
		var head0 := Vector3(x + side * 3.6, top_y, z0)
		var head1 := Vector3(x + side * 3.6, top_y, z1)
		for end_z in [a.z + 9.0 * signf(b.z - a.z), b.z - 9.0 * signf(b.z - a.z)]:
			var anchor := Vector3(x + side * 3.3, deck_y + 3.2, end_z)
			var head := head0 if absf(end_z - z0) < absf(end_z - z1) else head1
			kit.tube(head, anchor, 0.12, 0.12, 6)
			# Short post at the boom edge for the stay to land on.
			kit.color = paint
			kit.beam(Vector3(x + side * 3.3, deck_y - 1.5, end_z), anchor, 0.4, 0.4)
			kit.color = white
	# Machinery house on top of the A-frame.
	kit.color = white
	var mid_z := (a.z + b.z) * 0.5
	kit.cube(Vector3(x, top_y + 3.0, mid_z), Vector3(8.6, 4.8, 30.0))
	kit.color = Color(0.25, 0.25, 0.27)
	kit.cube(Vector3(x, top_y + 5.6, mid_z), Vector3(8.0, 0.4, 29.0))
	# Trolley and operator cab hanging under the boom, clear of the low
	# walkway.
	var cab_z := lerpf(a.z, b.z, 0.82)
	kit.color = paint
	kit.cube(Vector3(x, deck_y - 4.6, cab_z), Vector3(5.6, 1.6, 6.0))
	kit.color = white
	kit.cube(Vector3(x - 1.2, deck_y - 7.0, cab_z), Vector3(2.6, 2.6, 3.0))
	kit.color = Color(0.1, 0.12, 0.14)
	kit.cube(Vector3(x - 1.2, deck_y - 7.0, cab_z + 1.55), Vector3(2.3, 1.6, 0.1))
	# Spreader dangling on its cables.
	kit.color = Color(0.85, 0.65, 0.1)
	kit.cube(Vector3(x, deck_y - 13.0, cab_z), Vector3(2.6, 0.8, 12.4))
	kit.color = Color(0.1, 0.1, 0.1)
	for c in [-1.0, 1.0]:
		kit.tube(Vector3(x + c, deck_y - 5.4, cab_z), Vector3(x + c, deck_y - 12.6, cab_z), 0.05, 0.05, 4)
	kit.instance(self, mat)

	# Red aviation lights on top.
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1.0, 0.1, 0.05)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.08, 0.02)
	lamp.emission_energy_multiplier = 6.0
	var bulbs := MeshKit.new()
	for dz in [-14.5, 14.5]:
		for dx in [-4.0, 4.0]:
			bulbs.cube(Vector3(x + dx, top_y + 6.1, mid_z + dz), Vector3(0.45, 0.45, 0.45))
	bulbs.instance(self, lamp, false)
	# Warm floodlights under the machinery house, lighting the boom.
	for dz in [-12.0, 12.0]:
		var flood := SpotLight3D.new()
		flood.light_color = Color(1.0, 0.82, 0.6)
		flood.light_energy = 4.0
		flood.spot_range = 30.0
		flood.spot_angle = 55.0
		flood.position = Vector3(x, top_y + 0.4, mid_z + dz)
		flood.rotation_degrees = Vector3(-90, 0, 0)
		add_child(flood)


## The rest of the port around the arena: a container terminal with more
## cranes and a docked ship to the north, a breakwater with a lighthouse to
## the east, the city to the west and ships out on the sunset to the south.
func _build_port() -> void:
	var concrete := make_shader_material("concrete", {"tint": Color(0.62, 0.6, 0.57)})
	var quay := MeshKit.new()
	quay.cube(Vector3(0, 1.0, -330), Vector3(1400, 6.0, 220))
	quay.cube(Vector3(-700, 1.0, 100), Vector3(600, 6.0, 1100))
	quay.instance(self, concrete)

	# Terminal yard: rows of container stacks.
	var transforms := []
	var colours := []
	for row in 7:
		for bay in 24:
			if _rng.randf() < 0.12:
				continue
			var origin := Vector3(-420 + bay * 36.0, 4.0, -265 - row * 22.0)
			var height := _rng.randi_range(1, 5)
			for across in 6:
				var tiers := clampi(height + _rng.randi_range(-1, 1), 1, 5)
				for tier in tiers:
					var p := origin + Vector3(across * CONTAINER.x, CONTAINER.y * (tier + 0.5), 0)
					transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), p))
					colours.append(CONTAINER_COLOURS[_rng.randi() % CONTAINER_COLOURS.size()])
	add_multimesh(_container_mesh, transforms, colours)

	# A docked container ship, bow to the east.
	_build_ship(Vector3(40, 0, -196), 290.0, 42.0, true)
	_build_ship(Vector3(-160, 0, 420), 210.0, 32.0, true, 0.15)
	_build_ship(Vector3(320, 0, 600), 140.0, 22.0, false, -0.4)
	_build_ship(Vector3(-420, 0, 760), 110.0, 18.0, false, 0.6)

	# Simplified cranes along the terminal quay.
	var crane_mat := make_shader_material("steel", {"paint": Color(1, 1, 1), "rust_amount": 0.2, "grime_height": 6.0})
	var cranes := MeshKit.new()
	for i in 6:
		var cx := -330.0 + i * 115.0
		cranes.color = [Color(0.85, 0.22, 0.08), Color(0.14, 0.34, 0.66), Color(0.9, 0.9, 0.88)][i % 3]
		for side in [-1.0, 1.0]:
			for dz in [-245.0, -270.0]:
				cranes.beam(Vector3(cx + side * 9.0, 4.0, dz), Vector3(cx + side * 7.0, 46.0, dz), 1.6, 1.6)
			cranes.beam(Vector3(cx + side * 7.0, 46.0, -245.0), Vector3(cx + side * 7.0, 46.0, -270.0), 1.4, 1.4)
		cranes.beam(Vector3(cx, 47.0, -150.0), Vector3(cx, 47.0, -300.0), 3.0, 3.0)
		cranes.beam(Vector3(cx - 8.0, 46.0, -258.0), Vector3(cx + 8.0, 46.0, -258.0), 1.4, 1.4)
		cranes.beam(Vector3(cx, 66.0, -258.0), Vector3(cx, 48.0, -150.0), 0.5, 0.5)
		cranes.beam(Vector3(cx, 66.0, -258.0), Vector3(cx, 48.0, -300.0), 0.5, 0.5)
		cranes.beam(Vector3(cx - 7.0, 46.0, -258.0), Vector3(cx, 66.0, -258.0), 0.8, 0.8)
		cranes.beam(Vector3(cx + 7.0, 46.0, -258.0), Vector3(cx, 66.0, -258.0), 0.8, 0.8)
		cranes.color = Color(0.9, 0.9, 0.88)
		cranes.cube(Vector3(cx, 51.0, -280.0), Vector3(9.0, 6.0, 16.0))
	cranes.instance(self, crane_mat)

	# Breakwater and lighthouse to the east.
	var rock := make_shader_material("concrete", {"tint": Color(0.42, 0.4, 0.38), "rough_rocks": 1.0})
	var wall := MeshKit.new()
	for i in 40:
		var p := Vector3(330 + _rng.randf_range(-8, 8), _rng.randf_range(-1.0, 0.5), -120 + i * 12.0)
		var s := _rng.randf_range(4.0, 7.0)
		wall.box(Transform3D(Basis.from_euler(Vector3(_rng.randf(), _rng.randf() * TAU, _rng.randf())), p), Vector3(s, s * 0.7, s))
	wall.cube(Vector3(330, 1.5, 120), Vector3(8, 3.0, 480))
	wall.instance(self, rock)
	var tower := MeshKit.new()
	tower.color = Color(0.92, 0.92, 0.9)
	tower.tube(Vector3(330, 3, 365), Vector3(330, 26, 365), 3.2, 2.2, 16, true)
	tower.color = Color(0.75, 0.12, 0.1)
	tower.tube(Vector3(330, 12, 365), Vector3(330, 17, 365), 2.85, 2.6, 16)
	tower.tube(Vector3(330, 26, 365), Vector3(330, 31, 365), 1.8, 1.8, 12, true)
	tower.instance(self, make_shader_material("steel", {"paint": Color(1, 1, 1), "rust_amount": 0.1, "grime_height": 6.0, "seam_spacing": 50.0}))
	var beacon := OmniLight3D.new()
	beacon.light_color = Color(1.0, 0.85, 0.55)
	beacon.light_energy = 3.0
	beacon.omni_range = 40.0
	beacon.position = Vector3(330, 29, 365)
	add_child(beacon)

	_build_skyline()

	# Mooring buoys and channel markers round the arena.
	var buoys := MeshKit.new()
	for i in 14:
		var angle := TAU * i / 14.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(125.0, 160.0)
		var p := Vector3(cos(angle) * r, -0.4, sin(angle) * r)
		buoys.color = Color(0.85, 0.15, 0.08) if i % 2 == 0 else Color(0.1, 0.5, 0.2)
		buoys.tube(p, p + Vector3.UP * 2.2, 0.9, 0.5, 10, true)
		buoys.tube(p + Vector3.UP * 2.2, p + Vector3.UP * 4.0, 0.15, 0.15, 6)
	buoys.instance(self, make_shader_material("steel", {"paint": Color(1, 1, 1), "rust_amount": 0.3, "grime_height": 1.0}))


## A ship: hull, deck house and, for container ships, rows of containers.
func _build_ship(centre: Vector3, length: float, beam: float, boxes: bool, yaw := 0.0) -> void:
	var basis := Basis(Vector3.UP, yaw)
	var xform := Transform3D(basis, centre)
	var kit := MeshKit.new()
	kit.color = Color(0.18, 0.2, 0.26) if boxes else Color(0.55, 0.12, 0.1)
	kit.box(xform * Transform3D(Basis.IDENTITY, Vector3(0, 4.0, 0)), Vector3(length, 12.0, beam))
	# Tapered bow.
	kit.box(xform * Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(length * 0.5, 4.0, 0)), Vector3(beam * 0.7, 12.0, beam * 0.7))
	kit.color = Color(0.5, 0.1, 0.08)
	kit.box(xform * Transform3D(Basis.IDENTITY, Vector3(0, -1.0, 0)), Vector3(length + 1.0, 2.2, beam + 0.2))
	kit.color = Color(0.92, 0.92, 0.9)
	var house_x := -length * 0.36
	kit.box(xform * Transform3D(Basis.IDENTITY, Vector3(house_x, 18.0, 0)), Vector3(14.0, 16.0, beam * 0.9))
	kit.box(xform * Transform3D(Basis.IDENTITY, Vector3(house_x, 26.5, 0)), Vector3(10.0, 2.0, beam * 1.1))
	kit.color = Color(0.2, 0.2, 0.2)
	kit.box(xform * Transform3D(Basis.IDENTITY, Vector3(house_x - 10.0, 22.0, 0)), Vector3(5.0, 12.0, 6.0))
	kit.instance(self, make_shader_material("steel", {"paint": Color(1, 1, 1), "rust_amount": 0.35, "grime_height": 6.0, "seam_spacing": 6.0}))
	if not boxes:
		return
	var transforms := []
	var colours := []
	var bays := int((length * 0.75) / (CONTAINER.z + 1.5))
	for bay in bays:
		var bx := -length * 0.27 + bay * (CONTAINER.z + 1.5)
		var tiers := _rng.randi_range(3, 7)
		var across := int(beam / CONTAINER.x) - 1
		for row in across:
			for tier in clampi(tiers + _rng.randi_range(-1, 1), 1, 8):
				var p := Vector3(bx, 10.0 + CONTAINER.y * (tier + 0.5), (row - across * 0.5 + 0.5) * CONTAINER.x)
				transforms.append(xform * Transform3D(Basis(Vector3.UP, PI * 0.5), p))
				colours.append(CONTAINER_COLOURS[_rng.randi() % CONTAINER_COLOURS.size()])
	add_multimesh(_container_mesh, transforms, colours)


## The city to the west: towers with windows lighting up for the evening.
func _build_skyline() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mesh.material = make_shader_material("windows", {"night": 0.6})
	var transforms := []
	var custom := []
	for i in 70:
		var w := _rng.randf_range(18.0, 40.0)
		var d := _rng.randf_range(18.0, 40.0)
		var h := _rng.randf_range(25.0, 120.0) * (1.4 if _rng.randf() < 0.15 else 1.0)
		var p := Vector3(_rng.randf_range(-950.0, -680.0), h * 0.5 + 3.0, _rng.randf_range(-500.0, 650.0))
		transforms.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), p))
		custom.append(Color(_rng.randf(), _rng.randf_range(0.15, 0.45), _rng.randf(), _rng.randf()))
	add_multimesh(mesh, transforms, [], custom)
