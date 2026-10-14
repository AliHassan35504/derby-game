class_name RamBoost
extends Node3D
## The Ram pickup's effect on one car: for a few seconds its hits on other
## cars deal double damage and hits it takes do half, and it glows in a
## pulsing orange shell. Lives as a child of the car; picking up another Ram
## while one is running just resets the clock.

const DEALT := 2.0
const TAKEN := 0.5
const DURATION := 8.0
const COLOR := Color(1.0, 0.42, 0.12)

var car: DerbyCar
var time_left := DURATION

var _shell_mat: ShaderMaterial
var _light: OmniLight3D
var _clock := 0.0


## Gives a car the boost (or tops it up) and returns the effect node.
static func give(target: DerbyCar, seconds := DURATION) -> RamBoost:
	var boost := active_on(target)
	if boost == null:
		boost = RamBoost.new()
		boost.name = "RamBoost"
		target.add_child(boost)
	boost.time_left = seconds
	return boost


static func active_on(target: DerbyCar) -> RamBoost:
	for child in target.get_children():
		if child is RamBoost and not child.is_queued_for_deletion():
			return child
	return null


func _ready() -> void:
	car = get_parent() as DerbyCar
	car.damage_dealt_multiplier = DEALT
	car.damage_taken_multiplier = TAKEN
	var size: Vector3 = car.stats["size"]
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 24
	sphere.rings = 12
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = load("res://shaders/glow_shell.gdshader")
	_shell_mat.set_shader_parameter("tint", COLOR)
	_shell_mat.set_shader_parameter("power", 2.6)
	sphere.material = _shell_mat
	shell.mesh = sphere
	shell.scale = Vector3(size.x * 1.35, size.y * 1.6, size.z * 1.2)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shell)
	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.omni_range = 8.0
	_light.position.y = size.y * 0.6
	add_child(_light)


func _physics_process(delta: float) -> void:
	time_left -= delta
	_clock += delta
	if time_left <= 0.0 or not car.alive:
		end()
		return
	# Pulse, and flicker in the last two seconds as a warning.
	var pulse := 0.5 + 0.5 * sin(_clock * 9.0)
	var fading := time_left < 2.0 and fmod(time_left, 0.3) < 0.12
	_shell_mat.set_shader_parameter("strength", 0.25 if fading else 0.7 + 0.5 * pulse)
	_light.light_energy = 0.6 if fading else 1.6 + 1.2 * pulse


func end() -> void:
	if is_queued_for_deletion():
		return
	car.damage_dealt_multiplier = 1.0
	car.damage_taken_multiplier = 1.0
	queue_free()
