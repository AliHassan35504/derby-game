class_name BoardwalkMap
extends DerbyMap
## Long single-lane plank ramps on stilts high above the sea, joined by small
## platforms around a central hub with spike props.


func build() -> void:
	map_name = "Boardwalk"
	car_type = "van"
	rule_text = "Touch the sea and you're out"
	kill_height = 1.4
	water_height = 0.0
	road_width = 4.0
	stilt_bottom = -3.0
	stilt_clear_radius = 0.0

	make_environment(Color(0.22, 0.45, 0.82), Color(0.72, 0.82, 0.92), Color(0.1, 0.22, 0.32),
			Color(0.7, 0.8, 0.9), 0.0015, Vector3(-38, 30, 0), 1.35)
	add_ocean(0.0, Color(0.02, 0.11, 0.18), Color(0.07, 0.3, 0.38))

	var stilt := StandardMaterial3D.new()
	stilt.albedo_color = Color(0.3, 0.24, 0.18)
	stilt.roughness = 0.9
	set_materials(make_plank_material(Color(0.78, 0.68, 0.52), Color(0.46, 0.36, 0.25), 0.4), stilt)

	add_pad("hub", Vector3(0, 22, 0), Vector2(15, 15))
	add_pad("n", Vector3(0, 29, -60), Vector2(11, 11))
	add_pad("e", Vector3(60, 15, 0), Vector2(11, 11))
	add_pad("s", Vector3(0, 29, 60), Vector2(11, 11))
	add_pad("w", Vector3(-60, 15, 0), Vector2(11, 11))
	add_pad("ne", Vector3(44, 23, -44), Vector2(10, 10))
	add_pad("se", Vector3(44, 21, 44), Vector2(10, 10))
	add_pad("sw", Vector3(-44, 23, 44), Vector2(10, 10))
	add_pad("nw", Vector3(-44, 21, -44), Vector2(10, 10))

	for spoke in ["n", "e", "s", "w"]:
		add_road("hub", spoke)
	var ring := ["n", "ne", "e", "se", "s", "sw", "w", "nw", "n"]
	for i in ring.size() - 1:
		add_road(ring[i], ring[i + 1])

	# Spikes on the hub, like the props in the reference video.
	var spike_mat := StandardMaterial3D.new()
	spike_mat.albedo_color = Color(0.72, 0.72, 0.7)
	spike_mat.roughness = 0.7
	for corner in [Vector3(4.5, 0, 4.5), Vector3(-4.5, 0, 4.5), Vector3(4.5, 0, -4.5), Vector3(-4.5, 0, -4.5)]:
		var spike := CylinderMesh.new()
		spike.top_radius = 0.0
		spike.bottom_radius = 1.6
		spike.height = 4.0
		spike.radial_segments = 4
		add_obstacle(spike, spike.create_convex_shape(), Vector3(0, 24, 0) + corner, spike_mat, "hub")

	add_spawn("n", "hub")
	add_spawn("e", "hub")
	add_spawn("s", "hub")
	add_spawn("w", "hub")
	add_spawn("ne", "e")
	add_spawn("sw", "w")
	add_spawn("se", "s")
	add_spawn("nw", "n")
