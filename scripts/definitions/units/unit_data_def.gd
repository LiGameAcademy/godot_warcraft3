class_name UnitDataDef
extends Resource

## Units/UnitData.slk 一行定义。
##
## 职责：单位的「行为/移动/AI/分类」表（种族、移动类型、转向、死亡、
## 目标类型、建筑 pathTex、AI 放置等）。数值平衡在 UnitBalance；
## 模型/选中圈/阴影在 UnitUI；攻击在 UnitWeapons。

const TABLE_NAME := "UnitData"
const SLK_REL_PATH := "Units/UnitData.json"
const PRIMARY_KEY := "unitID"

@export var unit_id: String = "" ## 主键，与 unitBalanceID / unitUIID 对齐（如 hpea）
@export var sort_key: String = "" ## 编辑器排序键
@export var comment: String = "" ## 人类可读备注（非游戏内显示名）
@export var race: String = "" ## 种族：human / orc / undead / nightelf / naga / commoner / creep…
@export var prio: int = 0 ## AI 攻击优先级（越高越优先被电脑点名）
@export var threat: int = 0 ## AI 威胁等级（影响电脑集火/评估）
@export var type_name: String = "" ## 单位类型标签（SLK 列 type；如 stand / sapper 等）
@export var valid: bool = false ## 是否为有效可用单位（编辑器/游戏过滤）
@export var death_type: int = 0 ## 死亡类型：尸体可否被复活/腐化等（对象编辑器 Death Type）
@export var death: float = 0.0 ## 死亡后尸体停留时间（秒）
@export var can_sleep: bool = false ## 夜间可否睡觉（中立敌对常见）
@export var cargo_size: int = 0 ## 占用运输舱位（上运输船时）
@export var movetp: String = "" ## 移动类型：foot / horse / fly / hover / float / amphibious…
@export var move_height: float = 0.0 ## 飞行/悬浮高度（地面单位多为 0）
@export var move_floor: float = 0.0 ## 最低离地高度钳制
@export var turn_rate: float = 0.0 ## 转向率（圈/秒；对象编辑器 Turn Rate；玩法权威）
@export var prop_win: float = 0.0 ## 坡上最大倾斜角（Prop Window；模型俯仰/侧倾上限）
@export var orient_interp: int = 0 ## 朝向插值档位（转向平滑）
@export var formation: int = 0 ## 编队占位等级（群体移动时的队形槽）
@export var targ_type: String = "" ## 自身作为目标的分类：ground / air / structure / debris…
@export var path_tex: String = "" ## 建筑占位路径图（pathing texture；建筑专用）
@export var fat_los: bool = false ## 粗视野遮挡（Fat LOS；挡视野更「胖」）
@export var points: int = 0 ## 旧版积分/权重字段（少用）
@export var buff_type: String = "" ## AI 放置类型（buffType）：建筑功能分区，决定电脑往哪类区域盖（非战斗 Buff）
@export var buff_radius: float = 0.0 ## AI 放置半径（buffRadius）：电脑摆该建筑时与同类的间距
@export var name_count: int = 0 ## 英雄专有名数量（Proper Names）
@export var can_flee: bool = false ## AI 可否逃跑
@export var require_water_radius: float = 0.0 ## 放置所需水域半径（海军建筑等）
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记
@export var version: int = 0 ## 数据版本标记

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_id

static func from_slk_record(rec: Dictionary) -> UnitDataDef:
	var d := UnitDataDef.new()
	d.unit_id = str(rec.get("unitID", "")).strip_edges()
	d.sort_key = str(rec.get("sort", "")).strip_edges()
	d.comment = str(rec.get("comment(s)", "")).strip_edges()
	d.race = str(rec.get("race", "")).strip_edges()
	d.prio = int(rec.get("prio", 0))
	d.threat = int(rec.get("threat", 0))
	d.type_name = str(rec.get("type", "")).strip_edges()
	d.valid = int(rec.get("valid", 0)) != 0
	d.death_type = int(rec.get("deathType", 0))
	d.death = float(rec.get("death", 0.0))
	d.can_sleep = int(rec.get("canSleep", 0)) != 0
	d.cargo_size = int(rec.get("cargoSize", 0))
	d.movetp = str(rec.get("movetp", "")).strip_edges()
	d.move_height = float(rec.get("moveHeight", 0.0))
	d.move_floor = float(rec.get("moveFloor", 0.0))
	d.turn_rate = float(rec.get("turnRate", 0.0))
	d.prop_win = float(rec.get("propWin", 0.0))
	d.orient_interp = int(rec.get("orientInterp", 0))
	d.formation = int(rec.get("formation", 0))
	d.targ_type = str(rec.get("targType", "")).strip_edges()
	d.path_tex = str(rec.get("pathTex", "")).replace("\\", "/").strip_edges()
	d.fat_los = int(rec.get("fatLOS", 0)) != 0
	d.points = int(rec.get("points", 0))
	d.buff_type = str(rec.get("buffType", "")).strip_edges()
	d.buff_radius = float(rec.get("buffRadius", 0.0))
	d.name_count = int(rec.get("nameCount", 0))
	d.can_flee = int(rec.get("canFlee", 0)) != 0
	d.require_water_radius = float(rec.get("requireWaterRadius", 0.0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	d.version = int(rec.get("version", 0))
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
