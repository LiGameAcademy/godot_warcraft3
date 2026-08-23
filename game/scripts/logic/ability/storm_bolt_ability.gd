class_name StormBoltAbility
extends RefCounted

## 风暴之锤 AHtb（Logic）：单位目标魔法弹道 + 伤害 + 眩晕。

const ABIL_ID := "AHtb"
const MISSILE_SPEED := 1000.0


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
	var pipeline: Variant = ctx.get("damage_pipeline")
	var projectiles: Variant = ctx.get("projectile_service")
	if pipeline == null or projectiles == null:
		return {"ok": false, "reason": "战斗服务未就绪"}
	var dmg := maxf(ab.data_a_at(lv), 0.0)
	var req := {
		"attacker": caster,
		"target": target,
		"source_kind": "spell",
		"atk_type": "magic",
		"dice": 0,
		"sides": 1,
		"dmgplus": dmg,
	}
	var extra := {
		"spell_abil_id": ABIL_ID,
		"missile_art": AbilityCastCatalog.missile_art(ABIL_ID),
		"impact_art": AbilityCastCatalog.hit_effect_art(ABIL_ID),
	}
	var stun_sec := UnitStatusEffects.stun_duration_for(ab, lv, target)
	extra["stun_sec"] = stun_sec
	(projectiles as ProjectileService).fire_spell(
		caster, target, req, MISSILE_SPEED, extra
	)
	AbilityCastRules.commit_cost(caster, ABIL_ID, lv)
	AbilityCastPresenter.begin(caster, ABIL_ID, false, Vector2.INF)
	AbilityCastPresenter.end(caster)
	out["ok"] = true
	out["spell_target"] = target
	return out
