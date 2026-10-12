class_name DerbyCar
extends VehicleBody3D
## A derby car. Builds its own body, wheels and collision from a car type,
## takes damage from hard impacts with other cars, and is eliminated when its
## health runs out or it falls off the map. A controller node (player or bot)
## drives it by setting throttle_input, steer_input and handbrake_input.

signal eliminated(car: DerbyCar, reason: String)
signal health_changed(car: DerbyCar, health: float)

const CAR_TYPES := {
	"compact": {
		"label": "Compact", "mass": 750.0, "engine": 2400.0, "top_speed": 27.0, "steer": 0.62,
		"health": 80.0, "size": Vector3(1.7, 0.6, 3.4), "color": Color(0.96, 0.74, 0.12),
	},
	"sedan": {
		"label": "Sedan", "mass": 1050.0, "engine": 3000.0, "top_speed": 24.0, "steer": 0.52,
		"health": 100.0, "size": Vector3(1.9, 0.7, 4.0), "color": Color(0.18, 0.48, 0.95),
	},
	"truck": {
		"label": "Truck", "mass": 1700.0, "engine": 4600.0, "top_speed": 21.0, "steer": 0.42,
		"health": 130.0, "size": Vector3(2.2, 1.0, 4.8), "color": Color(0.86, 0.2, 0.16),
	},
}

## Impacts below this change in speed (m/s) do no damage.
const DAMAGE_THRESHOLD := 2.0
## Health lost per m/s of impact above the threshold.
const DAMAGE_PER_MPS := 11.0
## Hits taken on the front bumper (i.e. while ramming) hurt less.
const FRONT_ARMOR := 0.4
## Below this height the car counts as fallen off the map.
const FALL_HEIGHT := -12.0

@export var car_type := "sedan"
@export var display_name := "Car"
@export var body_color := Color.WHITE

var stats: Dictionary
var max_health := 100.0
var health := 100.0
var alive := true
var controls_enabled := false

var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false

var _prev_velocity := Vector3.ZERO
var _body_material: StandardMaterial3D
var _smoke: GPUParticles3D


func _init() -> void:
	contact_monitor = true
	max_contacts_reported = 8


func _ready() -> void:
	stats = CAR_TYPES.get(car_type, CAR_TYPES["sedan"])
	mass = stats["mass"]
	max_health = stats["health"]
	health = max_health
	if body_color == Color.WHITE:
		body_color = stats["color"]
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, -0.45, 0)
	_build_body()
	_build_wheels()


## Direction the car drives in when throttle is positive.
func get_forward() -> Vector3:
	return global_basis.z


func get_forward_speed() -> float:
	return linear_velocity.dot(get_forward())


func _physics_process(delta: float) -> void:
	if not alive:
		engine_force = 0.0
		brake = 2.0
		return

	if global_position.y < FALL_HEIGHT:
		_eliminate("fell off")
		return

	if controls_enabled:
		_apply_controls(delta)
	else:
		engine_force = 0.0
		brake = 30.0

	_check_impact_damage()
	_prev_velocity = linear_velocity


func _apply_controls(delta: float) -> void:
	# Positive steering turns the car left.
	steering = move_toward(steering, steer_input * float(stats["steer"]), delta * 3.0)
	var speed := get_forward_speed()
	var engine: float = stats["engine"]
	# Holding reverse while still rolling forward brakes first, then reverses.
	if throttle_input < 0.0 and speed > 1.5:
		engine_force = 0.0
		brake = 40.0
	elif throttle_input > 0.0 and speed < -1.5:
		engine_force = 0.0
		brake = 40.0
	else:
		# Engine power fades out as the car nears its top speed.
		var top: float = stats["top_speed"] * (1.0 if throttle_input > 0.0 else 0.4)
		var power := clampf(1.0 - absf(speed) / top, 0.0, 1.0)
		engine_force = throttle_input * engine * power
		brake = 0.0
	if handbrake_input:
		brake = 60.0


func _check_impact_damage() -> void:
	var dv_vec := linear_velocity - _prev_velocity
	var dv := dv_vec.length()
	if dv < DAMAGE_THRESHOLD:
		return
	var hit_car := false
	for body in get_colliding_bodies():
		if body is DerbyCar:
			hit_car = true
			break
	if not hit_car:
		return
	var amount := (dv - DAMAGE_THRESHOLD) * DAMAGE_PER_MPS
	# Being shoved backwards means the impact landed on our front bumper.
	if (-dv_vec).normalized().dot(get_forward()) > 0.5:
		amount *= FRONT_ARMOR
	take_damage(amount)


func take_damage(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(self, health)
	_update_damage_look()
	if health <= 0.0:
		_eliminate("wrecked")


func _eliminate(reason: String) -> void:
	if not alive:
		return
	alive = false
	controls_enabled = false
	if reason == "wrecked":
		_explode()
	eliminated.emit(self, reason)


func _explode() -> void:
	_body_material.albedo_color = Color(0.12, 0.11, 0.1)
	apply_central_impulse(Vector3.UP * mass * 6.0)
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 3.0)
	if _smoke:
		_smoke.amount_ratio = 1.0

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 12.0
	flash.omni_range = 14.0
	add_child(flash)
	var fireball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.55, 0.1)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.45, 0.05)
	fire_mat.emission_energy_multiplier = 4.0
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material = fire_mat
	fireball.mesh = sphere
	add_child(fireball)

	var tween := create_tween().set_parallel()
	tween.tween_property(fireball, "scale", Vector3.ONE * 4.0, 0.5)
	tween.tween_property(fire_mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_property(flash, "light_energy", 0.0, 0.8)
	tween.chain().tween_callback(fireball.queue_free)
	tween.tween_callback(flash.queue_free)


func _update_damage_look() -> void:
	var t := health / max_health
	_body_material.albedo_color = body_color.lerp(Color(0.2, 0.18, 0.16), (1.0 - t) * 0.7)
	if _smoke:
		_smoke.emitting = t < 0.5
		_smoke.amount_ratio = clampf(1.0 - t * 1.6, 0.2, 1.0)


func _build_body() -> void:
	var size: Vector3 = stats["size"]

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = body_color
	_body_material.roughness = 0.45
	_body_material.metallic = 0.3

	var chassis := MeshInstance3D.new()
	var chassis_mesh := BoxMesh.new()
	chassis_mesh.size = size
	chassis_mesh.material = _body_material
	chassis.mesh = chassis_mesh
	add_child(chassis)

	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(0.12, 0.16, 0.2)
	glass_mat.roughness = 0.1
	var cabin := MeshInstance3D.new()
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(size.x * 0.85, size.y * 0.75, size.z * 0.45)
	cabin_mesh.material = glass_mat
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0, size.y * 0.85, -size.z * 0.08)
	add_child(cabin)

	# Bright bumper on the front so you can tell which way a car is facing.
	var bumper_mat := StandardMaterial3D.new()
	bumper_mat.albedo_color = Color(0.85, 0.85, 0.85)
	bumper_mat.metallic = 0.8
	var bumper := MeshInstance3D.new()
	var bumper_mesh := BoxMesh.new()
	bumper_mesh.size = Vector3(size.x * 1.04, size.y * 0.35, 0.25)
	bumper_mesh.material = bumper_mat
	bumper.mesh = bumper_mesh
	bumper.position = Vector3(0, -size.y * 0.2, size.z * 0.5 + 0.1)
	add_child(bumper)

	_smoke = GPUParticles3D.new()
	_smoke.amount = 24
	_smoke.lifetime = 1.6
	_smoke.emitting = false
	_smoke.position = Vector3(0, size.y * 0.6, size.z * 0.35)
	var smoke_proc := ParticleProcessMaterial.new()
	smoke_proc.direction = Vector3.UP
	smoke_proc.spread = 20.0
	smoke_proc.initial_velocity_min = 1.5
	smoke_proc.initial_velocity_max = 3.0
	smoke_proc.gravity = Vector3(0, 0.5, 0)
	smoke_proc.scale_min = 0.6
	smoke_proc.scale_max = 1.4
	_smoke.process_material = smoke_proc
	var puff := SphereMesh.new()
	puff.radius = 0.35
	puff.height = 0.7
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.albedo_color = Color(0.25, 0.25, 0.25, 0.6)
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = smoke_mat
	_smoke.draw_pass_1 = puff
	add_child(_smoke)


func _build_wheels() -> void:
	var size: Vector3 = stats["size"]
	var radius := 0.42 if car_type != "truck" else 0.55
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.06, 0.06, 0.06)
	tire_mat.roughness = 0.9

	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var wheel := VehicleWheel3D.new()
			wheel.position = Vector3(side * size.x * 0.5, -size.y * 0.35, end * size.z * 0.34)
			wheel.use_as_steering = end > 0.0
			wheel.use_as_traction = true
			wheel.wheel_radius = radius
			wheel.wheel_rest_length = 0.3
			wheel.suspension_travel = 0.3
			wheel.suspension_stiffness = 40.0
			wheel.suspension_max_force = mass * 30.0
			wheel.damping_compression = 2.5
			wheel.damping_relaxation = 3.5
			wheel.wheel_friction_slip = 2.6
			wheel.wheel_roll_influence = 0.15

			var tire := MeshInstance3D.new()
			var tire_mesh := CylinderMesh.new()
			tire_mesh.top_radius = radius
			tire_mesh.bottom_radius = radius
			tire_mesh.height = 0.35
			tire_mesh.material = tire_mat
			tire.mesh = tire_mesh
			tire.rotation_degrees = Vector3(0, 0, 90)
			wheel.add_child(tire)
			add_child(wheel)
