extends Node3D
class_name BlizzardAreaDecal
## 技能地面范围圈（Present）：Godot Decal 投影到地形层，避免 PlaneMesh 与坡地/悬崖穿帮。
## 用于暴风雪瞄准/引导圈、群体传送落点标记等。

const TEX_REL := "ReplaceableTextures/Selection/SpellAreaOfEffect.png"
## 投影盒高度（Godot 单位）：越大越能盖住坡度；过大可能投到邻接无关面。
const PROJECTION_DEPTH := 4.0
## 与建筑 UberSplat 一致：贴花绕 Y 转 90°，对齐水平投影。
const YAW_LOCAL := PI * 0.5
const DEFAULT_COLOR := Color(0.45, 0.78, 1.0, 0.72)

var _age: float = 0.0
## <=0：预览模式，不自动销毁（由 Director 清理）。
var _lifetime: float = 0.0
var _radius_wc3: float = 200.0
var _color: Color = DEFAULT_COLOR
var _decal: Decal = null


static func spawn(
	parent: Node,
	center_wc3: Vector2,
	radius_wc3: float,
	lifetime_sec: float,
	heightfield: Wc3Heightfield = null,
	color: Color = DEFAULT_COLOR,
) -> BlizzardAreaDecal:
	if parent == null or center_wc3 == Vector2.INF:
		return null
	var fx := BlizzardAreaDecal.new()
	fx.name = "SpellAreaDecal"
	fx._radius_wc3 = maxf(radius_wc3, 1.0)
	fx._lifetime = lifetime_sec
	fx._color = color
	parent.add_child(fx)
	fx._setup(center_wc3, heightfield)
	return fx


## 瞄准预览：lifetime<=0 不自动消失。
static func spawn_preview(
	parent: Node,
	center_wc3: Vector2,
	radius_wc3: float,
	heightfield: Wc3Heightfield = null,
	color: Color = DEFAULT_COLOR,
) -> BlizzardAreaDecal:
	return spawn(parent, center_wc3, radius_wc3, 0.0, heightfield, color)


func reposition(
	center_wc3: Vector2, radius_wc3: float, heightfield: Wc3Heightfield = null
) -> void:
	if center_wc3 == Vector2.INF:
		return
	_radius_wc3 = maxf(radius_wc3, 1.0)
	_apply_size()
	_place(center_wc3, heightfield)


func set_tint(color: Color) -> void:
	_color = color
	if _decal != null:
		_decal.modulate = _color


func _setup(center_wc3: Vector2, heightfield: Wc3Heightfield) -> void:
	_age = 0.0
	_decal = Decal.new()
	_decal.name = "Decal"
	var tex: Texture2D = RuntimeAssets.load_converted_texture(TEX_REL)
	if tex != null:
		_decal.texture_albedo = tex
	_decal.modulate = _color
	_decal.albedo_mix = 0.9
	_decal.cull_mask = Wc3Coords.RENDER_LAYER_TERRAIN
	_decal.rotation.y = YAW_LOCAL
	add_child(_decal)
	_apply_size()
	_place(center_wc3, heightfield)
	set_process(true)


func _apply_size() -> void:
	if _decal == null:
		return
	var diam_g: float = maxf(_radius_wc3 * 2.0 * Wc3Coords.WORLD_SCALE, 0.05)
	_decal.size = Vector3(diam_g, PROJECTION_DEPTH, diam_g)


func _place(center_wc3: Vector2, heightfield: Wc3Heightfield) -> void:
	var z: float = 0.0
	if heightfield != null and heightfield.is_valid():
		z = heightfield.interpolated_height(center_wc3.x, center_wc3.y)
	## 投影盒中心抬到地表上方半深度，上下都能盖住起伏。
	var foot := Wc3Coords.wc3_xy_to_godot(center_wc3.x, center_wc3.y, z)
	global_position = foot + Vector3(0.0, PROJECTION_DEPTH * 0.5, 0.0)


func _process(delta: float) -> void:
	_age += delta
	if _decal != null:
		var pulse: float = 0.72 + 0.18 * sin(_age * 3.4)
		var c := _color
		c.a = clampf(_color.a * pulse, 0.18, 1.0)
		_decal.modulate = c
	if _lifetime <= 0.0:
		return
	if _age >= _lifetime:
		queue_free()
