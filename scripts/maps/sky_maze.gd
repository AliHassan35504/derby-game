class_name SkyMazeMap
extends DerbyMap
## A maze of narrow pale ramps on black stilts above the clouds. Two long
## diagonal bridges cross the middle, one high above the hub and one below it.

const SPACING := 44.0


func build() -> void:
	map_name = "Sky Maze"
	car_type = "sports"
	rule_text = "Thin air: nitro refills twice as fast"
	kill_height = 12.0
	road_width = 4.2
	stilt_bottom = -4.0
	stilt_clear_radius = 10.0
	nitro_refill_multiplier = 2.0

	make_environment(Color(0.16, 0.36, 0.78), Color(0.82, 0.88, 0.96), Color(0.9, 0.93, 0.97),
			Color(0.85, 0.9, 0.97), 0.001, Vector3(-30, -140, 0), 1.5)
	add_cloud_layer(0.0)

	var stilt := StandardMaterial3D.new()
	stilt.albedo_color = Color(0.06, 0.06, 0.07)
	stilt.metallic = 0.7
	stilt.roughness = 0.4
	set_materials(make_plank_material(Color(0.8, 0.78, 0.72), Color(0.55, 0.52, 0.47), 0.6), stilt)

	var heights := [
		[62.0, 50.0, 38.0],
		[50.0, 46.0, 50.0],
		[38.0, 50.0, 62.0],
	]
	for gx in 3:
		for gz in 3:
			var size := Vector2(13, 13) if gx == 1 and gz == 1 else Vector2(11, 11)
			add_pad(_id(gx, gz), Vector3((gx - 1) * SPACING, heights[gx][gz], (gz - 1) * SPACING), size)
	for gx in 3:
		for gz in 3:
			if gx < 2:
				add_road(_id(gx, gz), _id(gx + 1, gz))
			if gz < 2:
				add_road(_id(gx, gz), _id(gx, gz + 1))
	# High bridge over the hub, and a low one passing underneath it.
	add_road(_id(0, 0), _id(2, 2))
	add_road(_id(2, 0), _id(0, 2))

	add_spawn(_id(1, 0), _id(1, 1))
	add_spawn(_id(1, 2), _id(1, 1))
	add_spawn(_id(0, 1), _id(1, 1))
	add_spawn(_id(2, 1), _id(1, 1))
	add_spawn(_id(2, 0), _id(2, 1))
	add_spawn(_id(0, 2), _id(0, 1))
	add_spawn(_id(0, 0), _id(1, 0))
	add_spawn(_id(2, 2), _id(1, 2))


func _id(gx: int, gz: int) -> String:
	return "%d%d" % [gx, gz]
