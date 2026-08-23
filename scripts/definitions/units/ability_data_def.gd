class_name AbilityDataDef
extends Resource

## Units/AbilityData.slk 一行定义。
##
## 职责：技能玩法数据（等级、目标、施法时间、持续时间、冷却、魔法消耗、
## 作用范围/射程，以及 DataA–E / UnitID 等效果参数）。
## 后缀 1–4 对应技能等级 1–4；具体 Data* 含义因 code（技能引擎 ID）而异。

const TABLE_NAME := "AbilityData"
const SLK_REL_PATH := "Units/AbilityData.json"
const PRIMARY_KEY := "alias"

@export var alias: String = "" ## 技能别名/主键（四字符 ID，如 AHhb）
@export var code_id: String = "" ## 引擎技能码（code；决定 Data* 语义）
@export var comment: String = "" ## 人类可读备注
@export var version: int = 0 ## 数据版本标记
@export var use_in_editor: bool = false ## 是否在对象编辑器中可选
@export var hero: bool = false ## 是否为英雄技能
@export var item: bool = false ## 是否为物品技能
@export var sort_key: String = "" ## 编辑器排序键
@export var race: String = "" ## 所属种族
@export var check_dep: bool = false ## 是否检查科技依赖
@export var levels: int = 0 ## 最大等级数
@export var req_level: int = 0 ## 英雄学习所需英雄等级
@export var level_skip: int = 0 ## 每升一级所需额外英雄等级间隔
@export var priority: int = 0 ## AI/自动施法优先级
@export var targs: String = "" ## 默认目标过滤器（可被等级覆盖）
# —— 等级 1 ——
@export var cast1: float = 0.0 ## Lv1：施法时间（秒）
@export var dur1: float = 0.0 ## Lv1：普通单位上的持续时间
@export var hero_dur1: float = 0.0 ## Lv1：英雄上的持续时间
@export var cool1: float = 0.0 ## Lv1：冷却（秒）
@export var cost1: float = 0.0 ## Lv1：魔法消耗
@export var area1: float = 0.0 ## Lv1：作用范围（AoE）
@export var rng1: float = 0.0 ## Lv1：施法射程
@export var data_a1: float = 0.0 ## Lv1：效果参数 A（语义由 code 决定）
@export var data_b1: float = 0.0 ## Lv1：效果参数 B
@export var data_c1: float = 0.0 ## Lv1：效果参数 C
@export var data_d1: float = 0.0 ## Lv1：效果参数 D
@export var data_e1: float = 0.0 ## Lv1：效果参数 E
@export var unit_id1: String = "" ## Lv1：关联单位 ID（召唤物等）
# —— 等级 2 ——
@export var cast2: float = 0.0 ## Lv2：施法时间
@export var dur2: float = 0.0 ## Lv2：持续时间（普通）
@export var hero_dur2: float = 0.0 ## Lv2：持续时间（英雄）
@export var cool2: float = 0.0 ## Lv2：冷却
@export var cost2: float = 0.0 ## Lv2：魔法消耗
@export var area2: float = 0.0 ## Lv2：作用范围
@export var rng2: float = 0.0 ## Lv2：施法射程
@export var data_a2: float = 0.0 ## Lv2：效果参数 A
@export var data_b2: float = 0.0 ## Lv2：效果参数 B
@export var data_c2: float = 0.0 ## Lv2：效果参数 C
@export var data_d2: float = 0.0 ## Lv2：效果参数 D
@export var data_e2: float = 0.0 ## Lv2：效果参数 E
@export var unit_id2: String = "" ## Lv2：关联单位 ID
# —— 等级 3 ——
@export var cast3: float = 0.0 ## Lv3：施法时间
@export var dur3: float = 0.0 ## Lv3：持续时间（普通）
@export var hero_dur3: float = 0.0 ## Lv3：持续时间（英雄）
@export var cool3: float = 0.0 ## Lv3：冷却
@export var cost3: float = 0.0 ## Lv3：魔法消耗
@export var area3: float = 0.0 ## Lv3：作用范围
@export var rng3: float = 0.0 ## Lv3：施法射程
@export var data_a3: float = 0.0 ## Lv3：效果参数 A
@export var data_b3: float = 0.0 ## Lv3：效果参数 B
@export var data_c3: float = 0.0 ## Lv3：效果参数 C
@export var data_d3: float = 0.0 ## Lv3：效果参数 D
@export var data_e3: float = 0.0 ## Lv3：效果参数 E
@export var unit_id3: String = "" ## Lv3：关联单位 ID
# —— 等级 4 ——
@export var cast4: float = 0.0 ## Lv4：施法时间
@export var dur4: float = 0.0 ## Lv4：持续时间（普通）
@export var hero_dur4: float = 0.0 ## Lv4：持续时间（英雄）
@export var cool4: float = 0.0 ## Lv4：冷却
@export var cost4: float = 0.0 ## Lv4：魔法消耗
@export var area4: float = 0.0 ## Lv4：作用范围
@export var rng4: float = 0.0 ## Lv4：施法射程
@export var data_a4: float = 0.0 ## Lv4：效果参数 A
@export var data_b4: float = 0.0 ## Lv4：效果参数 B
@export var data_c4: float = 0.0 ## Lv4：效果参数 C
@export var data_d4: float = 0.0 ## Lv4：效果参数 D
@export var data_e4: float = 0.0 ## Lv4：效果参数 E
@export var unit_id4: String = "" ## Lv4：关联单位 ID
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else alias


## 有效等级（1…levels；无等级数据时至少 1）。
func clamp_level(level: int) -> int:
	var max_lv := maxi(levels, 1)
	return clampi(level, 1, max_lv)


## 学习下一 rank 所需英雄等级（current_rank=0 表示尚未学习）。
func required_hero_level_for_rank(current_rank: int) -> int:
	var base := req_level if req_level > 0 else 1
	var skip := maxi(level_skip, 0)
	return base + skip * maxi(current_rank, 0)


func cost_at(level: int) -> float:
	match clamp_level(level):
		1: return cost1
		2: return cost2
		3: return cost3
		4: return cost4
		_: return cost1


func cool_at(level: int) -> float:
	match clamp_level(level):
		1: return cool1
		2: return cool2
		3: return cool3
		4: return cool4
		_: return cool1


func cast_time_at(level: int) -> float:
	match clamp_level(level):
		1: return cast1
		2: return cast2
		3: return cast3
		4: return cast4
		_: return 0.0


func duration_at(level: int) -> float:
	match clamp_level(level):
		1: return dur1
		2: return dur2
		3: return dur3
		4: return dur4
		_: return dur1


func hero_duration_at(level: int) -> float:
	match clamp_level(level):
		1: return hero_dur1
		2: return hero_dur2
		3: return hero_dur3
		4: return hero_dur4
		_: return hero_dur1


func cast_range_at(level: int) -> float:
	## WC3：召唤类常用 AreaN 作施法距离；RngN>0 时优先 Rng。
	var lv := clamp_level(level)
	var rng := rng1
	var area := area1
	match lv:
		2: rng = rng2; area = area2
		3: rng = rng3; area = area3
		4: rng = rng4; area = area4
	if rng > 0.0:
		return rng
	if area > 0.0:
		return area
	return 99999.0


func area_at(level: int) -> float:
	match clamp_level(level):
		1: return area1
		2: return area2
		3: return area3
		4: return area4
		_: return area1


func data_a_at(level: int) -> float:
	match clamp_level(level):
		1: return data_a1
		2: return data_a2
		3: return data_a3
		4: return data_a4
		_: return data_a1


func data_b_at(level: int) -> float:
	match clamp_level(level):
		1: return data_b1
		2: return data_b2
		3: return data_b3
		4: return data_b4
		_: return data_b1


func data_c_at(level: int) -> float:
	match clamp_level(level):
		1: return data_c1
		2: return data_c2
		3: return data_c3
		4: return data_c4
		_: return data_c1


func data_d_at(level: int) -> float:
	match clamp_level(level):
		1: return data_d1
		2: return data_d2
		3: return data_d3
		4: return data_d4
		_: return data_d1


func summon_unit_id_at(level: int) -> String:
	match clamp_level(level):
		1: return unit_id1.strip_edges()
		2: return unit_id2.strip_edges()
		3: return unit_id3.strip_edges()
		4: return unit_id4.strip_edges()
		_: return unit_id1.strip_edges()

static func from_slk_record(rec: Dictionary) -> AbilityDataDef:
	var d := AbilityDataDef.new()
	d.alias = str(rec.get("alias", "")).strip_edges()
	d.code_id = str(rec.get("code", "")).strip_edges()
	d.comment = str(rec.get("comments", "")).strip_edges()
	d.version = int(rec.get("version", 0))
	d.use_in_editor = int(rec.get("useInEditor", 0)) != 0
	d.hero = int(rec.get("hero", 0)) != 0
	d.item = int(rec.get("item", 0)) != 0
	d.sort_key = str(rec.get("sort", "")).strip_edges()
	d.race = str(rec.get("race", "")).strip_edges()
	d.check_dep = int(rec.get("checkDep", 0)) != 0
	d.levels = int(rec.get("levels", 0))
	d.req_level = int(rec.get("reqLevel", 0))
	d.level_skip = int(rec.get("levelSkip", 0))
	d.priority = int(rec.get("priority", 0))
	d.targs = str(rec.get("targs", "")).strip_edges()
	d.cast1 = float(rec.get("Cast1", 0.0))
	d.dur1 = float(rec.get("Dur1", 0.0))
	d.hero_dur1 = float(rec.get("HeroDur1", 0.0))
	d.cool1 = float(rec.get("Cool1", 0.0))
	d.cost1 = float(rec.get("Cost1", 0.0))
	d.area1 = float(rec.get("Area1", 0.0))
	d.rng1 = float(rec.get("Rng1", 0.0))
	d.data_a1 = float(rec.get("DataA1", 0.0))
	d.data_b1 = float(rec.get("DataB1", 0.0))
	d.data_c1 = float(rec.get("DataC1", 0.0))
	d.data_d1 = float(rec.get("DataD1", 0.0))
	d.data_e1 = float(rec.get("DataE1", 0.0))
	d.unit_id1 = str(rec.get("UnitID1", "")).strip_edges()
	d.cast2 = float(rec.get("Cast2", 0.0))
	d.dur2 = float(rec.get("Dur2", 0.0))
	d.hero_dur2 = float(rec.get("HeroDur2", 0.0))
	d.cool2 = float(rec.get("Cool2", 0.0))
	d.cost2 = float(rec.get("Cost2", 0.0))
	d.area2 = float(rec.get("Area2", 0.0))
	d.rng2 = float(rec.get("Rng2", 0.0))
	d.data_a2 = float(rec.get("DataA2", 0.0))
	d.data_b2 = float(rec.get("DataB2", 0.0))
	d.data_c2 = float(rec.get("DataC2", 0.0))
	d.data_d2 = float(rec.get("DataD2", 0.0))
	d.data_e2 = float(rec.get("DataE2", 0.0))
	d.unit_id2 = str(rec.get("UnitID2", "")).strip_edges()
	d.cast3 = float(rec.get("Cast3", 0.0))
	d.dur3 = float(rec.get("Dur3", 0.0))
	d.hero_dur3 = float(rec.get("HeroDur3", 0.0))
	d.cool3 = float(rec.get("Cool3", 0.0))
	d.cost3 = float(rec.get("Cost3", 0.0))
	d.area3 = float(rec.get("Area3", 0.0))
	d.rng3 = float(rec.get("Rng3", 0.0))
	d.data_a3 = float(rec.get("DataA3", 0.0))
	d.data_b3 = float(rec.get("DataB3", 0.0))
	d.data_c3 = float(rec.get("DataC3", 0.0))
	d.data_d3 = float(rec.get("DataD3", 0.0))
	d.data_e3 = float(rec.get("DataE3", 0.0))
	d.unit_id3 = str(rec.get("UnitID3", "")).strip_edges()
	d.cast4 = float(rec.get("Cast4", 0.0))
	d.dur4 = float(rec.get("Dur4", 0.0))
	d.hero_dur4 = float(rec.get("HeroDur4", 0.0))
	d.cool4 = float(rec.get("Cool4", 0.0))
	d.cost4 = float(rec.get("Cost4", 0.0))
	d.area4 = float(rec.get("Area4", 0.0))
	d.rng4 = float(rec.get("Rng4", 0.0))
	d.data_a4 = float(rec.get("DataA4", 0.0))
	d.data_b4 = float(rec.get("DataB4", 0.0))
	d.data_c4 = float(rec.get("DataC4", 0.0))
	d.data_d4 = float(rec.get("DataD4", 0.0))
	d.data_e4 = float(rec.get("DataE4", 0.0))
	d.unit_id4 = str(rec.get("UnitID4", "")).strip_edges()
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("AbilityDataDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
