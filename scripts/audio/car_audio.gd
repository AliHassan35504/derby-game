class_name CarAudio
extends Node3D
## All the sound one DerbyCar makes. DerbyCar adds one of these in _ready.
##
## Engine: three loops recorded at known RPMs (low, mid, high) are
## crossfaded and pitched to a simulated RPM that comes from road speed
## through an automatic gearbox, revs up with wheelspin and in the air, and
## bounces off the limiter. Also tyre skid, nitro, scraping against other
## cars, impacts from the car's hit signal, landings, hop, horn, fire,
## explosion, splash and falling wind.
##
## The car the camera follows is louder and gets the wind rush. Loops that
## are silent are stopped, so a car normally uses two or three voices.

const ENGINE_DIR := "res://assets/audio/engine/"
const SFX_DIR := "res://assets/audio/sfx/"
const LEVELS := ["low", "mid", "high"]

## Per engine: the exact RPM of the low, mid and high loops (see
## tools/audio/make_sounds.py), idle and redline, and gear count.
const ENGINES := {
	"v8": {"rpms": [1080.0, 3000.0, 5568.0], "idle": 820.0, "redline": 6000.0, "gears": 4},
	"monster": {"rpms": [900.0, 2625.0, 4800.0], "idle": 720.0, "redline": 5000.0, "gears": 3},
	"six": {"rpms": [1500.0, 4575.0, 8160.0], "idle": 950.0, "redline": 8500.0, "gears": 5},
	"four": {"rpms": [1500.0, 4425.0, 7584.0], "idle": 950.0, "redline": 7600.0, "gears": 5},
}
## Car style -> [engine, pitch scale, volume offset in dB].
const STYLE_ENGINE := {
	"van": ["v8", 0.92, 0.0], "muscle": ["v8", 1.0, 1.5], "pickup": ["v8", 0.86, 0.5],
	"monster": ["monster", 1.0, 2.0], "sports": ["six", 1.0, 0.0], "sedan": ["six", 0.84, -2.0],
	"rally": ["four", 1.0, 0.0],
}

## The followed car sounds this much louder, and carries further.
const FOCUS_DB := 3.0
const FOCUS_UNIT_SIZE := 11.0
const UNIT_SIZE := 6.0
const MAX_DISTANCE := 160.0
## Shortest gap between two impact sounds from one car.
const IMPACT_GAP := 0.09

var car: DerbyCar

var _engine: Dictionary
var _pitch_scale := 1.0
var _engine_db := 0.0
var _engine_players: Array[AudioStreamPlayer3D] = []
var _skid: AudioStreamPlayer3D
var _scrape: AudioStreamPlayer3D
var _nitro: AudioStreamPlayer3D
var _fire: AudioStreamPlayer3D
var _wind: AudioStreamPlayer
var _shots: Array[AudioStreamPlayer3D] = []
var _shot_next := 0

var _rpm := 800.0
var _gear := 0
var _load := 0.0
var _limiter := 0.0
var _skid_level := 0.0
var _scrape_level := 0.0
var _nitro_level := 0.0
var _wind_level := 0.0
var _was_nitro := false
var _prev_velocity := Vector3.ZERO
var _prev_hop_cooldown := 0.0
var _air_time := 0.0
var _air_fall_speed := 0.0
var _fall_whooshed := false
var _last_impact := -10.0
var _clock := 0.0
var _glass_left := 2
var _exploded := false
var _focus := false
var _player_controlled := false
var _focus_check := 0.0


func _init() -> void:
	name = "CarAudio"


func _ready() -> void:
	car = get_parent() as DerbyCar
	if car == null:
		set_physics_process(false)
		return
	var style: Array = STYLE_ENGINE.get(car.stats.get("style", "van"), STYLE_ENGINE["van"])
	_engine = ENGINES[style[0]]
	_pitch_scale = style[1]
	_engine_db = style[2]
	_rpm = _engine["idle"]
	for level in LEVELS:
		_engine_players.append(_make_player(load(ENGINE_DIR + "%s_%s.wav" % [style[0], level]), UNIT_SIZE))
	_skid = _make_player(load(SFX_DIR + "skid_loop.wav"), 5.0)
	_scrape = _make_player(load(SFX_DIR + "scrape_loop.wav"), 6.0)
	_nitro = _make_player(load(SFX_DIR + "nitro_loop.wav"), 5.0)
	_fire = _make_player(load(SFX_DIR + "fire_loop.wav"), 5.0)
	_fire.position = Vector3(0, 0.5, car.stats["size"].z * 0.3)
	for i in 3:
		_shots.append(_make_player(null, 9.0))
	_wind = AudioStreamPlayer.new()
	_wind.stream = load(SFX_DIR + "wind_loop.wav")
	_wind.bus = Sfx.bus(Sfx.SFX_BUS)
	add_child(_wind)
	car.hit.connect(_on_hit)
	car.eliminated.connect(_on_eliminated)
	_prev_velocity = car.linear_velocity


## Sounds the horn.
func honk() -> void:
	_shot(load(SFX_DIR + "horn.ogg"), -3.0, randf_range(0.98, 1.02))


func _make_player(stream: AudioStream, unit_size: float) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = Sfx.bus(Sfx.SFX_BUS)
	player.unit_size = unit_size
	player.max_distance = MAX_DISTANCE
	player.volume_db = -80.0
	add_child(player)
	return player


func _physics_process(delta: float) -> void:
	_clock += delta
	_focus_check -= delta
	if _focus_check <= 0.0:
		_focus_check = 0.25
		_update_focus()
	var on_ground := car.is_on_ground()
	var velocity := car.linear_velocity
	var speed := absf(car.get_forward_speed())
	var throttle := absf(car.throttle_input) if car.controls_enabled else 0.0
	var slip := _wheel_slip()

	_update_engine(delta, speed, throttle, slip, on_ground)
	_update_skid(delta, velocity, speed, slip, on_ground)
	_update_scrape(delta)
	_update_nitro(delta)
	_update_air(delta, velocity, on_ground)
	_update_wind(delta, velocity)
	_update_fire()
	_check_bumps(velocity)

	if car.hop_cooldown > _prev_hop_cooldown + 0.5:
		_shot(load(SFX_DIR + "hop.ogg"), 0.0, randf_range(0.95, 1.05))
	_prev_hop_cooldown = car.hop_cooldown
	if _player_controlled and car.alive and InputMap.has_action("horn") and Input.is_action_just_pressed("horn"):
		honk()
	_prev_velocity = velocity


func _update_focus() -> void:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var focus := camera is ChaseCamera and (camera as ChaseCamera).target == car
	_player_controlled = false
	for child in car.get_children():
		if child is PlayerController:
			_player_controlled = true
	if focus == _focus:
		return
	_focus = focus
	var unit := FOCUS_UNIT_SIZE if focus else UNIT_SIZE
	for player in _engine_players:
		player.unit_size = unit
	if not focus:
		_wind.stop()


## 0 when every wheel on the road grips, 1 when they all slide.
func _wheel_slip() -> float:
	var total := 0.0
	var count := 0
	for child in car.get_children():
		var wheel := child as VehicleWheel3D
		if wheel and wheel.is_in_contact():
			total += 1.0 - clampf(wheel.get_skidinfo(), 0.0, 1.0)
			count += 1
	return total / count if count > 0 else 0.0


func _gear_top(gear: int, top: float) -> float:
	var gears: int = _engine["gears"]
	return top * pow(float(gear + 1) / gears, 0.8)


func _update_engine(delta: float, speed: float, throttle: float, slip: float, on_ground: bool) -> void:
	var idle: float = _engine["idle"]
	var redline: float = _engine["redline"]
	var gears: int = _engine["gears"]
	var top: float = car.stats["top_speed"] * (1.35 if car.is_nitro_active() else 1.1)
	var target := 0.0
	if car.alive:
		if _gear < gears - 1 and speed > _gear_top(_gear, top) * 0.94:
			_gear += 1
		elif _gear > 0 and speed < _gear_top(_gear - 1, top) * 0.62:
			_gear -= 1
		target = lerpf(idle, redline, clampf(speed / _gear_top(_gear, top), 0.0, 1.0))
		# Slipping the clutch at a crawl.
		target = maxf(target, idle + throttle * (redline - idle) * 0.3)
		# Wheels spinning or in the air: the revs run away.
		var free_rev := 1.0 if not on_ground else clampf(slip * 1.5, 0.0, 1.0)
		target = lerpf(target, maxf(target, idle + throttle * (redline - idle) * 0.95), free_rev)
	var rate := 7000.0 if target > _rpm else 4000.0
	if not car.alive:
		rate = 1500.0
	_rpm = move_toward(_rpm, target, rate * delta)
	# Bounce off the rev limiter.
	_limiter = maxf(_limiter - delta, 0.0)
	if car.alive and throttle > 0.5 and _rpm > redline * 0.985 and _limiter <= 0.0:
		_rpm -= redline * 0.07
		_limiter = 0.07
	_load = move_toward(_load, throttle if car.alive else 0.0, delta * 6.0)

	var rpms: Array = _engine["rpms"]
	var weights := [0.0, 0.0, 0.0]
	var r := maxf(_rpm, 1.0)
	if r <= rpms[0]:
		weights[0] = 1.0
	elif r >= rpms[2]:
		weights[2] = 1.0
	else:
		var i := 0 if r < rpms[1] else 1
		var f := (log(r) - log(rpms[i])) / (log(rpms[i + 1]) - log(rpms[i]))
		weights[i] = cos(f * PI * 0.5)
		weights[i + 1] = sin(f * PI * 0.5)
	var rev := clampf((_rpm - idle) / (redline - idle), 0.0, 1.0)
	# Louder under load and with revs; dead engines fade out as they spin down.
	var base_db := _engine_db - 6.0 + 4.0 * _load + 3.0 * rev + (FOCUS_DB if _focus else 0.0)
	var alive_gain := 1.0 if car.alive else clampf(_rpm / idle, 0.0, 1.0)
	for k in 3:
		var player := _engine_players[k]
		var gain: float = weights[k] * alive_gain
		if gain < 0.01:
			if player.playing:
				player.stop()
			continue
		player.volume_db = base_db + linear_to_db(gain)
		player.pitch_scale = clampf(_rpm / rpms[k] * _pitch_scale, 0.3, 3.5)
		if not player.playing:
			player.play(randf() * player.stream.get_length())


func _update_skid(delta: float, velocity: Vector3, speed: float, slip: float, on_ground: bool) -> void:
	var lateral := absf(velocity.dot(car.global_basis.x))
	var target := 0.0
	if on_ground and car.alive:
		target = maxf(clampf((lateral - 2.5) / 6.0, 0.0, 1.0), clampf((slip - 0.25) / 0.5, 0.0, 1.0) * clampf(maxf(speed, lateral) / 6.0, 0.0, 1.0))
		if car.handbrake_input and speed > 3.0:
			target = maxf(target, 0.6)
	_skid_level = move_toward(_skid_level, target, delta * (8.0 if target > _skid_level else 4.0))
	_loop_level(_skid, _skid_level, -4.0, 0.9 + 0.15 * _skid_level + speed * 0.004)


func _update_scrape(delta: float) -> void:
	var target := 0.0
	if car.alive:
		for body in car.get_colliding_bodies():
			var other := body as DerbyCar
			if other == null or other == car:
				continue
			# Only one car of a touching pair plays the grind.
			if other.alive and car.get_instance_id() > other.get_instance_id():
				continue
			var rel := (car.linear_velocity - other.linear_velocity).length()
			target = maxf(target, clampf((rel - 1.0) / 7.0, 0.0, 1.0))
	_scrape_level = move_toward(_scrape_level, target, delta * (10.0 if target > _scrape_level else 3.0))
	_loop_level(_scrape, _scrape_level, -2.0, 0.85 + 0.3 * _scrape_level)


func _update_nitro(delta: float) -> void:
	var active := car.is_nitro_active()
	if active and not _was_nitro:
		_shot(load(SFX_DIR + "nitro_burst.ogg"), -1.0, randf_range(0.95, 1.05))
	_was_nitro = active
	_nitro_level = move_toward(_nitro_level, 1.0 if active else 0.0, delta * (3.0 if active else 4.0))
	_loop_level(_nitro, _nitro_level, -5.0, 1.0)


func _update_air(delta: float, velocity: Vector3, on_ground: bool) -> void:
	if on_ground:
		if _air_time > 0.35 and _air_fall_speed > 3.0 and car.alive:
			var stream: AudioStream = load(SFX_DIR + "land_%d.ogg" % (randi() % 2 + 1))
			_shot(stream, clampf(-14.0 + _air_fall_speed * 1.2, -14.0, 2.0), randf_range(0.9, 1.05))
			_last_impact = _clock
		_air_time = 0.0
		_air_fall_speed = 0.0
		_fall_whooshed = false
		return
	_air_time += delta
	_air_fall_speed = maxf(_air_fall_speed, -velocity.y)
	# Dropping off the map (or a long way): the long whoosh.
	if not _fall_whooshed and _air_time > 0.4 and velocity.y < -8.0:
		_fall_whooshed = true
		_shot(load(SFX_DIR + "fall_whoosh.ogg"), 0.0 if _focus else -4.0, randf_range(0.95, 1.05))


func _update_wind(delta: float, velocity: Vector3) -> void:
	if not _focus:
		return
	var target := clampf((velocity.length() - 8.0) / 25.0, 0.0, 1.0)
	_wind_level = move_toward(_wind_level, target, delta * 1.5)
	if _wind_level < 0.01:
		if _wind.playing:
			_wind.stop()
		return
	_wind.volume_db = -6.0 + linear_to_db(_wind_level)
	_wind.pitch_scale = 0.85 + 0.35 * _wind_level
	if not _wind.playing:
		_wind.play(randf() * _wind.stream.get_length())


func _update_fire() -> void:
	var level := 0.0
	if _exploded:
		level = 1.0
	elif car.alive and car.health < car.max_health * 0.2:
		level = 0.35
	_loop_level(_fire, level, -2.0, 1.0)


## Sets a loop's volume from a 0..1 level, starting or stopping it.
func _loop_level(player: AudioStreamPlayer3D, level: float, max_db: float, pitch: float) -> void:
	if level < 0.01:
		if player.playing:
			player.stop()
		return
	player.volume_db = max_db + linear_to_db(level) + (FOCUS_DB * 0.5 if _focus else 0.0)
	player.pitch_scale = clampf(pitch, 0.3, 3.0)
	if not player.playing:
		player.play(randf() * player.stream.get_length())


func _shot(stream: AudioStream, volume_db: float, pitch := 1.0) -> void:
	var player := _shots[_shot_next]
	_shot_next = (_shot_next + 1) % _shots.size()
	player.stream = stream
	player.volume_db = volume_db + (FOCUS_DB if _focus else 0.0)
	player.pitch_scale = pitch
	player.play()


## Knocks that did no damage (car.hit only fires for damage) and the body
## slamming onto the road.
func _check_bumps(velocity: Vector3) -> void:
	if not car.alive or _clock - _last_impact < IMPACT_GAP * 2.0:
		return
	var dv := (velocity - _prev_velocity).length()
	if dv < 1.3:
		return
	var touching_car := false
	for body in car.get_colliding_bodies():
		if body is DerbyCar:
			touching_car = true
	if touching_car and dv < DerbyCar.DAMAGE_THRESHOLD + 0.5:
		_last_impact = _clock
		_shot(_pick("bump", 3), -12.0 + dv * 3.0, randf_range(0.9, 1.1))
	elif not touching_car and dv > 5.0 and car.get_colliding_bodies().size() > 0 and _air_time == 0.0:
		_last_impact = _clock
		_shot(_pick("bump", 3), -8.0 + dv, randf_range(0.8, 0.95))


func _on_hit(_car: DerbyCar, amount: float) -> void:
	if _clock - _last_impact < IMPACT_GAP:
		return
	_last_impact = _clock
	if amount < 6.0:
		_shot(_pick("bump", 3), -6.0 + amount, randf_range(0.9, 1.1))
		return
	var heavy := clampf((amount - 6.0) / 24.0, 0.0, 1.0)
	_shot(_pick("crunch", 3), lerpf(-8.0, 1.0, heavy), randf_range(0.92, 1.08) * lerpf(1.1, 0.95, heavy))
	if amount > 22.0 and _glass_left > 0 and randf() < 0.7:
		_glass_left -= 1
		_shot(load(SFX_DIR + "glass.ogg"), lerpf(-6.0, -1.0, heavy), randf_range(0.92, 1.08))


func _on_eliminated(_car: DerbyCar, reason: String, _by: DerbyCar) -> void:
	if reason == "wrecked" or reason == "flipped":
		_exploded = true
		Sfx.play_at(load(SFX_DIR + "explosion.ogg"), car.global_position, 2.0 + (FOCUS_DB if _focus else 0.0), 22.0, randf_range(0.92, 1.05))
	elif reason == "fell off":
		var water := _water_height()
		if not is_nan(water):
			var at := Vector3(car.global_position.x, water, car.global_position.z)
			Sfx.play_at(load(SFX_DIR + "splash.ogg"), at, 2.0 if _focus else 0.0, 16.0, randf_range(0.9, 1.05))
	_skid_level = 0.0
	_scrape_level = 0.0


func _water_height() -> float:
	var parent := car.get_parent()
	if parent:
		for child in parent.get_children():
			if child is DerbyMap:
				return (child as DerbyMap).water_height
	return NAN


func _pick(prefix: String, count: int) -> AudioStream:
	return load(SFX_DIR + "%s_%d.ogg" % [prefix, randi() % count + 1])
