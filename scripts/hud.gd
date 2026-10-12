class_name DerbyHud
extends CanvasLayer
## On-screen info: player health, nitro and hop, round timer, cars alive,
## kill feed, the Next Derby screen, spectator hint and round results.

const ACCENT := Color(1.0, 0.72, 0.15)

var _status_box: VBoxContainer
var _car_label: Label
var _health_bar: ProgressBar
var _nitro_bar: ProgressBar
var _hop_label: Label
var _map_label: Label
var _timer_label: Label
var _alive_label: Label
var _center_label: Label
var _sub_label: Label
var _feed: VBoxContainer
var _spectate_label: Label
var _quality_label: Label
var _intro: PanelContainer
var _intro_stage: Label
var _intro_map: Label
var _intro_car: Label
var _intro_rule: Label
var _intro_count: Label
var _results: PanelContainer
var _results_title: Label
var _results_grid: GridContainer
var _standings_box: VBoxContainer
var _standings_grid: GridContainer
var _results_footer: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_status_box = VBoxContainer.new()
	_place(_status_box, Vector2(0, 0), Rect2(24, 20, 280, 0))
	root.add_child(_status_box)
	_car_label = _make_label(20)
	_status_box.add_child(_car_label)
	_health_bar = _make_bar(Color(0.3, 0.85, 0.35))
	_status_box.add_child(_health_bar)
	var nitro_row := HBoxContainer.new()
	var nitro_tag := _make_label(14)
	nitro_tag.text = "NITRO"
	nitro_row.add_child(nitro_tag)
	_nitro_bar = _make_bar(Color(0.3, 0.6, 1.0))
	_nitro_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_nitro_bar.custom_minimum_size.y = 10
	nitro_row.add_child(_nitro_bar)
	_status_box.add_child(nitro_row)
	_hop_label = _make_label(14)
	_status_box.add_child(_hop_label)

	_map_label = _make_label(18)
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_map_label, Vector2(0.5, 0), Rect2(-200, 14, 400, 0))
	root.add_child(_map_label)
	_timer_label = _make_label(40)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_timer_label, Vector2(0.5, 0), Rect2(-200, 38, 400, 0))
	root.add_child(_timer_label)

	_alive_label = _make_label(26)
	_alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_place(_alive_label, Vector2(1, 0), Rect2(-300, 20, 276, 0))
	root.add_child(_alive_label)
	_feed = VBoxContainer.new()
	_place(_feed, Vector2(1, 0), Rect2(-460, 62, 436, 0))
	root.add_child(_feed)

	_center_label = _make_label(72)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_center_label, Vector2(0.5, 0.5), Rect2(-600, -150, 1200, 0))
	root.add_child(_center_label)
	_sub_label = _make_label(24)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_sub_label, Vector2(0.5, 0.5), Rect2(-600, -40, 1200, 0))
	root.add_child(_sub_label)

	_spectate_label = _make_label(20)
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_spectate_label, Vector2(0.5, 1), Rect2(-400, -90, 800, 0))
	root.add_child(_spectate_label)

	var hint := _make_label(14)
	hint.text = "W/S drive · A/D steer · Shift nitro · E hop · Q brace · Space handbrake · Esc pause"
	hint.modulate = Color(1, 1, 1, 0.7)
	_place(hint, Vector2(0, 1), Rect2(24, -40, 1000, 0))
	root.add_child(hint)
	_quality_label = _make_label(14)
	_quality_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_quality_label.modulate = Color(1, 1, 1, 0.7)
	_place(_quality_label, Vector2(1, 1), Rect2(-324, -40, 300, 0))
	root.add_child(_quality_label)

	_build_intro(root)
	_build_results(root)


func _build_intro(root: Control) -> void:
	_intro = _make_panel()
	_place(_intro, Vector2(0.5, 0.5), Rect2(-330, -170, 660, 0))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_intro.add_child(box)
	var title := _make_label(26)
	title.text = "NEXT DERBY"
	title.add_theme_color_override("font_color", ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_intro_stage = _make_label(18)
	_intro_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_stage.modulate = Color(1, 1, 1, 0.75)
	box.add_child(_intro_stage)
	_intro_map = _make_label(64)
	_intro_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_intro_map)
	_intro_car = _make_label(26)
	_intro_car.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_intro_car)
	_intro_rule = _make_label(20)
	_intro_rule.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_rule.modulate = Color(1, 1, 1, 0.85)
	box.add_child(_intro_rule)
	_intro_count = _make_label(20)
	_intro_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_count.add_theme_color_override("font_color", ACCENT)
	box.add_child(_intro_count)
	_intro.visible = false
	root.add_child(_intro)


func _build_results(root: Control) -> void:
	_results = _make_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_results.add_child(box)
	_results_title = _make_label(36)
	_results_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_title.add_theme_color_override("font_color", ACCENT)
	box.add_child(_results_title)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 56)
	box.add_child(columns)
	_results_grid = GridContainer.new()
	_results_grid.columns = 5
	_results_grid.add_theme_constant_override("h_separation", 30)
	_results_grid.add_theme_constant_override("v_separation", 4)
	columns.add_child(_results_grid)
	_standings_box = VBoxContainer.new()
	var standings_title := _make_label(16)
	standings_title.text = "CHAMPIONSHIP"
	standings_title.add_theme_color_override("font_color", ACCENT)
	_standings_box.add_child(standings_title)
	_standings_grid = GridContainer.new()
	_standings_grid.columns = 3
	_standings_grid.add_theme_constant_override("h_separation", 24)
	_standings_grid.add_theme_constant_override("v_separation", 4)
	_standings_box.add_child(_standings_grid)
	columns.add_child(_standings_box)
	_results_footer = _make_label(16)
	_results_footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_results_footer.modulate = Color(1, 1, 1, 0.7)
	box.add_child(_results_footer)
	_results.visible = false
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_results)
	root.add_child(holder)


func show_intro(map_name: String, car_label: String, rule: String, stage := "") -> void:
	_results.visible = false
	_intro.visible = true
	_intro_stage.text = stage
	_intro_stage.visible = stage != ""
	_intro_map.text = map_name
	_intro_car.text = "Everyone drives: %s" % car_label
	_intro_rule.text = rule
	_status_box.visible = false


func set_intro_countdown(seconds: float) -> void:
	_intro_count.text = "Starting in %d" % ceili(seconds)


func hide_intro() -> void:
	_intro.visible = false
	_status_box.visible = true


## rows: Array of [place, name, survived seconds, knock-offs, is_player,
## points gained]. standings: Array of [place, name, points, is_player], or
## empty outside a championship.
func show_results(title: String, rows: Array, standings := [], footer := "") -> void:
	_results.visible = true
	_results_title.text = title
	_results_footer.text = footer
	_results_grid.visible = true
	_clear(_results_grid)
	var with_points := not standings.is_empty()
	_results_grid.columns = 5 if with_points else 4
	var headers := ["#", "Driver", "Survived", "Knock-offs"]
	if with_points:
		headers.append("Pts")
	for header in headers:
		_add_cell(_results_grid, header, 16, false, true)
	for row in rows:
		var cells := [str(row[0]), row[1], "%d:%04.1f" % [int(row[2]) / 60, fmod(row[2], 60.0)], str(row[3])]
		if with_points:
			cells.append("+%d" % row[5])
		for cell in cells:
			_add_cell(_results_grid, cell, 20, row[4])
	_fill_standings(standings)


## End of a championship: just the final table.
func show_final(title: String, standings: Array, footer: String) -> void:
	_results.visible = true
	_results_title.text = title
	_results_footer.text = footer
	_results_grid.visible = false
	_fill_standings(standings)


func _fill_standings(standings: Array) -> void:
	_standings_box.visible = not standings.is_empty()
	_clear(_standings_grid)
	for header in ["#", "Driver", "Points"]:
		_add_cell(_standings_grid, header, 16, false, true)
	for row in standings:
		for cell in [str(row[0]), row[1], str(row[2])]:
			_add_cell(_standings_grid, cell, 20, row[3])


func _add_cell(grid: GridContainer, text: String, font_size: int, highlight: bool, header := false) -> void:
	var label := _make_label(font_size)
	label.text = text
	if header:
		label.modulate = Color(1, 1, 1, 0.6)
	if highlight:
		label.add_theme_color_override("font_color", ACCENT)
	grid.add_child(label)


func _clear(node: Node) -> void:
	for child in node.get_children():
		child.free()


func hide_results() -> void:
	_results.visible = false


func set_map(map_name: String) -> void:
	_map_label.text = map_name.to_upper()


func set_timer(seconds: float, warning: bool) -> void:
	var s := maxi(ceili(seconds), 0)
	_timer_label.text = "%d:%02d" % [s / 60, s % 60]
	_timer_label.add_theme_color_override("font_color", Color(1, 0.35, 0.25) if warning else Color.WHITE)


func set_quality(text: String) -> void:
	_quality_label.text = "Graphics: %s (F3)" % text


func update_player(car: DerbyCar) -> void:
	_car_label.text = "%s · %s" % [car.stats["label"], "OUT" if not car.alive else "HP %d" % ceili(car.health)]
	_health_bar.max_value = car.max_health
	_health_bar.value = car.health
	_nitro_bar.value = car.nitro * 100.0
	if not car.alive:
		_hop_label.text = ""
	elif car.hop_cooldown > 0.0:
		_hop_label.text = "HOP in %.1fs" % car.hop_cooldown
	else:
		_hop_label.text = "HOP ready (E)"


func set_alive_count(alive: int, total: int) -> void:
	_alive_label.text = "Alive: %d / %d" % [alive, total]


func set_spectating(name: String) -> void:
	_spectate_label.text = "" if name == "" else "Spectating %s · ←/→ to switch" % name


func show_message(text: String, sub := "") -> void:
	_center_label.text = text
	_sub_label.text = sub


func add_feed(text: String, highlight := false) -> void:
	var label := _make_label(18)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if highlight:
		label.add_theme_color_override("font_color", ACCENT)
	_feed.add_child(label)
	while _feed.get_child_count() > 6:
		_feed.get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(6.0)
	tween.tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)


func clear_feed() -> void:
	for child in _feed.get_children():
		child.queue_free()


## Pins a control to an anchor point on screen, with rect giving its offset
## and width from that point.
func _place(control: Control, anchor: Vector2, rect: Rect2) -> void:
	control.anchor_left = anchor.x
	control.anchor_right = anchor.x
	control.anchor_top = anchor.y
	control.anchor_bottom = anchor.y
	control.offset_left = rect.position.x
	control.offset_right = rect.position.x + rect.size.x
	control.offset_top = rect.position.y
	control.offset_bottom = rect.position.y + rect.size.y


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.82)
	style.border_color = Color(ACCENT, 0.8)
	style.border_width_top = 3
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _make_bar(color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(280, 16)
	bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	bar.add_theme_stylebox_override("fill", fill)
	bar.add_theme_stylebox_override("background", bg)
	return bar


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(font_size / 6, 3))
	return label
