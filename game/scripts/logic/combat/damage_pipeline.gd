class_name DamagePipeline
extends RefCounted

## 单位伤害唯一入口（Logic）。树伤仍走 TreeRegistry.apply_damage。

signal damage_applied(result: Dictionary)

var rng: CombatRng = CombatRng.new()
var death: DeathService = null


## StrikeRequest 字段：
##   attacker: Node3D, target: Node3D
##   atk_type / dice / sides / dmgplus（可省略 → 读武器表）
##   source_kind: "weapon" | "spell" | …
func apply(req: Dictionary) -> Dictionary:
	var empty := {
		"ok": false,
		"amount": 0.0,
		"killed": false,
		"attacker": null,
		"target": null,
	}
	var attacker: Node3D = req.get("attacker") as Node3D
	var target: Node3D = req.get("target") as Node3D
	if attacker == null or target == null:
		return empty
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return empty
	if not WorldMembership.is_in_world(target):
		return empty
	var source_kind := str(req.get("source_kind", "weapon"))
	# 技能 AOE（暴风雪等）走友伤过滤，不要求敌对/同主。
	if source_kind == "spell":
		if not CombatQuery.is_valid_spell_aoe_target(attacker, target):
			return empty
	elif not CombatQuery.is_valid_attack_target(attacker, target):
		return empty
	if UnitLife.get_life(target) <= 0.0:
		return empty

	var atk_type := str(req.get("atk_type", "")).strip_edges()
	var dice := int(req.get("dice", -1))
	var sides := int(req.get("sides", -1))
	var dmgplus := float(req.get("dmgplus", -1.0))
	if atk_type.is_empty() or dice < 0 or sides < 0 or dmgplus < 0.0:
		var w := CombatQuery.weapons_of(attacker)
		if w != null:
			if atk_type.is_empty():
				atk_type = w.atk_type1
			if dice < 0:
				dice = w.dice1
			if sides < 0:
				sides = w.sides1
			if dmgplus < 0.0:
				dmgplus = w.dmgplus1
	if dice < 0:
		dice = 0
	if sides < 1:
		sides = 1
	if dmgplus < 0.0:
		dmgplus = 0.0

	var roll := dmgplus
	for _i in range(dice):
		roll += float(rng.randi_range(1, maxi(sides, 1)))
	if source_kind == "weapon" and attacker is Node3D:
		roll *= UnitStatusEffects.damage_mul(attacker as Node3D)

	var def_type := "none"
	var armor := 0.0
	var bal := CombatQuery.balance_of(target)
	if bal != null:
		def_type = bal.def_type
		armor = bal.realdef if bal.realdef != 0.0 else bal.def
	armor += UnitStatusEffects.bonus_armor(target)

	var mult := CombatDamageTable.multiplier(atk_type, def_type)
	var after_type := roll * mult
	if CombatDamageTable.normalize_atk(atk_type) == "pierce":
		after_type *= DefendController.pierce_taken_factor(target)
	var amount := CombatDamageTable.apply_armor(after_type, armor)
	# 最低伤：有命中时至少 1（对齐常见 WC3 观感；0 骰全 0 除外）
	if amount > 0.0 and amount < 1.0:
		amount = 1.0

	var life_before := UnitLife.get_life(target)
	var life_after := maxf(0.0, life_before - amount)
	UnitLife.set_life(target, life_after)
	var killed := life_after <= 0.0
	if killed and death != null:
		death.kill(target, attacker)

	var result := {
		"ok": true,
		"amount": amount,
		"roll": roll,
		"mult": mult,
		"armor": armor,
		"atk_type": atk_type,
		"def_type": def_type,
		"killed": killed,
		"attacker": attacker,
		"target": target,
		"source_kind": source_kind,
	}
	damage_applied.emit(result)
	return result
