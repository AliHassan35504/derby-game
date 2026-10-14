class_name PauseMenu
extends CanvasLayer
## Esc during a round: resume, restart, settings or back to the title.
## Pauses the scene tree while open.

signal restart_requested
signal menu_requested
signal settings_changed

var _buttons: Control
var _settings: SettingsPanel
var _first: Button


func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UiKit.theme()
	add_child(root)
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0, 0, 0, 0.5)
	root.add_child(shade)

	var panel := UiKit.panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := UiKit.label("PAUSED", 40, UiKit.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_first = UiKit.button("Resume", close)
	box.add_child(_first)
	box.add_child(UiKit.button("Restart round", func() -> void:
		close()
		restart_requested.emit()))
	box.add_child(UiKit.button("Settings", func() -> void:
		_buttons.visible = false
		_settings.open()))
	box.add_child(UiKit.button("Quit to title", func() -> void:
		close()
		menu_requested.emit()))
	box.add_child(UiKit.button("Quit to desktop", func() -> void: get_tree().quit()))
	_buttons = UiKit.centered(panel)
	root.add_child(_buttons)

	_settings = SettingsPanel.new()
	_settings.changed.connect(func() -> void: settings_changed.emit())
	_settings.closed.connect(func() -> void:
		_buttons.visible = true
		_first.grab_focus())
	var holder := UiKit.centered(_settings)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(holder)
	_settings.visible = false
	visible = false


func open() -> void:
	visible = true
	_buttons.visible = true
	_settings.visible = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_first.grab_focus()


func close() -> void:
	visible = false
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	if visible and not _settings.visible and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		close()
