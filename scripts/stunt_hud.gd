class_name StuntHud
extends Control
## The HUD for pickups and stunt cash: animated "+$250 BIG HIT" popups, the
## pickup notice ("REPAIR"), the player's round cash under the health bars
## and the Ram timer. Sits on top of DerbyHud (game.gd adds it there).

const CASH_COLOR := Color(0.45, 1.0, 0.5)
const GOLD := Color(1.0, 0.8, 0.2)
const POPUP_SIZE := Vector2(560, 92)
const POPUP_STEP := 68.0
const MAX_POPUPS := 3

var car: DerbyCar

var _cash_label: Label
var _ram_label: Label
var _popups: Array[Control] = []
var _notice: Control
var _shown_cash := 0.0
var _cash := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cash_label = _label(28, GOLD)
	_cash_label.position = Vector2(24, 128)
	add_child(_cash_label)
	_ram_label = _label(18, RamBoost.COLOR.lerp(Color.WHITE, 0.2))
	_ram_label.position = Vector2(24, 166)
	add_child(_ram_label)
	clear()


## Follow a car (the player's) for the cash total and Ram timer.
func set_car(target: DerbyCar) -> void:
	car = target


func set_cash(amount: int) -> void:
	_cash = amount


func clear() -> void:
	_cash = 0
	_shown_cash = 0.0
	_cash_label.text = ""
	_ram_label.text = ""
	for p in _popups:
		p.queue_free()
	_popups.clear()
	if _notice:
		_notice.queue_free()
		_notice = null


## "+$250" with what it was for, popping in under the car and floating up.
func popup_cash(amount: int, what: String) -> void:
	var box := _popup_box(Vector2(0.5, 0.8))
	var money := _label(44 if amount >= 500 else 38, CASH_COLOR if amount < 1000 else GOLD)
	money.text = "+" + Career.money(amount)
	money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(money)
	var tag := _label(20, Color.WHITE)
	tag.text = what
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(tag)
	# Older popups move up out of the way.
	for p in _popups:
		var t := p.create_tween()
		t.set_ignore_time_scale(true)
		t.tween_property(p, "position:y", -POPUP_STEP, 0.15).as_relative()
	_popups.push_front(box)
	while _popups.size() > MAX_POPUPS:
		_popups.pop_back().queue_free()
	_animate(box, 1.4)
	Sfx.ui("cash", -4.0 if amount < 500 else -1.0, 1.0 if amount < 500 else 1.12)


## Big coloured word in the upper middle of the screen, e.g. "REPAIR".
func notice(text: String, hint: String, color: Color) -> void:
	if _notice:
		_notice.queue_free()
	var box := _popup_box(Vector2(0.5, 0.28))
	var word := _label(56, color.lerp(Color.WHITE, 0.15))
	word.text = text
	word.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(word)
	var sub := _label(20, Color.WHITE)
	sub.text = hint
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)
	_notice = box
	_animate(box, 1.3)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.01)
	if car == null or not is_instance_valid(car):
		_cash_label.text = ""
		_ram_label.text = ""
		return
	# Count the total up toward the real figure.
	_shown_cash = move_toward(_shown_cash, _cash, maxf(absf(_cash - _shown_cash) * 6.0, 200.0) * real)
	_cash_label.text = Career.money(roundi(_shown_cash)) if _cash > 0 or _shown_cash > 0.0 else "$0"
	var boost := RamBoost.active_on(car) if car.alive else null
	_ram_label.text = "RAM ×2  %.1fs" % boost.time_left if boost else ""


func _popup_box(anchor: Vector2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", -6)
	box.anchor_left = anchor.x
	box.anchor_right = anchor.x
	box.anchor_top = anchor.y
	box.anchor_bottom = anchor.y
	box.offset_left = -POPUP_SIZE.x * 0.5
	box.offset_right = POPUP_SIZE.x * 0.5
	box.offset_top = -POPUP_SIZE.y * 0.5
	box.offset_bottom = POPUP_SIZE.y * 0.5
	box.pivot_offset = POPUP_SIZE * 0.5
	add_child(box)
	return box


## Pop in (overshoot), hold, then float up and fade out.
func _animate(box: Control, hold: float) -> void:
	box.scale = Vector2.ONE * 0.3
	box.modulate.a = 0.0
	var t := box.create_tween()
	t.set_ignore_time_scale(true)
	t.tween_property(box, "scale", Vector2.ONE * 1.18, 0.12).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(box, "modulate:a", 1.0, 0.1)
	t.tween_property(box, "scale", Vector2.ONE, 0.12).set_ease(Tween.EASE_IN_OUT)
	t.tween_interval(hold)
	t.tween_property(box, "modulate:a", 0.0, 0.45)
	t.parallel().tween_property(box, "scale", Vector2.ONE * 0.9, 0.45)
	t.tween_callback(func() -> void:
		_popups.erase(box)
		if _notice == box:
			_notice = null
		box.queue_free())


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", maxi(font_size / 5, 4))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
