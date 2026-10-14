class_name Career
extends RefCounted
## The player's career totals, saved to user://profile.cfg between runs:
## stunt cash earned, rounds played and won, knockouts, longest survival in
## a round and the hardest hit dealt. The title menu's Career screen shows
## them.

const DEFAULT_PATH := "user://profile.cfg"

## Tests point this somewhere else.
static var path := DEFAULT_PATH
static var total_cash := 0
static var rounds := 0
static var wins := 0
static var knockouts := 0
static var best_survival := 0.0
static var biggest_hit := 0.0
static var _loaded := false


static func load_profile() -> void:
	_loaded = true
	reset()
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	total_cash = maxi(int(cfg.get_value("career", "total_cash", 0)), 0)
	rounds = maxi(int(cfg.get_value("career", "rounds", 0)), 0)
	wins = clampi(int(cfg.get_value("career", "wins", 0)), 0, rounds)
	knockouts = maxi(int(cfg.get_value("career", "knockouts", 0)), 0)
	best_survival = maxf(float(cfg.get_value("career", "best_survival", 0.0)), 0.0)
	biggest_hit = maxf(float(cfg.get_value("career", "biggest_hit", 0.0)), 0.0)


static func save_profile() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("career", "total_cash", total_cash)
	cfg.set_value("career", "rounds", rounds)
	cfg.set_value("career", "wins", wins)
	cfg.set_value("career", "knockouts", knockouts)
	cfg.set_value("career", "best_survival", best_survival)
	cfg.set_value("career", "biggest_hit", biggest_hit)
	cfg.save(path)


static func reset() -> void:
	total_cash = 0
	rounds = 0
	wins = 0
	knockouts = 0
	best_survival = 0.0
	biggest_hit = 0.0


static func ensure_loaded() -> void:
	if not _loaded:
		load_profile()


## Adds one finished round and saves.
static func record_round(cash: int, won: bool, round_knockouts: int, survived: float, hit: float) -> void:
	ensure_loaded()
	total_cash += maxi(cash, 0)
	rounds += 1
	if won:
		wins += 1
	knockouts += maxi(round_knockouts, 0)
	best_survival = maxf(best_survival, survived)
	biggest_hit = maxf(biggest_hit, hit)
	save_profile()


## Label / value rows for the Career screen.
static func rows() -> Array:
	ensure_loaded()
	var rate := "–" if rounds == 0 else "%d%%" % roundi(100.0 * wins / rounds)
	return [
		["Stunt cash", money(total_cash)],
		["Rounds played", str(rounds)],
		["Wins", "%d  (%s)" % [wins, rate]],
		["Knockouts", str(knockouts)],
		["Longest survival", "%d:%02d" % [int(best_survival) / 60, int(best_survival) % 60]],
		["Biggest hit", "%d damage" % roundi(biggest_hit)],
	]


## 12345 -> "$12,345".
static func money(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-$" if amount < 0 else "$") + digits + out
