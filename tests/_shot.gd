extends SceneTree
var game
var f := 0
func _initialize():
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
func _process(_d):
	f += 1
	var args := OS.get_cmdline_user_args()
	if f == 30 and args.size() > 1 and args[1] == "race":
		game.start_quick_race(int(args[2]))
	if f == 30 and args.size() > 1 and args[1] == "settings":
		game.menu._home.visible = false
		game.menu._settings.open()
	if f == (400 if args.size() > 1 and args[1] == "race" else 90):
		root.get_viewport().get_texture().get_image().save_png(args[0])
		quit()
	return false
