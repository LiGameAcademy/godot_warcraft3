class_name UnitModelPresenter
extends RefCounted

## 单位模型、动画、粒子和交互组件绑定；不改变玩法状态。
var map_root: MapLoader

func configure(map: MapLoader) -> void:
	map_root = map

func ensure_visual(unit: Node3D) -> Unit:
	var cache: MapModelCache = null
	if map_root != null and map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	var u: Unit = Unit.of(unit)
	if u == null:
		# 旧存档/非 Unit 根：不应再挂 UnitVisual 子节点；尽量当实体用
		AppLog.warn(AppLog.Layer.PRESENT, "UnitModelPresenter", "ensure_unit: 非 Unit 根 %s" % unit)
		ensure_interaction(unit)
		return null
	u.bind_cache(cache)
	u.bind_animation_player(AnimPlayback.find_animation_player(u))
	ensure_interaction(u)
	return u


func ensure_interaction(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var d: Dictionary = unit.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	var kind := InteractableComponent.SmartKind.NONE
	if tid == "ngol":
		kind = InteractableComponent.SmartKind.GOLD_MINE
	InteractionSetup.attach(unit, kind)


func swap_model(unit: Node3D, type_id: String, owner_id: int, variation: int) -> bool:
	if map_root == null:
		return false
	var cache: MapModelCache = null
	var catalog = null
	if map_root.has_method("get_model_cache"):
		cache = map_root.get_model_cache()
	if map_root.has_method("get_id_catalog"):
		catalog = map_root.get_id_catalog()
	if cache == null or catalog == null:
		return false
	var glb: String = catalog.converted_glb_path(type_id, variation)
	if glb.is_empty():
		return false
	var unit_soft := not BuildingVisual.is_building(type_id)
	var inst: Node3D = cache.instance_glb(glb, unit_soft) as Node3D
	if inst == null:
		return false
	var color_i := MapUnitLayer.resolve_team_color_index(type_id, owner_id)
	cache.apply_team_color(inst, color_i, false)
	inst.name = Unit.MODEL_NODE_NAME
	var u: Unit = Unit.of(unit)
	var old: Node3D = null
	if u != null:
		old = u.model_node()
	else:
		old = unit.get_node_or_null(Unit.MODEL_NODE_NAME) as Node3D
	if old != null:
		old.name = "Model_Old"
		old.queue_free()
	unit.remove_meta(AnimPlayback.META_ANIM_PLAYER)
	unit.add_child(inst)
	# 新 Model 置顶（旧节点可能延后释放）
	unit.move_child(inst, 0)
	var vis := ensure_visual(unit)
	var ap := AnimPlayback.find_animation_player(inst)
	if ap == null:
		ap = AnimPlayback.find_animation_player(unit)
	if vis != null:
		vis.bind_cache(cache)
		vis.bind_animation_player(ap)
	var u2 := Unit.of(unit)
	if u2 != null and ap != null:
		u2.bind_animation_player(ap)
	if ap != null:
		AnimPlayback.bind_animation_player(unit, ap)
	cache.autoplay_stand(unit)
	if cache.has_method("snap_stand_geoset_visibility"):
		cache.call("snap_stand_geoset_visibility", unit)
	if Wc3Pe2Particles.has_emitters(glb):
		Wc3Pe2Particles.attach_to(unit, glb)
		Wc3Pe2Particles.apply_sequence(unit, "Stand")
	return true


func apply_building_phase(building: Node3D, type_id: String) -> void:
	var u := Unit.of(building)
	if u != null:
		u.set_stance(AnimSequenceResolver.stance_for_building_type(type_id), true)
	var cache: MapModelCache = map_root.get_model_cache() if map_root != null else null
	if cache != null:
		BuildingVisual.apply_phase(cache, building, type_id, BuildingVisual.Phase.IDLE)
		cache.snap_stand_geoset_visibility(building)
