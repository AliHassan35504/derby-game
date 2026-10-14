extends SceneTree
# A bot should finish off a car parked at the edge of a pad instead of
# driving past it. Run with:
#   godot --headless --path . -s tests/push_test.gd

var map: DerbyMap
var bot_car: DerbyCar
var victim: DerbyCar
var t := 0.0


func _initialize() -> void:
	map = BoardwalkMap.new()
	root.add_child(map)


func _spawn() -> void:
	victim = _make_car(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(64.0, 16.6, 2.5)))
	bot_car = _make_car(map.get_spawn_points(5)[4])
	var bot := BotController.new()
	bot.map = map
	bot.skill = 0.9
	bot.rivals = [bot_car, victim]
	bot_car.add_child(bot)
	bot_car.controls_enabled = true


func _make_car(xform: Transform3D) -> DerbyCar:
	var car := DerbyCar.new()
	car.car_type = map.car_type
	car.transform = xform
	car.kill_height = map.kill_height
	root.add_child(car)
	return car


func _physics_process(delta: float) -> bool:
	if victim == null:
		_spawn()
		return false
	t += delta
	if not victim.alive:
		print("PUSH TEST PASS: victim knocked off after %.1fs, bot %s" % [t, "alive" if bot_car.alive else "fell too"])
		return true
	if t > 40.0:
		print("PUSH TEST FAIL: victim still on the pad after 40s; bot at %s" % bot_car.global_position)
		return true
	return false
