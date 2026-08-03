class_name UnitDataDef
extends Resource

## Units/UnitData.slk 一行定义。

const TABLE_NAME := "UnitData"
const SLK_REL_PATH := "Units/UnitData.json"
const PRIMARY_KEY := "unitID"

@export var unit_id: String = ""				## 单位ID
@export var sort_key: String = ""				## 排序键
@export var comment: String = ""				## 注释
@export var race: String = ""					## 种族
@export var prio: int = 0						## 优先级
@export var threat: int = 0						## 威胁
@export var type_name: String = ""				## 类型名称
@export var valid: bool = false					## 有效
@export var death_type: int = 0					## 死亡类型
@export var death: float = 0.0					## 死亡
@export var can_sleep: bool = false				## 可睡眠
@export var cargo_size: int = 0					## 货物大小
@export var movetp: String = ""					## 移动类型
@export var move_height: float = 0.0			## 移动高度
@export var move_floor: float = 0.0				## 移动地板
@export var turn_rate: float = 0.0				## 转向率
@export var prop_win: float = 0.0				## 胜利概率
@export var orient_interp: int = 0				## 旋转插值
@export var formation: int = 0					## 编队
@export var targ_type: String = ""				## 目标类型
@export var path_tex: String = ""				## 路径纹理
@export var fat_los: bool = false				## 宽视野
@export var points: int = 0						## 点数
@export var buff_type: String = ""				## 缓冲类型
@export var buff_radius: float = 0.0			## 缓冲半径
@export var name_count: int = 0					## 名称计数
@export var can_flee: bool = false				## 可逃跑
@export var require_water_radius: float = 0.0	## 需要水半径
@export var in_beta: bool = false				## 是否在Beta
@export var version: int = 0					## 版本

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
