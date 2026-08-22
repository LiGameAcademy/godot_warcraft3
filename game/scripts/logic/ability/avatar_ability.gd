class_name AvatarAbility
extends RefCounted

## 天神下凡 AHav（Logic）：自 buff，委托 AvatarController。

const ABIL_ID := "AHav"


static func try_cast(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	if abil_id.strip_edges() != ABIL_ID:
		out["reason"] = "未实现的技能"
		return out
	var lv := AbilityCatalog.level_for(caster, ABIL_ID)
	var check := AbilityCastRules.can_cast_self(caster, ABIL_ID, lv)
	if not bool(check.get("ok", false)):
		return check
	var ctrl := AvatarController.ensure_on(caster)
	if ctrl == null:
		return {"ok": false, "reason": "无法激活天神"}
	if ctrl.is_active():
		return {"ok": false, "reason": "已在天神下凡"}
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	if not ctrl.activate(lv, cache):
		return {"ok": false, "reason": "激活失败"}
	AbilityCastRules.commit_cost(caster, ABIL_ID, lv)
	AbilityCastPresenter.begin(caster, ABIL_ID, false, Vector2.INF)
	AbilityCastPresenter.end(caster)
	out["ok"] = true
	return out
