class_name UnitUiDef
extends Resource

## Units/unitUI.slk 一行定义。
##
## 职责：单位的「表现/编辑器 UI」表（模型路径、音效集、选中圈、阴影、
## 染色、uberSplat、编辑器可见性等）。
## 注意：walk/run 是动画速率参考，不是玩法移动速度（玩法用 UnitBalance.spd）。

const TABLE_NAME := "UnitUI"
const SLK_REL_PATH := "Units/unitUI.json"
const PRIMARY_KEY := "unitUIID"

@export var unit_uiid: String = "" ## 主键，与 unitID 对齐
@export var sort_ui: String = "" ## 编辑器 UI 排序键
@export var file: String = "" ## 模型路径（.mdx；相对 Units/ 等资源根）
@export var file_ver_flags: int = 0 ## 模型 Extra Versions：非 0 表示有 expansion（如 TFT `_V1`）；见 CONTENT_PACKS.md
@export var unit_sound: String = "" ## 单位音效集名（UnitSound）
@export var tileset_specific: bool = false ## 是否仅特定地形集可用
@export var name_key: String = "" ## 显示名字符串键（对象编辑器 Name）
@export var unit_class: String = "" ## 编辑器分类（unitClass）
@export var special: bool = false ## 是否为特殊单位（Special）
@export var campaign: bool = false ## 是否仅战役可用
@export var in_editor: bool = false ## 是否在对象编辑器中显示
@export var hidden_in_editor: bool = false ## 是否在编辑器中隐藏
@export var hostile_pal: bool = false ## 是否出现在敌对单位面板
@export var drop_items: bool = false ## 死亡时可否掉落物品
@export var nbmm_icon: bool = false ## 中立建筑小地图图标
@export var use_click_helper: bool = false ## 是否使用点击辅助碰撞体
@export var blend: float = 0.0 ## 动画混合时间（秒）
@export var scale: float = 0.0 ## 选中/交互缩放相关（非 modelScale）
@export var scale_bull: bool = false ## 是否缩放投射物（Scale Bullet）
@export var max_pitch: float = 0.0 ## 模型最大俯仰角
@export var max_roll: float = 0.0 ## 模型最大侧倾角
@export var elev_pts: float = 0.0 ## 放置时采样高程的点数
@export var elev_rad: float = 0.0 ## 放置时采样高程的半径
@export var fog_rad: float = 0.0 ## 战争迷雾相关半径（建筑等）
@export var walk: float = 0.0 ## 行走动画速率参考（非玩法移速；玩法用 UnitBalance.spd）
@export var run: float = 0.0 ## 奔跑动画速率参考（非玩法移速）
@export var sel_z: float = 0.0 ## 选中圈高度偏移（Z）
@export var weap1: String = "" ## 武器音效/附件槽 1
@export var weap2: String = "" ## 武器音效/附件槽 2
@export var team_color: int = 0 ## 默认队伍色索引（-1 常表示玩家色）
@export var custom_team_color: bool = false ## 是否使用自定义队伍色
@export var armor: String = "" ## 受击护甲音效类型（Metal / Flesh / Wood…）
@export var model_scale: float = 0.0 ## 模型缩放（对象编辑器 Scaling Value）
@export var red: int = 0 ## 模型染色 R（0–255）
@export var green: int = 0 ## 模型染色 G
@export var blue: int = 0 ## 模型染色 B
@export var uber_splat: String = "" ## 地面贴花 ID（建筑脚下 UberSplat）
@export var unit_shadow: String = "" ## 单位阴影贴图路径
@export var building_shadow: String = "" ## 建筑阴影贴图路径
@export var shadow_w: float = 0.0 ## 阴影宽度
@export var shadow_h: float = 0.0 ## 阴影高度
@export var shadow_x: float = 0.0 ## 阴影 X 偏移
@export var shadow_y: float = 0.0 ## 阴影 Y 偏移
@export var shadow_on_water: bool = false ## 水面上是否显示阴影
@export var sel_circ_on_water: bool = false ## 水面上是否显示选中圈
@export var occ_h: float = 0.0 ## 遮挡高度（Occlusion Height；视野/遮挡）
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := name_key.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_uiid

static func from_slk_record(rec: Dictionary) -> UnitUiDef:
	var d := UnitUiDef.new()
	d.unit_uiid = str(rec.get("unitUIID", "")).strip_edges()
	d.sort_ui = str(rec.get("sortUI", "")).strip_edges()
	d.file = str(rec.get("file", "")).replace("\\", "/").strip_edges()
	d.file_ver_flags = int(rec.get("fileVerFlags", 0))
	d.unit_sound = str(rec.get("unitSound", "")).strip_edges()
	d.tileset_specific = int(rec.get("tilesetSpecific", 0)) != 0
	d.name_key = str(rec.get("name", "")).strip_edges()
	d.unit_class = str(rec.get("unitClass", "")).strip_edges()
	d.special = int(rec.get("special", 0)) != 0
	d.campaign = int(rec.get("campaign", 0)) != 0
	d.in_editor = int(rec.get("inEditor", 0)) != 0
	d.hidden_in_editor = int(rec.get("hiddenInEditor", 0)) != 0
	d.hostile_pal = int(rec.get("hostilePal", 0)) != 0
	d.drop_items = int(rec.get("dropItems", 0)) != 0
	d.nbmm_icon = int(rec.get("nbmmIcon", 0)) != 0
	d.use_click_helper = int(rec.get("useClickHelper", 0)) != 0
	d.blend = float(rec.get("blend", 0.0))
	d.scale = float(rec.get("scale", 0.0))
	d.scale_bull = int(rec.get("scaleBull", 0)) != 0
	d.max_pitch = float(rec.get("maxPitch", 0.0))
	d.max_roll = float(rec.get("maxRoll", 0.0))
	d.elev_pts = float(rec.get("elevPts", 0.0))
	d.elev_rad = float(rec.get("elevRad", 0.0))
	d.fog_rad = float(rec.get("fogRad", 0.0))
	d.walk = float(rec.get("walk", 0.0))
	d.run = float(rec.get("run", 0.0))
	d.sel_z = float(rec.get("selZ", 0.0))
	d.weap1 = str(rec.get("weap1", "")).strip_edges()
	d.weap2 = str(rec.get("weap2", "")).strip_edges()
	d.team_color = int(rec.get("teamColor", 0))
	d.custom_team_color = int(rec.get("customTeamColor", 0)) != 0
	d.armor = str(rec.get("armor", "")).strip_edges()
	d.model_scale = float(rec.get("modelScale", 0.0))
	d.red = int(rec.get("red", 0))
	d.green = int(rec.get("green", 0))
	d.blue = int(rec.get("blue", 0))
	d.uber_splat = str(rec.get("uberSplat", "")).replace("\\", "/").strip_edges()
	d.unit_shadow = str(rec.get("unitShadow", "")).replace("\\", "/").strip_edges()
	d.building_shadow = str(rec.get("buildingShadow", "")).replace("\\", "/").strip_edges()
	d.shadow_w = float(rec.get("shadowW", 0.0))
	d.shadow_h = float(rec.get("shadowH", 0.0))
	d.shadow_x = float(rec.get("shadowX", 0.0))
	d.shadow_y = float(rec.get("shadowY", 0.0))
	d.shadow_on_water = int(rec.get("shadowOnWater", 0)) != 0
	d.sel_circ_on_water = int(rec.get("selCircOnWater", 0)) != 0
	d.occ_h = float(rec.get("occH", 0.0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitUiDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
