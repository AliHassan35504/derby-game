extends SceneTree
# Checks the audio: every sound loads, loops are set to loop (WAV loops are
# QOA-compressed), the buses exist, and a car's audio and the Sfx helper run
# without errors (headless uses the dummy audio driver). Run with:
#   godot --headless --path . -s tests/audio_test.gd

const LOOPS := ["skid_loop", "scrape_loop", "wind_loop", "fire_loop", "nitro_loop"]

var map: DerbyMap
var cars: Array[DerbyCar] = []
var frames := 0
var failures := 0


func _initialize() -> void:
	for bus in ["Master", "Music", "SFX"]:
		_expect(AudioServer.get_bus_index(bus) >= 0, "bus %s exists" % bus)
	for engine in CarAudio.ENGINES:
		for level in CarAudio.LEVELS:
			_check_wav(CarAudio.ENGINE_DIR + "%s_%s.wav" % [engine, level])
	for loop in LOOPS:
		_check_wav(CarAudio.SFX_DIR + loop + ".wav")
	for path in Sfx.UI.values():
		_expect(load(path) is AudioStreamOggVorbis, "loads " + path)
	for path in Sfx.MUSIC.values():
		var music := load(path) as AudioStreamOggVorbis
		_expect(music != null and music.loop, "music loops: " + path)
		if music:
			_expect(music.get_length() >= 60.0 and music.get_length() <= 120.0, "music length %.1fs" % music.get_length())
	for name in ["bump_1", "bump_2", "bump_3", "crunch_1", "crunch_2", "crunch_3", "glass", "land_1", "land_2",
			"explosion", "splash", "fall_whoosh", "nitro_burst", "hop", "horn"]:
		_expect(load(CarAudio.SFX_DIR + name + ".ogg") is AudioStreamOggVorbis, "loads " + name)

	map = BoardwalkMap.new()
	root.add_child(map)
	Sfx.play_music("menu")


func _check_wav(path: String) -> void:
	var wav := load(path) as AudioStreamWAV
	_expect(wav != null, "loads " + path)
	if wav:
		_expect(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD, "loops: " + path)
		_expect(wav.format == AudioStreamWAV.FORMAT_QOA, "QOA: " + path)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("AUDIO TEST FAIL: ", what)


func _physics_process(_delta: float) -> bool:
	frames += 1
	if frames == 2:
		var spawns := map.get_spawn_points(3)
		var types := ["van", "monster", "rally"]
		for i in 3:
			var car := DerbyCar.new()
			car.car_type = types[i]
			car.transform = spawns[i]
			car.kill_height = map.kill_height
			root.add_child(car)
			car.controls_enabled = true
			car.throttle_input = 1.0
			car.nitro_input = i == 0
			cars.append(car)
	elif frames == 10:
		for i in 4:
			Sfx.countdown(3.0 - i)
		Sfx.ui("click")
		cars[0].take_damage(3.0)
		cars[1].take_damage(30.0)
		cars[1].hop_input = true
		(cars[2].get_node("CarAudio") as CarAudio).honk()
	elif frames == 60:
		cars[1].take_damage(1000.0)
		cars[2].global_position.y = map.kill_height - 1.0
	elif frames == 120:
		Sfx.elimination(true)
		Sfx.round_over(true)
		for car in cars:
			var audio: CarAudio = null
			for child in car.get_children():
				if child is CarAudio:
					audio = child
			_expect(audio != null, "car has CarAudio")
		_expect(not cars[1].alive and not cars[2].alive, "cars eliminated")
		var voices := 0
		for node in root.find_children("*", "AudioStreamPlayer3D", true, false):
			if (node as AudioStreamPlayer3D).playing:
				voices += 1
		print("3D voices playing with 3 cars: %d" % voices)
		_expect(voices <= 15, "voice count sensible")
	elif frames == 240:
		if failures == 0:
			print("AUDIO TEST PASS")
		quit(1 if failures > 0 else 0)
	return false
