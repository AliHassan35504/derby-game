class_name Sfx
extends Node
## Music and non-positional sound: UI clicks, the countdown, stings, plus
## fire-and-forget sounds at a point in the world (explosions, splashes).
## Everything is called statically, e.g. Sfx.ui("click") or
## Sfx.play_music("round"). The first call adds one Sfx node under the
## scene tree's root that owns the players; calls made before it is in the
## tree are queued.
##
## Buses (default_bus_layout.tres): "Music" and "SFX" both feed "Master".
## A settings menu sets volumes with Sfx.set_volume("Music", 0.0..1.0).

const MUSIC := {
	"menu": "res://assets/audio/music/menu.ogg",
	"round": "res://assets/audio/music/round.ogg",
}
const UI := {
	"click": "res://assets/audio/ui/click.ogg",
	"hover": "res://assets/audio/ui/hover.ogg",
	"beep": "res://assets/audio/ui/beep.ogg",
	"go": "res://assets/audio/ui/go.ogg",
	"win": "res://assets/audio/ui/sting_win.ogg",
	"lose": "res://assets/audio/ui/sting_lose.ogg",
	"elimination": "res://assets/audio/ui/sting_elimination.ogg",
	"player_out": "res://assets/audio/ui/sting_player_out.ogg",
	"cash": "res://assets/audio/ui/cash.ogg",
}
const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
## Music level under the effects (the Music bus volume goes on top).
const MUSIC_DB := -7.0
const CROSSFADE := 1.6
## Most world one-shots playing at once; the oldest is cut for a new one.
const MAX_WORLD_VOICES := 10
const UI_VOICES := 4

static var _instance: Sfx
static var _countdown_shown := 0

var _music: Array[AudioStreamPlayer] = []
var _music_target: Array[float] = [0.0, 0.0]
var _music_name := ""
var _current := 0
var _ui: Array[AudioStreamPlayer] = []
var _ui_next := 0
var _world: Array[AudioStreamPlayer3D] = []
var _queued: Array[Callable] = []
var _back_to_menu_at := -1.0
var _clock := 0.0


## Crossfades to a music track ("menu" or "round"); "" fades the music out.
static func play_music(track: String) -> void:
	var sfx := _node()
	if sfx:
		sfx._run(sfx._play_music.bind(track))


## Plays a UI or announcer sound from UI (non-positional).
static func ui(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var sfx := _node()
	if sfx and UI.has(sound):
		sfx._run(sfx._play_ui.bind(load(UI[sound]), volume_db, pitch))


## Plays a sound once at a world position. Lives on after whatever made it.
static func play_at(stream: AudioStream, at: Vector3, volume_db := 0.0, unit_size := 12.0, pitch := 1.0) -> void:
	var sfx := _node()
	if sfx and stream:
		sfx._run(sfx._play_world.bind(stream, at, volume_db, unit_size, pitch))


## Call every frame of the pre-round countdown with the seconds left: beeps
## on 3, 2 and 1, then sounds the GO horn and starts the round music.
static func countdown(seconds_left: float) -> void:
	var shown := ceili(seconds_left) if seconds_left > 0.0 else 0
	if shown == _countdown_shown:
		return
	_countdown_shown = shown
	if shown > 0:
		ui("beep", 0.0, 1.0 if shown > 1 else 1.12)
	else:
		ui("go")
		play_music("round")


## A car was knocked out.
static func elimination(is_player: bool) -> void:
	ui("player_out" if is_player else "elimination", 0.0 if is_player else -4.0)


## The round ended: a win or lose sting, then back to the menu music.
static func round_over(player_won: bool) -> void:
	ui("win" if player_won else "lose")
	var sfx := _node()
	if sfx:
		sfx._run(sfx._duck_then_menu)


## Gives a button hover and click sounds.
static func hook_button(button: BaseButton) -> void:
	button.mouse_entered.connect(func() -> void: ui("hover"))
	button.focus_entered.connect(func() -> void: ui("hover"))
	button.pressed.connect(func() -> void: ui("click"))


## Sets a bus volume from a 0..1 slider value ("Master", "Music" or "SFX").
static func set_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


static func get_volume(bus: String) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0 or AudioServer.is_bus_mute(idx):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(idx))


## The bus a sound should go to, falling back to Master if the layout is
## missing.
static func bus(name: StringName) -> StringName:
	return name if AudioServer.get_bus_index(name) >= 0 else &"Master"


static func _node() -> Sfx:
	if is_instance_valid(_instance):
		return _instance
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	_instance = Sfx.new()
	_instance.name = "Sfx"
	_instance.process_mode = Node.PROCESS_MODE_ALWAYS
	# The root may be busy adding the main scene right now.
	tree.root.add_child.call_deferred(_instance)
	return _instance


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = bus(MUSIC_BUS)
		player.volume_db = -80.0
		add_child(player)
		_music.append(player)
	for i in UI_VOICES:
		var player := AudioStreamPlayer.new()
		player.bus = bus(SFX_BUS)
		add_child(player)
		_ui.append(player)
	for call in _queued:
		call.call()
	_queued.clear()


func _exit_tree() -> void:
	if _instance == self:
		_instance = null
	# The game is quitting. Stop every player and give the audio thread a
	# moment to let go of the playbacks, or they are reported as leaked.
	var tree := get_tree()
	if tree and tree.root:
		for node in tree.root.find_children("*", "AudioStreamPlayer", true, false):
			(node as AudioStreamPlayer).stop()
		for node in tree.root.find_children("*", "AudioStreamPlayer3D", true, false):
			(node as AudioStreamPlayer3D).stop()
	OS.delay_msec(120)


func _run(call: Callable) -> void:
	if is_inside_tree() and is_node_ready():
		call.call()
	else:
		_queued.append(call)


func _process(delta: float) -> void:
	# Fade in real time, unaffected by slow motion.
	var real := delta / maxf(Engine.time_scale, 0.01)
	_clock += real
	if _back_to_menu_at > 0.0 and _clock >= _back_to_menu_at:
		_back_to_menu_at = -1.0
		_play_music("menu")
	for i in _music.size():
		var player := _music[i]
		var target := _music_target[i]
		var lin := move_toward(db_to_linear(player.volume_db), target, real / CROSSFADE)
		player.volume_db = linear_to_db(maxf(lin, 0.00001))
		if lin <= 0.0001 and target == 0.0 and player.playing:
			player.stop()


func _play_music(track: String) -> void:
	_back_to_menu_at = -1.0
	if not MUSIC.has(track):
		_music_name = ""
		_music_target = [0.0, 0.0]
		return
	if track == _music_name:
		_music_target[_current] = db_to_linear(MUSIC_DB)
		return
	_music_name = track
	_music_target[_current] = 0.0
	_current = 1 - _current
	var player := _music[_current]
	player.stream = load(MUSIC[track])
	player.volume_db = -60.0
	player.play()
	_music_target[_current] = db_to_linear(MUSIC_DB)


func _duck_then_menu() -> void:
	# Let the sting play over quieter music, then go back to the menu track.
	_music_target[_current] = db_to_linear(MUSIC_DB - 10.0)
	_back_to_menu_at = _clock + 3.5


func _play_ui(stream: AudioStream, volume_db: float, pitch: float) -> void:
	var player := _ui[_ui_next]
	_ui_next = (_ui_next + 1) % _ui.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _play_world(stream: AudioStream, at: Vector3, volume_db: float, unit_size: float, pitch: float) -> void:
	if _world.size() >= MAX_WORLD_VOICES:
		var oldest: AudioStreamPlayer3D = _world.pop_front()
		oldest.queue_free()
	var voice := AudioStreamPlayer3D.new()
	voice.stream = stream
	voice.bus = bus(SFX_BUS)
	voice.volume_db = volume_db
	voice.unit_size = unit_size
	voice.max_distance = 400.0
	voice.pitch_scale = pitch
	voice.finished.connect(voice.queue_free)
	voice.tree_exiting.connect(func() -> void: _world.erase(voice))
	add_child(voice)
	voice.global_position = at
	voice.play()
	_world.append(voice)
