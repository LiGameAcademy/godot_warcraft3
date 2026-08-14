class_name PlacementGhost
extends Node3D

## F2 建造 ghost：半透明 Box 标记 footprint + 建筑名 Label。
## 跟随鼠标；绿（合法）/红（非法）。
## commit() → 触发 commit_requested(building_id, site_wc3)；
## cancel() → 触发 cancel_requested。
##
## F2-4 简化：Box footprint 视觉，不接 GLB。
## 锦上添花：接 GLB + 真正建筑模型 + 全材质半透明 → 后置。

signal commit_requested(building_id: String, site_wc3: Vector2)
signal cancel_requested

const BOX_HEIGHT_GODOT := 0.35
const LABEL_OFFSET_GODOT := 0.25
const LEGAL_COLOR := Color(0.20, 0.85, 0.30, 0.50)
const ILLEGAL_COLOR := Color(0.85, 0.20, 0.20, 0.50)

var _building_id: String = ""
var _footprint: Vector2i = Vector2i.ZERO
var _box: MeshInstance3D = null
var _mat: StandardMaterial3D = null
var _label: Label3D = null
var _can_build: bool = true


func _ready() -> void:
	pass


func setup(building_id: String) -> void:
	_building_id = building_id
	_footprint = PlacementRules.get_footprint(building_id)
	_build_visual()


## 外部刷新位置 + 合法性颜色。
## wc3_xy 为中心；高度由调用方可选传入 Godot Y（默认 0）。
func update_position(wc3_xy: Vector2, can_build: bool, terrain_y_godot: float = 0.0) -> void:
	var godot_pos: Vector3 = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, 0.0)
	godot_pos.y = terrain_y_godot
	global_position = godot_pos
	if can_build != _can_build:
		_can_build = can_build
		_apply_color()


## 当前是否合法（最后一次 update 的 can_build）。
func is_legal() -> bool:
	return _can_build


func commit() -> void:
	commit_requested.emit(_building_id, Wc3Coords.godot_to_wc3_xy(global_position))


func cancel() -> void:
	cancel_requested.emit()


func _build_visual() -> void:
	# footprint 格 → Godot 尺寸（× PATHING_CELL × WORLD_SCALE）
	var w: float = float(_footprint.x) * Wc3Coords.PATHING_CELL * Wc3Coords.WORLD_SCALE
	var d: float = float(_footprint.y) * Wc3Coords.PATHING_CELL * Wc3Coords.WORLD_SCALE
	if w <= 0.0:
		w = Wc3Coords.PATHING_CELL * Wc3Coords.WORLD_SCALE
	if d <= 0.0:
		d = Wc3Coords.PATHING_CELL * Wc3Coords.WORLD_SCALE
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, BOX_HEIGHT_GODOT, d)
	_box = MeshInstance3D.new()
	_box.mesh = mesh
	_mat = StandardMaterial3D.new()
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = LEGAL_COLOR
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box.material_override = _mat
	add_child(_box)

	_label = Label3D.new()
	_label.text = _display_name()
	_label.font_size = 64
	_label.pixel_size = 0.002
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, BOX_HEIGHT_GODOT * 0.5 + LABEL_OFFSET_GODOT, 0.0)
	_label.modulate = LEGAL_COLOR
	_label.no_depth_test = true
	add_child(_label)


func _apply_color() -> void:
	var c: Color = LEGAL_COLOR if _can_build else ILLEGAL_COLOR
	if _mat != null:
		_mat.albedo_color = c
	if _label != null:
		_label.modulate = c


func _display_name() -> String:
	# 简化：id + 造价（hhou 80g / hbar 140g...）。F2-7 / 锦上添花再读 WESTRING。
	var g: int = BuildingCatalog.get_gold_cost(_building_id)
	var l: int = BuildingCatalog.get_lumber_cost(_building_id)
	return "%s  %dg/%dl" % [_building_id, g, l]
