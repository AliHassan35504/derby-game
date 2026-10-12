class_name BotController
extends Node
## Derby AI for narrow floating roads. Bots navigate pad to pad along the
## map's roads toward their target, slowing before each turn, and switch to
## ramming once the target is close and there is road between them. Ground
## probes in front of the car act as a safety net: if the way ahead has no
## road under it, the bot picks a safe heading or backs up.

const HEADINGS := [-0.9, -0.6, -0.35, -0.15, 0.0, 0.15, 0.35, 0.6, 0.9]
## Distances checked along a heading. How many in a row have road under them
## is that heading's "depth".
const PROBE_DISTANCES := [3.0, 6.0, 10.0, 15.0, 21.0]
## Braking the bots plan with, in m/s².
const PLAN_DECEL := 3.0
## Ram the target directly once it is this close.
const HUNT_RANGE := 26.0

var rivals: Array = []
var map: DerbyMap
## 0..1, lowers aim accuracy and reaction for easier bots.
var skill := 0.8

@onready var car: DerbyCar = get_parent()

var _target: DerbyCar
var _retarget_in := 0.0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _reverse_steer := 0.0
var _think_in := 0.0
var _waypoint := ""
var _previous := ""
var _next := ""
var _from := Vector3.ZERO
var _corner_limit := 30.0
var _steer := 0.0
var _speed_limit := 30.0
var _hunting := false
var _repicked := false
var _stuck_count := 0


func _physics_process(delta: float) -> void:
	if not car.alive or not car.controls_enabled:
		return
	_retarget_in -= delta
	if _target == null or not _target.alive or _retarget_in <= 0.0:
		_target = _pick_target()
		_retarget_in = randf_range(2.0, 4.0)

	var speed := car.get_forward_speed()
	if _reverse_time > 0.0:
		_reverse_time -= delta
		car.throttle_input = -0.8
		car.steer_input = _reverse_steer
		car.nitro_input = false
		car.brace_input = false
		# Stop backing up before the road behind runs out.
		if _heading_depth(-_reverse_steer * 0.5, true) == 0:
			_reverse_time = 0.0
		return

	_think_in -= delta
	if _think_in <= 0.0:
		_think_in = 0.1
		_think(speed)

	car.steer_input = _steer
	car.handbrake_input = false
	if speed > _speed_limit + 0.5:
		car.throttle_input = -1.0
	elif speed > _speed_limit - 0.5:
		car.throttle_input = 0.0
	else:
		car.throttle_input = 1.0

	car.nitro_input = false
	car.brace_input = false
	if _target and _hunting:
		var to_target := _target.global_position - car.global_position
		var aligned := to_target.normalized().dot(car.get_forward())
		car.nitro_input = aligned > 0.95 and to_target.length() < 20.0 and _speed_limit >= 15.0 and randf() < skill
		# Save nitro for side and rear hits, not head-ons that send both off.
		var facing_us := _target.get_forward().dot(-to_target.normalized()) > 0.3
		car.nitro_input = car.nitro_input and not facing_us
		var closing := (_target.linear_velocity - car.linear_velocity).dot(-to_target.normalized())
		car.brace_input = to_target.length() < 9.0 and closing > 10.0 and skill > 0.7

	# Back out if pinned against something.
	if absf(speed) < 0.8 and car.throttle_input > 0.3:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.5:
		_stuck_time = 0.0
		# Stuck twice running: probably beached on an edge, so hop free.
		_stuck_count += 1
		if _stuck_count >= 2:
			_stuck_count = 0
			car.hop_input = true
		_start_reverse()
	if absf(speed) > 3.0:
		_stuck_count = 0


func _think(speed: float) -> void:
	var pos := car.global_position
	_repicked = false
	var goal := _navigate(pos)
	var goal_angle := _angle_to(goal)

	if _hunting:
		_ram(pos, goal, goal_angle, speed)
		return

	# Safety net: is there road toward the goal? If not, find a heading that
	# has road, as close to the goal as possible.
	var heading := clampf(goal_angle, -0.9, 0.9)
	var depth := _heading_depth(heading)
	if (not _hunting and absf(goal_angle) > 1.4) or (depth < 2 and absf(goal_angle) > 0.5):
		# A sharp turn on a pad, or the way on is behind us: creep round on
		# full lock, and back up (a three-point turn) before running out of
		# pad in front.
		_steer = signf(goal_angle)
		_speed_limit = 3.0 if speed < 4.0 else 0.0
		if _heading_depth(signf(goal_angle) * 0.5) < 1 or _heading_depth(0.0) < 1:
			_speed_limit = 0.0
			if absf(speed) < 1.0:
				_start_reverse()
		return
	if depth < 2:
		var best := INF
		var best_depth := 0
		for h in HEADINGS:
			var d := _heading_depth(h)
			if d < 2:
				continue
			var score := absf(h - heading) + (PROBE_DISTANCES.size() - d) * 0.2
			if score < best:
				best = score
				heading = h
				best_depth = d
		depth = best_depth
		if depth < 2:
			_speed_limit = 0.0
			if absf(speed) < 1.5:
				_start_reverse()
			return

	var reach := clampf(_flat(goal - pos).length(), 3.0, 15.0) if heading == clampf(goal_angle, -0.9, 0.9) else 8.0
	_steer = _pursuit_steer(heading, reach, speed)
	if randf() > skill:
		_steer += randf_range(-0.1, 0.1)

	# Speed: slow for sharp steering, short visible road and coming turns.
	var limit := 30.0
	limit = minf(limit, lerpf(28.0, 4.5, clampf(absf(goal_angle) / 0.7, 0.0, 1.0)))
	limit = minf(limit, [0.0, 0.0, 8.0, 12.0, 18.0, 30.0][depth])
	limit = minf(limit, _corner_limit)
	_speed_limit = limit


## Drive straight at the target. If the road ends just past it (it is on an
## edge, or beached), come in slower for a firm shove we can stop after;
## otherwise hit as hard as the corner ahead allows.
func _ram(pos: Vector3, goal: Vector3, goal_angle: float, speed: float) -> void:
	var dist := _flat(goal - pos).length()
	_steer = _pursuit_steer(clampf(goal_angle, -0.9, 0.9), clampf(dist, 3.0, 15.0), speed)
	var limit := minf(lerpf(13.0, 18.0, skill), _corner_limit + 5.0)
	var depth := _heading_depth(clampf(goal_angle, -0.9, 0.9))
	var road_beyond: bool = depth >= PROBE_DISTANCES.size() or PROBE_DISTANCES[depth] > dist + 7.0
	if not road_beyond:
		limit = minf(limit, 6.5 + 0.7 * maxf(dist - 6.0, 0.0))
	# Never charge at the very edge unless the target is right there and
	# still on the road; once it goes over, stop rather than follow it.
	if depth == 0 and (dist > 5.0 or not _target.is_on_ground()):
		limit = 0.0
	elif depth <= 1 and not road_beyond:
		limit = minf(limit, 4.0)
	_speed_limit = limit


## Pure pursuit: the steering input that puts the car on an arc through a
## point at this angle and distance.
func _pursuit_steer(heading: float, reach: float, speed: float) -> float:
	var wheelbase: float = car.stats["size"].z * float(car.stats["wheel_z"]) * 2.0
	var angle := atan(wheelbase * 2.0 * sin(heading) / reach)
	return clampf(angle / car.max_steer_at(speed), -1.0, 1.0)


## Picks where to drive this tick: straight at the target when hunting,
## otherwise a point a little way ahead along the road route (pure pursuit),
## so the bot follows the road's centre line and rounds corners on the pads.
func _navigate(pos: Vector3) -> Vector3:
	_hunting = false
	if map == null:
		return _target.global_position if _target else pos + car.get_forward() * 10.0
	var hunt_aim := Vector3.ZERO
	if _target:
		var to_target := _target.global_position - pos
		if to_target.length() < HUNT_RANGE and absf(to_target.y) < 3.0 and _target.is_on_ground() and _road_reaches(_target.global_position):
			_hunting = true
			# Lead the target a little so the bot hits where it is going.
			hunt_aim = _target.global_position + _target.linear_velocity * 0.3 * skill

	if _waypoint == "":
		_pick_road(pos)
	var wp := map.pad_position(_waypoint)
	var seg := _flat(wp - _from)
	var seg_len := maxf(seg.length(), 0.01)
	var dir := seg / seg_len
	var t := clampf(_flat(pos - _from).dot(dir), 0.0, seg_len)
	var remaining := seg_len - t
	# Got bumped onto a different road than planned: work out where we are.
	var off_line := _flat(pos - (_from + dir * t)).length()
	if off_line > map.road_width * 0.5 + 2.5 and not _on_pad(pos, _previous) and not _on_pad(pos, _waypoint) and not _repicked:
		_repicked = true
		_pick_road(pos)
		return _navigate(pos)
	# Start turning onto the next road early enough to sweep round the
	# corner on an arc the car can actually drive, instead of cutting it.
	var turn_in: float = _plan_corner(dir)[0]
	if (remaining < turn_in or _flat(wp - pos).length() < 1.5) and _next != _waypoint:
		_previous = _waypoint
		_from = wp
		_waypoint = _next
		_next = _next_after(_waypoint)
		return _navigate(pos)

	# Follow the road's centre line, a little way ahead of the car.
	var lookahead := clampf(absf(car.get_forward_speed()) * 0.6, 4.0, 12.0)
	var aim := _from + dir * (t + (minf(lookahead, remaining) if _next == _waypoint else lookahead))
	aim.y = pos.y
	_corner_limit = _corner_speed(dir, remaining)
	return hunt_aim if _hunting else aim


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


func _next_after(pad: String) -> String:
	var links: Array = map.pad_links(pad)
	if links.is_empty():
		return pad
	if _target:
		var path := map.route(pad, map.nearest_pad(_target.global_position))
		if path.size() > 1:
			return path[1]
	# No target, or already at its pad: wander, avoiding turning straight back.
	var options := links.filter(func(l: String) -> bool: return l != _previous)
	return (options if not options.is_empty() else links).pick_random()


## Works out which road the car is on, and which way along it to drive.
## On a pad, the next road leads toward the target. On a road, keep going
## the way the car faces, so a bot that just backed up carries on.
func _pick_road(pos: Vector3) -> void:
	var here := map.nearest_pad(pos)
	var here_pos := map.pad_position(here)
	if _on_pad(pos, here) or map.pad_links(here).is_empty():
		_previous = ""
		_from = here_pos
		_waypoint = _next_after(here)
		_previous = here
	else:
		# Find the road whose centre line is closest to the car.
		var best_dist := INF
		var best_a := here
		var best_b := here
		for a in [here] + map.pad_links(here):
			for b in map.pad_links(a):
				var pa := map.pad_position(a)
				var pb := map.pad_position(b)
				var d := _distance_to_segment(_flat(pos), _flat(pa), _flat(pb)) + absf(pos.y - lerpf(pa.y, pb.y, 0.5)) * 0.2
				if d < best_dist:
					best_dist = d
					best_a = a
					best_b = b
		# Drive toward whichever end the car is facing.
		var toward_b := _flat(map.pad_position(best_b) - map.pad_position(best_a)).dot(car.get_forward()) > 0.0
		_previous = best_a if toward_b else best_b
		_waypoint = best_b if toward_b else best_a
		_from = map.pad_position(_previous)
	_next = _next_after(_waypoint)


func _on_pad(pos: Vector3, pad: String) -> bool:
	return pad != "" and _flat(pos - map.pad_position(pad)).length() < map.pad_radius(pad) * 1.1 and absf(pos.y - map.pad_position(pad).y) < 4.0


func _distance_to_segment(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return (a + ab * t).distance_to(p)


## Plans the turn at the waypoint: the widest arc that fits on the pad
## (but no tighter than the car can steer), where along the road to start
## turning onto it, and how fast the car can take it.
## Returns [turn-in distance before the pad centre, corner speed].
func _plan_corner(incoming: Vector3) -> Array:
	if _next == _waypoint:
		return [1.5, 3.0]
	var outgoing := _flat(map.pad_position(_next) - map.pad_position(_waypoint)).normalized()
	var turn := acos(clampf(incoming.dot(outgoing), -1.0, 1.0))
	if turn > 1.9:
		# Hairpin: stop at the centre and do a three-point turn.
		return [1.5, 3.0]
	if turn < 0.05:
		return [1.5, 30.0]
	var half_turn := tan(turn * 0.5)
	var room := map.pad_radius(_waypoint) * 0.8
	var radius := clampf(room / half_turn, car.turning_radius(), 25.0)
	var turn_in := clampf(radius * half_turn, 1.5, room)
	return [turn_in, maxf(sqrt(float(car.stats["cornering"]) * radius), 3.0)]


## How fast we can be going now and still make the turn at the waypoint.
func _corner_speed(incoming: Vector3, remaining: float) -> float:
	var plan := _plan_corner(incoming)
	var corner: float = plan[1]
	if _next == _waypoint:
		return sqrt(2.0 * PLAN_DECEL * remaining) + 3.0
	return sqrt(corner * corner + 2.0 * PLAN_DECEL * maxf(remaining - float(plan[0]), 0.0))


func _start_reverse() -> void:
	_waypoint = ""
	# Reversing flips steering, so turning the other way swings the nose
	# round. Pick the reverse arc with the most road behind the car, so bots
	# don't back off the edge of a narrow ramp.
	var preferred := -signf(_steer) if absf(_steer) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
	var best_score := -INF
	for s in [preferred, preferred * 0.5, 0.0, -preferred * 0.5, -preferred]:
		var depth := _heading_depth(-s * 0.5, true)
		var score := depth - absf(s - preferred) * 0.3
		if score > best_score:
			best_score = score
			_reverse_steer = s
	var room := _heading_depth(-_reverse_steer * 0.5, true)
	_reverse_time = 0.0 if room == 0 else (0.5 if room == 1 else randf_range(0.9, 1.4))


## Angle from the car's nose to a point around its up axis; positive means
## the point is to the left.
func _angle_to(point: Vector3) -> float:
	var local := car.global_transform.affine_inverse() * point
	return atan2(local.x, local.z)


## How many probe distances in a row along this heading have road under both
## sides of the car.
func _heading_depth(heading: float, backward := false) -> int:
	var space := car.get_world_3d().direct_space_state
	var forward := -car.get_forward() if backward else car.get_forward()
	forward.y = 0.0
	forward = forward.normalized().rotated(Vector3.UP, heading)
	var right := Vector3.UP.cross(forward).normalized()
	var origin := car.global_position
	var half_width: float = car.stats["size"].x * 0.5
	var depth := 0
	for d in PROBE_DISTANCES:
		for side in [-half_width, half_width]:
			var point := origin + forward * float(d) + right * float(side)
			var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 5.0, point + Vector3.DOWN * 8.0, DerbyMap.ROAD_LAYER)
			if space.intersect_ray(query).is_empty():
				return depth
		depth += 1
	return depth


## Whether there is road under us all the way to a point (but not
## necessarily beyond it, so a car stuck on an edge still counts).
func _road_reaches(point: Vector3) -> bool:
	var angle := _angle_to(point)
	if absf(angle) > 0.9:
		return false
	var dist := _flat(point - car.global_position).length()
	var needed := 0
	for d in PROBE_DISTANCES:
		if d < dist - 2.5:
			needed += 1
	return _heading_depth(angle) >= needed


func _pick_target() -> DerbyCar:
	var best: DerbyCar
	var best_score := INF
	for other in rivals:
		if other == car or not other.alive:
			continue
		var offset: Vector3 = other.global_position - car.global_position
		# Prefer close rivals on roughly the same level, and easy prey: a car
		# that is stuck, damaged or already teetering on an edge.
		var score := offset.length() + absf(offset.y) * 2.0 + randf() * 15.0
		# (Everyone is still at the start of a round.)
		if other.linear_velocity.length() < 2.0 and car.survived > 6.0:
			score -= 20.0
		score -= (1.0 - other.health / other.max_health) * 15.0
		if score < best_score:
			best_score = score
			best = other
	return best
