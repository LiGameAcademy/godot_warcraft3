class_name InnerFireAbility
extends RefCounted

## 心灵之火 Ainf（Logic）：友军 buff +HP/攻/甲（P0：攻/甲）。

const ABIL_ID := "Ainf"


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
		out["reason"] = "无效友军目标"
		return out
	var lv := AbilityCatalog.level_for(caster, ABIL_ID)
	var check := AbilityCastRules.can_cast_unit(caster, ABIL_ID, target, lv)
	if not bool(check.get("ok", false)):
		return check
	var ctrl := InnerFireController.ensure_on(target)
	if ctrl == null:
		return {"ok": false, "reason": "无法施加 buff"}
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	if ctrl.is_active():
		ctrl.refresh(lv, cache)
	else:
		if not ctrl.activate(lv, cache):
			return {"ok": false, "reason": "激活失败"}
	AbilityCastPresenter.begin(
		caster, ABIL_ID, false, Wc3Coords.godot_to_wc3_xy(target.global_position)
	)
	AbilityCastPresenter.end(caster)
	AbilityCastRules.commit_cost(caster, ABIL_ID, lv)
	out["ok"] = true
	out["buff_target"] = target
	return out
