class_name SlowAbility
extends RefCounted

## 减速 Aslo（Logic）：敌军点目标减速 + 攻速降低。

const ABIL_ID := "Aslo"


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
	if not CombatQuery.is_valid_ability_unit_target(caster, target, abil_id):
		out["reason"] = "无效敌军目标"
		return out
	var lv := AbilityCatalog.level_for(caster, ABIL_ID)
	var check := AbilityCastRules.can_cast_unit(caster, ABIL_ID, target, lv)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	var dur := maxf(ab.duration_at(lv), 0.0)
	var move_mul := clampf(ab.data_a_at(lv), 0.05, 1.0)
	var attack_mul := clampf(ab.data_b_at(lv), 0.05, 1.0)
	if dur > 0.0:
		UnitStatusEffects.apply_slow(target, dur, move_mul)
		UnitStatusEffects.apply_attack_slow(target, dur, attack_mul)
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	var hit_art := AbilityCastCatalog.hit_effect_art(ABIL_ID)
	if not hit_art.is_empty():
		SpellHitFx.spawn_on(target, hit_art, cache)
	var clap_art := AbilityCastCatalog.caster_art(ABIL_ID)
	if not clap_art.is_empty():
		SpellHitFx.spawn_on(caster, clap_art, cache)
	AbilityCastPresenter.begin(
		caster, ABIL_ID, false, Wc3Coords.godot_to_wc3_xy(target.global_position)
	)
	AbilityCastPresenter.end(caster)
	AbilityCastRules.commit_cost(caster, ABIL_ID, lv)
	out["ok"] = true
	out["spell_target"] = target
	return out
