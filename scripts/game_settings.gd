class_name GameSettings
extends RefCounted
## Player settings, saved to user://settings.cfg between runs: graphics,
## display, audio volumes, camera and the derby rules picked in the menu.

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["Low", "Medium", "High"]
const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]
## Bot skill range for each difficulty.
const DIFFICULTY_SKILL := [Vector2(0.35, 0.55), Vector2(0.55, 0.85), Vector2(0.85, 1.0)]
const ROUND_LENGTHS := [90.0, 150.0, 240.0]
const ROUND_LENGTH_NAMES := ["Short (1:30)", "Normal (2:30)", "Long (4:00)"]
const RENDER_SCALES := [0.5, 0.67, 0.77, 1.0]
const RENDER_SCALE_NAMES := ["Performance (50%)", "Balanced (67%)", "Quality (77%)", "Native (100%)"]

static var quality := 2
static var fullscreen := true
static var vsync := true
static var render_scale := 3
static var fov := 72.0
static var master_volume := 0.9
static var music_volume := 0.6
static var sfx_volume := 0.9
static var bot_count := 5
static var difficulty := 1
static var round_length := 1
static var player_name := "You"
static var player_color := 0
static var mouse_sensitivity := 1.0
static var invert_y := false
## Swing the camera back behind the car after free look.
static var auto_center := true
static var camera_view := 0


static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	quality = clampi(cfg.get_value("graphics", "quality", quality), 0, QUALITY_NAMES.size() - 1)
	fullscreen = cfg.get_value("graphics", "fullscreen", fullscreen)
	vsync = cfg.get_value("graphics", "vsync", vsync)
	render_scale = clampi(cfg.get_value("graphics", "render_scale", render_scale), 0, RENDER_SCALES.size() - 1)
	fov = clampf(cfg.get_value("graphics", "fov", fov), 55.0, 95.0)
	master_volume = clampf(cfg.get_value("audio", "master", master_volume), 0.0, 1.0)
	music_volume = clampf(cfg.get_value("audio", "music", music_volume), 0.0, 1.0)
	sfx_volume = clampf(cfg.get_value("audio", "sfx", sfx_volume), 0.0, 1.0)
	bot_count = clampi(cfg.get_value("derby", "bots", bot_count), 1, 9)
	difficulty = clampi(cfg.get_value("derby", "difficulty", difficulty), 0, DIFFICULTY_NAMES.size() - 1)
	round_length = clampi(cfg.get_value("derby", "round_length", round_length), 0, ROUND_LENGTHS.size() - 1)
	player_name = str(cfg.get_value("player", "name", player_name)).strip_edges().left(16)
	if player_name == "":
		player_name = "You"
	player_color = clampi(cfg.get_value("player", "color", player_color), 0, DerbyCar.BODY_COLORS.size() - 1)
	mouse_sensitivity = clampf(cfg.get_value("camera", "mouse_sensitivity", mouse_sensitivity), 0.2, 3.0)
	invert_y = cfg.get_value("camera", "invert_y", invert_y)
	auto_center = cfg.get_value("camera", "auto_center", auto_center)
	camera_view = clampi(cfg.get_value("camera", "view", camera_view), 0, ChaseCamera.VIEW_NAMES.size() - 1)


static func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("graphics", "fullscreen", fullscreen)
	cfg.set_value("graphics", "vsync", vsync)
	cfg.set_value("graphics", "render_scale", render_scale)
	cfg.set_value("graphics", "fov", fov)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("derby", "bots", bot_count)
	cfg.set_value("derby", "difficulty", difficulty)
	cfg.set_value("derby", "round_length", round_length)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "color", player_color)
	cfg.set_value("camera", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("camera", "invert_y", invert_y)
	cfg.set_value("camera", "auto_center", auto_center)
	cfg.set_value("camera", "view", camera_view)
	cfg.save(PATH)


## Applies window mode, vsync and render scale.
static func apply_display(viewport: Viewport) -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var scale: float = RENDER_SCALES[render_scale]
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = scale


## Sets bus volumes. Buses that don't exist are skipped.
static func apply_audio() -> void:
	for pair in [["Master", master_volume], ["Music", music_volume], ["SFX", sfx_volume]]:
		var bus := AudioServer.get_bus_index(pair[0])
		if bus >= 0:
			AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(pair[1], 0.0001)))
			AudioServer.set_bus_mute(bus, pair[1] <= 0.001)


static func round_seconds() -> float:
	return ROUND_LENGTHS[round_length]


static func random_bot_skill() -> float:
	var span: Vector2 = DIFFICULTY_SKILL[difficulty]
	return randf_range(span.x, span.y)
