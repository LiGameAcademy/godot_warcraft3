class_name AbilityDataDef
extends Resource

## Units/AbilityData.slk 一行定义。

const TABLE_NAME := "AbilityData"
const SLK_REL_PATH := "Units/AbilityData.json"
const PRIMARY_KEY := "alias"

@export var alias: String = ""
@export var code_id: String = ""
@export var comment: String = ""
@export var version: int = 0
@export var use_in_editor: bool = false
@export var hero: bool = false
@export var item: bool = false
@export var sort_key: String = ""
@export var race: String = ""
@export var check_dep: bool = false
@export var levels: int = 0
@export var req_level: int = 0
@export var level_skip: int = 0
@export var priority: int = 0
@export var targs: String = ""
@export var cast1: float = 0.0
@export var dur1: float = 0.0
@export var hero_dur1: float = 0.0
@export var cool1: float = 0.0
@export var cost1: float = 0.0
@export var area1: float = 0.0
@export var rng1: float = 0.0
@export var data_a1: float = 0.0
@export var data_b1: float = 0.0
@export var data_c1: float = 0.0
@export var data_d1: float = 0.0
@export var data_e1: float = 0.0
@export var unit_id1: String = ""
@export var cast2: float = 0.0
@export var dur2: float = 0.0
@export var hero_dur2: float = 0.0
@export var cool2: float = 0.0
@export var cost2: float = 0.0
@export var area2: float = 0.0
@export var rng2: float = 0.0
@export var data_a2: float = 0.0
@export var data_b2: float = 0.0
@export var data_c2: float = 0.0
@export var data_d2: float = 0.0
@export var data_e2: float = 0.0
@export var unit_id2: String = ""
@export var cast3: float = 0.0
@export var dur3: float = 0.0
@export var hero_dur3: float = 0.0
@export var cool3: float = 0.0
@export var cost3: float = 0.0
@export var area3: float = 0.0
@export var rng3: float = 0.0
@export var data_a3: float = 0.0
@export var data_b3: float = 0.0
@export var data_c3: float = 0.0
@export var data_d3: float = 0.0
@export var data_e3: float = 0.0
@export var unit_id3: String = ""
@export var cast4: float = 0.0
@export var dur4: float = 0.0
@export var hero_dur4: float = 0.0
@export var cool4: float = 0.0
@export var cost4: float = 0.0
@export var area4: float = 0.0
@export var rng4: float = 0.0
@export var data_a4: float = 0.0
@export var data_b4: float = 0.0
@export var data_c4: float = 0.0
@export var data_d4: float = 0.0
@export var data_e4: float = 0.0
@export var unit_id4: String = ""
@export var in_beta: bool = false

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else alias

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
