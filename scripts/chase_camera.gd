class_name ChaseCamera
extends Camera3D
## Third-person camera. Follows behind a car with a free look you steer with
## the mouse or right stick (it swings back behind the car a moment after you
## let go while driving), has near / far / hood views, a look-back button,
## mouse-wheel zoom, pulls in when scenery is in the way and shakes on big
## hits. Can instead slowly orbit a point (used on the Next Derby screen).

enum View { NEAR, FAR, HOOD }
const VIEW_NAMES := ["Near chase", "Far chase", "Hood"]
## Distance and height behind the car for the chase views.
const VIEW_OFFSETS := [Vector2(8.5, 3.2), Vector2(13.0, 5.0)]
const MIN_PITCH := -0.45
const MAX_PITCH := 1.2
## Seconds without look input before the camera swings back behind the car.
const RECENTER_DELAY := 1.4
const STICK_SPEED := 2.6

@export var smoothing := 6.0

var target: DerbyCar
var orbit_center := Vector3.ZERO
var orbit_radius := 90.0
var orbit_height := 45.0
var orbiting := false
var view := View.NEAR
## Player-controlled look: yaw is relative to the car's heading.
var look_yaw := 0.0
var look_pitch := 0.0
var zoom := 1.0
var look_back := false
## Free look on/off (off in menus, autotest and while spectating with no input).
var free_look_enabled := true
var base_fov := 72.0

var _trauma := 0.0
var _orbit_angle := 0.0
var _heading := 0.0
var _idle := 10.0
var _showcase := false


func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func cycle_view() -> String:
	view = ((view + 1) % VIEW_NAMES.size()) as View
	reset_look()
	return VIEW_NAMES[view]


func reset_look() -> void:
	look_yaw = 0.0
	look_pitch = 0.0
	_idle = 10.0


func _unhandled_input(event: InputEvent) -> void:
	if orbiting or not free_look_enabled or target == null:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := 0.0025 * GameSettings.mouse_sensitivity
		var motion: Vector2 = event.relative
		look_yaw -= motion.x * sens
		var dy := motion.y * sens * (-1.0 if GameSettings.invert_y else 1.0)
		look_pitch = clampf(look_pitch + dy, MIN_PITCH, MAX_PITCH)
		_idle = 0.0
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom = clampf(zoom - 0.08, 0.6, 1.6)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom = clampf(zoom + 0.08, 0.6, 1.6)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			reset_look()


func _process(delta: float) -> void:
	# Real-time delta keeps the camera smooth during slow motion.
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	if orbiting:
		_orbit_angle += real_delta * (0.35 if _showcase else 0.12)
		if _showcase and is_instance_valid(target):
			orbit_center = target.global_position + Vector3.UP * 0.8
		var offset := Vector3(cos(_orbit_angle), 0, sin(_orbit_angle)) * orbit_radius
		var orbit_pos := orbit_center + offset + Vector3.UP * orbit_height
		if _showcase:
			global_position = global_position.lerp(orbit_pos, clampf(real_delta * 2.5, 0.0, 1.0))
		else:
			global_position = orbit_pos
		look_at(orbit_center, Vector3.UP)
		fov = lerpf(fov, base_fov, clampf(real_delta * 3.0, 0.0, 1.0))
		return
	if target == null or not is_instance_valid(target):
		return
	_read_stick(real_delta)
	_idle += real_delta

	var forward := target.get_forward()
	var flat := Vector3(forward.x, 0.0, forward.z)
	if flat.length() > 0.1:
		var heading := atan2(flat.x, flat.z)
		# Swing round smoothly, faster when the gap is big.
		_heading = lerp_angle(_heading, heading, clampf(4.0 * real_delta, 0.0, 1.0))
	var speed := target.linear_velocity.length()
	if GameSettings.auto_center and _idle > RECENTER_DELAY and speed > 3.0:
		var rate := clampf(real_delta * 2.2, 0.0, 1.0)
		look_yaw = lerp_angle(look_yaw, 0.0, rate)
		look_pitch = lerpf(look_pitch, 0.0, rate)

	if view == View.HOOD:
		_hood_view(real_delta, forward)
	else:
		_chase_view(real_delta, speed)

	# A little wider at speed and on nitro, for a sense of pace.
	var kick := clampf(speed / 30.0, 0.0, 1.0) * 6.0 + (5.0 if target.is_nitro_active() else 0.0)
	fov = lerpf(fov, base_fov + kick, clampf(real_delta * 3.0, 0.0, 1.0))
	_shake(real_delta)


func _read_stick(real_delta: float) -> void:
	if not free_look_enabled:
		return
	var stick := Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
	if stick.length() < 0.2:
		return
	look_yaw -= stick.x * STICK_SPEED * real_delta
	var dy := stick.y * STICK_SPEED * 0.6 * real_delta * (-1.0 if GameSettings.invert_y else 1.0)
	look_pitch = clampf(look_pitch + dy, MIN_PITCH, MAX_PITCH)
	_idle = 0.0


func _chase_view(real_delta: float, _speed: float) -> void:
	var size: Vector3 = target.stats["size"]
	var offsets: Vector2 = VIEW_OFFSETS[view]
	var dist := (offsets.x + size.z * 0.4) * zoom
	var height := offsets.y + size.y * 0.5
	var yaw := _heading + look_yaw + (PI if look_back else 0.0)
	# Pitch the boom: the base height plus whatever the player looks down by.
	var base_pitch := atan2(height, dist)
	var pitch := clampf(base_pitch + look_pitch, -0.2, 1.35)
	var boom := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	var pivot := target.global_position + Vector3.UP * (1.0 + size.y * 0.25)
	var length := Vector2(dist, height).length()
	var desired := pivot - Vector3(boom.x, -boom.y, boom.z) * length
	desired = _avoid_scenery(pivot, desired)
	# Follow tightly in free look so the mouse feels direct.
	var follow := smoothing * (2.5 if _idle < 0.3 or look_back else 1.0)
	global_position = global_position.lerp(desired, clampf(follow * real_delta, 0.0, 1.0))
	if look_back:
		global_position = desired
	if global_position.distance_to(pivot) > 0.5:
		look_at(pivot, Vector3.UP)


func _hood_view(_real_delta: float, forward: Vector3) -> void:
	var size: Vector3 = target.stats["size"]
	var basis := target.global_basis
	global_position = target.global_position + basis.y * (size.y * 0.5 + 0.35) + forward * (size.z * 0.12)
	var dir := forward.rotated(basis.y, look_yaw + (PI if look_back else 0.0))
	dir = dir.rotated(basis.x.normalized(), look_pitch * 0.8)
	look_at(global_position + dir * 10.0, basis.y)


## Pulls the camera in front of walls, pillars and roads between it and the car.
func _avoid_scenery(pivot: Vector3, desired: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return desired
	var query := PhysicsRayQueryParameters3D.create(pivot, desired, 1)
	query.exclude = [target.get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return desired
	var point: Vector3 = hit["position"]
	var back := (desired - pivot).normalized()
	return point - back * 0.4


func _shake(real_delta: float) -> void:
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


## Slowly circles a point high over the map (menu and Next Derby screen).
func start_orbit(center: Vector3) -> void:
	orbit_center = center
	orbit_radius = 90.0
	orbit_height = 45.0
	_showcase = false
	orbiting = true


## Slowly circles a car, starting from where the camera is now (the winner
## at the end of a round).
func showcase(car: DerbyCar) -> void:
	target = car
	var from := global_position - car.global_position
	_orbit_angle = atan2(from.z, from.x)
	orbit_radius = 10.0 + float(car.stats["size"].z)
	orbit_height = 3.5
	orbit_center = car.global_position
	_showcase = true
	orbiting = true


func snap_to_target() -> void:
	if target == null:
		return
	orbiting = false
	_showcase = false
	reset_look()
	var forward := target.get_forward()
	_heading = atan2(forward.x, forward.z)
	var offsets: Vector2 = VIEW_OFFSETS[View.FAR if view == View.FAR else View.NEAR]
	global_position = target.global_position - forward * offsets.x + Vector3.UP * offsets.y
	look_at(target.global_position + Vector3.UP, Vector3.UP)
