class_name DerbyCar
extends VehicleBody3D
## A derby car. Builds its own body, wheels and collision from a car type,
## takes damage from hard impacts with other cars, and has three abilities:
## nitro, a hydraulic hop and brace (heavier but slower). It is eliminated
## when wrecked, when it falls below the map, or when it stays on its roof.
## A controller node (player or bot) drives it through the *_input fields.

signal eliminated(car: DerbyCar, reason: String, by: DerbyCar)
signal health_changed(car: DerbyCar, health: float)
signal hit(car: DerbyCar, amount: float)

const CAR_TYPES := {
	"van": {
		"label": "Hot Rod Van", "style": "van", "mass": 1500.0, "engine": 4400.0, "top_speed": 24.0,
		"steer": 0.5, "health": 120.0, "size": Vector3(2.1, 1.7, 4.6),
		"wheel_radius": 0.42, "wheel_width": 0.32, "wheel_y": -0.75, "wheel_z": 0.33,
		"travel": 0.3, "stiffness": 38.0, "grip": 2.6, "com_y": -0.75, "cornering": 4.5,
	},
	"sports": {
		"label": "Stinger GT", "style": "sports", "mass": 1250.0, "engine": 4600.0, "top_speed": 34.0,
		"steer": 0.42, "health": 90.0, "size": Vector3(2.0, 0.85, 4.5),
		"wheel_radius": 0.38, "wheel_width": 0.34, "wheel_y": -0.3, "wheel_z": 0.34,
		"travel": 0.2, "stiffness": 55.0, "grip": 3.0, "com_y": -0.35, "cornering": 6.0,
	},
	"sedan": {
		"label": "Cruiser Sedan", "style": "sedan", "mass": 1450.0, "engine": 4400.0, "top_speed": 27.0,
		"steer": 0.46, "health": 110.0, "size": Vector3(1.9, 1.45, 4.8),
		"wheel_radius": 0.36, "wheel_width": 0.28, "wheel_y": -0.5, "wheel_z": 0.31,
		"travel": 0.25, "stiffness": 42.0, "grip": 2.8, "com_y": -0.55, "cornering": 5.0,
	},
	"pickup": {
		"label": "Ranger Pickup", "style": "pickup", "mass": 1900.0, "engine": 5800.0, "top_speed": 25.0,
		"steer": 0.45, "health": 140.0, "size": Vector3(2.1, 1.8, 5.2),
		"wheel_radius": 0.44, "wheel_width": 0.34, "wheel_y": -0.7, "wheel_z": 0.32,
		"travel": 0.35, "stiffness": 34.0, "grip": 2.9, "com_y": -0.8, "cornering": 4.3,
	},
	"muscle": {
		"label": "Bulldog Muscle", "style": "muscle", "mass": 1600.0, "engine": 6000.0, "top_speed": 31.0,
		"steer": 0.44, "health": 115.0, "size": Vector3(2.0, 1.25, 4.9),
		"wheel_radius": 0.38, "wheel_width": 0.34, "wheel_y": -0.42, "wheel_z": 0.32,
		"travel": 0.22, "stiffness": 48.0, "grip": 2.8, "com_y": -0.45, "cornering": 5.2,
	},
	"rally": {
		"label": "Kestrel Rally", "style": "rally", "mass": 1100.0, "engine": 4100.0, "top_speed": 29.0,
		"steer": 0.5, "health": 85.0, "size": Vector3(1.8, 1.45, 4.0),
		"wheel_radius": 0.34, "wheel_width": 0.26, "wheel_y": -0.5, "wheel_z": 0.32,
		"travel": 0.3, "stiffness": 40.0, "grip": 3.2, "com_y": -0.55, "cornering": 5.5,
	},
	"monster": {
		"label": "Big Foot", "style": "monster", "mass": 2300.0, "engine": 8200.0, "top_speed": 23.0,
		"steer": 0.45, "health": 160.0, "size": Vector3(2.5, 1.5, 4.6),
		"wheel_radius": 0.95, "wheel_width": 0.75, "wheel_y": -0.9, "wheel_z": 0.36,
		"travel": 0.55, "stiffness": 24.0, "grip": 3.2, "com_y": -1.0, "cornering": 3.8,
	},
}

const BODY_COLORS := [
	Color(0.12, 0.35, 0.85), Color(0.85, 0.12, 0.1), Color(0.95, 0.75, 0.1),
	Color(0.15, 0.65, 0.3), Color(0.92, 0.92, 0.92), Color(0.55, 0.2, 0.75),
	Color(0.95, 0.45, 0.1), Color(0.1, 0.1, 0.1), Color(0.2, 0.7, 0.8),
]

## Impacts below this change in speed (m/s) do no damage.
const DAMAGE_THRESHOLD := 2.0
## Health lost per m/s of impact above the threshold.
const DAMAGE_PER_MPS := 11.0
## Hits taken on the front bumper (i.e. while ramming) hurt less.
const FRONT_ARMOR := 0.4
## A car that touched us this recently gets credit for knocking us out.
const CREDIT_WINDOW := 5.0
## Seconds a car can sit on its roof before it blows up.
const FLIP_LIMIT := 3.0

const NITRO_DRAIN := 0.45
const NITRO_REFILL := 0.12
const NITRO_FORCE := 9.0
const HOP_IMPULSE := 6.5
const HOP_COOLDOWN := 3.5
const BRACE_MASS := 1.8
## Anti-roll assist while the wheels are on the road, so cars lean in turns
## instead of rolling over on their own. Hits and drops still flip them.
const ANTI_ROLL := 6.0
const ROLL_DAMPING := 1.5
## Air control (player only): how hard the keys pitch and roll the car in
## the air, per kg, and the fastest spin they can build up.
const AIR_PITCH := 4.0
const AIR_ROLL := 1.3
const AIR_SPIN_LIMIT := 3.0
## Handbrake: rear wheels lock up and lose grip so the tail slides out.
const HANDBRAKE_REAR := 15.0
const HANDBRAKE_GRIP := 0.75
## Below this health fraction the engine starts to lose power, misfire and
## the steering pulls to one side.
const DAMAGE_WEAR_START := 0.5
const HORN_COOLDOWN := 0.5

@export var car_type := "van"
@export var display_name := "Car"
@export var body_color := Color(0.12, 0.35, 0.85)

var stats: Dictionary
var max_health := 100.0
var health := 100.0
var alive := true
var controls_enabled := false
## Lowest safe height; below this the car is out. Set by the map.
var kill_height := -20.0
var nitro_refill_multiplier := 1.0
var hop_multiplier := 1.0
## Map surface grip, e.g. lower on ice. Set before the car is added.
var grip_multiplier := 1.0

var throttle_input := 0.0
var steer_input := 0.0
var handbrake_input := false
var nitro_input := false
var brace_input := false
## Set true for one frame to request a hop.
var hop_input := false
## Lets the steer/throttle keys pitch and roll the car in the air.
var air_control := false

var nitro := 1.0
var hop_cooldown := 0.0
var flipped_time := 0.0
var last_toucher: DerbyCar
var last_touch_time := -100.0
var knockoffs := 0
var survived := 0.0

var _base_mass := 1000.0
var _prev_velocity := Vector3.ZERO
var _paint: StandardMaterial3D
var _smoke: GPUParticles3D
var _fire: GPUParticles3D
var _flames: GPUParticles3D
var _clock := 0.0
var _front_wheels: Array[VehicleWheel3D] = []
var _rear_wheels: Array[VehicleWheel3D] = []
var _tyre_smoke: Array[GPUParticles3D] = []
var _misfire := 0.0
var _next_misfire := 2.0
## Which way a damaged car's steering pulls (-1 or 1).
var _pull_side := 1.0
var _horn_ready := 0.0


func _init() -> void:
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = 2
	collision_mask = 1 | 2


func _ready() -> void:
	stats = CAR_TYPES.get(car_type, CAR_TYPES["van"])
	_base_mass = stats["mass"]
	mass = _base_mass
	max_health = stats["health"]
	health = max_health
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, stats["com_y"], 0)
	_pull_side = -1.0 if randf() < 0.5 else 1.0
	_build_body()
	_build_wheels()
	add_child(CarAudio.new())


## Direction the car drives in when throttle is positive.
func get_forward() -> Vector3:
	return global_basis.z


func get_forward_speed() -> float:
	return linear_velocity.dot(get_forward())


## How far the front wheels can turn at this speed. They turn further when
## slow so cars can get round the corners on the small platforms.
func max_steer_at(speed: float) -> float:
	return stats["steer"] * lerpf(1.9, 1.0, clampf(absf(speed) / 20.0, 0.0, 1.0))


## Rough radius of the tightest turn at a crawl, used by the bots to plan
## corners. Includes a little extra for tyre slip.
func turning_radius() -> float:
	var wheelbase: float = stats["size"].z * float(stats["wheel_z"]) * 2.0
	return wheelbase / tan(max_steer_at(4.0)) * 1.15


func is_on_ground() -> bool:
	for child in get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			return true
	return false


func is_nitro_active() -> bool:
	return alive and controls_enabled and nitro_input and nitro > 0.02


## Sounds the horn (ignored while it is still sounding).
func honk() -> void:
	if not alive or _clock < _horn_ready:
		return
	_horn_ready = _clock + HORN_COOLDOWN
	var audio := get_node_or_null("CarAudio")
	if audio:
		audio.honk()


## 1 when healthy, falling towards 0 as damage wears the car out.
func wear() -> float:
	return clampf((health / max_health) / DAMAGE_WEAR_START, 0.0, 1.0)


func wheels_touching() -> int:
	var touching := 0
	for wheel in _front_wheels + _rear_wheels:
		if wheel.is_in_contact():
			touching += 1
	return touching


func _physics_process(delta: float) -> void:
	_clock += delta
	if not alive:
		engine_force = 0.0
		brake = 2.0
		return
	if controls_enabled:
		survived += delta

	if global_position.y < kill_height:
		_eliminate("fell off")
		return

	if global_basis.y.y < 0.35 and controls_enabled:
		flipped_time += delta
		if flipped_time > FLIP_LIMIT:
			health = 0.0
			health_changed.emit(self, health)
			_eliminate("flipped")
			return
	else:
		flipped_time = 0.0

	hop_cooldown = maxf(hop_cooldown - delta, 0.0)
	if controls_enabled:
		_apply_controls(delta)
	else:
		engine_force = 0.0
		brake = 30.0
		_flames.emitting = false

	_stabilize()
	_air_control()
	_update_tyre_smoke()
	_track_contacts()
	_check_impact_damage()
	_prev_velocity = linear_velocity


func _apply_controls(delta: float) -> void:
	var speed := get_forward_speed()
	# Positive steering turns the car left.
	var max_steer := max_steer_at(speed)
	# A badly damaged car pulls to one side; the driver has to fight it.
	var pull := (1.0 - wear()) * 0.12 * _pull_side
	steering = move_toward(steering, clampf(steer_input * max_steer + pull, -max_steer, max_steer), delta * 3.0)
	var engine: float = stats["engine"]
	var top: float = stats["top_speed"]
	# Damage costs power and top speed, and a wrecked engine misfires.
	var worn := wear()
	engine *= lerpf(0.6, 1.0, worn)
	top *= lerpf(0.8, 1.0, worn)
	if worn < 0.6:
		_next_misfire -= delta
		if _next_misfire <= 0.0:
			_misfire = randf_range(0.1, 0.25)
			_next_misfire = randf_range(0.6, 2.5) * (0.4 + worn)
	_misfire = maxf(_misfire - delta, 0.0)
	if _misfire > 0.0:
		engine *= 0.1

	mass = _base_mass * (BRACE_MASS if brace_input else 1.0)
	if brace_input:
		engine *= 0.75
		top *= 0.6

	var boosting := is_nitro_active()
	if boosting:
		nitro = maxf(nitro - NITRO_DRAIN * delta, 0.0)
		top *= 1.35
		apply_central_force(get_forward() * mass * NITRO_FORCE)
	else:
		nitro = minf(nitro + NITRO_REFILL * nitro_refill_multiplier * delta, 1.0)
	_flames.emitting = boosting

	# Holding reverse while still rolling forward brakes first, then reverses.
	if throttle_input < 0.0 and speed > 1.5:
		engine_force = 0.0
		brake = 40.0
	elif throttle_input > 0.0 and speed < -1.5:
		engine_force = 0.0
		brake = 40.0
	else:
		# Engine power fades out as the car nears its top speed.
		var limit := top * (1.0 if throttle_input > 0.0 else 0.4)
		var power := clampf(1.0 - absf(speed) / limit, 0.0, 1.0)
		engine_force = throttle_input * engine * power
		brake = 0.0
	# The handbrake only locks the rear wheels, so the tail slides out for
	# handbrake turns and drifts. Setting brake above resets every wheel.
	var rear_grip: float = stats["grip"] * grip_multiplier * (HANDBRAKE_GRIP if handbrake_input else 1.0)
	for wheel in _rear_wheels:
		wheel.wheel_friction_slip = rear_grip
		if handbrake_input:
			wheel.brake = maxf(wheel.brake, HANDBRAKE_REAR)
			wheel.engine_force = 0.0

	if hop_input:
		hop_input = false
		if hop_cooldown <= 0.0 and is_on_ground():
			hop_cooldown = HOP_COOLDOWN
			apply_central_impulse(Vector3.UP * mass * HOP_IMPULSE * hop_multiplier)


func _stabilize() -> void:
	var touching := 0
	for child in get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			touching += 1
	if touching < 3:
		return
	var forward := get_forward()
	var roll := global_basis.x.y
	var roll_rate := angular_velocity.dot(forward)
	apply_torque(-forward * (roll * ANTI_ROLL + roll_rate * ROLL_DAMPING) * _base_mass)


## Lets the player straighten the car in the air: throttle/reverse pitch
## the nose down/up and steering rolls it, like GTA.
func _air_control() -> void:
	if not air_control or not controls_enabled or wheels_touching() > 0:
		return
	var right := global_basis.x
	var forward := get_forward()
	var pitch_rate := angular_velocity.dot(right)
	var roll_rate := angular_velocity.dot(forward)
	var pitch := throttle_input
	var roll := -steer_input
	if absf(pitch_rate) < AIR_SPIN_LIMIT or signf(pitch_rate) != signf(pitch):
		apply_torque(right * pitch * AIR_PITCH * mass)
	if absf(roll_rate) < AIR_SPIN_LIMIT or signf(roll_rate) != signf(roll):
		apply_torque(forward * roll * AIR_ROLL * mass)


func _update_tyre_smoke() -> void:
	var speed := linear_velocity.length()
	for i in _rear_wheels.size():
		var wheel := _rear_wheels[i]
		var sliding := wheel.is_in_contact() and wheel.get_skidinfo() < 0.35 and speed > 4.0
		_tyre_smoke[i].emitting = sliding and alive


func _track_contacts() -> void:
	for body in get_colliding_bodies():
		if body is DerbyCar and body != self:
			last_toucher = body
			last_touch_time = _clock


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
	if brace_input:
		amount *= 0.7
	CarVisuals.apply_impact(self, dv_vec)
	# No single crash takes more than 40% health, so head-on hits hurt
	# without ending the round on the first second.
	take_damage(minf(amount, max_health * 0.4))


func take_damage(amount: float) -> void:
	if not alive or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(self, health)
	hit.emit(self, amount)
	_update_damage_look()
	if health <= 0.0:
		_eliminate("wrecked")


func get_credit() -> DerbyCar:
	if last_toucher and _clock - last_touch_time <= CREDIT_WINDOW:
		return last_toucher
	return null


func _eliminate(reason: String) -> void:
	if not alive:
		return
	alive = false
	controls_enabled = false
	_flames.emitting = false
	var by := get_credit()
	if by:
		by.knockoffs += 1
	if reason == "wrecked" or reason == "flipped":
		_explode()
	eliminated.emit(self, reason, by)


func _explode() -> void:
	_paint.albedo_color = Color(0.09, 0.08, 0.07)
	_paint.metallic = 0.1
	_paint.roughness = 0.9
	apply_central_impulse(Vector3.UP * mass * 6.0)
	apply_torque_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * mass * 3.0)
	_smoke.emitting = true
	_smoke.amount_ratio = 1.0
	_fire.emitting = true

	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.2)
	flash.light_energy = 14.0
	flash.omni_range = 16.0
	add_child(flash)
	var fireball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var fire_mat := StandardMaterial3D.new()
	fire_mat.albedo_color = Color(1.0, 0.55, 0.1)
	fire_mat.emission_enabled = true
	fire_mat.emission = Color(1.0, 0.45, 0.05)
	fire_mat.emission_energy_multiplier = 5.0
	fire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material = fire_mat
	fireball.mesh = sphere
	add_child(fireball)

	var tween := create_tween().set_parallel()
	tween.tween_property(fireball, "scale", Vector3.ONE * 4.5, 0.5)
	tween.tween_property(fire_mat, "albedo_color:a", 0.0, 0.5)
	tween.tween_property(flash, "light_energy", 0.0, 0.9)
	tween.chain().tween_callback(fireball.queue_free)
	tween.tween_callback(flash.queue_free)


func _update_damage_look() -> void:
	var t := health / max_health
	_paint.albedo_color = body_color.lerp(Color(0.18, 0.16, 0.14), (1.0 - t) * 0.6)
	_paint.clearcoat = 0.6 * t
	_smoke.emitting = t < 0.6
	_smoke.amount_ratio = clampf(1.2 - t * 1.6, 0.2, 1.0)
	_fire.emitting = t < 0.2


func _build_body() -> void:
	var size: Vector3 = stats["size"]
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	add_child(shape)

	_paint = CarVisuals.build_body(self, stats["style"], size, body_color)
	_flames = CarVisuals.build_nitro_flames(self, size)
	_smoke = _make_particles(Color(0.3, 0.3, 0.3, 0.55), 0.38, 1.8, 2.5, 32)
	_smoke.position = Vector3(0, size.y * 0.5, size.z * 0.32)
	_fire = _make_particles(Color(1.0, 0.45, 0.1, 0.9), 0.3, 0.6, 3.0, 24, true)
	_fire.position = Vector3(0, size.y * 0.45, size.z * 0.3)


func _make_particles(color: Color, radius: float, life: float, speed: float, count: int, glow := false) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = count
	particles.lifetime = life
	particles.emitting = false
	particles.local_coords = false
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 18.0
	proc.initial_velocity_min = speed * 0.6
	proc.initial_velocity_max = speed
	proc.gravity = Vector3(0, 0.6, 0)
	proc.scale_min = 0.6
	proc.scale_max = 1.5
	particles.process_material = proc
	var puff := SphereMesh.new()
	puff.radius = radius
	puff.height = radius * 2.0
	puff.radial_segments = 8
	puff.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if glow:
		mat.emission_enabled = true
		mat.emission = Color(color.r, color.g, color.b)
		mat.emission_energy_multiplier = 4.0
	puff.material = mat
	particles.draw_pass_1 = puff
	add_child(particles)
	return particles


func _build_wheels() -> void:
	var size: Vector3 = stats["size"]
	var radius: float = stats["wheel_radius"]
	var width: float = stats["wheel_width"]
	for side in [-1.0, 1.0]:
		for end in [-1.0, 1.0]:
			var wheel := VehicleWheel3D.new()
			wheel.position = Vector3(side * (size.x * 0.5 - width * 0.35), stats["wheel_y"], end * size.z * float(stats["wheel_z"]))
			wheel.use_as_steering = end > 0.0
			wheel.use_as_traction = true
			wheel.wheel_radius = radius
			wheel.wheel_rest_length = stats["travel"]
			wheel.suspension_travel = stats["travel"]
			wheel.suspension_stiffness = stats["stiffness"]
			wheel.suspension_max_force = _base_mass * 40.0
			wheel.damping_compression = 2.5
			wheel.damping_relaxation = 3.5
			wheel.wheel_friction_slip = stats["grip"] * grip_multiplier
			wheel.wheel_roll_influence = 0.12
			wheel.add_child(CarVisuals.build_wheel(radius, width, stats["style"]))
			add_child(wheel)
			if end > 0.0:
				_front_wheels.append(wheel)
			else:
				_rear_wheels.append(wheel)
				var smoke := _make_particles(Color(0.85, 0.85, 0.85, 0.35), 0.45, 1.4, 1.2, 20)
				smoke.position = wheel.position + Vector3(0, -radius * 0.8, 0)
				(smoke.process_material as ParticleProcessMaterial).scale_max = 2.4
				(smoke.process_material as ParticleProcessMaterial).gravity = Vector3(0, 0.4, 0)
				_tyre_smoke.append(smoke)
