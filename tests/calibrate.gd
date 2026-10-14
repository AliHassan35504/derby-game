extends SceneTree
# Drives each car type on flat ground and prints speed and turning, to check
# the car physics after tuning changes. Run with:
#   godot --headless --path . -s tests/calibrate.gd

var cars := []
var t := 0.0

func _initialize() -> void:
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1000, 2, 1000)
	shape.shape = box
	ground.add_child(shape)
	ground.position.y = -1
	root.add_child(ground)
	var i := 0
	for type in DerbyCar.CAR_TYPES.keys():
		var car := DerbyCar.new()
		car.car_type = type
		car.position = Vector3(i * 30.0, 1.5, 0)
		root.add_child(car)
		cars.append(car)
		i += 1

func _physics_process(delta: float) -> bool:
	t += delta
	for car in cars:
		car.controls_enabled = t > 0.5
		car.throttle_input = 1.0 if t < 6.0 else 0.0
		car.steer_input = 1.0 if t > 4.0 and t < 6.0 else 0.0
	if int(t * 60) % 60 == 0:
		for car in cars:
			print("%4.1fs %-8s fwd_speed=%5.1f pos=%s yaw=%5.1f up=%.2f" % [t, car.car_type, car.get_forward_speed(), car.global_position.snapped(Vector3.ONE * 0.1), rad_to_deg(car.global_rotation.y), car.global_basis.y.y])
	return t > 7.0
