class_name CarVisuals
extends RefCounted
## Builds the visible model for each car type out of simple meshes: painted
## body panels, glass, lights, bumpers and detailed wheels. Returns the paint
## material so the car can darken it as it takes damage.


static func build_body(car: Node3D, style: String, size: Vector3, color: Color) -> StandardMaterial3D:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = color
	paint.metallic = 0.55
	paint.roughness = 0.32
	paint.clearcoat_enabled = true
	paint.clearcoat = 0.6
	paint.clearcoat_roughness = 0.15

	match style:
		"van":
			_build_van(car, size, paint)
		"sports":
			_build_sports(car, size, paint)
		"monster":
			_build_monster(car, size, paint)
		_:
			_box(car, size, Vector3.ZERO, paint)
	return paint


static func build_wheel(radius: float, width: float, style: String) -> Node3D:
	var root := Node3D.new()
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.05, 0.05, 0.05)
	tire_mat.roughness = 0.92
	var tire := MeshInstance3D.new()
	var tire_mesh := CylinderMesh.new()
	tire_mesh.top_radius = radius
	tire_mesh.bottom_radius = radius
	tire_mesh.height = width
	tire_mesh.radial_segments = 24
	tire_mesh.material = tire_mat
	tire.mesh = tire_mesh
	tire.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(tire)

	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.75, 0.76, 0.78) if style != "monster" else Color(0.15, 0.15, 0.16)
	rim_mat.metallic = 0.9
	rim_mat.roughness = 0.25
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = radius * 0.62
	rim_mesh.bottom_radius = radius * 0.62
	rim_mesh.height = width * 1.04
	rim_mesh.radial_segments = 16
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation_degrees = Vector3(0, 0, 90)
	root.add_child(rim)

	# Spokes so you can see the wheels turning.
	for i in 5:
		var spoke := MeshInstance3D.new()
		var spoke_mesh := BoxMesh.new()
		spoke_mesh.size = Vector3(width * 1.08, radius * 1.15, radius * 0.12)
		spoke_mesh.material = rim_mat
		spoke.mesh = spoke_mesh
		spoke.rotation = Vector3(TAU * i / 5.0, 0, 0)
		root.add_child(spoke)
	return root


static func build_nitro_flames(car: Node3D, size: Vector3) -> GPUParticles3D:
	var flames := GPUParticles3D.new()
	flames.amount = 40
	flames.lifetime = 0.25
	flames.emitting = false
	flames.local_coords = false
	flames.position = Vector3(0, -size.y * 0.15, -size.z * 0.5 - 0.1)
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 0, -1)
	proc.spread = 8.0
	proc.initial_velocity_min = 6.0
	proc.initial_velocity_max = 9.0
	proc.gravity = Vector3.ZERO
	proc.scale_min = 0.5
	proc.scale_max = 1.0
	flames.process_material = proc
	var puff := SphereMesh.new()
	puff.radius = 0.16
	puff.height = 0.32
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 0.6, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.55, 1.0)
	mat.emission_energy_multiplier = 6.0
	puff.material = mat
	flames.draw_pass_1 = puff
	car.add_child(flames)
	return flames


static func _build_van(car: Node3D, s: Vector3, paint: StandardMaterial3D) -> void:
	# Tall boxy van: body, slightly narrower upper cabin, windows and a roof rack.
	_box(car, Vector3(s.x, s.y * 0.55, s.z), Vector3(0, -s.y * 0.2, 0), paint)
	_box(car, Vector3(s.x * 0.97, s.y * 0.48, s.z * 0.97), Vector3(0, s.y * 0.3, -s.z * 0.01), paint)
	var glass := _glass()
	_box(car, Vector3(s.x * 0.92, s.y * 0.32, 0.06), Vector3(0, s.y * 0.32, s.z * 0.475), glass)
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.05, s.y * 0.26, s.z * 0.55), Vector3(side * s.x * 0.487, s.y * 0.34, s.z * 0.12), glass)
	var trim := _trim()
	_box(car, Vector3(s.x * 0.8, 0.08, s.z * 0.55), Vector3(0, s.y * 0.58, -s.z * 0.05), trim)
	_bumpers(car, s, trim)
	_lights(car, s, s.y * -0.12)
	_stripe(car, s, Color(0.95, 0.95, 0.9), -s.y * 0.05)


static func _build_sports(car: Node3D, s: Vector3, paint: StandardMaterial3D) -> void:
	# Low wedge: long body, sloped glass cabin set back, rear wing.
	_box(car, Vector3(s.x, s.y * 0.7, s.z), Vector3(0, -s.y * 0.15, 0), paint)
	var hood := MeshInstance3D.new()
	var hood_mesh := PrismMesh.new()
	hood_mesh.left_to_right = 1.0
	hood_mesh.size = Vector3(s.z * 0.35, s.y * 0.28, s.x * 0.98)
	hood_mesh.material = paint
	hood.mesh = hood_mesh
	hood.rotation_degrees = Vector3(0, 90, 0)
	hood.position = Vector3(0, s.y * 0.33, s.z * 0.3)
	car.add_child(hood)
	var cabin := MeshInstance3D.new()
	var cabin_mesh := PrismMesh.new()
	cabin_mesh.left_to_right = 0.45
	cabin_mesh.size = Vector3(s.z * 0.5, s.y * 0.55, s.x * 0.84)
	cabin_mesh.material = _glass()
	cabin.mesh = cabin_mesh
	cabin.rotation_degrees = Vector3(0, 90, 0)
	cabin.position = Vector3(0, s.y * 0.47, -s.z * 0.06)
	car.add_child(cabin)
	var trim := _trim()
	# Rear wing on two posts.
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.08, s.y * 0.35, 0.12), Vector3(side * s.x * 0.32, s.y * 0.38, -s.z * 0.44), trim)
	_box(car, Vector3(s.x * 0.95, 0.05, 0.42), Vector3(0, s.y * 0.56, -s.z * 0.45), trim)
	_bumpers(car, s, trim)
	_lights(car, s, -s.y * 0.05)
	for side in [-1.0, 1.0]:
		var pipe := MeshInstance3D.new()
		var pipe_mesh := CylinderMesh.new()
		pipe_mesh.top_radius = 0.06
		pipe_mesh.bottom_radius = 0.07
		pipe_mesh.height = 0.25
		pipe_mesh.material = trim
		pipe.mesh = pipe_mesh
		pipe.rotation_degrees = Vector3(90, 0, 0)
		pipe.position = Vector3(side * 0.25, -s.y * 0.35, -s.z * 0.5)
		car.add_child(pipe)


static func _build_monster(car: Node3D, s: Vector3, paint: StandardMaterial3D) -> void:
	# Pickup body perched on a visible frame, with a roll bar and roof lights.
	var trim := _trim()
	_box(car, Vector3(s.x * 0.55, s.y * 0.2, s.z * 0.95), Vector3(0, -s.y * 0.35, 0), trim)
	_box(car, Vector3(s.x * 0.92, s.y * 0.4, s.z * 0.96), Vector3(0, s.y * 0.0, 0), paint)
	_box(car, Vector3(s.x * 0.88, s.y * 0.42, s.z * 0.32), Vector3(0, s.y * 0.4, s.z * 0.06), paint)
	var glass := _glass()
	_box(car, Vector3(s.x * 0.8, s.y * 0.28, 0.06), Vector3(0, s.y * 0.43, s.z * 0.225), glass)
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.05, s.y * 0.24, s.z * 0.22), Vector3(side * s.x * 0.442, s.y * 0.43, s.z * 0.06), glass)
		_box(car, Vector3(0.1, s.y * 0.5, 0.1), Vector3(side * s.x * 0.38, s.y * 0.45, -s.z * 0.15), trim)
	_box(car, Vector3(s.x * 0.86, 0.1, 0.1), Vector3(0, s.y * 0.7, -s.z * 0.15), trim)
	# Bed floor.
	_box(car, Vector3(s.x * 0.84, 0.05, s.z * 0.4), Vector3(0, s.y * 0.2, -s.z * 0.28), trim)
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color(1, 0.95, 0.8)
	lamp.emission_enabled = true
	lamp.emission = Color(1, 0.92, 0.75)
	lamp.emission_energy_multiplier = 2.5
	for i in 4:
		var bulb := MeshInstance3D.new()
		var bulb_mesh := CylinderMesh.new()
		bulb_mesh.top_radius = 0.09
		bulb_mesh.bottom_radius = 0.09
		bulb_mesh.height = 0.08
		bulb_mesh.material = lamp
		bulb.mesh = bulb_mesh
		bulb.rotation_degrees = Vector3(90, 0, 0)
		bulb.position = Vector3((i - 1.5) * s.x * 0.2, s.y * 0.66, s.z * 0.12)
		car.add_child(bulb)
	_bumpers(car, s, trim)
	_lights(car, s, s.y * 0.05)
	_stripe(car, s, Color(0.95, 0.95, 0.95), s.y * 0.05)


static func _bumpers(car: Node3D, s: Vector3, mat: Material) -> void:
	_box(car, Vector3(s.x * 1.02, s.y * 0.16, 0.18), Vector3(0, -s.y * 0.32, s.z * 0.5 + 0.06), mat)
	_box(car, Vector3(s.x * 1.02, s.y * 0.16, 0.18), Vector3(0, -s.y * 0.32, -s.z * 0.5 - 0.06), mat)


static func _lights(car: Node3D, s: Vector3, y: float) -> void:
	var head := StandardMaterial3D.new()
	head.albedo_color = Color(1, 1, 0.95)
	head.emission_enabled = true
	head.emission = Color(1, 0.97, 0.9)
	head.emission_energy_multiplier = 3.0
	var tail := StandardMaterial3D.new()
	tail.albedo_color = Color(0.8, 0.05, 0.05)
	tail.emission_enabled = true
	tail.emission = Color(1, 0.1, 0.05)
	tail.emission_energy_multiplier = 2.0
	for side in [-1.0, 1.0]:
		_box(car, Vector3(s.x * 0.22, s.y * 0.1, 0.05), Vector3(side * s.x * 0.36, y, s.z * 0.5 + 0.01), head)
		_box(car, Vector3(s.x * 0.2, s.y * 0.09, 0.05), Vector3(side * s.x * 0.37, y, -s.z * 0.5 - 0.01), tail)


static func _stripe(car: Node3D, s: Vector3, color: Color, y: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.4
	for side in [-1.0, 1.0]:
		_box(car, Vector3(0.02, s.y * 0.07, s.z * 0.8), Vector3(side * (s.x * 0.5 + 0.005), y, 0), mat)


static func _glass() -> StandardMaterial3D:
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.06, 0.09, 0.12)
	glass.metallic = 0.2
	glass.roughness = 0.05
	return glass


static func _trim() -> StandardMaterial3D:
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.1, 0.1, 0.11)
	trim.metallic = 0.6
	trim.roughness = 0.4
	return trim


static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = mat
	mesh.mesh = box
	mesh.position = pos
	parent.add_child(mesh)
	return mesh
