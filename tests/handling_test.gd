extends SceneTree
# Checks the driving mechanics on a flat test floor: the handbrake slides the
# tail out, air control pitches and rolls the car, and a worn-out car is
# slower than a healthy one. Run with:
#   godot --headless --path . -s tests/handling_test.gd

const FLOOR_Y := 0.0

var _phase := 0
var _t := 0.0
var _car: DerbyCar
var _results := {}
var _failures: Array[String] = []


func _initialize() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 1, 1000)
	shape.shape = box
	shape.position.y = FLOOR_Y - 0.5
	floor_body.add_child(shape)
	root.add_child(floor_body)


func _spawn(pos: Vector3, health_fraction := 1.0) -> DerbyCar:
	if _car:
		_car.queue_free()
	var car := DerbyCar.new()
	car.car_type = "sports"
	car.position = pos
	root.add_child(car)
	car.health = car.max_health * health_fraction
	car.controls_enabled = true
	_car = car
	_t = 0.0
	return car


## Yaw change while a car at speed steers hard, with or without handbrake.
func _turn_phase(delta: float, handbrake: bool, key: String) -> bool:
	if _t == 0.0:
		_spawn(Vector3(0, 1.5, 0))
	_t += delta
	_car.throttle_input = 1.0 if _t < 3.0 else 0.0
	if _t >= 3.0:
		_car.steer_input = 1.0
		_car.handbrake_input = handbrake
	if _t >= 3.0 and not _results.has(key + "_start"):
		_results[key + "_start"] = _car.global_basis.z
		_results[key + "_speed"] = _car.get_forward_speed()
	if _t >= 4.2:
		var start: Vector3 = _results[key + "_start"]
		_results[key] = rad_to_deg(start.signed_angle_to(_car.global_basis.z, Vector3.UP))
		# How far the travel direction lags behind where the nose points.
		var v := _car.linear_velocity
		_results[key + "_slip"] = rad_to_deg(absf(Vector3(v.x, 0, v.z).signed_angle_to(_car.global_basis.z, Vector3.UP)))
		return true
	return false


func _air_phase(delta: float, control: bool, key: String) -> bool:
	if _t == 0.0:
		_spawn(Vector3(50, 200, 50))
		_car.air_control = control
	_t += delta
	_car.throttle_input = 1.0
	_car.steer_input = 1.0
	if _t >= 1.0:
		var b := _car.global_basis
		_results[key + "_pitch"] = rad_to_deg(asin(clampf(-b.z.y, -1, 1)))
		_results[key + "_roll"] = rad_to_deg(asin(clampf(b.x.y, -1, 1)))
		return true
	return false


func _speed_phase(delta: float, health_fraction: float, key: String) -> bool:
	if _t == 0.0:
		_spawn(Vector3(-100, 1.5, -100), health_fraction)
	_t += delta
	_car.throttle_input = 1.0
	if _t >= 5.0:
		_results[key] = _car.get_forward_speed()
		return true
	return false


func _physics_process(delta: float) -> bool:
	var done := false
	match _phase:
		0:
			done = _turn_phase(delta, false, "grip")
		1:
			done = _turn_phase(delta, true, "handbrake")
		2:
			done = _air_phase(delta, true, "air")
		3:
			done = _air_phase(delta, false, "noair")
		4:
			done = _speed_phase(delta, 1.0, "healthy")
		5:
			done = _speed_phase(delta, 0.15, "worn")
		_:
			_report()
			return true
	if done:
		_phase += 1
		_t = 0.0
	return false


func _report() -> void:
	print("handling: ", _results)
	if absf(_results["handbrake_slip"]) < absf(_results["grip_slip"]) + 8.0:
		_failures.append("handbrake does not slide the tail out (slip %.1f vs %.1f)" % [_results["handbrake_slip"], _results["grip_slip"]])
	if absf(_results["handbrake_slip"]) > 80.0:
		_failures.append("handbrake spins the car right round (slip %.1f)" % _results["handbrake_slip"])
	# Positive pitch is nose down, negative roll is rolled to the left.
	if _results["air_pitch"] < 15.0:
		_failures.append("air control did not pitch the nose down (%.1f)" % _results["air_pitch"])
	if _results["air_roll"] > -10.0:
		_failures.append("air control did not roll the car (%.1f)" % _results["air_roll"])
	if absf(_results["noair_pitch"]) > 5.0 or absf(_results["noair_roll"]) > 5.0:
		_failures.append("bots get air control")
	if _results["worn"] > _results["healthy"] * 0.92:
		_failures.append("a worn car is not slower (%.1f vs %.1f)" % [_results["worn"], _results["healthy"]])
	if _failures.is_empty():
		print("HANDLING TEST PASS")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		quit(1)
