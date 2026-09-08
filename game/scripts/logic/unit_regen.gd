class_name UnitRegen
extends RefCounted

## 单位自然回复（Logic）。
## - HP：`UnitBalance.regenHP` +（英雄）STR×0.05；受 `regenType` 门禁
## - 蓝：`UnitBalance.regenMana` +（英雄）INT×0.05 + `BuffQuery.mana_regen_bonus`（辉煌等）
## - blight / night 等条件回复：昼夜与荒芜地未接前暂不回复（见 docs）

const HERO_HP_REGEN_PER_STR := 0.05
const HERO_MANA_REGEN_PER_INT := 0.05


static func strength_at_level(bal: UnitBalanceDef, hero_level: int) -> float:
	if bal == null:
		return 0.0
	var lv := maxi(hero_level, 1)
	return float(bal.str_base) + float(lv - 1) * bal.st_rplus


## 当前是否允许自然回血（不含 rate==0）。
static func allows_hp_regen(regen_type: String) -> bool:
	var t := regen_type.strip_edges().to_lower()
	if t.is_empty() or t == "none" or t == "-":
		return false
	# always：常驻。blight / night 等条件回复待世界系统接入后再开。
	return t == "always"


static func hp_rate_from_balance(bal: UnitBalanceDef, is_hero: bool, hero_level: int = 1) -> float:
	if bal == null or not allows_hp_regen(bal.regen_type):
		return 0.0
	var rate := maxf(bal.regen_hp, 0.0)
	if is_hero:
		rate += strength_at_level(bal, hero_level) * HERO_HP_REGEN_PER_STR
	return rate


static func mana_rate_from_balance(bal: UnitBalanceDef, is_hero: bool, hero_level: int = 1) -> float:
	if bal == null:
		return 0.0
	var rate := maxf(bal.regen_mana, 0.0)
	if is_hero:
		var lv := maxi(hero_level, 1)
		var intel := float(bal.int_base) + float(lv - 1) * bal.in_tplus
		rate += intel * HERO_MANA_REGEN_PER_INT
	return rate


static func hp_rate_per_sec(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	var bal := CombatQuery.balance_of(node)
	var tid := CombatQuery.type_id_of(node)
	return hp_rate_from_balance(bal, TechPresence.is_hero_id(tid), AbilityCatalog.hero_level_of(node))


static func mana_rate_per_sec(node: Node3D) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	if not UnitMana.has_mana(node):
		return 0.0
	var bal := CombatQuery.balance_of(node)
	var tid := CombatQuery.type_id_of(node)
	var rate := mana_rate_from_balance(bal, TechPresence.is_hero_id(tid), AbilityCatalog.hero_level_of(node))
	rate += BuffQuery.mana_regen_bonus(node)
	return rate


static func can_tick(node: Node3D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	if not WorldMembership.is_in_world(node):
		return false
	if UnitLife.is_under_construction(node):
		return false
	if UnitLife.get_life(node) <= 0.0:
		return false
	return true


## 单单位每帧自然回复（HP + 蓝）。
static func tick_unit(node: Node3D, delta: float) -> void:
	if delta <= 0.0 or not can_tick(node):
		return
	var hp_rate := hp_rate_per_sec(node)
	if hp_rate > 0.0:
		UnitLife.regenerate(node, hp_rate * delta)
	var mana_rate := mana_rate_per_sec(node)
	if mana_rate > 0.0:
		UnitMana.regenerate(node, mana_rate * delta)
