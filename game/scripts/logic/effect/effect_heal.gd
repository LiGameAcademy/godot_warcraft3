class_name EffectHeal
extends RefCounted

## 治疗原子：按 AbilityData 字段回血（默认 data_a）。


static func run(ec: EffectContext, data_field: String = "data_a") -> float:
	if ec == null or ec.target == null or not is_instance_valid(ec.target):
		return 0.0
	var ab := AbilityCatalog.data(ec.abil_id)
	if ab == null:
		return 0.0
	var amount := 0.0
	match data_field:
		"data_b":
			amount = ab.data_b_at(ec.level)
		"data_c":
			amount = ab.data_c_at(ec.level)
		_:
			amount = ab.data_a_at(ec.level)
	amount = maxf(amount, 0.0)
	if amount <= 0.0:
		return 0.0
	UnitLife.ensure(ec.target)
	var before := UnitLife.get_life(ec.target)
	var mx := UnitLife.get_max_life(ec.target)
	var after := mini(before + amount, mx)
	UnitLife.set_life(ec.target, after)
	var healed := maxf(after - before, 0.0)
	ec.result["heal_amount"] = healed
	ec.result["heal_target"] = ec.target
	return healed
