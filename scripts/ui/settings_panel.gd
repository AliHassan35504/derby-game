class_name SettingsPanel
extends PanelContainer
## Graphics, audio and derby settings. Changes apply straight away and are
## saved when the panel closes.

signal changed
signal closed

var _first: Control


func _init() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = UiKit.PANEL_BG
	style.border_color = Color(UiKit.ACCENT, 0.8)
	style.border_width_top = 3
	style.set_corner_radius_all(8)
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 22
	style.content_margin_bottom = 24
	add_theme_stylebox_override("panel", style)
	theme = UiKit.theme()

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var title := UiKit.label("SETTINGS", 32, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 48)
	box.add_child(columns)
	var left := _grid()
	var right := _grid()
	columns.add_child(left)
	columns.add_child(right)

	_section(left, "Graphics")
	_first = _option(left, "Quality", GameSettings.QUALITY_NAMES, GameSettings.quality,
			func(i: int) -> void: GameSettings.quality = i)
	_option(left, "Display", ["Windowed", "Fullscreen"], 1 if GameSettings.fullscreen else 0,
			func(i: int) -> void: GameSettings.fullscreen = i == 1; GameSettings.apply_display(get_viewport()))
	_option(left, "VSync", ["Off", "On"], 1 if GameSettings.vsync else 0,
			func(i: int) -> void: GameSettings.vsync = i == 1; GameSettings.apply_display(get_viewport()))
	_option(left, "Render scale", GameSettings.RENDER_SCALE_NAMES, GameSettings.render_scale,
			func(i: int) -> void: GameSettings.render_scale = i; GameSettings.apply_display(get_viewport()))
	_slider(left, "Field of view", 55.0, 95.0, 1.0, GameSettings.fov,
			func(v: float) -> void: GameSettings.fov = v)
	_section(left, "Audio")
	_slider(left, "Master volume", 0.0, 1.0, 0.05, GameSettings.master_volume,
			func(v: float) -> void: GameSettings.master_volume = v; GameSettings.apply_audio())
	_slider(left, "Music volume", 0.0, 1.0, 0.05, GameSettings.music_volume,
			func(v: float) -> void: GameSettings.music_volume = v; GameSettings.apply_audio())
	_slider(left, "Effects volume", 0.0, 1.0, 0.05, GameSettings.sfx_volume,
			func(v: float) -> void: GameSettings.sfx_volume = v; GameSettings.apply_audio())

	_section(right, "Derby")
	var name_edit := LineEdit.new()
	name_edit.text = GameSettings.player_name
	name_edit.max_length = 16
	name_edit.custom_minimum_size.x = 260
	name_edit.text_changed.connect(func(t: String) -> void:
		GameSettings.player_name = t.strip_edges() if t.strip_edges() != "" else "You")
	_row(right, "Driver name", name_edit)
	_colors(right)
	var bots := []
	for i in range(1, 10):
		bots.append(str(i))
	_option(right, "Bots", bots, GameSettings.bot_count - 1,
			func(i: int) -> void: GameSettings.bot_count = i + 1)
	_option(right, "Bot difficulty", GameSettings.DIFFICULTY_NAMES, GameSettings.difficulty,
			func(i: int) -> void: GameSettings.difficulty = i)
	_option(right, "Round length", GameSettings.ROUND_LENGTH_NAMES, GameSettings.round_length,
			func(i: int) -> void: GameSettings.round_length = i)
	var note := UiKit.label("Derby changes apply from the next round.", 15, UiKit.MUTED)
	right.add_child(Control.new())
	right.add_child(note)

	var back := UiKit.button("Back", _close, 240)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(back)


func open() -> void:
	visible = true
	_first.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	GameSettings.save_settings()
	visible = false
	closed.emit()


func _grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	return grid


func _section(grid: GridContainer, text: String) -> void:
	grid.add_child(UiKit.label(text.to_upper(), 16, UiKit.ACCENT))
	grid.add_child(Control.new())


func _row(grid: GridContainer, text: String, control: Control) -> void:
	var l := UiKit.label(text, 19)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(l)
	control.custom_minimum_size.x = maxf(control.custom_minimum_size.x, 260)
	grid.add_child(control)


func _option(grid: GridContainer, text: String, items: Array, selected: int, on_pick: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item in items:
		option.add_item(str(item))
	option.selected = selected
	option.item_selected.connect(func(i: int) -> void:
		on_pick.call(i)
		changed.emit())
	_row(grid, text, option)
	return option


func _slider(grid: GridContainer, text: String, low: float, high: float, step: float, value: float, on_change: Callable) -> void:
	var holder := HBoxContainer.new()
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var readout := UiKit.label("", 16, UiKit.MUTED)
	readout.custom_minimum_size.x = 52
	var show_value := func(v: float) -> void:
		readout.text = str(int(v)) if high > 1.0 else "%d%%" % roundi(v * 100.0)
	show_value.call(value)
	slider.value_changed.connect(func(v: float) -> void:
		show_value.call(v)
		on_change.call(v)
		changed.emit())
	holder.add_child(slider)
	holder.add_child(readout)
	_row(grid, text, holder)


func _colors(grid: GridContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var swatches: Array[Button] = []
	for i in DerbyCar.BODY_COLORS.size():
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(26, 26)
		var style := StyleBoxFlat.new()
		style.bg_color = DerbyCar.BODY_COLORS[i]
		style.set_corner_radius_all(13)
		style.set_border_width_all(2)
		style.border_color = Color(1, 1, 1, 0.2)
		var chosen := style.duplicate() as StyleBoxFlat
		chosen.border_color = UiKit.ACCENT
		chosen.set_border_width_all(4)
		swatch.set_meta("styles", [style, chosen])
		swatch.add_theme_stylebox_override("hover", chosen)
		swatch.add_theme_stylebox_override("focus", chosen)
		swatch.add_theme_stylebox_override("pressed", chosen)
		swatches.append(swatch)
		row.add_child(swatch)
	var refresh := func() -> void:
		for j in swatches.size():
			swatches[j].add_theme_stylebox_override("normal", swatches[j].get_meta("styles")[1 if j == GameSettings.player_color else 0])
	for i in swatches.size():
		swatches[i].pressed.connect(func() -> void:
			GameSettings.player_color = i
			refresh.call()
			changed.emit())
	refresh.call()
	_row(grid, "Car colour", row)
