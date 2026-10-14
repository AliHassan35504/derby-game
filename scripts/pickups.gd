class_name PickupManager
extends Node3D
## Pickups for one round: places a few on the map's pads (never on the
## roads), lets cars collect them by driving through, applies the effect and
## respawns them after a while. Also sends badly hurt bots on a short detour
## to a repair that is up on a nearby pad.
##
## Add it under the map, then call setup(). The game listens to collected
## for the HUD notice.

signal collected(car: DerbyCar, kind: int)

## How close a car's centre must get to a pickup's to collect it.
const COLLECT_RADIUS := 2.7
const RESPAWN_TIME := 18.0
const RESPAWN_JITTER := 6.0
## Pickups next to a spawn point show up this long after the start, so
## nobody gets one for free at GO.
const SPAWN_PAD_DELAY := 6.0
const REPAIR_FRACTION := 0.4
const SHOCK_RADIUS := 16.0
const SHOCK_PUSH := 9.0
const SHOCK_LIFT := 5.5
## Bots under this share of their health look for a repair.
const BOT_REPAIR_HEALTH := 0.45
## A repair at most this many roads away counts as nearby for a bot.
const BOT_DETOUR_HOPS := 3
const BOT_DETOUR_TIMEOUT := 20.0
## Chance of each kind on a respawn.
const WEIGHTS := {Pickup.Kind.REPAIR: 0.32, Pickup.Kind.NITRO: 0.26, Pickup.Kind.RAM: 0.21, Pickup.Kind.SHOCKWAVE: 0.21}

var map: DerbyMap
var cars: Array = []
var pickups: Array[Pickup] = []
var respawn_time := RESPAWN_TIME
var respawn_jitter := RESPAWN_JITTER
## Pickups collected this round, by kind name (for the autotest log).
var collected_counts := {}

var _avoid: Array[Vector3] = []
var _placed := false
var _fight_time := -1.0
## Bot car -> [pickup, seconds left] for bots on a repair detour.
var _detours := {}
var _detour_check := 0.0

var _pickup_sound: AudioStream
var _shock_sound: AudioStream


## avoid: spawn positions; pickups there appear a little after the start.
func setup(derby_map: DerbyMap, round_cars: Array, avoid: Array[Vector3] = []) -> void:
	map = derby_map
	cars = round_cars
	_avoid = avoid
	name = "Pickups"
	_pickup_sound = load("res://assets/audio/sfx/pickup.ogg")
	_shock_sound = load("res://assets/audio/sfx/shockwave.ogg")


## How many pickups a map with this many pads gets.
static func count_for(pad_count: int) -> int:
	return clampi(pad_count / 2, 3, 6)


func _physics_process(delta: float) -> void:
	if map == null:
		return
	if not _placed:
		# Placement looks at the physics world, so wait until the map's
		# bodies are in it.
		_placed = true
		_place()
		return
	if _fight_time < 0.0:
		for car in cars:
			if is_instance_valid(car) and car.controls_enabled:
				_fight_time = 0.0
				break
	else:
		_fight_time += delta

	# Pickups go with their pad once it has fallen and been freed.
	if pickups.any(func(p) -> bool: return not is_instance_valid(p)):
		pickups.assign(pickups.filter(func(p) -> bool: return is_instance_valid(p)))
	for pickup in pickups:
		if pickup.retired:
			continue
		var pad_body := map.pad_body(pickup.pad)
		if pad_body == null or not is_instance_valid(pad_body) or pad_body.collision_layer == 0:
			pickup.retire()
			continue
		if not pickup.active:
			# Respawn clocks only run once the fight is on.
			if _fight_time >= 0.0:
				pickup.respawn_in -= delta
				if pickup.respawn_in <= 0.0:
					pickup.appear(_random_kind() if pickup.times_collected > 0 else -1)
			continue
		var at := pickup.centre()
		for car in cars:
			if is_instance_valid(car) and car.alive and car.controls_enabled and car.global_position.distance_to(at) < COLLECT_RADIUS:
				collect(pickup, car)
				break

	_detour_check -= delta
	if _detour_check <= 0.0:
		_detour_check = 0.5
		_update_bot_detours(0.5)


## A car drives through a pickup: apply it, play the sound, start the
## respawn clock.
func collect(pickup: Pickup, car: DerbyCar) -> void:
	if not pickup.active:
		return
	var kind := pickup.kind
	var kind_name: String = Pickup.INFO[kind]["name"]
	collected_counts[kind_name] = collected_counts.get(kind_name, 0) + 1
	apply(car, kind)
	Sfx.play_at(_pickup_sound, pickup.centre(), 2.0, 14.0, [1.0, 1.12, 0.9, 0.8][kind])
	pickup.vanish(respawn_time + randf() * respawn_jitter)
	# Bots heading for this one can go back to hunting.
	for other in _detours.keys():
		if _detours[other][0] == pickup:
			_end_detour(other)
	collected.emit(car, kind)


func apply(car: DerbyCar, kind: int) -> void:
	match kind:
		Pickup.Kind.REPAIR:
			car.heal(car.max_health * REPAIR_FRACTION)
		Pickup.Kind.NITRO:
			car.nitro = 1.0
		Pickup.Kind.RAM:
			RamBoost.give(car)
		Pickup.Kind.SHOCKWAVE:
			shockwave(car)


## Shoves every other car near this one outward and up, and credits this
## car if that sends them off the road.
func shockwave(car: DerbyCar) -> void:
	var origin := car.global_position
	for other in cars:
		if not is_instance_valid(other) or other == car or not other.alive:
			continue
		var offset: Vector3 = other.global_position - origin
		var flat := Vector3(offset.x, 0, offset.z)
		var dist := offset.length()
		if dist > SHOCK_RADIUS:
			continue
		var dir := flat.normalized() if flat.length() > 0.3 else Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
		var falloff := 1.0 - 0.55 * dist / SHOCK_RADIUS
		other.apply_central_impulse((dir * SHOCK_PUSH + Vector3.UP * SHOCK_LIFT) * other.mass * falloff)
		other.apply_torque_impulse(dir.cross(Vector3.UP) * -other.mass * 1.2 * falloff)
		other.register_push(car)
	Sfx.play_at(_shock_sound, origin, 3.0, 18.0)
	_shock_effect(origin)


func _shock_effect(origin: Vector3) -> void:
	var fx := Node3D.new()
	fx.name = "ShockwaveFx"
	map.add_child(fx)
	fx.global_position = origin
	var color: Color = Pickup.INFO[Pickup.Kind.SHOCKWAVE]["color"]
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.85
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 6
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ring_mat.albedo_color = Color(color.lerp(Color.WHITE, 0.3), 1.0)
	torus.material = ring_mat
	ring.mesh = torus
	ring.scale = Vector3(1, 0.6, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(ring)
	var bubble := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 32
	sphere.rings = 16
	var bubble_mat := ShaderMaterial.new()
	bubble_mat.shader = load("res://shaders/glow_shell.gdshader")
	bubble_mat.set_shader_parameter("tint", color)
	bubble_mat.set_shader_parameter("power", 3.0)
	bubble_mat.set_shader_parameter("strength", 1.2)
	sphere.material = bubble_mat
	bubble.mesh = sphere
	bubble.scale = Vector3.ONE * 1.5
	bubble.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx.add_child(bubble)
	var flash := OmniLight3D.new()
	flash.light_color = color
	flash.light_energy = 8.0
	flash.omni_range = SHOCK_RADIUS * 1.2
	fx.add_child(flash)

	var tween := fx.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector3(SHOCK_RADIUS, 1.2, SHOCK_RADIUS), 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(ring_mat, "albedo_color:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tween.tween_property(bubble, "scale", Vector3.ONE * SHOCK_RADIUS * 0.75, 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(v: float) -> void: bubble_mat.set_shader_parameter("strength", v), 1.2, 0.0, 0.5)
	tween.tween_property(flash, "light_energy", 0.0, 0.6)
	tween.chain().tween_callback(fx.queue_free)


func _random_kind() -> int:
	var roll := randf()
	for kind in WEIGHTS:
		roll -= WEIGHTS[kind]
		if roll <= 0.0:
			return kind
	return Pickup.Kind.REPAIR


## Picks pads spread round the map, the central one first, avoiding pads
## with something standing in the middle, and spawn pads where possible.
func _place() -> void:
	var candidates := []
	for id in map.pad_ids():
		var spot = _clear_spot(id)
		if spot == null:
			continue
		var near_spawn := false
		for p in _avoid:
			if Vector2(p.x - spot.x, p.z - spot.z).length() < map.pad_radius(id) + 2.0 and absf(p.y - spot.y) < 6.0:
				near_spawn = true
		candidates.append({"id": id, "pos": spot, "spawn": near_spawn})
	var count := mini(count_for(map.pad_ids().size()), candidates.size())
	var chosen := []
	while chosen.size() < count:
		var best = null
		var best_score := -INF
		for c in candidates:
			if chosen.has(c):
				continue
			var score := 0.0
			if chosen.is_empty():
				score = -Vector2(c["pos"].x, c["pos"].z).length()
			else:
				score = INF
				for o in chosen:
					score = minf(score, (c["pos"] as Vector3).distance_to(o["pos"]))
			if c["spawn"]:
				score -= 1000.0
			if score > best_score:
				best_score = score
				best = c
		chosen.append(best)

	# Every kind turns up at least once when there are enough spots.
	var kinds := [Pickup.Kind.REPAIR, Pickup.Kind.NITRO, Pickup.Kind.RAM, Pickup.Kind.SHOCKWAVE]
	kinds.shuffle()
	while kinds.size() < chosen.size():
		kinds.append(_random_kind())
	for i in chosen.size():
		var c: Dictionary = chosen[i]
		var pickup := Pickup.new()
		pickup.name = "Pickup_" + c["id"]
		pickup.pad = c["id"]
		pickup.kind = kinds[i]
		map.pad_body(c["id"]).add_child(pickup)
		pickup.global_position = c["pos"]
		pickup.rotation = Vector3.ZERO
		if c["spawn"]:
			pickup.respawn_in = SPAWN_PAD_DELAY
		else:
			pickup.appear()
		pickups.append(pickup)


## The pad's centre, or a spot near it, with nothing standing on it; null
## when there is none.
func _clear_spot(id: String):
	var centre := map.pad_position(id)
	var half := map.pad_half(id)
	var space := get_world_3d().direct_space_state
	var probe := SphereShape3D.new()
	probe.radius = 1.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = DerbyMap.ROAD_LAYER
	var reach := maxf(minf(half.x, half.y) - 2.2, 0.0)
	for offset in [Vector3.ZERO, Vector3(reach, 0, 0), Vector3(-reach, 0, 0), Vector3(0, 0, reach), Vector3(0, 0, -reach)]:
		var spot: Vector3 = centre + offset
		query.transform = Transform3D(Basis.IDENTITY, spot + Vector3.UP * 1.9)
		if not space.intersect_shape(query, 1).is_empty():
			continue
		# Something solid has to be under it (the pad itself).
		var ray := PhysicsRayQueryParameters3D.create(spot + Vector3.UP * 0.4, spot + Vector3.DOWN * 0.6, DerbyMap.ROAD_LAYER)
		if space.intersect_ray(ray).is_empty():
			continue
		return spot
	return null


func _update_bot_detours(step: float) -> void:
	for car in _detours.keys():
		var entry: Array = _detours[car]
		entry[1] -= step
		var pickup: Pickup = entry[0]
		if not is_instance_valid(car) or not car.alive or entry[1] <= 0.0 or not is_instance_valid(pickup) \
				or not pickup.active or pickup.kind != Pickup.Kind.REPAIR or car.health > car.max_health * 0.8:
			_end_detour(car)
	for car in cars:
		if not is_instance_valid(car) or not car.alive or not car.controls_enabled or _detours.has(car):
			continue
		if car.health > car.max_health * BOT_REPAIR_HEALTH:
			continue
		var bot := _bot_of(car)
		if bot == null:
			continue
		var here := map.nearest_pad(car.global_position)
		var best: Pickup
		var best_hops := BOT_DETOUR_HOPS + 1
		for pickup in pickups:
			if not is_instance_valid(pickup) or not pickup.active or pickup.kind != Pickup.Kind.REPAIR:
				continue
			if _taken_by_other(pickup, car):
				continue
			var path := map.route(here, pickup.pad)
			var hops := path.size() - 1
			if hops < 0 or (hops == 0 and here != pickup.pad) or hops >= best_hops:
				continue
			best = pickup
			best_hops = hops
		if best:
			_detours[car] = [best, BOT_DETOUR_TIMEOUT]
			bot.set_detour(best.pad)


func _end_detour(car) -> void:
	_detours.erase(car)
	if is_instance_valid(car):
		var bot := _bot_of(car)
		if bot:
			bot.set_detour("")


func _taken_by_other(pickup: Pickup, car: DerbyCar) -> bool:
	for other in _detours:
		if other != car and _detours[other][0] == pickup:
			return true
	return false


func _bot_of(car: DerbyCar) -> BotController:
	for child in car.get_children():
		if child is BotController:
			return child
	return null


## Bots currently heading for a repair (for tests).
func detouring() -> Array:
	return _detours.keys()
