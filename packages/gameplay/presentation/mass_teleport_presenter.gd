class_name MassTeleportPresenter
extends RefCounted

## 群体传送表现（Present · AHmt）：读条期施法者光环、出发脚印、落点特效。
## FX 挂单位实体根（on_entity_root），避免进 MODEL_SCALE≈0.01 子树被二次缩小。

const ABIL_ID := "AHmt"
const CASTER_FX_NAME := "MassTeleportCasterFx"
const DEST_MARKER_NAME := "MassTeleportDestMarker"
const SFX_KEY := "MassTeleportTarget"
## 落点预览圈半径（WC3）：标记落点，非选人 Area。
const DEST_PREVIEW_RADIUS_WC3 := 140.0
const DEST_COLOR := Color(0.55, 0.88, 1.0, 0.78)


static func begin_cast(caster: Node3D, goal_wc3: Vector2, cast_sec: float, ctx: Dictionary) -> void:
	if caster == null or not is_instance_valid(caster):
		return
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	var art := AbilityFxCatalog.caster_art(ABIL_ID)
	AbilityAttachFxPresenter.sync_attach(
		caster,
		CASTER_FX_NAME,
		art,
		true,
		cache,
		Vector3(0.0, 0.05, 0.0),
		true,
		"origin",
		1.0,
		true
	)
	_spawn_dest_marker(goal_wc3, cast_sec, ctx)


static func end_cast(caster: Node3D, ctx: Dictionary = {}) -> void:
	if caster != null and is_instance_valid(caster):
		AbilityAttachFxPresenter.sync_attach(caster, CASTER_FX_NAME, "", false)
	_clear_dest_marker(ctx)


## 在瞬移前调用：脚印留在旧坐标地面。
static func play_departures(units: Array, ctx: Dictionary) -> void:
	var special := AbilityFxCatalog.special_art(ABIL_ID)
	if special.is_empty():
		return
	var map_root: Node = ctx.get("map_root")
	var played_sfx := false
	for n in units:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var unit := n as Node3D
		_spawn_departure_footprint(unit, special, ctx)
		if not played_sfx and map_root != null:
			AbilitySfx.play_oneshot(map_root, SFX_KEY, unit.global_position)
			played_sfx = true


static func play_arrival(caster: Node3D, goal_wc3: Vector2, ctx: Dictionary) -> void:
	# 落点：MassTeleportTo（Birth 符文/光柱）
	AbilityCastPresenter.spawn_ground_effect(ABIL_ID, goal_wc3, 3.2, ctx)
	if caster == null or not is_instance_valid(caster):
		return
	var caster_art := AbilityFxCatalog.caster_art(ABIL_ID)
	if caster_art.is_empty():
		return
	# 到达后再闪一下施法者环（实体根，避免缩没）
	AbilityAttachFxPresenter.spawn_timed(
		caster,
		caster_art,
		2.0,
		ctx.get("model_cache") as MapModelCache,
		"origin",
		Vector3(0.0, 0.05, 0.0),
		true
	)
	var map_root: Node = ctx.get("map_root")
	if map_root != null:
		AbilitySfx.play_oneshot(map_root, SFX_KEY, caster.global_position)


static func _spawn_departure_footprint(unit: Node3D, art_rel: String, ctx: Dictionary) -> void:
	var map_root: Node = ctx.get("map_root")
	if map_root == null or unit == null:
		return
	var xy := Wc3Coords.godot_to_wc3_xy(unit.global_position)
	var cache: MapModelCache = ctx.get("model_cache") as MapModelCache
	var hf: Variant = ctx.get("heightfield")
	AbilityGroundFx.spawn(
		map_root,
		xy,
		art_rel,
		2.4,
		cache,
		hf as Wc3Heightfield if hf != null else null
	)


static func _spawn_dest_marker(goal_wc3: Vector2, cast_sec: float, ctx: Dictionary) -> void:
	_clear_dest_marker(ctx)
	var map_root: Node = ctx.get("map_root")
	if map_root == null or goal_wc3 == Vector2.INF:
		return
	var hf: Variant = ctx.get("heightfield")
	var marker := BlizzardAreaDecal.spawn(
		map_root,
		goal_wc3,
		DEST_PREVIEW_RADIUS_WC3,
		maxf(cast_sec, 0.35) + 0.35,
		hf as Wc3Heightfield if hf != null else null,
		DEST_COLOR
	)
	if marker != null:
		marker.name = DEST_MARKER_NAME


static func _clear_dest_marker(ctx: Dictionary) -> void:
	var map_root: Node = ctx.get("map_root")
	if map_root == null:
		return
	var existing := map_root.get_node_or_null(DEST_MARKER_NAME)
	if existing != null:
		existing.queue_free()
