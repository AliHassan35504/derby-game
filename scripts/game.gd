extends Node3D
## Runs derby rounds: spawns the arena, the player and the bots, counts down,
## watches for eliminations and declares the last car standing the winner.
##
## Run with `-- --autotest` to replace the player with a bot, play one round
## and quit, printing the result. CI uses this as a smoke test.

const BOT_COUNT := 5
const COUNTDOWN := 3.0
## After this long a round goes to sudden death and every car loses health.
const SUDDEN_DEATH_AFTER := 75.0
const SUDDEN_DEATH_DPS := 4.0
const RESTART_DELAY := 6.0
const AUTOTEST_TIMEOUT := 240.0

const BOT_NAMES := ["Crusher", "Rustbucket", "Mad Max", "Bumper", "Wrecker", "Tank", "Dent", "Scrapper"]
const BOT_COLORS := [
	Color(0.2, 0.75, 0.3), Color(0.7, 0.3, 0.85), Color(0.95, 0.5, 0.15),
	Color(0.15, 0.75, 0.8), Color(0.9, 0.9, 0.9), Color(0.95, 0.35, 0.55),
]

enum State { COUNTDOWN, FIGHT, OVER }

var arena: DerbyArena
var camera: ChaseCamera
var hud: DerbyHud
var cars: Array[DerbyCar] = []
var player: DerbyCar
var state := State.COUNTDOWN
var round_time := 0.0
var autotest := false

var _state_time := 0.0
var _sudden_death := false


func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	if autotest:
		Engine.time_scale = 4.0
		Engine.physics_ticks_per_second = 240
		Engine.max_physics_steps_per_frame = 32
	_setup_input()
	arena = DerbyArena.new()
	add_child(arena)
	camera = ChaseCamera.new()
	camera.fov = 70.0
	add_child(camera)
	hud = DerbyHud.new()
	add_child(hud)
	start_round()


func start_round() -> void:
	for car in cars:
		car.queue_free()
	cars.clear()
	hud.clear_feed()

	var spawns := arena.get_spawn_points(BOT_COUNT + 1)
	var types := DerbyCar.CAR_TYPES.keys()
	var names := BOT_NAMES.duplicate()
	names.shuffle()

	player = _spawn_car("sedan", "You", Color.WHITE, spawns[0])
	if autotest:
		_attach_bot(player)
	else:
		var controller := PlayerController.new()
		player.add_child(controller)

	for i in BOT_COUNT:
		var car := _spawn_car(types.pick_random(), names[i], BOT_COLORS[i % BOT_COLORS.size()], spawns[i + 1])
		_attach_bot(car)

	for car in cars:
		for child in car.get_children():
			if child is BotController:
				child.rivals = cars

	camera.target = player
	camera.snap_to_target()
	hud.set_player(player)
	hud.set_alive_count(cars.size(), cars.size())
	state = State.COUNTDOWN
	_state_time = 0.0
	round_time = 0.0
	_sudden_death = false


func _spawn_car(type: String, car_name: String, color: Color, spawn: Transform3D) -> DerbyCar:
	var car := DerbyCar.new()
	car.car_type = type
	car.display_name = car_name
	car.body_color = color
	car.transform = spawn
	add_child(car)
	car.eliminated.connect(_on_car_eliminated)
	car.health_changed.connect(_on_car_health_changed)
	cars.append(car)
	return car


func _attach_bot(car: DerbyCar) -> void:
	var bot := BotController.new()
	bot.arena_radius = arena.radius
	bot.skill = randf_range(0.55, 0.95)
	car.add_child(bot)


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.COUNTDOWN:
			var left := COUNTDOWN - _state_time
			hud.show_message(str(ceili(left)) if left > 0.0 else "", "Last car standing wins")
			if left <= 0.0:
				state = State.FIGHT
				_state_time = 0.0
				hud.show_message("SMASH!")
				for car in cars:
					car.controls_enabled = true
		State.FIGHT:
			round_time += delta
			if _state_time > 1.0 and not _sudden_death:
				hud.show_message("")
			if round_time > SUDDEN_DEATH_AFTER:
				if not _sudden_death:
					_sudden_death = true
					hud.show_message("SUDDEN DEATH", "Every car is losing health")
				elif round_time > SUDDEN_DEATH_AFTER + 2.0:
					hud.show_message("")
				for car in cars:
					car.take_damage(SUDDEN_DEATH_DPS * delta)
			if autotest and round_time > AUTOTEST_TIMEOUT:
				print("AUTOTEST FAIL: round did not finish in %ds" % AUTOTEST_TIMEOUT)
				get_tree().quit(1)
		State.OVER:
			if autotest:
				return
			if _state_time > RESTART_DELAY:
				start_round()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		start_round()


func _on_car_health_changed(car: DerbyCar, _health: float) -> void:
	if car == player:
		hud.update_health(car)


func _on_car_eliminated(car: DerbyCar, reason: String) -> void:
	var alive := cars.filter(func(c: DerbyCar) -> bool: return c.alive)
	hud.set_alive_count(alive.size(), cars.size())
	hud.add_feed("%s %s" % [car.display_name, reason])
	if autotest:
		print("[%5.1fs] %s (%s) %s" % [round_time, car.display_name, car.car_type, reason])
	if car == player:
		hud.update_health(car)
		if alive.size() > 0:
			camera.target = alive[0]
	elif camera.target == car and alive.size() > 0:
		camera.target = alive[0]

	if state == State.FIGHT and alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else null)


func _end_round(winner: DerbyCar) -> void:
	state = State.OVER
	_state_time = 0.0
	for car in cars:
		car.controls_enabled = false
	if winner:
		camera.target = winner
	var title := "DRAW"
	if winner == player and not autotest:
		title = "YOU WIN!"
	elif winner:
		title = "%s WINS" % winner.display_name.to_upper()
	hud.show_message(title, "Next round in %d seconds · R to restart now" % RESTART_DELAY)
	if autotest:
		var who := "nobody" if winner == null else "%s (%s)" % [winner.display_name, winner.car_type]
		print("AUTOTEST PASS: winner %s after %.1fs" % [who, round_time])
		get_tree().quit(0)


func _setup_input() -> void:
	_add_action("accelerate", [KEY_W, KEY_UP], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_action("reverse", [KEY_S, KEY_DOWN], JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_action("steer_left", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add_action("steer_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add_action("handbrake", [KEY_SPACE], -1, 0.0, JOY_BUTTON_A)
	_add_action("restart", [KEY_R], -1, 0.0, JOY_BUTTON_START)


func _add_action(action: String, keys: Array, axis: int, axis_dir: float, button := -1) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, 0.2)
	for key in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)
	if axis >= 0:
		var joy := InputEventJoypadMotion.new()
		joy.axis = axis
		joy.axis_value = axis_dir
		InputMap.action_add_event(action, joy)
	if button >= 0:
		var joy_button := InputEventJoypadButton.new()
		joy_button.button_index = button
		InputMap.action_add_event(action, joy_button)
