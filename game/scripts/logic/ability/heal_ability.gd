class_name HealAbility
extends RefCounted

## 治疗 Ahea（Logic）：友军点目标即时回血。

const ABIL_ID := "Ahea"


static func try_cast(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	if abil_id.strip_edges() != ABIL_ID:
		out["reason"] = "未实现的技能"
		return out
	if caster == null or target == null or not is_instance_valid(caster) or not is_instance_valid(target):
		out["reason"] = "无效目标"
		return out
	if not CombatQuery.is_valid_ally_spell_target(caster, target):
		out["reason"] = "无效友军目标"
		return out
	var lv := AbilityCatalog.level_for(caster, ABIL_ID)
	var check := AbilityCastRules.can_cast_unit(caster, ABIL_ID, target, lv)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	var amount := maxf(ab.data_a_at(lv), 0.0)
	if amount <= 0.0:
		return {"ok": false, "reason": "无治疗量"}
	UnitLife.ensure(target)
	var before := UnitLife.get_life(target)
	var mx := UnitLife.get_max_life(target)
	var after := mini(before + amount, mx)
	UnitLife.set_life(target, after)
	var healed := maxf(after - before, 0.0)
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	var hit_art := AbilityCastCatalog.hit_effect_art(ABIL_ID)
	if not hit_art.is_empty():
		SpellHitFx.spawn_on(target, hit_art, cache)
	AbilityCastPresenter.begin(
		caster, ABIL_ID, false, Wc3Coords.godot_to_wc3_xy(target.global_position)
	)
	AbilityCastPresenter.end(caster)
	AbilityCastRules.commit_cost(caster, ABIL_ID, lv)
	out["ok"] = true
	out["heal_target"] = target
	out["heal_amount"] = healed
	return out
