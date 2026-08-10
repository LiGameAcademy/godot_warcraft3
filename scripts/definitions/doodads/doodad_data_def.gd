class_name DoodadDataDef
extends Resource

## Doodads/Doodads.slk 一行定义。
##
## 职责：装饰物（不可破坏 Props / 植物 / 水面装饰等）静态数据：
## 模型路径、缩放、放置规则、路径占位、小地图色、变体顶点染色。
## 注意：可破坏的树/岩石等在 Units/DestructableData，不在本表。

const TABLE_NAME := "Doodads"
const SLK_REL_PATH := "Doodads/Doodads.json"
const PRIMARY_KEY := "doodID"

@export var dood_id: String = "" ## 主键（四字符 doodID，如 APms）
@export var category: String = "" ## 编辑器分类字母：O=道具 Props，E=环境/植物，S=结构，W=水，C/Z=特殊等
@export var tilesets: String = "" ## 可用地形集（逗号分隔字母；* = 全部）
@export var tileset_specific: bool = false ## 是否仅特定地形集可用
@export var file: String = "" ## 模型路径（无扩展名；相对 Doodads/…）
@export var comment: String = "" ## 人类可读备注（编辑器注释名）
@export var name_key: String = "" ## 显示名字符串键（WESTRING_DOOD_*）
@export var dood_class: String = "" ## 装饰物子类（doodClass；常为 _）
@export var sound_loop: String = "" ## 循环环境音效名（空/_ = 无）
@export var sel_size: float = 0.0 ## 选中尺寸（0 = 用模型默认）
@export var def_scale: float = 1.0 ## 默认缩放
@export var min_scale: float = 0.0 ## 最小缩放
@export var max_scale: float = 0.0 ## 最大缩放
@export var can_place_rand_scale: bool = false ## 放置时是否在 [min,max] 随机缩放
@export var use_click_helper: bool = false ## 是否使用点击辅助碰撞体
@export var ignore_model_click: bool = false ## 是否忽略模型网格点击（只点辅助体）
@export var max_pitch: float = 0.0 ## 最大俯仰角（“-” 解析为 0）
@export var max_roll: float = 0.0 ## 最大侧倾角（“-” 解析为 0）
@export var vis_radius: float = 0.0 ## 可见/裁剪相关半径（Vis Radius）
@export var walkable: bool = false ## 顶部是否可行走
@export var num_var: int = 0 ## 模型变体数量（1–10，对应 vert 染色槽）
@export var on_cliffs: bool = false ## 可否放在悬崖上
@export var on_water: bool = false ## 可否放在水上
@export var floats: bool = false ## 是否漂浮在水面
@export var shadow: bool = false ## 是否投射/显示阴影
@export var show_in_fog: bool = false ## 迷雾中是否仍可见轮廓
@export var anim_in_fog: bool = false ## 迷雾中是否继续播放动画
@export var fixed_rot: float = -1.0 ## 固定朝向角（度；-1 = 可自由旋转）
@export var path_tex: String = "" ## 路径占位图（none / PathTextures/…）
@export var show_in_mm: bool = false ## 是否显示在小地图
@export var use_mm_color: bool = false ## 是否使用自定义小地图色
@export var mm_red: int = 0 ## 小地图色 R（0–255）
@export var mm_green: int = 0 ## 小地图色 G
@export var mm_blue: int = 0 ## 小地图色 B
## 变体 1–10 的顶点染色（RGB）。索引 0 → 变体1（vertR01/G01/B01），最多 10 项。
@export var vert_colors: Array[Color] = []
@export var user_list: bool = false ## 是否出现在用户自定义列表
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记
@export var version: int = 0 ## 数据版本标记

## 显示名：优先 comment，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else dood_id


## 取变体染色；越界回退白色。
func vert_color_at(variant_index: int) -> Color:
	if variant_index < 0 or variant_index >= vert_colors.size():
		return Color.WHITE
	return vert_colors[variant_index]


static func from_slk_record(rec: Dictionary) -> DoodadDataDef:
	var d := DoodadDataDef.new()
	d.dood_id = str(rec.get("doodID", "")).strip_edges()
	d.category = str(rec.get("category", "")).strip_edges()
	d.tilesets = str(rec.get("tilesets", "")).strip_edges()
	d.tileset_specific = _truthy(rec.get("tilesetSpecific", 0))
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.name_key = str(rec.get("Name", "")).strip_edges()
	d.dood_class = _blank_to_empty(str(rec.get("doodClass", "")).strip_edges())
	d.sound_loop = _blank_to_empty(str(rec.get("soundLoop", "")).strip_edges())
	d.sel_size = _as_float(rec.get("selSize", 0.0))
	d.def_scale = _as_float(rec.get("defScale", 1.0), 1.0)
	d.min_scale = _as_float(rec.get("minScale", 0.0))
	d.max_scale = _as_float(rec.get("maxScale", 0.0))
	d.can_place_rand_scale = _truthy(rec.get("canPlaceRandScale", 0))
	d.use_click_helper = _truthy(rec.get("useClickHelper", 0))
	d.ignore_model_click = _truthy(rec.get("ignoreModelClick", 0))
	d.max_pitch = _as_float(rec.get("maxPitch", 0.0))
	d.max_roll = _as_float(rec.get("maxRoll", 0.0))
	d.vis_radius = _as_float(rec.get("visRadius", 0.0))
	d.walkable = _truthy(rec.get("walkable", 0))
	d.num_var = int(rec.get("numVar", 0))
	d.on_cliffs = _truthy(rec.get("onCliffs", 0))
	d.on_water = _truthy(rec.get("onWater", 0))
	d.floats = _truthy(rec.get("floats", 0))
	d.shadow = _truthy(rec.get("shadow", 0))
	d.show_in_fog = _truthy(rec.get("showInFog", 0))
	d.anim_in_fog = _truthy(rec.get("animInFog", 0))
	d.fixed_rot = _as_float(rec.get("fixedRot", -1.0), -1.0)
	d.path_tex = str(rec.get("pathTex", "")).replace("\\", "/").strip_edges()
	d.show_in_mm = _truthy(rec.get("showInMM", 0))
	d.use_mm_color = _truthy(rec.get("useMMColor", 0))
	d.mm_red = int(rec.get("MMRed", 0))
	d.mm_green = int(rec.get("MMGreen", 0))
	d.mm_blue = int(rec.get("MMBlue", 0))
	d.vert_colors = _parse_vert_colors(rec)
	d.user_list = _truthy(rec.get("UserList", 0))
	d.in_beta = _truthy(rec.get("InBeta", 0))
	d.version = int(rec.get("version", 0))
	return d


static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("DoodadDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)


static func _truthy(v: Variant) -> bool:
	return int(v) != 0


static func _blank_to_empty(s: String) -> String:
	return "" if s.is_empty() or s == "_" else s


static func _as_float(v: Variant, default: float = 0.0) -> float:
	var s := str(v).strip_edges()
	if s.is_empty() or s == "-" or s == "_":
		return default
	return float(s)


static func _parse_vert_colors(rec: Dictionary) -> Array[Color]:
	var out: Array[Color] = []
	for i in range(1, 11):
		var n := str(i).pad_zeros(2)
		var r := int(rec.get("vertR" + n, 255))
		var g := int(rec.get("vertG" + n, 255))
		var b := int(rec.get("vertB" + n, 255))
		out.append(Color(r / 255.0, g / 255.0, b / 255.0))
	return out
