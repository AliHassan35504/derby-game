class_name ChaseCamera
extends Camera3D
## Third-person camera that follows behind a car. When its car is out, it
## spectates whichever car is still alive.

@export var distance := 9.0
@export var height := 3.8
@export var smoothing := 6.0

var target: DerbyCar


func _physics_process(delta: float) -> void:
	if target == null:
		return
	var forward := target.get_forward()
	forward.y = 0.0
	if forward.length() < 0.1:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	var desired := target.global_position - forward * distance + Vector3.UP * height
	global_position = global_position.lerp(desired, clampf(smoothing * delta, 0.0, 1.0))
	var look_at_point := target.global_position + Vector3.UP * 1.0
	if global_position.distance_to(look_at_point) > 0.5:
		look_at(look_at_point, Vector3.UP)


func snap_to_target() -> void:
	if target == null:
		return
	var forward := target.get_forward()
	global_position = target.global_position - forward * distance + Vector3.UP * height
	look_at(target.global_position + Vector3.UP, Vector3.UP)
