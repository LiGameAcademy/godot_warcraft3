class_name AbilityCastPresenter
extends RefCounted

## 技能施法表现（Present）：朝向、Spell Sequence、地面特效。


static func begin(caster: Node3D, abil_id: String, channel: bool, goal_wc3: Vector2) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	_face_goal(caster, goal_wc3)
	var seq := AbilityCastCatalog.spell_sequence_for(abil_id)
	var u := Unit.of(caster)
	if u != null:
		u.play_spell_cast(seq, channel)
	else:
		_play_spell_on_body(caster, seq)


static func end(caster: Node3D) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var u := Unit.of(caster)
	if u != null:
		u.end_spell_cast()


static func spawn_ground_effect(
	abil_id: String,
	goal_wc3: Vector2,
	duration_sec: float,
	ctx: Dictionary
) -> void:
	var art := AbilityCastCatalog.ground_effect_art(abil_id)
	if art.is_empty():
		return
	var map_root: Node = ctx.get("map_root")
	if map_root == null:
		return
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	var hf: Variant = ctx.get("heightfield")
	AbilityGroundFx.spawn(
		map_root,
		goal_wc3,
		art,
		duration_sec,
		cache,
		hf as Wc3Heightfield if hf != null else null
	)


## 单位附着一次性特效（传送 Caster/Target 等）；lifetime 后自动清。
static func spawn_unit_timed_fx(
	host: Node3D,
	art_rel: String,
	lifetime_sec: float,
	ctx: Dictionary,
	attach_hint: String = "origin",
	local_offset: Vector3 = Vector3(0.0, 0.05, 0.0),
	on_entity_root: bool = true
) -> void:
	if host == null or not is_instance_valid(host) or art_rel.strip_edges().is_empty():
		return
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	AbilityAttachFxPresenter.spawn_timed(
		host,
		art_rel,
		lifetime_sec,
		cache,
		attach_hint,
		local_offset,
		on_entity_root
	)


static func _face_goal(caster: Node3D, goal_wc3: Vector2) -> void:
	if goal_wc3 == Vector2.INF:
		return
	var from := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var dir := goal_wc3 - from
	if dir.length_squared() < 1.0:
		return
	caster.rotation.y = atan2(dir.y, dir.x)


static func _play_spell_on_body(body: Node3D, logical: String) -> void:
	var ap := AnimPlayback.find_animation_player(body)
	var fallbacks := ["Spell Throw", "Spell Channel", "Spell", "Attack"]
	AnimPlayback.play_logical(body, logical, 0.0, null, 0, fallbacks, ap)
	Wc3Pe2Particles.apply_sequence(body, logical)
