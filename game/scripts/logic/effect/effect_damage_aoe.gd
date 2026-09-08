class_name EffectDamageAoe
extends RefCounted

## AOE 伤害原子：半径内目标走 DamagePipeline（spell）。
## - run：仅敌军（雷霆一击等）
## - run_all_victims：友伤全量（暴风雪等，含建筑）


static func run(
	ec: EffectContext,
	center_wc3: Vector2,
	radius_wc3: float,
	damage: float,
	atk_type: String = "magic"
) -> Array:
	var hits: Array = []
	if ec == null or damage <= 0.0:
		return hits
	var pipe := ec.damage_pipeline()
	var host := ec.unit_host()
	if pipe == null or host == null or ec.caster == null:
		return hits
	var foes := CombatQuery.units_hostile_in_radius(host, ec.caster, center_wc3, radius_wc3)
	for n in foes:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var foe := n as Node3D
		var result := pipe.apply({
			"attacker": ec.caster,
			"target": foe,
			"source_kind": "spell",
			"spell_abil_id": ec.abil_id,
			"atk_type": atk_type,
			"dice": 0,
			"sides": 1,
			"dmgplus": damage,
		})
		if bool(result.get("ok", false)):
			hits.append(foe)
	ec.result["hit_count"] = hits.size()
	ec.result["hit_units"] = hits
	return hits


## 友伤 AOE：`units_blizzard_victims_in_radius`（扣 collision）；建筑可乘系数。
static func run_all_victims(
	ec: EffectContext,
	center_wc3: Vector2,
	radius_wc3: float,
	damage: float,
	atk_type: String = "spells",
	building_damage_factor: float = 1.0,
	play_hit_fx: bool = true
) -> Array:
	var hits: Array = []
	if ec == null or damage <= 0.0:
		return hits
	var pipe := ec.damage_pipeline()
	var host := ec.unit_host()
	if pipe == null or host == null or ec.caster == null:
		return hits
	var victims := CombatQuery.units_blizzard_victims_in_radius(
		host, ec.caster, center_wc3, radius_wc3
	)
	var hit_art := ""
	if play_hit_fx:
		hit_art = AbilityCastCatalog.hit_effect_art(ec.abil_id)
	var cache := ec.model_cache()
	for n in victims:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var unit := n as Node3D
		var dmg := damage
		var tid := CombatQuery.type_id_of(unit)
		if building_damage_factor < 1.0 and BuildingCatalog.is_building(tid):
			dmg *= building_damage_factor
		var result := pipe.apply({
			"attacker": ec.caster,
			"target": unit,
			"source_kind": "spell",
			"spell_abil_id": ec.abil_id,
			"atk_type": atk_type,
			"dice": 0,
			"sides": 1,
			"dmgplus": dmg,
		})
		if not bool(result.get("ok", false)):
			continue
		hits.append(unit)
		if play_hit_fx:
			if not hit_art.is_empty():
				SpellHitFx.spawn_on(unit, hit_art, cache)
			UnitHitFlash.flash(unit, true)
	ec.result["hit_count"] = hits.size()
	ec.result["hit_units"] = hits
	return hits
