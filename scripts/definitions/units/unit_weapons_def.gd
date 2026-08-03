class_name UnitWeaponsDef
extends Resource

## Units/UnitWeapons.slk 一行定义。

const TABLE_NAME := "UnitWeapons"
const SLK_REL_PATH := "Units/UnitWeapons.json"
const PRIMARY_KEY := "unitWeapID"

@export var unit_weap_id: String = ""
@export var sort_weap: String = ""
@export var sort2: String = ""
@export var comment: String = ""
@export var weaps_on: int = 0
@export var acquire: float = 0.0
@export var min_range: float = 0.0
@export var castpt: float = 0.0
@export var castbsw: float = 0.0
@export var launch_x: float = 0.0
@export var launch_y: float = 0.0
@export var launch_z: float = 0.0
@export var launch_swim_z: float = 0.0
@export var impact_z: float = 0.0
@export var impact_swim_z: float = 0.0
@export var weap_type1: String = ""
@export var targs1: String = ""
@export var show_ui1: bool = false
@export var range_n1: float = 0.0
@export var rng_tst: String = ""
@export var rng_buff1: float = 0.0
@export var atk_type1: String = ""
@export var weap_tp1: String = ""
@export var cool1: float = 0.0
@export var mincool1: float = 0.0
@export var dice1: int = 0
@export var sides1: int = 0
@export var dmgplus1: float = 0.0
@export var dmg_up1: float = 0.0
@export var mindmg1: float = 0.0
@export var avgdmg1: float = 0.0
@export var maxdmg1: float = 0.0
@export var dmgpt1: float = 0.0
@export var back_sw1: float = 0.0
@export var farea1: float = 0.0
@export var harea1: float = 0.0
@export var qarea1: float = 0.0
@export var hfact1: float = 0.0
@export var qfact1: float = 0.0
@export var splash_targs1: String = ""
@export var targ_count1: int = 0
@export var damage_loss1: float = 0.0
@export var spill_dist1: float = 0.0
@export var spill_radius1: float = 0.0
@export var dmg_upg: String = ""
@export var dmod1: float = 0.0
@export var dps: float = 0.0
@export var weap_type2: String = ""
@export var targs2: String = ""
@export var show_ui2: bool = false
@export var range_n2: float = 0.0
@export var rng_tst2: float = 0.0
@export var rng_buff2: float = 0.0
@export var atk_type2: String = ""
@export var weap_tp2: String = ""
@export var cool2: float = 0.0
@export var mincool2: float = 0.0
@export var dice2: int = 0
@export var sides2: int = 0
@export var dmgplus2: float = 0.0
@export var dmg_up2: float = 0.0
@export var mindmg2: float = 0.0
@export var avgdmg2: float = 0.0
@export var maxdmg2: float = 0.0
@export var dmgpt2: float = 0.0
@export var back_sw2: float = 0.0
@export var farea2: float = 0.0
@export var harea2: float = 0.0
@export var qarea2: float = 0.0
@export var hfact2: float = 0.0
@export var qfact2: float = 0.0
@export var splash_targs2: String = ""
@export var targ_count2: int = 0
@export var damage_loss2: float = 0.0
@export var spill_dist2: float = 0.0
@export var spill_radius2: float = 0.0
@export var in_beta: bool = false

## 显示名：优先 comment/name，否则主键。
func display_name() -> String:
	var c := comment.strip_edges()
	return c if not c.is_empty() and c != "_" else unit_weap_id

static func from_slk_record(rec: Dictionary) -> UnitWeaponsDef:
	var d := UnitWeaponsDef.new()
	d.unit_weap_id = str(rec.get("unitWeapID", "")).strip_edges()
	d.sort_weap = str(rec.get("sortWeap", "")).strip_edges()
	d.sort2 = str(rec.get("sort2", "")).strip_edges()
	d.comment = str(rec.get("comment(s)", "")).strip_edges()
	d.weaps_on = int(rec.get("weapsOn", 0))
	d.acquire = float(rec.get("acquire", 0.0))
	d.min_range = float(rec.get("minRange", 0.0))
	d.castpt = float(rec.get("castpt", 0.0))
	d.castbsw = float(rec.get("castbsw", 0.0))
	d.launch_x = float(rec.get("launchX", 0.0))
	d.launch_y = float(rec.get("launchY", 0.0))
	d.launch_z = float(rec.get("launchZ", 0.0))
	d.launch_swim_z = float(rec.get("launchSwimZ", 0.0))
	d.impact_z = float(rec.get("impactZ", 0.0))
	d.impact_swim_z = float(rec.get("impactSwimZ", 0.0))
	d.weap_type1 = str(rec.get("weapType1", "")).strip_edges()
	d.targs1 = str(rec.get("targs1", "")).strip_edges()
	d.show_ui1 = int(rec.get("showUI1", 0)) != 0
	d.range_n1 = float(rec.get("rangeN1", 0.0))
	d.rng_tst = str(rec.get("RngTst", "")).strip_edges()
	d.rng_buff1 = float(rec.get("RngBuff1", 0.0))
	d.atk_type1 = str(rec.get("atkType1", "")).strip_edges()
	d.weap_tp1 = str(rec.get("weapTp1", "")).strip_edges()
	d.cool1 = float(rec.get("cool1", 0.0))
	d.mincool1 = float(rec.get("mincool1", 0.0))
	d.dice1 = int(rec.get("dice1", 0))
	d.sides1 = int(rec.get("sides1", 0))
	d.dmgplus1 = float(rec.get("dmgplus1", 0.0))
	d.dmg_up1 = float(rec.get("dmgUp1", 0.0))
	d.mindmg1 = float(rec.get("mindmg1", 0.0))
	d.avgdmg1 = float(rec.get("avgdmg1", 0.0))
	d.maxdmg1 = float(rec.get("maxdmg1", 0.0))
	d.dmgpt1 = float(rec.get("dmgpt1", 0.0))
	d.back_sw1 = float(rec.get("backSw1", 0.0))
	d.farea1 = float(rec.get("Farea1", 0.0))
	d.harea1 = float(rec.get("Harea1", 0.0))
	d.qarea1 = float(rec.get("Qarea1", 0.0))
	d.hfact1 = float(rec.get("Hfact1", 0.0))
	d.qfact1 = float(rec.get("Qfact1", 0.0))
	d.splash_targs1 = str(rec.get("splashTargs1", "")).strip_edges()
	d.targ_count1 = int(rec.get("targCount1", 0))
	d.damage_loss1 = float(rec.get("damageLoss1", 0.0))
	d.spill_dist1 = float(rec.get("spillDist1", 0.0))
	d.spill_radius1 = float(rec.get("spillRadius1", 0.0))
	d.dmg_upg = str(rec.get("DmgUpg", "")).strip_edges()
	d.dmod1 = float(rec.get("dmod1", 0.0))
	d.dps = float(rec.get("DPS", 0.0))
	d.weap_type2 = str(rec.get("weapType2", "")).strip_edges()
	d.targs2 = str(rec.get("targs2", "")).strip_edges()
	d.show_ui2 = int(rec.get("showUI2", 0)) != 0
	d.range_n2 = float(rec.get("rangeN2", 0.0))
	d.rng_tst2 = float(rec.get("RngTst2", 0.0))
	d.rng_buff2 = float(rec.get("RngBuff2", 0.0))
	d.atk_type2 = str(rec.get("atkType2", "")).strip_edges()
	d.weap_tp2 = str(rec.get("weapTp2", "")).strip_edges()
	d.cool2 = float(rec.get("cool2", 0.0))
	d.mincool2 = float(rec.get("mincool2", 0.0))
	d.dice2 = int(rec.get("dice2", 0))
	d.sides2 = int(rec.get("sides2", 0))
	d.dmgplus2 = float(rec.get("dmgplus2", 0.0))
	d.dmg_up2 = float(rec.get("dmgUp2", 0.0))
	d.mindmg2 = float(rec.get("mindmg2", 0.0))
	d.avgdmg2 = float(rec.get("avgdmg2", 0.0))
	d.maxdmg2 = float(rec.get("maxdmg2", 0.0))
	d.dmgpt2 = float(rec.get("dmgpt2", 0.0))
	d.back_sw2 = float(rec.get("backSw2", 0.0))
	d.farea2 = float(rec.get("Farea2", 0.0))
	d.harea2 = float(rec.get("Harea2", 0.0))
	d.qarea2 = float(rec.get("Qarea2", 0.0))
	d.hfact2 = float(rec.get("Hfact2", 0.0))
	d.qfact2 = float(rec.get("Qfact2", 0.0))
	d.splash_targs2 = str(rec.get("splashTargs2", "")).strip_edges()
	d.targ_count2 = int(rec.get("targCount2", 0))
	d.damage_loss2 = float(rec.get("damageLoss2", 0.0))
	d.spill_dist2 = float(rec.get("spillDist2", 0.0))
	d.spill_radius2 = float(rec.get("spillRadius2", 0.0))
	d.in_beta = int(rec.get("InBeta", 0)) != 0
	return d

static func register_to(store: Node) -> void:
	if store == null or not store.has_method("register_table"):
		push_error("UnitWeaponsDef: 无法注册到 DefStore")
		return
	store.register_table(TABLE_NAME, SLK_REL_PATH, PRIMARY_KEY, from_slk_record)
