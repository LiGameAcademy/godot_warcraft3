class_name EffectDamageAoe
extends RefCounted

## AOE 伤害原子：半径内敌军走 DamagePipeline（spell / magic）。


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
		pipe.apply({
			"attacker": ec.caster,
			"target": foe,
			"source_kind": "spell",
			"atk_type": atk_type,
			"dice": 0,
			"sides": 1,
			"dmgplus": damage,
		})
		hits.append(foe)
	ec.result["hit_count"] = hits.size()
	ec.result["hit_units"] = hits
	return hits
