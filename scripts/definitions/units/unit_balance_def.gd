class_name UnitBalanceDef
extends Resource

## Units/UnitBalance.slk 一行定义。

const TABLE_NAME := "UnitBalance"
const SLK_REL_PATH := "Units/UnitBalance.json"
const PRIMARY_KEY := "unitBalanceID"

@export var unit_balance_id: String = ""
@export var sort_balance: String = ""
@export var sort2: String = ""
@export var comment: String = ""
@export var level: int = 0
@export var goldcost: int = 0
@export var lumbercost: int = 0
@export var gold_rep: int = 0
@export var lumber_rep: int = 0
@export var fmade: int = 0
@export var fused: int = 0
@export var bountydice: int = 0
@export var bountysides: int = 0
@export var bountyplus: int = 0
@export var stock_max: int = 0
@export var stock_regen: int = 0
@export var stock_start: int = 0
@export var hp: int = 0
@export var real_hp: int = 0
@export var regen_hp: float = 0.0
@export var regen_type: String = ""
@export var mana_n: int = 0
@export var real_m: int = 0
@export var mana0: int = 0
@export var regen_mana: float = 0.0
@export var def: float = 0.0
@export var def_up: float = 0.0
@export var realdef: float = 0.0
@export var def_type: String = ""
@export var spd: float = 0.0
@export var min_spd: float = 0.0
@export var max_spd: float = 0.0
@export var bldtm: int = 0
@export var reptm: int = 0
@export var sight: int = 0
@export var nsight: int = 0
@export var str_base: int = 0
@export var int_base: int = 0
@export var agi_base: int = 0
@export var st_rplus: float = 0.0
@export var in_tplus: float = 0.0
@export var ag_iplus: float = 0.0
@export var abil_test: int = 0
@export var primary_attr: String = ""
@export var upgrades: String = ""
@export var tilesets: String = ""
@export var nbrandom: bool = false
@export var isbldg: bool = false
@export var prevent_place: String = ""
@export var require_place: String = ""
@export var repulse: bool = false
@export var repulse_param: int = 0
@export var repulse_group: int = 0
@export var repulse_prio: int = 0
@export var collision: float = 0.0
@export var in_beta: bool = false

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
	d.level = int(rec.get("level", 0))
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
