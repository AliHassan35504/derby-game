class_name SkidMarks
extends MultiMeshInstance3D
## Dark tyre marks left on the road where wheels slide. One per map, shared
## by every car: marks are small quads in a ring buffer, so the oldest fade
## out of existence once the buffer is full.

const GROUP := &"skid_marks"
const MAX_MARKS := 3000
## Road length each mark covers (m).
const STEP := 0.3

var _next := 0


static func find(node: Node) -> SkidMarks:
	return node.get_tree().get_first_node_in_group(GROUP) as SkidMarks if node.is_inside_tree() else null


func _init() -> void:
	name = "SkidMarks"
	add_to_group(GROUP)
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	# Lay the quad flat: its normal points up the local Y axis.
	quad.orientation = PlaneMesh.FACE_Y
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.03, 0.03, 0.03, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = 0
	multimesh = mm


## Lays one mark from `from` to `to` on a surface with the given normal.
func add_mark(from: Vector3, to: Vector3, normal: Vector3, width: float, strength: float) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.01:
		return
	var up := normal.normalized()
	var forward := (along - up * along.dot(up)).normalized()
	if forward.length() < 0.5:
		return
	var side := up.cross(forward).normalized()
	var basis := Basis(side * width, up, forward * length)
	var origin := (from + to) * 0.5 + up * 0.03
	multimesh.set_instance_transform(_next, Transform3D(basis, origin))
	multimesh.set_instance_color(_next, Color(1, 1, 1, clampf(strength, 0.2, 1.0)))
	_next = (_next + 1) % MAX_MARKS
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _next if _next > 0 else MAX_MARKS)
