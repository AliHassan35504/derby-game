class_name StuntScore
extends Node
## Stunt cash for one round, like the SA-MP derby: every driver earns money
## for big hits (more for harder ones), knockouts credited to them, airtime
## (wheels off the ground for a second or more, landing on their wheels),
## and at the end of the round for how long they survived and for winning.
##
## Add it under the map, call setup() with the round's cars, and listen to
## cash_awarded for the HUD popups. finish_round() adds the end bonuses.

signal cash_awarded(car: DerbyCar, amount: int, label: String)

## Hits that take less health than this earn nothing.
const HIT_MIN := 14.0
const MEGA_HIT := 34.0
const CASH_PER_DAMAGE := 10.0
const KNOCKOUT_CASH := 500
## Airtime: at least this long off the ground, paid per second.
const AIR_MIN := 1.0
const AIR_CASH_PER_SECOND := 150.0
## A hop launches the car for about this long on its own, so that much of a
## hop's airtime doesn't count (hopping on the spot earns nothing).
const HOP_AIR := 1.3
## Cars upright at least this much (basis.y.y) when they land get paid.
const UPRIGHT := 0.75
const SURVIVAL_CASH_PER_SECOND := 8.0
const WIN_CASH := 1000
## Several hits on one car within this time pay once (the biggest).
const HIT_GAP := 0.35

var cars: Array = []
## Car -> cash this round.
var cash := {}
## Car -> damage of its biggest hit this round.
var biggest_hit := {}

## Car -> seconds in the air so far, or -1 on the ground.
var _air := {}
var _air_from_hop := {}
var _last_hit := {}
var _clock := 0.0


func setup(round_cars: Array) -> void:
	name = "StuntScore"
	cars = round_cars
	for car in cars:
		cash[car] = 0
		biggest_hit[car] = 0.0
		_air[car] = -1.0
		car.impact.connect(_on_impact)
		car.eliminated.connect(_on_eliminated)


func award(car: DerbyCar, amount: int, label: String) -> void:
	if car == null or not cash.has(car) or amount <= 0:
		return
	cash[car] += amount
	cash_awarded.emit(car, amount, label)


func cash_of(car: DerbyCar) -> int:
	return cash.get(car, 0)


## End of round bonuses: survival time for everyone, plus the winner's
## prize.
func finish_round(winner: DerbyCar) -> void:
	for car in cars:
		if not is_instance_valid(car):
			continue
		award(car, int(roundf(car.survived * SURVIVAL_CASH_PER_SECOND / 10.0)) * 10, "SURVIVAL")
		if car == winner:
			award(car, WIN_CASH, "WINNER")


func _on_impact(victim: DerbyCar, by: DerbyCar, amount: float) -> void:
	if by == null or not by.alive or not cash.has(by):
		return
	biggest_hit[by] = maxf(biggest_hit[by], amount)
	if amount < HIT_MIN:
		return
	# Both cars in a crash report it, and a crash can register over a few
	# frames: pay only the first hit on the same victim in a short window.
	var key := "%d>%d" % [by.get_instance_id(), victim.get_instance_id()]
	if _clock - float(_last_hit.get(key, -10.0)) < HIT_GAP:
		return
	_last_hit[key] = _clock
	var paid := int(roundf(amount * CASH_PER_DAMAGE / 10.0)) * 10
	award(by, paid, "MEGA HIT" if amount >= MEGA_HIT else "BIG HIT")


func _on_eliminated(car: DerbyCar, reason: String, by: DerbyCar) -> void:
	_air[car] = -1.0
	if by and by != car and by.alive:
		award(by, KNOCKOUT_CASH, "WRECKED" if reason == "wrecked" else "KNOCKOUT")


func _physics_process(delta: float) -> void:
	_clock += delta
	for car in cars:
		if not is_instance_valid(car) or not car.alive or not car.controls_enabled:
			_air[car] = -1.0
			continue
		var air: float = _air[car]
		if not car.is_on_ground():
			if air < 0.0:
				air = 0.0
				# Launched by a hop that just fired?
				_air_from_hop[car] = car.hop_cooldown > DerbyCar.HOP_COOLDOWN - 0.25
			# Sliding along on its side or roof isn't flying: start again.
			for body in car.get_colliding_bodies():
				if not body is DerbyCar:
					air = 0.0
					_air_from_hop[car] = false
					break
			_air[car] = air + delta
			continue
		if air >= 0.0:
			_air[car] = -1.0
			var counted: float = air - (HOP_AIR * car.hop_multiplier if _air_from_hop.get(car, false) else 0.0)
			if counted >= AIR_MIN and car.global_basis.y.y > UPRIGHT:
				award(car, maxi(int(roundf(counted * AIR_CASH_PER_SECOND / 10.0)) * 10, 150), "AIRTIME %.1fs" % air)
