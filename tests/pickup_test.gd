extends SceneTree
# Checks pickups, stunt cash and the career file: every pickup kind does
# what it says when a car drives through it and comes back after the
# respawn delay, Ram doubles the damage of a real crash, a long drop pays
# airtime cash, a badly hurt bot detours to a nearby repair, pickups go
# when the map collapses, and the career profile saves and loads. Run with:
#   godot --headless --path . -s tests/pickup_test.gd

const FLOOR := Vector3(600, 200, 600)

var map: DerbyMap
var manager: PickupManager
var stunts: StuntScore
var cars: Array = []
var a: DerbyCar
var b: DerbyCar
var c: DerbyCar
var bot_car: DerbyCar
var prey: DerbyCar
var bot: BotController
var failures := 0
var step := 0
var wait := 0
var t := 0.0
var awards: Array = []
var crash_damage: Array[float] = []
var _pending: Pickup
var _health_before := 0.0
var _respawn_pickup: Pickup
var _bot_health := 0.0


func _initialize() -> void:
	_check_career()
	map = BoardwalkMap.new()
	root.add_child(map)
	# A flat test floor far from the map for crash and airtime checks.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = DerbyMap.ROAD_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(160, 1, 160)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = FLOOR - Vector3(0, 0.5, 0)
	root.add_child(floor_body)


func _make_car(pos: Vector3, yaw := 0.0) -> DerbyCar:
	var car := DerbyCar.new()
	car.car_type = map.car_type
	car.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	car.kill_height = map.kill_height
	root.add_child(car)
	cars.append(car)
	return car


func _expect(ok: bool, what: String) -> void:
	if ok:
		print("  ok: ", what)
	else:
		failures += 1
		print("PICKUP TEST FAIL: ", what)


func _place(car: DerbyCar, pos: Vector3, yaw := 0.0) -> void:
	car.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	car.linear_velocity = Vector3.ZERO
	car.angular_velocity = Vector3.ZERO


func _pickup_of(kind: int) -> Pickup:
	for p in manager.pickups:
		if p.active and p.kind == kind:
			return p
	return null


## Teleports car a onto the pickup of this kind.
func _drive_through(kind: int) -> Pickup:
	var p := _pickup_of(kind)
	_expect(p != null, "an active %s pickup" % Pickup.INFO[kind]["name"])
	if p:
		_place(a, p.centre())
	return p


func _physics_process(delta: float) -> bool:
	t += delta
	if wait > 0:
		wait -= 1
		return false
	match step:
		0:
			a = _make_car(FLOOR + Vector3(0, 1.2, 0))
			b = _make_car(FLOOR + Vector3(12, 1.2, 0))
			c = _make_car(FLOOR + Vector3(-30, 1.2, -30))
			var spawns := map.get_spawn_points(8)
			bot_car = _make_car(spawns[0].origin)
			bot_car.global_transform = spawns[0]
			prey = _make_car(spawns[2].origin)
			prey.global_transform = spawns[2]
			for car in [a, b, c]:
				car.controls_enabled = true
			manager = PickupManager.new()
			map.add_child(manager)
			manager.setup(map, cars)
			manager.respawn_time = 1.0
			manager.respawn_jitter = 0.0
			stunts = StuntScore.new()
			map.add_child(stunts)
			stunts.setup(cars)
			stunts.cash_awarded.connect(func(car: DerbyCar, amount: int, label: String) -> void: awards.append([car, amount, label]))
			wait = 10
		1:
			var pads := {}
			var kinds := {}
			for p in manager.pickups:
				pads[p.pad] = true
				kinds[p.kind] = true
				_expect(p.get_parent() == map.pad_body(p.pad), "pickup sits on pad %s" % p.pad)
				_expect(p.active and p.visible, "pickup on %s is up" % p.pad)
			_expect(manager.pickups.size() == PickupManager.count_for(map.pad_ids().size()), "%d pickups on %d pads" % [manager.pickups.size(), map.pad_ids().size()])
			_expect(pads.size() == manager.pickups.size(), "one pickup per pad")
			_expect(kinds.size() == 4, "every kind on the map")
			# Repair.
			a.health = a.max_health * 0.3
			_health_before = a.health
			_pending = _drive_through(Pickup.Kind.REPAIR)
			wait = 2
		2:
			_expect(is_equal_approx(a.health, _health_before + a.max_health * PickupManager.REPAIR_FRACTION), "repair adds 40%% health (%.0f -> %.0f)" % [_health_before, a.health])
			_expect(_pending and not _pending.active, "repair pickup is gone after collecting")
			_respawn_pickup = _pending
			# Nitro.
			a.nitro = 0.0
			_pending = _drive_through(Pickup.Kind.NITRO)
			wait = 2
		3:
			_expect(a.nitro > 0.99, "nitro refilled (%.2f)" % a.nitro)
			# Ram.
			_pending = _drive_through(Pickup.Kind.RAM)
			wait = 2
		4:
			var boost := RamBoost.active_on(a)
			_expect(boost != null, "ram glow on the car")
			_expect(a.damage_dealt_multiplier == 2.0 and a.damage_taken_multiplier == 0.5, "ram doubles damage dealt and halves damage taken")
			if boost:
				boost.time_left = 0.1
			wait = 12
		5:
			_expect(RamBoost.active_on(a) == null and a.damage_dealt_multiplier == 1.0 and a.damage_taken_multiplier == 1.0, "ram wears off")
			# Shockwave: b parked next to the pickup gets blown away.
			var p := _pickup_of(Pickup.Kind.SHOCKWAVE)
			_expect(p != null, "an active SHOCKWAVE pickup")
			if p:
				var side := Vector3(p.global_position.x, 0, p.global_position.z).normalized()
				_place(b, p.centre() + side.cross(Vector3.UP) * 4.0 + Vector3.UP * 0.2)
				_pending = p
			wait = 20
		6:
			b.linear_velocity = Vector3.ZERO
			_place(a, _pending.centre())
			wait = 3
		7:
			var away := Vector3(b.global_position.x - a.global_position.x, 0, b.global_position.z - a.global_position.z).normalized()
			_expect(b.linear_velocity.dot(away) > 3.0 and b.linear_velocity.y > 1.0, "shockwave shoves the other car out and up (%s)" % b.linear_velocity)
			_expect(b.get_credit() == a, "shockwave credits the collector")
			# Crash on the test floor, without and then with Ram.
			_setup_crash()
			wait = 90
		8:
			crash_damage.append(b.max_health - b.health)
			RamBoost.give(a, 30.0)
			_setup_crash()
			wait = 90
		9:
			crash_damage.append(b.max_health - b.health)
			_expect(_respawn_pickup.active and _respawn_pickup.visible, "collected pickup respawned after the delay")
			var ratio := crash_damage[1] / maxf(crash_damage[0], 0.01)
			_expect(crash_damage[0] > 5.0 and ratio > 1.5 and ratio < 2.5, "ram doubles crash damage (%.1f -> %.1f)" % [crash_damage[0], crash_damage[1]])
			var hit_cash := awards.filter(func(w: Array) -> bool: return w[0] == a and String(w[2]).ends_with("HIT"))
			_expect(not hit_cash.is_empty(), "a big hit pays stunt cash (%s)" % [hit_cash.map(func(w: Array) -> String: return "%s $%d" % [w[2], w[1]])])
			RamBoost.active_on(a).end()
			# Airtime: drop c from 11 m onto the floor.
			_place(c, FLOOR + Vector3(-30, 12.0, -30))
			wait = 240
		10:
			var air := awards.filter(func(w: Array) -> bool: return w[0] == c and String(w[2]).begins_with("AIRTIME"))
			_expect(air.size() == 1 and air[0][1] >= 150, "a long drop landed upright pays airtime cash (%s)" % [air.map(func(w: Array) -> String: return "%s $%d" % [w[2], w[1]])])
			stunts.finish_round(c)
			_expect(stunts.cash_of(c) >= StuntScore.WIN_CASH, "the winner gets the win bonus ($%d)" % stunts.cash_of(c))
			# Bot detour: make the hub's pickup a repair and hurt the bot.
			var hub: Pickup = null
			for p in manager.pickups:
				if p.pad == "hub":
					hub = p
			_expect(hub != null, "a pickup on the hub")
			if hub:
				if not hub.active:
					hub.appear()
				hub.set_kind(Pickup.Kind.REPAIR)
			for p in manager.pickups:
				if p != hub and p.kind == Pickup.Kind.REPAIR:
					p.set_kind(Pickup.Kind.NITRO)
			for car in [a, b, c]:
				car.controls_enabled = false
				_place(car, FLOOR + Vector3(randf_range(-60, 60), 1.2, randf_range(-60, 60)))
			bot = BotController.new()
			bot.map = map
			bot.skill = 0.9
			bot.rivals = [bot_car, prey]
			bot_car.add_child(bot)
			bot_car.health = bot_car.max_health * 0.3
			_bot_health = bot_car.health
			bot_car.controls_enabled = true
			t = 0.0
			wait = 90
		11:
			_expect(manager.detouring().has(bot_car) and bot.detour_pad == "hub", "hurt bot heads for the repair on the hub (%s)" % bot.detour_pad)
			step += 1
			t = 0.0
			return false
		12:
			if bot_car.health > _bot_health + 1.0:
				_expect(true, "bot picked up the repair after %.1fs" % t)
				_expect(bot.detour_pad == "" or not manager.detouring().has(bot_car), "bot goes back to hunting")
			elif t < 30.0 and bot_car.alive:
				return false
			else:
				_expect(false, "bot reached the repair within 30s (at %s, alive %s)" % [bot_car.global_position, bot_car.alive])
			# Collapse the whole map: pickups go with their pads.
			bot_car.health = bot_car.max_health * 0.2
			while map.collapse_next():
				pass
			wait = 70
		13:
			var retired := manager.pickups.all(func(p) -> bool: return not is_instance_valid(p) or (p.retired and not p.active))
			_expect(retired, "pickups on fallen pads are gone")
			wait = 300
		14:
			_expect(manager.pickups.is_empty(), "freed pickups are dropped once the pads are gone (%d left)" % manager.pickups.size())
			_finish()
			return true
	step += 1
	return false


func _setup_crash() -> void:
	b.health = b.max_health
	b._update_damage_look()
	# a coasts (controls on, no throttle, so no brakes); b is parked.
	b.controls_enabled = false
	_place(b, FLOOR + Vector3(0, 1.0, 20), PI * 0.5)
	_place(a, FLOOR + Vector3(0, 1.0, 8))
	a.linear_velocity = Vector3(0, 0, 11)


func _check_career() -> void:
	Career.path = "user://profile_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.path))
	Career.load_profile()
	_expect(Career.rounds == 0 and Career.total_cash == 0, "fresh career is empty")
	Career.record_round(1250, true, 2, 75.5, 31.0)
	Career.record_round(300, false, 1, 40.0, 44.0)
	Career.reset()
	Career.load_profile()
	_expect(Career.total_cash == 1550 and Career.rounds == 2 and Career.wins == 1 and Career.knockouts == 3, "career totals saved and loaded")
	_expect(is_equal_approx(Career.best_survival, 75.5) and is_equal_approx(Career.biggest_hit, 44.0), "career bests saved and loaded")
	_expect(Career.money(1234567) == "$1,234,567" and Career.money(950) == "$950", "money formatting")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Career.path))


func _finish() -> void:
	if failures == 0:
		print("PICKUP TEST PASS")
	quit(1 if failures > 0 else 0)
