class_name Wc3RibbonEmitter
extends MeshInstance3D
## WC3 RibbonEmitter 运行时条带：按世界路径环形缓冲建 strip。
## 飞弹飞行时留下青蓝拖尾；编辑器内 Birth 平移轨也会拉出短带。
## 层：presentation（`scripts/presentation/wc3_model/`）。

const META_ACTIVE_SEQS := "wc3_ribbon_active_sequences"
const META_ALWAYS_ON := "wc3_ribbon_always_on"

@export var ribbon_emitting: bool = false:
	set(v):
		ribbon_emitting = v
		if not v:
			# 停发后仍老化淡出，不清空
			pass

var life_span: float = 0.35
var emission_rate: float = 40.0
var half_height: float = 30.0
var ribbon_color: Color = Color(0.03, 0.46, 1.0, 0.9)

var _sample_left: float = 0.0
var _points: Array[Dictionary] = [] # {pos: Vector3, age: float}
var _mat: StandardMaterial3D


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material_override == null and _mat != null:
		material_override = _mat


func configure(
	p_life: float,
	p_rate: float,
	height_above: float,
	height_below: float,
	color: Color,
	tex: Texture2D
) -> void:
	life_span = maxf(0.05, p_life)
	emission_rate = maxf(1.0, p_rate)
	half_height = maxf(0.5, (height_above + height_below) * 0.5)
	ribbon_color = color
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.vertex_color_use_as_albedo = true
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_mat.albedo_color = Color.WHITE
	if tex != null:
		_mat.albedo_texture = tex
	_mat.resource_local_to_scene = true
	material_override = _mat


func set_active_for_sequence(seq_key: String) -> void:
	if bool(get_meta(META_ALWAYS_ON, false)):
		ribbon_emitting = true
		return
	var seqs: PackedStringArray = get_meta(META_ACTIVE_SEQS, PackedStringArray()) as PackedStringArray
	ribbon_emitting = _seqs_match(seqs, seq_key)


func _process(delta: float) -> void:
	var interval := 1.0 / emission_rate
	if ribbon_emitting:
		_sample_left -= delta
		while _sample_left <= 0.0:
			_points.append({"pos": global_position, "age": 0.0})
			_sample_left += interval
			if _sample_left > 0.0:
				break
	else:
		_sample_left = 0.0

	var alive: Array[Dictionary] = []
	for pt in _points:
		var age := float(pt["age"]) + delta
		if age <= life_span:
			alive.append({"pos": pt["pos"], "age": age})
	_points = alive

	# 静止或首点：沿局部前进补极短假点（须用世界尺度，勿用 MDX 厘米当米）
	if ribbon_emitting and _points.size() == 1:
		var p0: Vector3 = _points[0]["pos"]
		var tip := maxf(_world_half_height() * 0.2, 0.08)
		var forward := -global_transform.basis.z
		if forward.length_squared() < 1e-8:
			forward = global_transform.basis.y
		_points.append({"pos": p0 + forward.normalized() * tip, "age": 0.0})

	_rebuild_mesh()


## MDX HeightAbove/Below 与 pe2 一样落在 MODEL_SCALE 子树里；
## 路径点是世界坐标，半宽必须 × 全局缩放，否则会变成「铺满战场的大条带」。
func _world_half_height() -> float:
	var s := global_transform.basis.get_scale()
	var scale_avg := (absf(s.x) + absf(s.y) + absf(s.z)) / 3.0
	return half_height * maxf(scale_avg, 1e-6)


func _rebuild_mesh() -> void:
	if _points.size() < 2:
		mesh = null
		return
	var world_half := _world_half_height()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nseg := _points.size() - 1
	for i in range(nseg):
		var a: Dictionary = _points[i]
		var b: Dictionary = _points[i + 1]
		var pa: Vector3 = a["pos"]
		var pb: Vector3 = b["pos"]
		var tangent := pb - pa
		if tangent.length_squared() < 1e-8:
			continue
		tangent = tangent.normalized()
		var side := Vector3.UP.cross(tangent)
		if side.length_squared() < 1e-8:
			side = Vector3.RIGHT.cross(tangent)
		side = side.normalized() * world_half
		var fa := clampf(1.0 - float(a["age"]) / life_span, 0.0, 1.0)
		var fb := clampf(1.0 - float(b["age"]) / life_span, 0.0, 1.0)
		# 尾端更透明，避免整条等亮像「全局光带」
		var ca := Color(ribbon_color.r, ribbon_color.g, ribbon_color.b, ribbon_color.a * fa * fa)
		var cb := Color(ribbon_color.r, ribbon_color.g, ribbon_color.b, ribbon_color.a * fb * fb)
		var u0 := float(i) / float(maxi(nseg, 1))
		var u1 := float(i + 1) / float(maxi(nseg, 1))
		# 变到局部（MeshInstance 用 local verts）
		var inv := global_transform.affine_inverse()
		var a_l := inv * (pa - side)
		var a_r := inv * (pa + side)
		var b_l := inv * (pb - side)
		var b_r := inv * (pb + side)
		_add_tri(st, a_l, a_r, b_r, Vector2(u0, 0), Vector2(u0, 1), Vector2(u1, 1), ca, ca, cb)
		_add_tri(st, a_l, b_r, b_l, Vector2(u0, 0), Vector2(u1, 1), Vector2(u1, 0), ca, cb, cb)
	mesh = st.commit()
	if mesh != null:
		mesh.resource_local_to_scene = true


func _add_tri(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	uv0: Vector2,
	uv1: Vector2,
	uv2: Vector2,
	c0: Color,
	c1: Color,
	c2: Color
) -> void:
	st.set_color(c0)
	st.set_uv(uv0)
	st.add_vertex(p0)
	st.set_color(c1)
	st.set_uv(uv1)
	st.add_vertex(p1)
	st.set_color(c2)
	st.set_uv(uv2)
	st.add_vertex(p2)


static func _seqs_match(seqs: PackedStringArray, want_key: String) -> bool:
	if seqs.is_empty():
		return false
	var want := want_key.strip_edges().to_lower().replace("_", " ")
	for s in seqs:
		var t := str(s).strip_edges().to_lower().replace("_", " ")
		if t == want or t.begins_with(want) or want.begins_with(t):
			return true
		# Birth / Birth-1
		if t.get_slice(" ", 0) == want.get_slice(" ", 0):
			return true
	return false
