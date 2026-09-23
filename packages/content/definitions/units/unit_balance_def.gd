class_name UnitBalanceDef
extends Resource

## Units/UnitBalance.slk 一行定义。
##
## 职责：单位的「数值平衡」表（造价、人口、生命/魔法、护甲、视野、英雄属性、
## 碰撞半径、商店库存等）。对象编辑器里大部分 Stats 页签落在这张表。
## 注意：移动动画速率在 UnitUI.walk；转向率在 UnitData.turnRate；
## 本表的 spd 才是对象编辑器「移动速度」那一栏（玩法速度）。

const TABLE_NAME := "UnitBalance"
const SLK_REL_PATH := "Units/UnitBalance.json"
const PRIMARY_KEY := "unitBalanceID"

@export var unit_balance_id: String = "" ## 主键，与 unitID 对齐（如 hpea / htow）
@export var sort_balance: String = "" ## 编辑器分类排序键（种族/类型粗排）
@export var sort2: String = "" ## 二级排序键
@export var comment: String = "" ## 人类可读备注（单位名注释，非游戏内显示名）
@export var level: int = -1 ## 单位等级（中立敌对、经验/赏金；"-" / 空 → -1 表示无等级）
@export var goldcost: int = 0 ## 训练/建造金币消耗
@export var lumbercost: int = 0 ## 训练/建造木材消耗
@export var gold_rep: int = 0 ## 修理回收金币（常与 goldcost 相同）
@export var lumber_rep: int = 0 ## 修理回收木材
@export var fmade: int = 0 ## 提供的人口（主城/农场等；非建筑多为 0 或 "-"）
@export var fused: int = 0 ## 占用人口（训练该单位需要的食物）
@export var bountydice: int = 0 ## 击杀赏金：骰子个数
@export var bountysides: int = 0 ## 击杀赏金：每骰面数
@export var bountyplus: int = 0 ## 击杀赏金：固定加算（dice×sides + plus）
@export var stock_max: int = 0 ## 商店/佣兵最大库存
@export var stock_regen: int = 0 ## 库存补充间隔（秒）
@export var stock_start: int = 0 ## 开局库存数量
@export var hp: int = 0 ## 最大生命（对象编辑器 Hit Points）
@export var real_hp: int = 0 ## 实际 HP（编辑器内部/校验用，通常等于 hp）
@export var regen_hp: float = 0.0 ## 生命回复速率（点/秒）
@export var regen_type: String = "" ## 回复条件：none / always / blight / night 等
@export var mana_n: int = 0 ## 最大魔法值
@export var real_m: int = 0 ## 实际魔法上限（通常等于 mana_n）
@export var mana0: int = 0 ## 出生初始魔法
@export var regen_mana: float = 0.0 ## 魔法回复速率（点/秒）
@export var def: float = 0.0 ## 基础护甲
@export var def_up: float = 0.0 ## 每级升级增加的护甲
@export var realdef: float = 0.0 ## 实际护甲（通常等于 def）
@export var def_type: String = "" ## 护甲类型：small/medium/large/fort/hero/divine/none…
@export var spd: float = 0.0 ## 移动速度（对象编辑器 Stats - Speed；玩法权威）
@export var min_spd: float = 0.0 ## 最小移动速度钳制（减速不会低于此）
@export var max_spd: float = 0.0 ## 最大移动速度钳制（加速不会高于此；0 常表示无上限）
@export var bldtm: int = 0 ## 建造/训练时间（秒）
@export var reptm: int = 0 ## 修理时间基准（秒）
@export var sight: int = 0 ## 白天视野半径（WC3）
@export var nsight: int = 0 ## 夜晚视野半径（WC3）
@export var str_base: int = 0 ## 英雄基础力量（非英雄为 0）
@export var int_base: int = 0 ## 英雄基础智力
@export var agi_base: int = 0 ## 英雄基础敏捷
@export var st_rplus: float = 0.0 ## 英雄每级力量成长
@export var in_tplus: float = 0.0 ## 英雄每级智力成长
@export var ag_iplus: float = 0.0 ## 英雄每级敏捷成长
@export var abil_test: int = 0 ## 编辑器/测试用技能相关标记（极少用）
@export var primary_attr: String = "" ## 英雄主属性：STR / AGI / INT
@export var upgrades: String = "" ## 影响该单位的升级 ID 列表（逗号分隔）
@export var tilesets: String = "" ## 可出现的地形集（佣兵营/中立建筑等）
@export var nbrandom: bool = false ## 是否参与随机中立建筑池
@export var isbldg: bool = false ## 是否为建筑（与 UnitUI/建筑判定交叉）
@export var prevent_place: String = "" ## 禁止放置的地形/路径类型掩码
@export var require_place: String = "" ## 必须放置的地形/路径类型（如金矿上）
@export var repulse: bool = false ## 是否启用推挤/排斥（飞行单位等）
@export var repulse_param: int = 0 ## 推挤参数
@export var repulse_group: int = 0 ## 推挤分组
@export var repulse_prio: int = 0 ## 推挤优先级
@export var collision: float = 0.0 ## 碰撞半径（WC3）；选中/寻路净空/软分离用
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_balance_id

static func from_slk_record(rec: Dictionary) -> UnitBalanceDef:
	var d := UnitBalanceDef.new()
	d.unit_balance_id = str(rec.get("unitBalanceID", "")).strip_edges()
	d.sort_balance = str(rec.get("sortBalance", "")).strip_edges()
	d.sort2 = str(rec.get("sort2", "")).strip_edges()
	d.comment = str(rec.get("comment(s)", "")).strip_edges()
	d.level = _parse_level(rec.get("level", ""))
	d.goldcost = int(rec.get("goldcost", 0))
	d.lumbercost = int(rec.get("lumbercost", 0))
	d.gold_rep = int(rec.get("goldRep", 0))
	d.lumber_rep = int(rec.get("lumberRep", 0))
	d.fmade = int(rec.get("fmade", 0))
	d.fused = int(rec.get("fused", 0))
	d.bountydice = int(rec.get("bountydice", 0))
	d.bountysides = int(rec.get("bountysides", 0))
	d.bountyplus = int(rec.get("bountyplus", 0))
	d.stock_max = int(rec.get("stockMax", 0))
	d.stock_regen = int(rec.get("stockRegen", 0))
	d.stock_start = int(rec.get("stockStart", 0))
	d.hp = int(rec.get("HP", 0))
	d.real_hp = int(rec.get("realHP", 0))
	d.regen_hp = float(rec.get("regenHP", 0.0))
	d.regen_type = str(rec.get("regenType", "")).strip_edges()
	d.mana_n = int(rec.get("manaN", 0))
	d.real_m = int(rec.get("realM", 0))
	d.mana0 = int(rec.get("mana0", 0))
	d.regen_mana = float(rec.get("regenMana", 0.0))
	d.def = float(rec.get("def", 0.0))
	d.def_up = float(rec.get("defUp", 0.0))
	d.realdef = float(rec.get("realdef", 0.0))
	d.def_type = str(rec.get("defType", "")).strip_edges()
	d.spd = float(rec.get("spd", 0.0))
	d.min_spd = float(rec.get("minSpd", 0.0))
	d.max_spd = float(rec.get("maxSpd", 0.0))
	d.bldtm = int(rec.get("bldtm", 0))
	d.reptm = int(rec.get("reptm", 0))
	d.sight = int(rec.get("sight", 0))
	d.nsight = int(rec.get("nsight", 0))
	d.str_base = int(rec.get("STR", 0))
	d.int_base = int(rec.get("INT", 0))
	d.agi_base = int(rec.get("AGI", 0))
	d.st_rplus = float(rec.get("STRplus", 0.0))
	d.in_tplus = float(rec.get("INTplus", 0.0))
	d.ag_iplus = float(rec.get("AGIplus", 0.0))
	d.abil_test = int(rec.get("abilTest", 0))
	d.primary_attr = str(rec.get("Primary", "")).strip_edges()
	d.upgrades = str(rec.get("upgrades", "")).strip_edges()
	d.tilesets = str(rec.get("tilesets", "")).strip_edges()
	d.nbrandom = int(rec.get("nbrandom", 0)) != 0
	d.isbldg = int(rec.get("isbldg", 0)) != 0
	d.prevent_place = str(rec.get("preventPlace", "")).strip_edges()
	d.require_place = str(rec.get("requirePlace", "")).strip_edges()
	d.repulse = int(rec.get("repulse", 0)) != 0
	d.repulse_param = int(rec.get("repulseParam", 0))
	d.repulse_group = int(rec.get("repulseGroup", 0))
	d.repulse_prio = int(rec.get("repulsePrio", 0))
	d.collision = float(rec.get("collision", 0.0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitBalanceDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)


## SLK 中 level 常为 "-" 表示无等级；与 Catalog 筛选语义对齐为 -1。
static func _parse_level(v: Variant) -> int:
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	var s := str(v).strip_edges()
	if s.is_empty() or s == "-" or s == "_":
		return -1
	if s.is_valid_int():
		return int(s)
	return -1
