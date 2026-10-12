extends SceneTree
# Drives the title menu and a whole championship headless, ending each
# round by knocking cars out, to check the game flow has no script errors.
# Run with:
#   godot --headless --path . -s tests/menu_test.gd

var game: Node
var t := 0.0
var step := 0
var wait := 0.0


func _initialize() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)


func _process(delta: float) -> bool:
	t += delta
	wait -= delta
	if wait > 0.0:
		return false
	match step:
		0:
			_check(game.state == game.State.MENU, "starts on the title menu")
			_check(game.menu.maps.size() == game.MAPS.size(), "menu lists every map")
			game.start_championship()
			wait = 1.0
		1:
			_check(game.state == game.State.INTRO, "championship starts with the intro")
			game.pause_menu.open()
			_check(paused, "pause menu pauses the game")
			game.pause_menu.close()
			wait = 9.0
		2:
			_check(game.state == game.State.FIGHT, "round reaches the fight")
			_knock_out_all_but_one()
			wait = 0.5
		3:
			_check(game.state == game.State.RESULTS, "results after one car is left")
			if game._series_index + 1 < game._playlist.size():
				game._next_round()
				step = 2
				wait = 9.0
				return false
			game._next_round()
		4:
			_check(game.state == game.State.FINAL, "final standings after the last map")
			game.show_menu()
			wait = 0.5
		5:
			_check(game.state == game.State.MENU, "back on the title menu")
			game.start_quick_race(1)
			wait = 9.0
		6:
			_check(game.state == game.State.FIGHT and game.map.map_name == game.menu.maps[1]["name"], "quick race on the picked map")
			print("MENU TEST PASS")
			quit(0)
			return true
	step += 1
	return false


func _knock_out_all_but_one() -> void:
	for car in game.cars.slice(1):
		car._eliminate("fell off")


func _check(ok: bool, what: String) -> void:
	if not ok:
		print("MENU TEST FAIL: %s (state %d, %.1fs)" % [what, game.state, t])
		quit(1)
		step = -1
