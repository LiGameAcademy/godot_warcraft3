class_name SelectionRing
extends MeshInstance3D

## 脚底选中环 / 交互闪环 Present。由单位挂载后注入 Selectable / Interactable。

const SEL_CIRCLE_TEX := "ReplaceableTextures/Selection/SelectionCircleMed.png"
const COLOR_OWN := Color(0.15, 1.0, 0.25, 1.0)
const COLOR_NEUTRAL := Color(1.0, 0.92, 0.15, 1.0)
## 略高于地面 UberSplat / 地形，减轻穿插与贴花遮挡（死亡落环用 0.15）。
const Y_BIAS := 0.16
## 悬停环相对选中色的透明度。
const HOVER_ALPHA := 0.42

var _plane: PlaneMesh = null
var _mat: StandardMaterial3D = null
var _flash_tween: Tween = null
## 闪环前的选中外观，便于 flash 结束后还原
var _saved_visible: bool = false
var _saved_color: Color = COLOR_OWN
var _saved_diameter: float = 1.0
var _saved_scale: Vector3 = Vector3.ONE


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ensure_mesh_mat()
	position = Vector3(0.0, Y_BIAS, 0.0)
	if not visible:
		# 默认隐藏，等 Selectable 选中再显示
		pass


func _ensure_mesh_mat() -> void:
	if _plane == null:
		_plane = mesh as PlaneMesh
		if _plane == null:
			_plane = PlaneMesh.new()
			_plane.orientation = PlaneMesh.FACE_Y
			_plane.size = Vector2.ONE
			mesh = _plane
	if _mat == null:
		_mat = material_override as StandardMaterial3D
		if _mat == null:
			_mat = StandardMaterial3D.new()
			_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_mat.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
			_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			_mat.render_priority = 20
			var tex: Texture2D = RuntimeAssets.load_converted_texture(SEL_CIRCLE_TEX)
			if tex != null:
				_mat.albedo_texture = tex
			material_override = _mat


func configure(diameter: float, color: Color, render_priority: int = 20) -> void:
	_ensure_mesh_mat()
	set_diameter(diameter)
	set_ring_color(color)
	_mat.render_priority = render_priority
	scale = Vector3.ONE
	visible = true


func set_diameter(diameter: float) -> void:
	_ensure_mesh_mat()
	var d := maxf(diameter, 0.2)
	_plane.size = Vector2(d, d)


func set_ring_color(color: Color) -> void:
	_ensure_mesh_mat()
	_mat.albedo_color = color


func get_ring_color() -> Color:
	_ensure_mesh_mat()
	return _mat.albedo_color


func get_diameter() -> float:
	_ensure_mesh_mat()
	return _plane.size.x


## 显示为选中环（持久）。
func show_selected(diameter: float, color: Color) -> void:
	_kill_flash_tween()
	configure(diameter, color, 20)


## 悬停预览环（半透明；与选中同贴图，alpha 更低）。
func show_hover(diameter: float, color: Color) -> void:
	_kill_flash_tween()
	var c := color
	c.a = minf(c.a, HOVER_ALPHA)
	configure(diameter, c, 19)


## 取消选中：隐藏，不销毁节点。
func hide_selected() -> void:
	_kill_flash_tween()
	visible = false
	scale = Vector3.ONE


## 交互闪环：同实例上播黄环淡出，结束后回调（由 Interactable 决定是否还原选中）。
func play_interact_flash(
	diameter: float,
	duration: float = 0.65,
	color: Color = COLOR_NEUTRAL,
	on_finished: Callable = Callable()
) -> void:
	_kill_flash_tween()
	_saved_visible = visible
	_saved_color = get_ring_color()
	_saved_diameter = get_diameter()
	_saved_scale = scale
	configure(maxf(diameter, 0.4), color, 21)
	var tree := get_tree()
	if tree == null:
		if on_finished.is_valid():
			on_finished.call()
		return
	_ensure_mesh_mat()
	var dur := maxf(duration, 0.15)
	_flash_tween = tree.create_tween()
	_flash_tween.set_parallel(true)
	var c0 := _mat.albedo_color
	var c1 := Color(c0.r, c0.g, c0.b, 0.0)
	_flash_tween.tween_property(_mat, "albedo_color", c1, dur).set_ease(Tween.EASE_IN)
	_flash_tween.tween_property(self, "scale", Vector3(1.25, 1.0, 1.25), dur).set_ease(Tween.EASE_OUT)
	_flash_tween.chain().tween_callback(func() -> void:
		_flash_tween = null
		scale = _saved_scale
		if on_finished.is_valid():
			on_finished.call()
		elif _saved_visible:
			configure(_saved_diameter, _saved_color, 20)
		else:
			visible = false
	)


func _kill_flash_tween() -> void:
	if _flash_tween != null and is_instance_valid(_flash_tween):
		_flash_tween.kill()
	_flash_tween = null
