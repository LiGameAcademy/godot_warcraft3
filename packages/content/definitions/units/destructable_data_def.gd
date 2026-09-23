class_name DestructableDataDef
extends Resource

## Units/DestructableData.slk 一行定义。
##
## 职责：可破坏物静态数据（树/岩石/门/围栏等：模型、占位、生命、路径图、修理等）。

const TABLE_NAME := "DestructableData"
const SLK_REL_PATH := "Units/DestructableData.json"
const PRIMARY_KEY := "DestructableID"

@export var destructable_id: String = "" ## 主键（四字符可破坏物 ID）
@export var category: String = "" ## 编辑器分类（树木/岩石/大门…）
@export var tilesets: String = "" ## 可用地形集（* = 全部）
@export var tileset_specific: bool = false ## 是否仅特定地形集
@export var file: String = "" ## 模型路径
@export var lightweight: bool = false ## 轻量模型（简化碰撞/表现）
@export var fat_los: bool = false ## 粗视野遮挡（Fat LOS）
@export var tex_id: int = 0 ## 可替换纹理 ID（Replaceable ID）
@export var tex_file: String = "" ## 可替换纹理文件
@export var comment: String = "" ## 人类可读备注
@export var name_key: String = "" ## 显示名字符串键
@export var editor_suffix: String = "" ## 编辑器名称后缀
@export var dood_class: String = "" ## 装饰物/可破坏物子类
@export var use_click_helper: bool = false ## 是否使用点击辅助体
@export var on_cliffs: bool = false ## 可否放在悬崖上
@export var on_water: bool = false ## 可否放在水上
@export var can_place_dead: bool = false ## 可否以死亡状态放置
@export var walkable: bool = false ## 顶部是否可行走（桥面等）
@export var cliff_height: float = 0.0 ## 关联悬崖高度档
@export var targ_type: String = "" ## 作为攻击目标的分类（tree / debris / wall…）
@export var armor: String = "" ## 护甲/受击音效类型
@export var num_var: int = 0 ## 模型变体数量
@export var hp: int = 0 ## 生命值
@export var occ_h: float = 0.0 ## 遮挡高度（Occlusion Height）
@export var fly_h: float = 0.0 ## 飞行单位通过高度参考
@export var fixed_rot: float = 0.0 ## 固定朝向角（-1 常表示可自由旋转）
@export var sel_size: float = 0.0 ## 选中尺寸
@export var min_scale: float = 0.0 ## 最小缩放
@export var max_scale: float = 0.0 ## 最大缩放
@export var can_place_rand_scale: bool = false ## 放置时是否随机缩放
@export var max_pitch: float = 0.0 ## 最大俯仰
@export var max_roll: float = 0.0 ## 最大侧倾
@export var radius: float = 0.0 ## 碰撞/选择半径
@export var fog_radius: float = 0.0 ## 迷雾相关半径
@export var fog_vis: bool = false ## 是否影响迷雾可见性
@export var path_tex: String = "" ## 存活时路径占位图
@export var path_tex_death: String = "" ## 死亡后路径占位图
@export var death_snd: String = "" ## 死亡音效
@export var shadow: String = "" ## 阴影贴图
@export var color_r: int = 0 ## 染色 R
@export var color_g: int = 0 ## 染色 G
@export var color_b: int = 0 ## 染色 B
@export var show_in_mm: bool = false ## 是否显示在小地图
@export var use_mm_color: bool = false ## 是否使用自定义小地图色
@export var mm_red: int = 0 ## 小地图色 R
@export var mm_green: int = 0 ## 小地图色 G
@export var mm_blue: int = 0 ## 小地图色 B
@export var build_time: int = 0 ## 建造/修复基准时间（可修复物）
@export var repair_time: int = 0 ## 修理时间
@export var gold_rep: int = 0 ## 修理金币消耗
@export var lumber_rep: int = 0 ## 修理木材消耗
@export var user_list: bool = false ## 是否出现在用户自定义列表
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记
@export var version: int = 0 ## 数据版本标记
@export var selectable: bool = false ## 是否可选中
@export var selcircsize: float = 0.0 ## 选中圈大小
@export var portraitmodel: String = "" ## 肖像模型路径

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else destructable_id

static func from_slk_record(rec: Dictionary) -> DestructableDataDef:
	var d := DestructableDataDef.new()
	d.destructable_id = str(rec.get("DestructableID", "")).strip_edges()
	d.category = str(rec.get("category", "")).strip_edges()
	d.tilesets = str(rec.get("tilesets", "")).strip_edges()
	d.tileset_specific = int(rec.get("tilesetSpecific", 0)) != 0
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.lightweight = int(rec.get("lightweight", 0)) != 0
	d.fat_los = int(rec.get("fatLOS", 0)) != 0
	d.tex_id = int(rec.get("texID", 0))
	d.tex_file = str(rec.get("texFile", "")).replace("\\", "/").strip_edges()
	d.comment = str(rec.get("comment", "")).strip_edges()
	d.name_key = str(rec.get("Name", "")).strip_edges()
	d.editor_suffix = str(rec.get("EditorSuffix", "")).strip_edges()
	d.dood_class = str(rec.get("doodClass", "")).strip_edges()
	d.use_click_helper = int(rec.get("useClickHelper", 0)) != 0
	d.on_cliffs = int(rec.get("onCliffs", 0)) != 0
	d.on_water = int(rec.get("onWater", 0)) != 0
	d.can_place_dead = int(rec.get("canPlaceDead", 0)) != 0
	d.walkable = int(rec.get("walkable", 0)) != 0
	d.cliff_height = float(rec.get("cliffHeight", 0.0))
	d.targ_type = str(rec.get("targType", "")).strip_edges()
	d.armor = str(rec.get("armor", "")).strip_edges()
	d.num_var = int(rec.get("numVar", 0))
	d.hp = int(rec.get("HP", 0))
	d.occ_h = float(rec.get("occH", 0.0))
	d.fly_h = float(rec.get("flyH", 0.0))
	d.fixed_rot = float(rec.get("fixedRot", 0.0))
	d.sel_size = float(rec.get("selSize", 0.0))
	d.min_scale = float(rec.get("minScale", 0.0))
	d.max_scale = float(rec.get("maxScale", 0.0))
	d.can_place_rand_scale = int(rec.get("canPlaceRandScale", 0)) != 0
	d.max_pitch = float(rec.get("maxPitch", 0.0))
	d.max_roll = float(rec.get("maxRoll", 0.0))
	d.radius = float(rec.get("radius", 0.0))
	d.fog_radius = float(rec.get("fogRadius", 0.0))
	d.fog_vis = int(rec.get("fogVis", 0)) != 0
	d.path_tex = str(rec.get("pathTex", "")).replace("\\", "/").strip_edges()
	d.path_tex_death = str(rec.get("pathTexDeath", "")).replace("\\", "/").strip_edges()
	d.death_snd = str(rec.get("deathSnd", "")).strip_edges()
	d.shadow = str(rec.get("shadow", "")).replace("\\", "/").strip_edges()
	d.color_r = int(rec.get("colorR", 0))
	d.color_g = int(rec.get("colorG", 0))
	d.color_b = int(rec.get("colorB", 0))
	d.show_in_mm = int(rec.get("showInMM", 0)) != 0
	d.use_mm_color = int(rec.get("useMMColor", 0)) != 0
	d.mm_red = int(rec.get("MMRed", 0))
	d.mm_green = int(rec.get("MMGreen", 0))
	d.mm_blue = int(rec.get("MMBlue", 0))
	d.build_time = int(rec.get("buildTime", 0))
	d.repair_time = int(rec.get("repairTime", 0))
	d.gold_rep = int(rec.get("goldRep", 0))
	d.lumber_rep = int(rec.get("lumberRep", 0))
	d.user_list = int(rec.get("UserList", 0)) != 0
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	d.version = int(rec.get("version", 0))
	d.selectable = int(rec.get("selectable", 0)) != 0
	d.selcircsize = float(rec.get("selcircsize", 0.0))
	d.portraitmodel = str(rec.get("portraitmodel", "")).replace("\\", "/").strip_edges()
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("DestructableDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
