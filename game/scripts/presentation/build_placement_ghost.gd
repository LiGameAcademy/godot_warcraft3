class_name BuildPlacementGhost
extends Node3D

## 建造预览幽灵：跟随鼠标光标，按 footprint 渲染矩形 + 法线方向。
## 颜色 = 合法/非法；提供 set_building(id) / set_position_wc3(x, y) / set_valid(ok)。
##
## 为什么独立 Node3D 而非 InstanceMesh：ECHO 地图开图就不会重 draw；MeshInstance + Shader
## 即可。footprint 框用 MeshInstance3D + Material（双面 BoxFlat 平铺）。
## 顶层 Node3D 而不是 BaseMaterial3D 更新即可。

const COLOR_OK := Color(0.20, 1.00, 0.35, 0.55)
const COLOR_BAD := Color(1.00, 0.20, 0.20, 0.55)
const Y_BIAS := 0.05 ## 浮在地表一点点，避免 Z-fighting

var _mesh: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _box_size: Vector2 = Vector2(128.0, 128.0) ## wc3 中心到边长
var _is_valid: bool = true


func _ready() -> void:
	top_level = true
	_mesh = MeshInstance3D.new()
	_mesh.name = "GhostQuad"
	_mesh.top_level = true
	add_child(_mesh)
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.albedo_color = COLOR_OK
	_mat.no_depth_test = true
	_mesh.set_surface_override_material(0, _mat)
	_ensure_quad()


## 设置建筑 footprint（wc3 边长）。0 → 最小 32x32。
func set_building(building_id: String) -> void:
	var fp: Vector2i = PlacementRules.get_footprint(building_id)
	if fp.x <= 0 or fp.y <= 0:
		_box_size = Vector2(32.0, 32.0)
	else:
		_box_size = Vector2(float(fp.x) * 32.0, float(fp.y) * 32.0)
	_ensure_quad()


## 设置中心 wc3_xy + 当前地表 y。
func set_position_wc3(wc3_x: float, wc3_y: float, terrain_y: float) -> void:
	var gp := Wc3Coords.wc3_xy_to_godot(wc3_x, wc3_y, terrain_y)
	gp.y += Y_BIAS
	global_position = gp
	_ensure_quad()


## 合法 / 非法配色。
func set_valid(ok: bool) -> void:
	if _is_valid == ok:
		return
	_is_valid = ok
	if _mat != null:
		_mat.albedo_color = COLOR_BAD if not ok else COLOR_OK


## 隐藏显示（按 Esc 退出建造瞄准时调用）。
func set_visible_preview(v: bool) -> void:
	visible = v


func _ensure_quad() -> void:
	if _mesh == null:
		return
	# wc3 → godot: 1 pathing cell = 32 wc3 = 1.0 godot (Wc3Coords.WORLD_SCALE = 32)
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var sx := _box_size.x * inv
	var sz := _box_size.y * inv
	# QuadMesh：以本地 XZ 平面铺开
	var qm := QuadMesh.new()
	qm.size = Vector2(sx, sz)
	# QuadMesh 立在 XY 平面；绕 X 旋转 -90° 摊到 XZ
	_mesh.mesh = qm
	_mesh.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
