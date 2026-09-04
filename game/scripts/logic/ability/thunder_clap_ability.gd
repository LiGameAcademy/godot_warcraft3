class_name ThunderClapAbility
extends RefCounted

## 雷霆一击 AHtc（Logic）：AOE 伤 + 减速。

const ABIL_ID := "AHtc"


static func try_cast(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	if abil_id.strip_edges() != ABIL_ID:
		return {"ok": false, "reason": "未实现的技能", "unit": null}
	var ec := EffectContext.from_cast(caster, ABIL_ID, ctx)
	var check := AbilityCastRules.can_cast_self(caster, ABIL_ID, ec.level)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return ec.fail("无技能数据")
	if ec.damage_pipeline() == null or ec.unit_host() == null:
		return ec.fail("战斗服务未就绪")
	var radius := maxf(ab.area_at(ec.level), 1.0)
	var dmg := maxf(ab.data_a_at(ec.level), 0.0)
	var slow_dur := maxf(ab.duration_at(ec.level), 0.0)
	var move_mul := clampf(1.0 - maxf(ab.data_c_at(ec.level), 0.0), 0.05, 1.0)
	if ab.data_d_at(ec.level) > 0.0:
		move_mul = clampf(ab.data_d_at(ec.level), 0.05, 1.0)
	var center := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var hits := EffectDamageAoe.run(ec, center, radius, dmg)
	if slow_dur > 0.0:
		for foe in hits:
			if foe is Node3D:
				EffectApplyBuff.apply_slow(foe as Node3D, slow_dur, move_mul)
	EffectPlayPresent.hit_caster(ec)
	EffectPlayPresent.cast_gesture(ec, center)
	AbilityCastRules.commit_cost(caster, ABIL_ID, ec.level)
	return ec.succeed({"hit_count": hits.size()})
