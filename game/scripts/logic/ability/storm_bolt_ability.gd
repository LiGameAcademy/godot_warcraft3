class_name StormBoltAbility
extends RefCounted

## 风暴之锤 AHtb（Logic）：弹道 + 伤害 + 眩晕。

const ABIL_ID := "AHtb"
const MISSILE_SPEED := 1000.0


static func try_cast(
	caster: Node3D,
	abil_id: String,
	target: Node3D,
	ctx: Dictionary
) -> Dictionary:
	if abil_id.strip_edges() != ABIL_ID:
		return {"ok": false, "reason": "未实现的技能", "unit": null}
	var ec := EffectContext.from_cast(caster, ABIL_ID, ctx, target)
	if caster == null or target == null or not is_instance_valid(caster) or not is_instance_valid(target):
		return ec.fail("无效目标")
	if not CombatQuery.is_valid_ability_unit_target(caster, target, ABIL_ID):
		return ec.fail("无效敌军目标")
	var check := AbilityCastRules.can_cast_unit(caster, ABIL_ID, target, ec.level)
	if not bool(check.get("ok", false)):
		return check
	var ab := AbilityCatalog.data(ABIL_ID)
	if ab == null:
		return ec.fail("无技能数据")
	var pipe := ec.damage_pipeline()
	var projectiles := ec.projectile_service()
	if pipe == null or projectiles == null:
		return ec.fail("战斗服务未就绪")
	var dmg := maxf(ab.data_a_at(ec.level), 0.0)
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
		"stun_sec": UnitStatusEffects.stun_duration_for(ab, ec.level, target),
	}
	projectiles.fire_spell(caster, target, req, MISSILE_SPEED, extra)
	AbilityCastRules.commit_cost(caster, ABIL_ID, ec.level)
	EffectPlayPresent.cast_gesture(ec)
	return ec.succeed({"spell_target": target})
