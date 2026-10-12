class_name BotController
extends Node
## Simple derby AI: picks a target, rams it, and turns back toward the middle
## whenever it is heading for the edge. Reverses out when stuck.

## How far ahead the bot looks when checking for the edge.
const LOOKAHEAD := 1.1
## Fraction of the arena radius treated as the safe zone.
const SAFE_FRACTION := 0.78

var arena_radius := 40.0
var rivals: Array = []
## 0..1, lowers aim accuracy and reaction for easier bots.
var skill := 0.8

@onready var car: DerbyCar = get_parent()

var _target: DerbyCar
var _retarget_in := 0.0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _wobble := randf() * TAU


func _physics_process(delta: float) -> void:
	if not car.alive or not car.controls_enabled:
		return
	_retarget_in -= delta
	if _target == null or not _target.alive or _retarget_in <= 0.0:
		_target = _pick_target()
		_retarget_in = randf_range(2.0, 4.0)

	var pos := car.global_position
	var speed := car.get_forward_speed()
	var ahead := pos + car.linear_velocity * LOOKAHEAD
	var flat_ahead := Vector2(ahead.x, ahead.z)
	var in_danger := flat_ahead.length() > arena_radius * SAFE_FRACTION

	var goal := Vector3.ZERO
	if not in_danger and _target:
		# Lead the target a little so the bot hits where it is going.
		goal = _target.global_position + _target.linear_velocity * 0.35 * skill
	_wobble += delta * 0.7
	goal += Vector3(sin(_wobble), 0, cos(_wobble)) * (1.0 - skill) * 6.0

	var local := car.global_transform.affine_inverse() * goal
	# Angle to the goal around the car's up axis; positive means goal is left.
	var angle := atan2(local.x, local.z)

	# Stuck against something: back out for a moment.
	if absf(speed) < 1.0 and car.throttle_input > 0.3:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if _stuck_time > 1.2:
		_reverse_time = 1.0
		_stuck_time = 0.0

	if _reverse_time > 0.0:
		_reverse_time -= delta
		car.throttle_input = -1.0
		car.steer_input = -signf(angle)
		car.handbrake_input = false
		return

	car.steer_input = clampf(angle * 2.0, -1.0, 1.0)
	if in_danger and absf(angle) > 1.9 and speed < 6.0:
		# Facing the drop with the middle behind us: back up while turning
		# (steering flips when reversing) instead of driving over the edge.
		car.throttle_input = -1.0
		car.steer_input = -signf(angle)
		car.handbrake_input = false
	elif in_danger:
		# Ease off and turn hard, using the handbrake if going too fast.
		car.throttle_input = 0.4 if speed < 10.0 else 0.0
		car.handbrake_input = speed > 14.0 and absf(angle) > 1.2
	else:
		car.throttle_input = 1.0 if absf(angle) < 2.0 else 0.6
		car.handbrake_input = false


func _pick_target() -> DerbyCar:
	var best: DerbyCar
	var best_score := INF
	for other in rivals:
		if other == car or not other.alive:
			continue
		# Prefer close cars and ones near the edge (easy knock-offs).
		var dist := car.global_position.distance_to(other.global_position)
		var edge := Vector2(other.global_position.x, other.global_position.z).length() / arena_radius
		var score := dist - edge * 20.0 + randf() * 10.0
		if score < best_score:
			best_score = score
			best = other
	return best
