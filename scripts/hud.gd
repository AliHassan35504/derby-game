class_name DerbyHud
extends CanvasLayer
## On-screen info: player health, cars left, countdown / round messages and a
## short feed of eliminations.

var _health_label: Label
var _health_bar: ProgressBar
var _alive_label: Label
var _center_label: Label
var _sub_label: Label
var _feed: VBoxContainer
var _hint: Label


func _ready() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var health_box := VBoxContainer.new()
	health_box.position = Vector2(24, 20)
	health_box.custom_minimum_size = Vector2(260, 0)
	root.add_child(health_box)
	_health_label = _make_label(22)
	health_box.add_child(_health_label)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(260, 18)
	_health_bar.show_percentage = false
	health_box.add_child(_health_bar)

	_alive_label = _make_label(26)
	_place(_alive_label, Vector2(1, 0), Rect2(-300, 20, 276, 0))
	_alive_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_alive_label)

	_feed = VBoxContainer.new()
	_place(_feed, Vector2(1, 0), Rect2(-400, 64, 376, 0))
	root.add_child(_feed)

	_center_label = _make_label(72)
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_center_label, Vector2(0.5, 0.5), Rect2(-500, -130, 1000, 0))
	root.add_child(_center_label)

	_sub_label = _make_label(24)
	_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_place(_sub_label, Vector2(0.5, 0.5), Rect2(-500, -20, 1000, 0))
	root.add_child(_sub_label)

	_hint = _make_label(16)
	_place(_hint, Vector2(0, 1), Rect2(24, -44, 900, 0))
	_hint.text = "W/S or ↑/↓ drive   A/D or ←/→ steer   Space handbrake   R restart"
	_hint.modulate = Color(1, 1, 1, 0.7)
	root.add_child(_hint)


func set_player(car: DerbyCar) -> void:
	_health_bar.max_value = car.max_health
	update_health(car)


func update_health(car: DerbyCar) -> void:
	if not car.alive:
		_health_label.text = "%s · OUT" % car.stats["label"]
	else:
		_health_label.text = "%s · HP %d" % [car.stats["label"], ceili(car.health)]
	_health_bar.value = car.health


func set_alive_count(alive: int, total: int) -> void:
	_alive_label.text = "Cars left: %d / %d" % [alive, total]


func show_message(text: String, sub := "") -> void:
	_center_label.text = text
	_sub_label.text = sub


func add_feed(text: String) -> void:
	var label := _make_label(18)
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed.add_child(label)
	while _feed.get_child_count() > 5:
		_feed.get_child(0).free()
	var tween := label.create_tween()
	tween.tween_interval(5.0)
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


func _make_label(font_size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(font_size / 6, 3))
	return label
