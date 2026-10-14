class_name MainMenu
extends CanvasLayer
## Title screen: championship, quick race on one map, career stats,
## settings, how to play, quit. The game shows a map flyover behind it.

signal championship_requested
signal quick_race_requested(map_index: int)
signal settings_changed

const VERSION := "v0.3"

## Returns the maps as [{"name", "car", "rule"}]; called the first time the
## map list is needed, since it takes a moment.
var map_info_source: Callable
var maps: Array:
	get:
		if _maps.is_empty() and map_info_source.is_valid():
			_maps = map_info_source.call()
		return _maps

var _maps: Array = []

var _home: Control
var _maps_screen: Control
var _help: Control
var _career: Control
var _career_grid: GridContainer
var _settings: SettingsPanel
var _home_first: Button


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	add_child(root)

	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.35)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade)

	_home = _build_home()
	root.add_child(_home)
	_maps_screen = _build_maps()
	root.add_child(_maps_screen)
	_help = _build_help()
	root.add_child(_help)
	_career = _build_career()
	root.add_child(_career)
	_settings = SettingsPanel.new()
	_settings.changed.connect(func() -> void: settings_changed.emit())
	_settings.closed.connect(_show_home)
	var settings_holder := UiKit.centered(_settings)
	settings_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(settings_holder)

	var version := UiKit.label(VERSION, 14, UiKit.MUTED)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.position = Vector2(-80, -36)
	root.add_child(version)
	_show_home()


func open() -> void:
	visible = true
	_show_home()


func _show_home() -> void:
	_home.visible = true
	_maps_screen.visible = false
	_help.visible = false
	_career.visible = false
	_settings.visible = false
	_home_first.grab_focus()


func _show(screen: Control) -> void:
	_home.visible = false
	screen.visible = true
	var first := _first_button(screen)
	if first:
		first.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel") and (_maps_screen.visible or _help.visible or _career.visible):
		get_viewport().set_input_as_handled()
		_show_home()


func _build_home() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UiKit.label("DERBY", 120, Color.WHITE)
	title.add_theme_constant_override("outline_size", 18)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var tagline := UiKit.label("One lane. No rails. Last car standing.", 26, UiKit.ACCENT)
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tagline)
	box.add_child(_spacer(26))
	_home_first = _menu_button(box, "Championship", func() -> void: championship_requested.emit())
	_menu_button(box, "Quick Race", func() -> void: _show(_maps_screen))
	_menu_button(box, "Career", func() -> void:
		_fill_career()
		_show(_career))
	_menu_button(box, "Settings", func() -> void:
		_home.visible = false
		_settings.open())
	_menu_button(box, "How to Play", func() -> void: _show(_help))
	_menu_button(box, "Quit", func() -> void: get_tree().quit())
	var holder := UiKit.centered(box)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return holder


func _build_maps() -> Control:
	var panel := UiKit.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var title := UiKit.label("QUICK RACE · PICK A MAP", 30, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	box.add_child(grid)
	var back := UiKit.button("Back", _show_home, 240)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	var holder := UiKit.centered(panel)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	holder.visibility_changed.connect(func() -> void:
		if holder.visible and grid.get_child_count() == 0:
			_fill_map_grid(grid))
	return holder


func _fill_map_grid(grid: GridContainer) -> void:
	for i in maps.size():
		var info: Dictionary = maps[i]
		var card := Button.new()
		card.custom_minimum_size = Vector2(420, 96)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.text = "%s\n%s · %s" % [info["name"], info["car"], info["rule"]]
		card.add_theme_font_size_override("font_size", 18)
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var index := i
		card.pressed.connect(func() -> void: quick_race_requested.emit(index))
		Sfx.hook_button(card)
		grid.add_child(card)
	if grid.get_child_count() > 0:
		(grid.get_child(0) as Control).grab_focus()


func _build_help() -> Control:
	var panel := UiKit.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UiKit.label("HOW TO PLAY", 30, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for line in [
		"Every driver gets the same car on each map. The roads are one car wide with no rails.",
		"Ram the others off the edge or smash them until they blow up. Last car driving wins.",
		"Hits on your front bumper hurt less, so ram rather than get rammed.",
		"In the last minute the map collapses from the outside in.",
		"Drive through pickups on the platforms: Repair, Nitro, Ram (double damage) and Shockwave.",
		"Big hits, knockouts and airtime earn stunt cash. Your totals are on the Career screen.",
		"Championship: every map in a row, points for each finish. Most points wins.",
	]:
		var l := UiKit.label(line, 18)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 760
		box.add_child(l)
	box.add_child(_spacer(6))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 4)
	for cell in ["Action", "Keyboard", "Gamepad",
			"Accelerate / reverse", "W / S or ↑ / ↓", "Right / left trigger",
			"Steer", "A / D or ← / →", "Left stick",
			"Nitro", "Shift", "Right bumper",
			"Hop", "E", "A",
			"Brace (heavier, slower, tougher)", "Q", "Left bumper",
			"Handbrake", "Space", "B",
			"Spectate when out", "← / →", "D-pad",
			"Pause", "Esc", "Start"]:
		var head: bool = cell in ["Action", "Keyboard", "Gamepad"]
		grid.add_child(UiKit.label(cell, 16 if head else 18, UiKit.MUTED if head else UiKit.TEXT))
	box.add_child(grid)
	var back := UiKit.button("Back", _show_home, 240)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	var holder := UiKit.centered(panel)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	return holder


## Career totals from user://profile.cfg (see scripts/career.gd).
func _build_career() -> Control:
	var panel := UiKit.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	var title := UiKit.label("CAREER", 30, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := UiKit.label("Earn stunt cash with big hits, knockouts, airtime, surviving and winning.", 16, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_career_grid = GridContainer.new()
	_career_grid.columns = 2
	_career_grid.add_theme_constant_override("h_separation", 60)
	_career_grid.add_theme_constant_override("v_separation", 10)
	_career_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_career_grid)
	box.add_child(_spacer(4))
	var back := UiKit.button("Back", _show_home, 240)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)
	var holder := UiKit.centered(panel)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.visible = false
	return holder


func _fill_career() -> void:
	Career.load_profile()
	for child in _career_grid.get_children():
		child.free()
	var rows := Career.rows()
	for i in rows.size():
		_career_grid.add_child(UiKit.label(rows[i][0], 20, UiKit.MUTED))
		var value := UiKit.label(rows[i][1], 34 if i == 0 else 24, UiKit.ACCENT if i == 0 else UiKit.TEXT)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_career_grid.add_child(value)


func _menu_button(box: VBoxContainer, text: String, callback: Callable) -> Button:
	var b := UiKit.button(text, callback, 360)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(b)
	return b


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = height
	return c


func _first_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and child.visible:
			return child
		var found := _first_button(child)
		if found:
			return found
	return null
