class_name EffectContext
extends RefCounted

## 技能 Effect 管道上下文（Logic）：施法一次共用，原子读写 result。

var caster: Node3D = null
var target: Node3D = null
var goal_wc3 := Vector2.INF
var abil_id: String = ""
var level: int = 0
var ctx: Dictionary = {}
var ok: bool = true
var reason: String = ""
var result: Dictionary = {}


static func from_cast(
	p_caster: Node3D,
	p_abil_id: String,
	p_ctx: Dictionary,
	p_target: Node3D = null,
	p_goal: Vector2 = Vector2.INF
) -> EffectContext:
	var ec := EffectContext.new()
	ec.caster = p_caster
	ec.target = p_target
	ec.goal_wc3 = p_goal
	ec.abil_id = p_abil_id.strip_edges()
	ec.ctx = p_ctx
	ec.level = AbilityCatalog.level_for(p_caster, ec.abil_id) if p_caster != null else 0
	return ec


func model_cache() -> MapModelCache:
	return ctx.get("model_cache") as MapModelCache


func damage_pipeline() -> DamagePipeline:
	return ctx.get("damage_pipeline") as DamagePipeline


func projectile_service() -> ProjectileService:
	return ctx.get("projectile_service") as ProjectileService


func unit_host() -> Node:
	var cb: Callable = ctx.get("unit_host", Callable())
	if not cb.is_valid():
		return null
	return cb.call() as Node


func fail(p_reason: String) -> Dictionary:
	ok = false
	reason = p_reason
	return to_dict()


func succeed(extra: Dictionary = {}) -> Dictionary:
	ok = true
	reason = ""
	for k in extra.keys():
		result[k] = extra[k]
	return to_dict()


func to_dict() -> Dictionary:
	var out := {
		"ok": ok,
		"reason": reason,
		"unit": result.get("unit", null),
	}
	for k in result.keys():
		out[k] = result[k]
	return out
