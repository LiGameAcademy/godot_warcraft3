class_name UnitWeaponsDef
extends Resource

## Units/UnitWeapons.slk 一行定义。
##
## 职责：单位攻击与武器（索敌距离、射程、伤害骰、冷却、溅射、弹道发射点等）。
## 后缀 1/2 对应武器槽 1、2（多数单位只用槽 1）。

const TABLE_NAME := "UnitWeapons"
const SLK_REL_PATH := "Units/UnitWeapons.json"
const PRIMARY_KEY := "unitWeapID"

@export var unit_weap_id: String = "" ## 主键，与 unitID 对齐
@export var sort_weap: String = "" ## 编辑器排序键
@export var sort2: String = "" ## 二级排序键
@export var comment: String = "" ## 人类可读备注
@export var weaps_on: int = 0 ## 启用的武器槽位掩码（bit0=武器1，bit1=武器2…）
@export var acquire: float = 0.0 ## 主动索敌距离（Acquisition Range）
@export var min_range: float = 0.0 ## 最小攻击距离（过近无法攻击）
@export var castpt: float = 0.0 ## 施法/攻击前摇共用参考（Cast Point）
@export var castbsw: float = 0.0 ## 施法后摇参考（Cast Backswing）
@export var launch_x: float = 0.0 ## 弹道发射点 X（相对模型）
@export var launch_y: float = 0.0 ## 弹道发射点 Y
@export var launch_z: float = 0.0 ## 弹道发射点 Z（地面）
@export var launch_swim_z: float = 0.0 ## 弹道发射点 Z（游泳时）
@export var impact_z: float = 0.0 ## 弹道命中高度 Z
@export var impact_swim_z: float = 0.0 ## 弹道命中高度 Z（目标在水中）
# —— 武器 1 ——
@export var weap_type1: String = "" ## 武器音效类型（Metal Light Chop 等）
@export var targs1: String = "" ## 可攻击目标过滤器（ground,air,structure…）
@export var show_ui1: bool = false ## 是否在 UI 显示该武器攻击
@export var range_n1: float = 0.0 ## 攻击射程
@export var rng_tst: String = "" ## 射程测试/编辑器相关（RngTst）
@export var rng_buff1: float = 0.0 ## 射程缓冲（RngBuff；接近边缘时的容差）
@export var atk_type1: String = "" ## 攻击类型：normal / pierce / siege / magic / chaos / spells / hero…
@export var weap_tp1: String = "" ## 武器弹道类型：instant / missile / artillery / line…
@export var cool1: float = 0.0 ## 攻击冷却（秒）
@export var mincool1: float = 0.0 ## 最小冷却钳制
@export var dice1: int = 0 ## 伤害骰个数
@export var sides1: int = 0 ## 每骰面数
@export var dmgplus1: float = 0.0 ## 伤害固定加算（dice×sides + plus）
@export var dmg_up1: float = 0.0 ## 升级每级增加的伤害
@export var mindmg1: float = 0.0 ## 预计算最小伤害（编辑器显示）
@export var avgdmg1: float = 0.0 ## 预计算平均伤害
@export var maxdmg1: float = 0.0 ## 预计算最大伤害
@export var dmgpt1: float = 0.0 ## 伤害点（攻击动画中出伤时刻，秒）
@export var back_sw1: float = 0.0 ## 攻击后摇（秒）
@export var farea1: float = 0.0 ## 全额溅射半径（Full Area）
@export var harea1: float = 0.0 ## 半额溅射半径（Half Area）
@export var qarea1: float = 0.0 ## 四分之一溅射半径（Quarter Area）
@export var hfact1: float = 0.0 ## 半额溅射伤害系数
@export var qfact1: float = 0.0 ## 四分之一溅射伤害系数
@export var splash_targs1: String = "" ## 溅射目标过滤器
@export var targ_count1: int = 0 ## 最大命中目标数（弹跳/多重等）
@export var damage_loss1: float = 0.0 ## 每次弹跳/穿透的伤害衰减
@export var spill_dist1: float = 0.0 ## 弹道溢出距离
@export var spill_radius1: float = 0.0 ## 弹道溢出半径
@export var dmg_upg: String = "" ## 关联的攻击升级 ID
@export var dmod1: float = 0.0 ## 伤害修正系数（编辑器/内部）
@export var dps: float = 0.0 ## 预计算 DPS（显示用）
# —— 武器 2（字段含义同武器 1）——
@export var weap_type2: String = "" ## 武器 2：音效类型
@export var targs2: String = "" ## 武器 2：可攻击目标
@export var show_ui2: bool = false ## 武器 2：是否显示在 UI
@export var range_n2: float = 0.0 ## 武器 2：射程
@export var rng_tst2: float = 0.0 ## 武器 2：射程测试值
@export var rng_buff2: float = 0.0 ## 武器 2：射程缓冲
@export var atk_type2: String = "" ## 武器 2：攻击类型
@export var weap_tp2: String = "" ## 武器 2：弹道类型
@export var cool2: float = 0.0 ## 武器 2：冷却
@export var mincool2: float = 0.0 ## 武器 2：最小冷却
@export var dice2: int = 0 ## 武器 2：伤害骰个数
@export var sides2: int = 0 ## 武器 2：每骰面数
@export var dmgplus2: float = 0.0 ## 武器 2：伤害加算
@export var dmg_up2: float = 0.0 ## 武器 2：升级伤害加成
@export var mindmg2: float = 0.0 ## 武器 2：最小伤害
@export var avgdmg2: float = 0.0 ## 武器 2：平均伤害
@export var maxdmg2: float = 0.0 ## 武器 2：最大伤害
@export var dmgpt2: float = 0.0 ## 武器 2：伤害点
@export var back_sw2: float = 0.0 ## 武器 2：后摇
@export var farea2: float = 0.0 ## 武器 2：全额溅射半径
@export var harea2: float = 0.0 ## 武器 2：半额溅射半径
@export var qarea2: float = 0.0 ## 武器 2：四分之一溅射半径
@export var hfact2: float = 0.0 ## 武器 2：半额溅射系数
@export var qfact2: float = 0.0 ## 武器 2：四分之一溅射系数
@export var splash_targs2: String = "" ## 武器 2：溅射目标
@export var targ_count2: int = 0 ## 武器 2：最大命中数
@export var damage_loss2: float = 0.0 ## 武器 2：伤害衰减
@export var spill_dist2: float = 0.0 ## 武器 2：溢出距离
@export var spill_radius2: float = 0.0 ## 武器 2：溢出半径
@export var in_beta: bool = false ## 是否属于 RoC（非 TFT）数据标记

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
