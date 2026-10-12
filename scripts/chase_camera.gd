class_name ChaseCamera
extends Camera3D
## Third-person camera. Follows behind a car, shakes on big hits, and can
## instead slowly orbit a point (used on the Next Derby screen).

@export var distance := 9.5
@export var height := 4.0
@export var smoothing := 6.0

var target: DerbyCar
var orbit_center := Vector3.ZERO
var orbit_radius := 90.0
var orbit_height := 45.0
var orbiting := false

var _trauma := 0.0
var _orbit_angle := 0.0


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	# Real-time delta keeps the camera smooth during slow motion.
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	if orbiting:
		_orbit_angle += real_delta * 0.12
		var offset := Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * orbit_radius
		global_position = orbit_center + offset + Vector3.UP * orbit_height
		look_at(orbit_center, Vector3.UP)
		return
	if target == null or not is_instance_valid(target):
		return
	var forward := target.get_forward()
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var size: Vector3 = target.stats["size"]
	var dist := distance + size.z * 0.4
	var desired := target.global_position - forward * dist + Vector3.UP * (height + size.y * 0.5)
	global_position = global_position.lerp(desired, clampf(smoothing * real_delta, 0.0, 1.0))
	var look_at_point := target.global_position + Vector3.UP * 1.0
	if global_position.distance_to(look_at_point) > 0.5:
		look_at(look_at_point, Vector3.UP)

	if _trauma > 0.0:
		_trauma = maxf(_trauma - real_delta * 1.5, 0.0)
		var shake := _trauma * _trauma
		rotate_object_local(Vector3.RIGHT, randf_range(-1, 1) * 0.05 * shake)
		rotate_object_local(Vector3.UP, randf_range(-1, 1) * 0.05 * shake)
		h_offset = randf_range(-1, 1) * 0.3 * shake
		v_offset = randf_range(-1, 1) * 0.3 * shake
	else:
		h_offset = 0.0
		v_offset = 0.0


func snap_to_target() -> void:
	if target == null:
		return
	orbiting = false
	var forward := target.get_forward()
	global_position = target.global_position - forward * distance + Vector3.UP * height
	look_at(target.global_position + Vector3.UP, Vector3.UP)
