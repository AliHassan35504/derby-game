class_name DerbyArena
extends Node3D
## The first derby map: a round concrete platform floating high above the
## sea, with two ramps and some loose crates. There are no walls, so pushing
## a car over the edge eliminates it.

@export var radius := 42.0

var _concrete: StandardMaterial3D


func _ready() -> void:
	_build_environment()
	_concrete = StandardMaterial3D.new()
	_concrete.albedo_color = Color(0.55, 0.55, 0.57)
	_concrete.roughness = 0.95
	_build_platform()
	_build_ramp(Vector3(0, 0, 16), 0.0)
	_build_ramp(Vector3(0, 0, -16), PI)
	for i in 6:
		var angle := TAU * (i + 0.5) / 6.0
		_build_crate(Vector3(cos(angle), 0, sin(angle)) * radius * 0.45 + Vector3.UP * 0.8)


## Spawn transforms spread around the platform, each facing the middle.
func get_spawn_points(count: int) -> Array[Transform3D]:
	var points: Array[Transform3D] = []
	for i in count:
		var angle := TAU * i / float(count)
		var pos := Vector3(cos(angle), 0, sin(angle)) * radius * 0.72 + Vector3.UP * 1.2
		# looking_at aims -Z, and cars drive along +Z, so aim -Z away from the
		# centre to make each car face the middle.
		var away := Vector3(pos.x, 0, pos.z).normalized()
		var basis := Basis.looking_at(away, Vector3.UP)
		points.append(Transform3D(basis, pos))
	return points


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.25, 0.45, 0.8)
	sky_mat.sky_horizon_color = Color(0.75, 0.82, 0.9)
	sky_mat.ground_horizon_color = Color(0.5, 0.6, 0.7)
	sky_mat.ground_bottom_color = Color(0.1, 0.25, 0.4)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.7, 0.78, 0.88)
	env.fog_density = 0.002
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 150.0
	add_child(sun)

	# Sea far below the platform. Purely visual: anything that falls this far
	# has already been eliminated.
	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2000, 2000)
	var sea_mat := StandardMaterial3D.new()
	sea_mat.albedo_color = Color(0.08, 0.3, 0.45)
	sea_mat.roughness = 0.2
	sea_mat.metallic = 0.4
	plane.material = sea_mat
	sea.mesh = plane
	sea.position.y = -60.0
	add_child(sea)


func _build_platform() -> void:
	var platform := StaticBody3D.new()
	platform.name = "Platform"
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = 2.0
	shape.shape = cylinder
	platform.add_child(shape)

	var mesh := MeshInstance3D.new()
	var cylinder_mesh := CylinderMesh.new()
	cylinder_mesh.top_radius = radius
	cylinder_mesh.bottom_radius = radius * 0.6
	cylinder_mesh.height = 2.0
	cylinder_mesh.radial_segments = 64
	cylinder_mesh.material = _concrete
	mesh.mesh = cylinder_mesh
	platform.add_child(mesh)

	# Hazard stripe around the rim so the edge reads clearly.
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.95, 0.45, 0.05)
	rim_mat.emission_enabled = true
	rim_mat.emission = Color(0.6, 0.25, 0.0)
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.6
	torus.outer_radius = radius
	torus.rings = 64
	torus.material = rim_mat
	rim.mesh = torus
	rim.position.y = 0.95
	rim.scale = Vector3(1, 0.15, 1)
	platform.add_child(rim)

	platform.position.y = -1.0
	add_child(platform)


func _build_ramp(pos: Vector3, yaw: float) -> void:
	# A symmetric hump, so it can be driven over from either side.
	var ramp := StaticBody3D.new()
	var prism := PrismMesh.new()
	prism.left_to_right = 0.5
	prism.size = Vector3(14, 1.8, 7)
	var ramp_mat := StandardMaterial3D.new()
	ramp_mat.albedo_color = Color(0.85, 0.75, 0.2)
	ramp_mat.roughness = 0.8
	prism.material = ramp_mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = prism
	ramp.add_child(mesh)
	var shape := CollisionShape3D.new()
	shape.shape = prism.create_convex_shape()
	ramp.add_child(shape)
	# The prism's slope runs along its X axis; turn it so cars hit it head on.
	ramp.rotation = Vector3(0, yaw + PI / 2.0, 0)
	ramp.position = pos + Vector3.UP * 0.9
	add_child(ramp)


func _build_crate(pos: Vector3) -> void:
	var crate := RigidBody3D.new()
	crate.mass = 150.0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 1.6
	shape.shape = box
	crate.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3.ONE * 1.6
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.38, 0.2)
	box_mesh.material = wood
	mesh.mesh = box_mesh
	crate.add_child(mesh)
	crate.position = pos
	add_child(crate)
