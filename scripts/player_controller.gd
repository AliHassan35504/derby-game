class_name PlayerController
extends Node
## Drives the parent car from keyboard or gamepad input.

@onready var car: DerbyCar = get_parent()


func _physics_process(_delta: float) -> void:
	car.throttle_input = Input.get_axis("reverse", "accelerate")
	# Steering right is negative on the car.
	car.steer_input = Input.get_axis("steer_right", "steer_left")
	car.handbrake_input = Input.is_action_pressed("handbrake")
