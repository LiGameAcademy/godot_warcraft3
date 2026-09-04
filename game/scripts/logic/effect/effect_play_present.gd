class_name EffectPlayPresent
extends RefCounted

## Present 原子：命中/施法者特效 + CastPresenter（Logic 不直接 new 粒子）。


static func hit_target(ec: EffectContext, art_override: String = "") -> void:
	if ec == null or ec.target == null or not is_instance_valid(ec.target):
		return
	var art := art_override.strip_edges()
	if art.is_empty():
		art = AbilityCastCatalog.hit_effect_art(ec.abil_id)
	if art.is_empty():
		return
	SpellHitFx.spawn_on(ec.target, art, ec.model_cache())


static func hit_caster(ec: EffectContext, art_override: String = "") -> void:
	if ec == null or ec.caster == null or not is_instance_valid(ec.caster):
		return
	var art := art_override.strip_edges()
	if art.is_empty():
		art = AbilityCastCatalog.caster_art(ec.abil_id)
	if art.is_empty():
		return
	SpellHitFx.spawn_on(ec.caster, art, ec.model_cache())


static func cast_gesture(ec: EffectContext, look_at: Vector2 = Vector2.INF) -> void:
	if ec == null or ec.caster == null or not is_instance_valid(ec.caster):
		return
	var goal := look_at
	if goal == Vector2.INF and ec.target != null and is_instance_valid(ec.target):
		goal = Wc3Coords.godot_to_wc3_xy(ec.target.global_position)
	elif goal == Vector2.INF and ec.goal_wc3 != Vector2.INF:
		goal = ec.goal_wc3
	AbilityCastPresenter.begin(ec.caster, ec.abil_id, false, goal)
	AbilityCastPresenter.end(ec.caster)
