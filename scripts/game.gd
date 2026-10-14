extends Node3D
## Runs the game: the title menu (with a map flyover behind it), then a
## championship across every map or quick races on one. Each round shows the
## Next Derby screen, spawns everyone in that map's car, counts down,
## collapses the map late in the round, tracks knock-offs and shows the
## results and championship standings.
##
## Run with `-- --autotest` to replace the player with a bot, play one round
## on every map at 4x speed and quit, printing the results. CI uses this.

const MAPS := [
	preload("res://scripts/maps/boardwalk.gd"),
	preload("res://scripts/maps/sky_maze.gd"),
	preload("res://scripts/maps/mountain_spiral.gd"),
	preload("res://scripts/maps/harbour_cranes.gd"),
	preload("res://scripts/maps/canyon_bridges.gd"),
	preload("res://scripts/maps/neon_overpass.gd"),
	preload("res://scripts/maps/frozen_peaks.gd"),
]
const INTRO_TIME := 5.0
const COUNTDOWN := 3.0
## The map starts falling apart when this much time is left (or 40% of a
## short round).
const COLLAPSE_AT := 60.0
const RESULTS_TIME := 7.0
## Championship points by finishing place.
const POINTS := [10, 8, 6, 5, 4, 3, 2, 1, 1, 1]

const BOT_NAMES := ["Crusher", "Rustbucket", "Mad Max", "Bumper", "Wrecker", "Tank", "Dent", "Scrapper", "Smasher", "Nitro Ned"]

enum State { MENU, INTRO, COUNTDOWN, FIGHT, RESULTS, FINAL }
enum Mode { CHAMPIONSHIP, QUICK_RACE, AUTOTEST }

var map: DerbyMap
var camera: ChaseCamera
var hud: DerbyHud
var menu: MainMenu
var pause_menu: PauseMenu
var cars: Array[DerbyCar] = []
var player: DerbyCar
var state := State.MENU
var mode := Mode.CHAMPIONSHIP
var round_time := 0.0
var round_length := 150.0
var autotest := false
## Pickups and stunt cash for the current round (children of the map).
var pickups: PickupManager
var stunts: StuntScore
var stunt_hud: StuntHud

## Map indices to play in order, and where we are in them.
var _playlist: Array[int] = []
var _series_index := 0
## Championship points by driver name, and the drivers (name, colour) kept
## the same through a championship.
var _points := {}
var _drivers: Array = []
var _backdrop_index := 0
var _state_time := 0.0
var _collapse_timer := 0.0
var _collapse_interval := 1.0
var _eliminated_order: Array[DerbyCar] = []
var _spectate_index := 0
var _rounds_played := 0
var _message_until := 0.0


func _ready() -> void:
	autotest = "--autotest" in OS.get_cmdline_user_args()
	if autotest:
		Engine.physics_ticks_per_second = 240
		Engine.max_physics_steps_per_frame = 32
	else:
		GameSettings.load_settings()
		GameSettings.apply_display(get_viewport())
	GameSettings.apply_audio()
	_setup_input()
	camera = ChaseCamera.new()
	camera.fov = GameSettings.fov
	camera.far = 3000.0
	add_child(camera)
	hud = DerbyHud.new()
	add_child(hud)
	hud.set_quality(GameSettings.QUALITY_NAMES[GameSettings.quality])
	stunt_hud = StuntHud.new()
	hud.add_child(stunt_hud)

	if autotest:
		mode = Mode.AUTOTEST
		_playlist.assign(range(MAPS.size()))
		_series_index = 0
		_pick_drivers(6)
		start_round()
		return

	menu = MainMenu.new()
	menu.map_info_source = _map_info
	menu.championship_requested.connect(start_championship)
	menu.quick_race_requested.connect(start_quick_race)
	menu.settings_changed.connect(_apply_settings)
	add_child(menu)
	pause_menu = PauseMenu.new()
	pause_menu.restart_requested.connect(start_round)
	pause_menu.menu_requested.connect(show_menu)
	pause_menu.settings_changed.connect(_apply_settings)
	add_child(pause_menu)
	show_menu()


## Title screen, with a slow flyover of one of the maps behind it.
func show_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	_clear_round()
	state = State.MENU
	hud.visible = false
	map = MAPS[_backdrop_index % MAPS.size()].new()
	_backdrop_index += 1
	add_child(map)
	map.apply_quality(GameSettings.quality)
	player = null
	camera.target = null
	camera.orbit_center = Vector3(0, 30, 0)
	camera.orbiting = true
	Sfx.play_music("menu")
	menu.open()


func start_championship() -> void:
	mode = Mode.CHAMPIONSHIP
	_playlist.assign(range(MAPS.size()))
	_series_index = 0
	_points.clear()
	_pick_drivers(GameSettings.bot_count + 1)
	for driver in _drivers:
		_points[driver[0]] = 0
	start_round()


func start_quick_race(map_index: int) -> void:
	mode = Mode.QUICK_RACE
	_playlist.assign([map_index])
	_series_index = 0
	_pick_drivers(GameSettings.bot_count + 1)
	start_round()


## Names and colours for this series: the player first, then the bots.
func _pick_drivers(count: int) -> void:
	var names := BOT_NAMES.duplicate()
	names.shuffle()
	var colors := DerbyCar.BODY_COLORS.duplicate()
	var player_color: Color = colors[GameSettings.player_color if not autotest else 0]
	colors.erase(player_color)
	colors.shuffle()
	_drivers = [["You" if autotest else GameSettings.player_name, player_color]]
	for i in range(1, count):
		_drivers.append([names[(i - 1) % names.size()], colors[(i - 1) % colors.size()]])


func _clear_round() -> void:
	for car in cars:
		car.queue_free()
	cars.clear()
	_eliminated_order.clear()
	if map:
		map.queue_free()
		map = null
	hud.clear_feed()
	hud.hide_results()
	hud.hide_intro()
	hud.show_message("")
	hud.set_spectating("")
	stunt_hud.clear()
	stunt_hud.set_car(null)


func start_round() -> void:
	get_tree().paused = false
	Engine.time_scale = 4.0 if autotest else 1.0
	_clear_round()
	if menu:
		menu.visible = false
	hud.visible = true
	round_length = 150.0 if autotest else GameSettings.round_seconds()

	map = MAPS[_playlist[_series_index % _playlist.size()]].new()
	Sfx.play_music("menu")
	add_child(map)
	map.apply_quality(GameSettings.quality)

	var spawns := map.get_spawn_points(_drivers.size())
	player = _spawn_car(_drivers[0][0], _drivers[0][1], spawns[0])
	if autotest:
		_attach_bot(player)
	else:
		player.add_child(PlayerController.new())
	for i in range(1, _drivers.size()):
		_attach_bot(_spawn_car(_drivers[i][0], _drivers[i][1], spawns[i]))
	for car in cars:
		for child in car.get_children():
			if child is BotController:
				child.rivals = cars
	_start_extras(spawns)

	camera.target = player
	camera.orbit_center = Vector3(0, 30, 0)
	camera.orbiting = true
	hud.set_map(map.map_name)
	var stage := ""
	if mode == Mode.CHAMPIONSHIP:
		stage = "Championship · Round %d of %d" % [_series_index + 1, _playlist.size()]
	hud.show_intro(map.map_name, DerbyCar.CAR_TYPES[map.car_type]["label"], map.rule_text, stage)
	hud.set_alive_count(cars.size(), cars.size())
	hud.set_timer(round_length, false)
	state = State.INTRO
	_state_time = 0.0
	round_time = 0.0
	_collapse_timer = 0.0


func _spawn_car(car_name: String, color: Color, spawn: Transform3D) -> DerbyCar:
	var car := DerbyCar.new()
	car.car_type = map.car_type
	car.display_name = car_name
	car.body_color = color
	car.transform = spawn
	car.kill_height = map.kill_height
	car.nitro_refill_multiplier = map.nitro_refill_multiplier
	car.hop_multiplier = map.hop_multiplier
	car.grip_multiplier = map.grip_multiplier
	add_child(car)
	car.eliminated.connect(_on_car_eliminated)
	car.hit.connect(_on_car_hit)
	cars.append(car)
	return car


func _attach_bot(car: DerbyCar) -> void:
	var bot := BotController.new()
	bot.skill = randf_range(0.55, 0.95) if autotest else GameSettings.random_bot_skill()
	bot.map = map
	car.add_child(bot)


func _physics_process(delta: float) -> void:
	_state_time += delta
	match state:
		State.MENU:
			return
		State.INTRO:
			hud.set_intro_countdown(INTRO_TIME - _state_time)
			if _state_time >= INTRO_TIME or autotest:
				hud.hide_intro()
				camera.snap_to_target()
				state = State.COUNTDOWN
				_state_time = 0.0
		State.COUNTDOWN:
			var left := COUNTDOWN - _state_time
			Sfx.countdown(left)
			hud.show_message(str(ceili(left)) if left > 0.0 else "", "Last car standing wins")
			if left <= 0.0:
				state = State.FIGHT
				_state_time = 0.0
				_flash_message("GO!", "", 1.2)
				for car in cars:
					car.controls_enabled = true
		State.FIGHT:
			_fight_step(delta)
		State.RESULTS:
			if not autotest and _state_time > RESULTS_TIME:
				_next_round()
	if player and is_instance_valid(player):
		hud.update_player(player)


func _fight_step(delta: float) -> void:
	round_time += delta
	var remaining := round_length - round_time
	var collapse_at := minf(COLLAPSE_AT, round_length * 0.4)
	hud.set_timer(remaining, remaining <= collapse_at)
	if _message_until > 0.0 and round_time > _message_until:
		_message_until = 0.0
		hud.show_message("")

	if remaining <= collapse_at:
		if _collapse_timer == 0.0:
			# Spread the collapse so the last piece goes as the clock hits 0.
			_collapse_interval = collapse_at / float(maxi(map.pieces_left(), 1))
			_collapse_timer = 0.0001
			_flash_message("COLLAPSE!", "The roads are falling away", 2.5)
			hud.add_feed("The map is collapsing!", true)
		_collapse_timer += delta
		if _collapse_timer >= _collapse_interval or (remaining <= 0.0 and map.pieces_left() > 0):
			_collapse_timer = 0.0001
			map.collapse_next()

	if remaining < -20.0:
		# Everyone is somehow still up after the map fell: call it.
		var alive := _alive_cars()
		alive.sort_custom(func(a: DerbyCar, b: DerbyCar) -> bool: return a.health > b.health)
		_end_round(alive[0] if alive.size() > 0 else null)


func _flash_message(text: String, sub: String, seconds: float) -> void:
	hud.show_message(text, sub)
	_message_until = round_time + seconds


func _alive_cars() -> Array[DerbyCar]:
	var alive: Array[DerbyCar] = []
	for car in cars:
		if car.alive:
			alive.append(car)
	return alive


func _unhandled_input(event: InputEvent) -> void:
	if state == State.MENU:
		return
	if event.is_action_pressed("pause") and pause_menu:
		get_viewport().set_input_as_handled()
		pause_menu.open()
	elif state == State.FINAL and (event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		show_menu()
	elif state == State.RESULTS and event.is_action_pressed("ui_accept") and _state_time > 1.5:
		_next_round()
	elif event.is_action_pressed("restart"):
		start_round()
	elif event.is_action_pressed("graphics"):
		GameSettings.quality = (GameSettings.quality + 1) % GameSettings.QUALITY_NAMES.size()
		GameSettings.save_settings()
		_apply_settings()
	elif player and not player.alive and state == State.FIGHT:
		if event.is_action_pressed("spectate_next"):
			_spectate(1)
		elif event.is_action_pressed("spectate_prev"):
			_spectate(-1)


func _spectate(step: int) -> void:
	var alive := _alive_cars()
	if alive.is_empty():
		hud.set_spectating("")
		return
	_spectate_index = posmod(_spectate_index + step, alive.size())
	camera.target = alive[_spectate_index]
	hud.set_spectating(camera.target.display_name)


func _on_car_hit(car: DerbyCar, amount: float) -> void:
	if car == camera.target:
		camera.add_trauma(clampf(amount / 50.0, 0.1, 0.8))


func _on_car_eliminated(car: DerbyCar, reason: String, by: DerbyCar) -> void:
	_eliminated_order.append(car)
	Sfx.elimination(car == player and not autotest)
	var alive := _alive_cars()
	hud.set_alive_count(alive.size(), cars.size())

	var text := ""
	if reason == "fell off" and map.is_over_water():
		_splash(Vector3(car.global_position.x, map.water_height, car.global_position.z))
		text = "%s knocked %s into the sea" % [by.display_name, car.display_name] if by else "%s went for a swim" % car.display_name
	elif reason == "fell off":
		text = "%s knocked %s off" % [by.display_name, car.display_name] if by else "%s fell off" % car.display_name
	elif reason == "flipped":
		text = "%s flipped and blew up" % car.display_name
	else:
		text = "%s wrecked %s" % [by.display_name, car.display_name] if by else "%s was wrecked" % car.display_name
	hud.add_feed(text, car == player or by == player)
	if autotest:
		print("  [%5.1fs] %s" % [round_time, text])

	if car == player and not autotest:
		_flash_message("YOU'RE OUT", "Placed #%d" % (alive.size() + 1), 3.0)
	if car == camera.target and alive.size() > 0:
		_spectate_index = 0
		camera.target = alive[0]
		if not player.alive:
			hud.set_spectating(alive[0].display_name)

	if state == State.FIGHT and alive.size() <= 1:
		_end_round(alive[0] if alive.size() == 1 else car)


func _splash(at: Vector3) -> void:
	var splash := GPUParticles3D.new()
	splash.amount = 60
	splash.lifetime = 1.4
	splash.one_shot = true
	splash.explosiveness = 0.95
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3.UP
	proc.spread = 35.0
	proc.initial_velocity_min = 6.0
	proc.initial_velocity_max = 14.0
	proc.gravity = Vector3(0, -12, 0)
	proc.scale_min = 0.5
	proc.scale_max = 1.6
	splash.process_material = proc
	var drop := SphereMesh.new()
	drop.radius = 0.35
	drop.height = 0.7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.96, 1.0, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	drop.material = mat
	splash.draw_pass_1 = drop
	map.add_child(splash)
	splash.global_position = at
	splash.emitting = true


func _end_round(winner: DerbyCar) -> void:
	if state == State.RESULTS:
		return
	state = State.RESULTS
	_state_time = 0.0
	for car in cars:
		car.controls_enabled = false
	if winner:
		camera.target = winner
	hud.set_spectating("")
	Sfx.round_over(winner == player and not autotest)
	stunts.finish_round(winner)

	var ranking: Array[DerbyCar] = []
	if winner:
		ranking.append(winner)
	for car in _alive_cars():
		if not ranking.has(car):
			ranking.append(car)
	var order := _eliminated_order.duplicate()
	order.reverse()
	for car in order:
		if not ranking.has(car):
			ranking.append(car)
	var rows := []
	for i in ranking.size():
		var car := ranking[i]
		var gained := 0
		if mode == Mode.CHAMPIONSHIP:
			gained = POINTS[mini(i, POINTS.size() - 1)]
			_points[car.display_name] = _points.get(car.display_name, 0) + gained
		rows.append([i + 1, car.display_name, car.survived, car.knockoffs, car == player and not autotest, gained, stunts.cash_of(car)])
	_record_career(winner)

	var title := "DRAW"
	if winner == player and not autotest:
		title = "YOU WIN!"
	elif winner:
		title = "%s WINS" % winner.display_name.to_upper()
	_message_until = 0.0
	hud.show_message("")
	var footer := "Enter: next round  ·  Esc: pause"
	if mode == Mode.QUICK_RACE:
		footer = "Enter: race again  ·  Esc: pause"
	elif mode == Mode.CHAMPIONSHIP and _series_index + 1 >= _playlist.size():
		footer = "Enter: final standings"
	hud.show_results("%s · %s" % [title, map.map_name], rows, _standings(), footer)

	if autotest:
		_finish_autotest_round(winner, ranking)
		return
	# A moment of slow motion on the final knock-off.
	Engine.time_scale = 0.3
	get_tree().create_timer(1.5, true, false, true).timeout.connect(func() -> void: Engine.time_scale = 1.0)


## Championship table: [place, name, points, is_player], best first.
func _standings() -> Array:
	if mode != Mode.CHAMPIONSHIP:
		return []
	var names := _points.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return _points[a] > _points[b])
	var table := []
	for i in names.size():
		table.append([i + 1, names[i], _points[names[i]], names[i] == _drivers[0][0]])
	return table


func _next_round() -> void:
	if mode == Mode.CHAMPIONSHIP and _series_index + 1 >= _playlist.size():
		_show_final()
		return
	if mode != Mode.QUICK_RACE:
		_series_index += 1
	start_round()


func _show_final() -> void:
	state = State.FINAL
	var table := _standings()
	var champion: String = table[0][1]
	var title := "YOU ARE THE CHAMPION!" if champion == _drivers[0][0] else "%s IS THE CHAMPION" % champion.to_upper()
	hud.show_final(title, table, "Enter: back to the title screen")


func _apply_settings() -> void:
	camera.fov = GameSettings.fov
	if map:
		map.apply_quality(GameSettings.quality)
	hud.set_quality(GameSettings.QUALITY_NAMES[GameSettings.quality])


## Name, car and twist of every map, for the menu. Maps only know these
## once built, so each is built hidden for a moment.
func _map_info() -> Array:
	var info := []
	var holder := Node3D.new()
	holder.visible = false
	add_child(holder)
	for script in MAPS:
		var m: DerbyMap = script.new()
		holder.add_child(m)
		info.append({"name": m.map_name, "car": DerbyCar.CAR_TYPES[m.car_type]["label"], "rule": m.rule_text})
	holder.free()
	return info


func _finish_autotest_round(winner: DerbyCar, ranking: Array[DerbyCar]) -> void:
	_rounds_played += 1
	var knocks := ranking.map(func(c: DerbyCar) -> String: return "%s %d" % [c.display_name, c.knockoffs])
	print("%s: winner %s after %.1fs; knock-offs: %s" % [
		map.map_name, "nobody" if winner == null else winner.display_name, round_time, ", ".join(knocks)])
	if round_time > round_length + 25.0:
		print("AUTOTEST FAIL: %s ran past the round length" % map.map_name)
		get_tree().quit(1)
		return
	if _rounds_played >= MAPS.size():
		print("AUTOTEST PASS: %d rounds" % _rounds_played)
		get_tree().quit(0)
		return
	_series_index += 1
	start_round()


# --- Pickups, stunt cash and career ------------------------------------------
# (scripts/pickups.gd, scripts/stunt_score.gd, scripts/stunt_hud.gd,
# scripts/career.gd)

func _start_extras(spawns: Array[Transform3D]) -> void:
	var avoid: Array[Vector3] = []
	for spawn in spawns:
		avoid.append(spawn.origin)
	pickups = PickupManager.new()
	map.add_child(pickups)
	pickups.setup(map, cars, avoid)
	pickups.collected.connect(_on_pickup_collected)
	stunts = StuntScore.new()
	map.add_child(stunts)
	stunts.setup(cars)
	stunts.cash_awarded.connect(_on_cash_awarded)
	stunt_hud.clear()
	stunt_hud.set_car(player)


func _on_pickup_collected(car: DerbyCar, kind: int) -> void:
	if car == player and not autotest:
		var info: Dictionary = Pickup.INFO[kind]
		stunt_hud.notice(info["name"], info["hint"], info["color"])


func _on_cash_awarded(car: DerbyCar, amount: int, label: String) -> void:
	if car != player:
		return
	stunt_hud.set_cash(stunts.cash_of(player))
	# End-of-round bonuses show in the results table instead.
	if state == State.FIGHT and not autotest:
		stunt_hud.popup_cash(amount, label)


func _record_career(winner: DerbyCar) -> void:
	if autotest:
		var earned := cars.map(func(c: DerbyCar) -> String: return "%s %s" % [c.display_name, Career.money(stunts.cash_of(c))])
		print("  pickups collected: %s; stunt cash: %s" % [pickups.collected_counts, ", ".join(earned)])
		return
	if player == null:
		return
	Career.record_round(stunts.cash_of(player), winner == player, player.knockoffs, player.survived, stunts.biggest_hit.get(player, 0.0))


func _setup_input() -> void:
	_add_action("accelerate", [KEY_W, KEY_UP], JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_add_action("reverse", [KEY_S, KEY_DOWN], JOY_AXIS_TRIGGER_LEFT, 1.0)
	_add_action("steer_left", [KEY_A, KEY_LEFT], JOY_AXIS_LEFT_X, -1.0)
	_add_action("steer_right", [KEY_D, KEY_RIGHT], JOY_AXIS_LEFT_X, 1.0)
	_add_action("handbrake", [KEY_SPACE], -1, 0.0, JOY_BUTTON_B)
	_add_action("nitro", [KEY_SHIFT], -1, 0.0, JOY_BUTTON_RIGHT_SHOULDER)
	_add_action("hop", [KEY_E], -1, 0.0, JOY_BUTTON_A)
	_add_action("brace", [KEY_Q], -1, 0.0, JOY_BUTTON_LEFT_SHOULDER)
	_add_action("restart", [KEY_R], -1, 0.0)
	_add_action("pause", [KEY_ESCAPE, KEY_P], -1, 0.0, JOY_BUTTON_START)
	_add_action("graphics", [KEY_F3], -1, 0.0)
	_add_action("spectate_next", [KEY_RIGHT, KEY_D], -1, 0.0, JOY_BUTTON_DPAD_RIGHT)
	_add_action("spectate_prev", [KEY_LEFT, KEY_A], -1, 0.0, JOY_BUTTON_DPAD_LEFT)


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
