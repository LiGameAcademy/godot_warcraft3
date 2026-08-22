class_name ThunderClapAbility
extends RefCounted

## 雷霆一击 AHtc（Logic）：以施法者为中心对敌军 AOE 伤害 + 减速。

const ABIL_ID := "AHtc"


static func try_cast(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	if abil_id.strip_edges() != ABIL_ID:
		out["reason"] = "未实现的技能"
		return out
	var lv := AbilityCatalog.level_for(caster, ABIL_ID)
	var check := AbilityCastRules.can_cast_self(caster, ABIL_ID, lv)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	var pipeline: Variant = ctx.get("damage_pipeline")
	var host_cb: Callable = ctx.get("unit_host", Callable())
	if pipeline == null or not host_cb.is_valid():
		return {"ok": false, "reason": "战斗服务未就绪"}
	var unit_host: Node = host_cb.call() as Node
	if unit_host == null:
		return {"ok": false, "reason": "单位层未就绪"}
	var radius := maxf(ab.area_at(lv), 1.0)
	var dmg := maxf(ab.data_a_at(lv), 0.0)
	var slow_dur := maxf(ab.duration_at(lv), 0.0)
	var move_mul := clampf(1.0 - maxf(ab.data_c_at(lv), 0.0), 0.05, 1.0)
	if ab.data_d_at(lv) > 0.0:
		move_mul = clampf(ab.data_d_at(lv), 0.05, 1.0)
	var center := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var hits := CombatQuery.units_hostile_in_radius(unit_host, caster, center, radius)
	var pipe := pipeline as DamagePipeline
	for n in hits:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var foe := n as Node3D
		if dmg > 0.0:
			pipe.apply({
				"attacker": caster,
				"target": foe,
				"source_kind": "spell",
				"atk_type": "magic",
				"dice": 0,
				"sides": 1,
				"dmgplus": dmg,
			})
		if slow_dur > 0.0:
			UnitStatusEffects.apply_slow(foe, slow_dur, move_mul)
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	var clap_art := AbilityCastCatalog.caster_art(ABIL_ID)
	if not clap_art.is_empty():
		SpellHitFx.spawn_on(caster, clap_art, cache)
	AbilityCastPresenter.begin(caster, ABIL_ID, false, center)
	AbilityCastPresenter.end(caster)
	AbilityCastRules.commit_cost(caster, ABIL_ID, lv)
	out["ok"] = true
	out["hit_count"] = hits.size()
	return out
