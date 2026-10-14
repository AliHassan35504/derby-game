class_name Pickup
extends Node3D
## One pickup spot on a pad: a glowing icon that spins and bobs above a ring
## on the deck. PickupManager places these, decides when they are collected
## and applies the effect; this node only knows how to look and how to
## appear and vanish. It sits under the pad's body, so it falls with the pad
## when the map collapses.

enum Kind { REPAIR, NITRO, RAM, SHOCKWAVE }

## Per kind: name shown on the icon and the HUD, a one-line hint, colour.
const INFO := {
	Kind.REPAIR: {"name": "REPAIR", "hint": "+40% health", "color": Color(0.3, 1.0, 0.45)},
	Kind.NITRO: {"name": "NITRO", "hint": "Nitro refilled", "color": Color(0.3, 0.7, 1.0)},
	Kind.RAM: {"name": "RAM", "hint": "Double damage, half taken for 8s", "color": Color(1.0, 0.42, 0.12)},
	Kind.SHOCKWAVE: {"name": "SHOCKWAVE", "hint": "Blasts nearby cars away", "color": Color(0.78, 0.45, 1.0)},
}
const ICON_HEIGHT := 1.7
const SPIN_SPEED := 1.7
const BOB := 0.22
const BEAM_HEIGHT := 8.0

var kind := Kind.REPAIR
## Pad id this pickup sits on (for the bots' detours).
var pad := ""
var active := false
## Seconds until it (re)appears while inactive.
var respawn_in := 0.0
## True once its pad has fallen away; it never comes back.
var retired := false
var times_collected := 0

var _spinner: Node3D
var _icon: Node3D
var _ring: MeshInstance3D
var _pool: MeshInstance3D
var _light: OmniLight3D
var _label: Label3D
var _icon_mat: StandardMaterial3D
var _ring_mat: StandardMaterial3D
var _orb_mat: ShaderMaterial
var _pool_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _clock := 0.0
var _tween: Tween


func _ready() -> void:
	_clock = randf() * TAU
	_icon_mat = StandardMaterial3D.new()
	_icon_mat.metallic = 0.35
	_icon_mat.roughness = 0.25
	_icon_mat.emission_enabled = true
	_icon_mat.emission_energy_multiplier = 1.3
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_orb_mat = ShaderMaterial.new()
	_orb_mat.shader = load("res://shaders/glow_shell.gdshader")
	_pool_mat = StandardMaterial3D.new()
	_pool_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pool_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_pool_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_pool_mat.albedo_texture = _radial_texture()

	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 1.75
	torus.outer_radius = 2.0
	torus.rings = 40
	torus.ring_segments = 6
	torus.material = _ring_mat
	_ring.mesh = torus
	_ring.scale = Vector3(1, 0.25, 1)
	_ring.position.y = 0.06
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)
	_pool = MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2(5.5, 5.5)
	quad.material = _pool_mat
	_pool.mesh = quad
	_pool.position.y = 0.04
	_pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_pool)

	# A faint beam of light so pickups on far pads stand out.
	_beam_mat = StandardMaterial3D.new()
	_beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam_mat.albedo_texture = _beam_texture()
	var beam := MeshInstance3D.new()
	var tube := CylinderMesh.new()
	tube.top_radius = 0.3
	tube.bottom_radius = 0.5
	tube.height = BEAM_HEIGHT
	tube.radial_segments = 16
	tube.cap_top = false
	tube.cap_bottom = false
	tube.material = _beam_mat
	beam.mesh = tube
	# It rises from just above the icon, so it doesn't wash the icon out.
	beam.position.y = ICON_HEIGHT + 1.2 + BEAM_HEIGHT * 0.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)

	_spinner = Node3D.new()
	_spinner.position.y = ICON_HEIGHT
	_spinner.scale = Vector3.ONE * 1.3
	add_child(_spinner)
	var orb := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.95
	sphere.height = 1.9
	sphere.radial_segments = 24
	sphere.rings = 12
	sphere.material = _orb_mat
	orb.mesh = sphere
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_spinner.add_child(orb)

	_light = OmniLight3D.new()
	_light.position.y = ICON_HEIGHT
	_light.omni_range = 7.0
	_light.light_energy = 1.6
	_light.shadow_enabled = false
	add_child(_light)

	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 64
	_label.outline_size = 16
	_label.pixel_size = 0.01
	_label.position.y = ICON_HEIGHT + 1.75
	_label.modulate = Color.WHITE
	_label.outline_modulate = Color(0, 0, 0, 0.85)
	add_child(_label)

	set_kind(kind)
	_set_shown(active)


func set_kind(k: Kind) -> void:
	kind = k
	if _spinner == null:
		return
	var color: Color = INFO[k]["color"]
	_icon_mat.albedo_color = color
	_icon_mat.emission = color
	_ring_mat.albedo_color = Color(color, 0.85)
	_orb_mat.set_shader_parameter("tint", Color(color, 1.0))
	_orb_mat.set_shader_parameter("strength", 0.28)
	_orb_mat.set_shader_parameter("power", 2.8)
	_orb_mat.set_shader_parameter("core", 0.0)
	_pool_mat.albedo_color = Color(color, 0.55)
	_beam_mat.albedo_color = Color(color, 0.45)
	_light.light_color = color
	_label.text = INFO[k]["name"]
	_label.modulate = color.lerp(Color.WHITE, 0.45)
	if _icon:
		_icon.free()
	_icon = _build_icon(k)
	_spinner.add_child(_icon)


## Pops into view, as a new kind if one is given.
func appear(new_kind := -1) -> void:
	if new_kind >= 0:
		set_kind(new_kind)
	active = true
	_set_shown(true)
	_kill_tween()
	scale = Vector3.ONE * 0.05
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Collected: a quick swell and flash, then hidden until respawn.
func vanish(respawn_seconds: float) -> void:
	active = false
	times_collected += 1
	respawn_in = respawn_seconds
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector3.ONE * 1.7, 0.16).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(_set_shown.bind(false))
	_tween.tween_callback(func() -> void: scale = Vector3.ONE)


## Its pad fell: gone for good.
func retire() -> void:
	active = false
	retired = true
	_kill_tween()
	_set_shown(false)


## Where cars have to get to collect it.
func centre() -> Vector3:
	return global_position + Vector3.UP * 1.0


func _process(delta: float) -> void:
	if not visible:
		return
	_clock += delta
	_spinner.rotation.y = _clock * SPIN_SPEED
	_spinner.position.y = ICON_HEIGHT + sin(_clock * 2.2) * BOB
	var pulse := 0.5 + 0.5 * sin(_clock * 3.4)
	_ring.scale = Vector3(1.0 + pulse * 0.08, 0.25, 1.0 + pulse * 0.08)
	_ring_mat.albedo_color.a = 0.55 + 0.4 * pulse
	_light.light_energy = 1.2 + 0.8 * pulse


func _set_shown(shown: bool) -> void:
	visible = shown


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null


func _build_icon(k: Kind) -> Node3D:
	var icon := Node3D.new()
	match k:
		Kind.REPAIR:
			# A chunky first-aid cross.
			_part(icon, _box(Vector3(1.05, 0.36, 0.36)), Vector3.ZERO)
			_part(icon, _box(Vector3(0.36, 1.05, 0.36)), Vector3.ZERO)
		Kind.NITRO:
			# A nitrous bottle with a valve on top, tipped a little.
			var bottle := CylinderMesh.new()
			bottle.top_radius = 0.3
			bottle.bottom_radius = 0.3
			bottle.height = 0.85
			bottle.radial_segments = 16
			var neck := CylinderMesh.new()
			neck.top_radius = 0.1
			neck.bottom_radius = 0.22
			neck.height = 0.22
			neck.radial_segments = 12
			_part(icon, bottle, Vector3(0, -0.08, 0))
			_part(icon, neck, Vector3(0, 0.45, 0))
			_part(icon, _box(Vector3(0.34, 0.1, 0.1)), Vector3(0, 0.6, 0))
			icon.rotation.z = 0.35
		Kind.RAM:
			# Two stacked chevrons: double damage.
			for i in 2:
				var prism := PrismMesh.new()
				prism.size = Vector3(1.0, 0.45, 0.3)
				_part(icon, prism, Vector3(0, -0.22 + i * 0.42, 0))
		Kind.SHOCKWAVE:
			# A core with two crossed rings round it.
			var core := SphereMesh.new()
			core.radius = 0.28
			core.height = 0.56
			_part(icon, core, Vector3.ZERO)
			for angle in [0.6, -0.6]:
				var ring := TorusMesh.new()
				ring.inner_radius = 0.48
				ring.outer_radius = 0.58
				ring.rings = 24
				ring.ring_segments = 6
				var part := _part(icon, ring, Vector3.ZERO)
				part.rotation = Vector3(PI * 0.5, 0, angle)
	return icon


func _part(parent: Node3D, mesh: PrimitiveMesh, pos: Vector3) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	mesh.material = _icon_mat
	m.mesh = mesh
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(m)
	return m


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static var _radial: GradientTexture2D
static var _beam: GradientTexture2D


## Bright at the bottom, gone at the top (cylinder UVs run top to bottom).
static func _beam_texture() -> GradientTexture2D:
	if _beam:
		return _beam
	_beam = GradientTexture2D.new()
	_beam.fill_from = Vector2(0, 0)
	_beam.fill_to = Vector2(0, 1)
	_beam.width = 4
	_beam.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.set_color(1, Color(1, 1, 1, 1))
	_beam.gradient = g
	return _beam


static func _radial_texture() -> GradientTexture2D:
	if _radial:
		return _radial
	_radial = GradientTexture2D.new()
	_radial.fill = GradientTexture2D.FILL_RADIAL
	_radial.fill_from = Vector2(0.5, 0.5)
	_radial.fill_to = Vector2(1.0, 0.5)
	_radial.width = 64
	_radial.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.35))
	_radial.gradient = g
	return _radial
