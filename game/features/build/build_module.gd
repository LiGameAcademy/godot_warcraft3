class_name BuildModule
extends Node

## 对局内建造调度：BuildSite 注册表、放置 / 瞄准视觉、开工/完工/取消、HUD 工地绑定。
## 总管只保留窄入口（begin/cancel/commit/issue_build 等），背后状态在本模块内。
## 召唤 / 建造完工入图 / 复活继续走总管入口，模块内只认 BuildOrder 与半成品。

signal construction_started(order: BuildOrder)
signal construction_progress(key: String, ratio: float, elapsed: float, total: float)
signal construction_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int)
signal construction_cancelled(order: BuildOrder)
signal placement_changed(building_id: String, site_wc3: Vector2, valid: bool)
signal placement_committed(building_id: String, site_wc3: Vector2)
signal placement_cancelled_notice()

const HUD_NODE_NAME := "BuildHudSite"

var _map_root: MapLoader
var _heightfield: Wc3Heightfield
var _pathing: Wc3PathingMap
var _path_query: PathQuery
var _crowd_query: UnitCrowdQuery
var _command_router: CommandRouter
var _session: GameSession
var _health_bar_manager: HealthBarManager
var _game_hud: GameHud
var _refresh_pathing: Callable
var _alloc_creation_number: Callable
var _build_entry_for: Callable
var _find_anim_player: Callable
var _issue_move: Callable
var _ensure_navigator: Callable
var _ensure_unit_visual: Callable
var _resync_health_bars: Callable
## (screen_pos: Vector2) -> Vector3；与 Director._ground_at_screen 同源（Heightfield 射线）。
var _ground_at_screen: Callable

## 工地宿主（工人离开后 BuildSite 挂于此）。
var _sites_host: Node = null
## "%s_x_y" → BuildSite
var _sites_by_key: Dictionary = {}
## building instance_id → BuildSite
var _sites_by_building: Dictionary = {}
## construction_key → { cn, node, building_id, site }
var _active_construction: Dictionary = {}

## HUD 当前绑定的工地。
var _hud_site: BuildSite = null

## 瞄准控制器 / 幽灵。
var _placement: BuildPlacementController = null
var _ghost: BuildPlacementGhost = null
## 是否处于工地钉住状态：开工令下达但工人尚未到位的工地。
var _site_ghost_pinned: bool = false
## 进入瞄准后需要先移动鼠标才能确认；避免同帧点 HUD 误提交。
var _confirm_armed: bool = false
## 最近一次光标坐标（GUI 检测 / 提交用）。
var _last_screen_pos: Vector2 = Vector2.ZERO


func configure(deps: Dictionary) -> void:
	_refresh_pathing = deps.get("refresh_pathing", Callable()) as Callable
	_map_root = deps.get("map_root") as MapLoader
	_heightfield = deps.get("heightfield") as Wc3Heightfield
	_pathing = deps.get("pathing") as Wc3PathingMap
	_path_query = deps.get("path_query") as PathQuery
	_crowd_query = deps.get("crowd_query") as UnitCrowdQuery
	_command_router = deps.get("command_router") as CommandRouter
	_session = deps.get("session") as GameSession
	_health_bar_manager = deps.get("health_bar_manager") as HealthBarManager
	_game_hud = deps.get("game_hud") as GameHud
	_alloc_creation_number = deps.get("alloc_creation_number", Callable()) as Callable
	_build_entry_for = deps.get("build_entry_for", Callable()) as Callable
	_find_anim_player = deps.get("find_anim_player", Callable()) as Callable
	_issue_move = deps.get("issue_move", Callable()) as Callable
	_ensure_navigator = deps.get("ensure_navigator", Callable()) as Callable
	_ensure_unit_visual = deps.get("ensure_unit_visual", Callable()) as Callable
	_resync_health_bars = deps.get("resync_health_bars", Callable()) as Callable
	_ground_at_screen = deps.get("ground_at_screen", Callable()) as Callable
	_ensure_sites_host()


func shutdown() -> void:
	cancel_placement()
	unbind_hud_site()
	_refresh_pathing = Callable()
	_map_root = null
	_heightfield = null
	_pathing = null
	_path_query = null
	_crowd_query = null
	_command_router = null
	_session = null
	_health_bar_manager = null
	_game_hud = null
	_alloc_creation_number = Callable()
	_build_entry_for = Callable()
	_find_anim_player = Callable()
	_issue_move = Callable()
	_ensure_navigator = Callable()
	_ensure_unit_visual = Callable()
	_resync_health_bars = Callable()
	_ground_at_screen = Callable()


func _exit_tree() -> void:
	shutdown()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		shutdown()


## 外部喂入当前光标位置（Director 的鼠标事件转发）。
func update_last_screen_pos(p: Vector2) -> void:
	_last_screen_pos = p


func _get_ground_hit_callable() -> Callable:
	return Callable(self, "_ground_hit_at_screen")


func _ground_hit_at_screen(screen_pos: Vector2) -> Vector3:
	_last_screen_pos = screen_pos
	# MapLoader 无地面拾取；必须走 Director 注入的 Heightfield 射线。
	if _ground_at_screen.is_valid():
		var hit: Variant = _ground_at_screen.call(screen_pos)
		if hit is Vector3:
			return hit as Vector3
	return Vector3.INF


func _heightfield_ref() -> Wc3Heightfield:
	return _heightfield


func _pathing_ref() -> Wc3PathingMap:
	return _pathing


func _path_query_ref() -> PathQuery:
	return _path_query


func _crowd_query_ref() -> UnitCrowdQuery:
	return _crowd_query


func _cell_reservation_ref() -> PathCellReservation:
	# BuildPlacementController 期望 pathing/cell_reservation 都可达；cell_reservation 由
	# Director 通过 path_query.bind_reservation 注入，这里复用 path_query 的引用。
	return _path_query_ref().reservation if _path_query != null else null


## BuildController 反查工地用（兼容旧 (site_wc3, building_id) 顺序）。
func find_site(site_wc3: Vector2, building_id: String) -> BuildSite:
	var key := site_lookup_key(building_id, site_wc3)
	var site: Variant = _sites_by_key.get(key)
	return site if is_instance_valid(site) and site.is_active() else null


func find_site_by_key(site_wc3: Vector2, building_id: String) -> BuildSite:
	return find_site(site_wc3, building_id)


func find_site_for_node(building_node: Node3D) -> BuildSite:
	if building_node == null or not is_instance_valid(building_node):
		return null
	var site: Variant = _sites_by_building.get(building_node.get_instance_id())
	if is_instance_valid(site) and site.is_active():
		return site
	var d: Dictionary = building_node.get_meta("unit_data", {})
	var bid := str(d.get("typeId", ""))
	var pos: Dictionary = d.get("position", {})
	return find_site(Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0))), bid)


func site_lookup_key(building_id: String, site_wc3: Vector2) -> String:
	if site_wc3 == Vector2.INF:
		return "%s_inf" % building_id
	return "%s_%.3f_%.3f" % [building_id, site_wc3.x, site_wc3.y]


func construction_key(order: BuildOrder) -> String:
	if order == null:
		return ""
	return site_lookup_key(order.building_id, order.site_wc3)


func build_entry_for(building_id: String, site_wc3: Vector2, player_owner: int, creation_number: int = -1) -> Dictionary:
	if _build_entry_for.is_valid():
		return _build_entry_for.call(building_id, site_wc3, player_owner, creation_number) as Dictionary
	return {
		"typeId": building_id,
		"position": {"x": site_wc3.x, "y": site_wc3.y},
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"owner": player_owner,
		"creationNumber": creation_number,
		"variation": 0,
		"isBuilding": true,
	}


func _alloc_cn() -> int:
	if _alloc_creation_number.is_valid():
		return int(_alloc_creation_number.call())
	return -1


## 工地宿主：BuildController 离开后 BuildSite 挂这里。
func _ensure_sites_host() -> void:
	if _sites_host != null and is_instance_valid(_sites_host):
		return
	var host := Node.new()
	host.name = "BuildSitesHost"
	host.add_to_group("build_sites_host")
	add_child(host)
	_sites_host = host


func register_site(site: BuildSite, building_node: Node3D, order: BuildOrder) -> void:
	if site == null or order == null:
		return
	var key := site_lookup_key(order.building_id, order.site_wc3)
	_sites_by_key[key] = site
	if building_node != null and is_instance_valid(building_node):
		_sites_by_building[building_node.get_instance_id()] = site
	if not site.build_completed.is_connected(_on_site_completed):
		site.build_completed.connect(_on_site_completed)


func unregister_site(order: BuildOrder, building_node: Node3D = null) -> void:
	if order == null:
		return
	var key := site_lookup_key(order.building_id, order.site_wc3)
	var site: Variant = _sites_by_key.get(key)
	_sites_by_key.erase(key)
	if is_instance_valid(site):
		if site.build_completed.is_connected(_on_site_completed):
			site.build_completed.disconnect(_on_site_completed)
	if building_node != null and is_instance_valid(building_node):
		_sites_by_building.erase(building_node.get_instance_id())
	if is_instance_valid(site) and site.is_active() == false:
		if site.get_parent() == _sites_host:
			site.queue_free()


func _on_site_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	# 与 BuildController 信号同名触发；BuildController 也会再发 build_completed，
	# _on_build_completed 用 _active_construction 状态机去重。
	on_construction_completed(order, site_wc3, player_owner)


## 半成品入图 → 注册工地 → 调进度 / 暂停表现 → 让位其它单位。
func on_construction_started(order: BuildOrder) -> void:
	if order == null or _map_root == null or _heightfield == null:
		return
	var key := construction_key(order)
	if _active_construction.has(key):
		return
	clear_pinned_ghost()
	var player_owner := order.owner
	if order.builder != null:
		var bc0 := order.builder.get_node_or_null("BuildController") as BuildController
		if bc0 != null and bc0.is_building() and _ensure_unit_visual.is_valid():
			var vis: Variant = _ensure_unit_visual.call(order.builder)
			if vis != null and vis.has_method("set_building_work"):
				vis.call("set_building_work", true)
	var cn := _alloc_cn()
	var entry := build_entry_for(order.building_id, order.site_wc3, player_owner, cn)
	entry["hitPoints"] = 5.0
	entry["under_construction"] = true
	var node := _map_root.add_unit_instance(entry, _heightfield.as_dict_view()) as Node3D
	if node == null:
		push_warning("BuildModule: 半成品建筑刷出失败 %s" % order.building_id)
		return
	UnitLife.ensure(node)
	UnitLife.set_under_construction(node, true)
	UnitLife.set_ratio(node, 0.05)
	var cache = map_root_get_model_cache()
	if cache != null:
		BuildingVisual.apply_phase(cache, node, order.building_id, BuildingVisual.Phase.BIRTH)
	var bc: BuildController = null
	if order.builder != null:
		bc = order.builder.get_node_or_null("BuildController") as BuildController
	var site: BuildSite = bc.current_site() if bc != null else null
	if site == null:
		site = find_site(order.site_wc3, order.building_id)
	_active_construction[key] = {
		"cn": cn,
		"node": node,
		"building_id": order.building_id,
		"site": site,
	}
	register_site(site, node, order)
	if site != null and not bool(site.get_meta("pause_wired", false)):
		site.set_meta("pause_wired", true)
		site.paused_changed.connect(_on_construction_paused.bind(key))
	if site != null:
		_apply_construction_paused(node, order.building_id, site.is_paused())
		var cb := _on_construction_progress.bind(key)
		if not site.progress_changed.is_connected(cb):
			site.progress_changed.connect(cb)
	_refresh_dynamic_pathing()
	_make_way_for_construction(order, node, site)
	if _resync_health_bars.is_valid():
		_resync_health_bars.call()
	construction_started.emit(order)
	if _game_hud != null:
		_game_hud.set_status("开工：%s" % order.building_id)


func on_construction_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	if order == null:
		return
	var key := construction_key(order)
	if not _active_construction.has(key):
		return
	var rec: Dictionary = _active_construction[key]
	var building_node: Node3D = rec.get("node") as Node3D
	_active_construction.erase(key)
	if building_node != null and is_instance_valid(building_node):
		UnitLife.set_under_construction(building_node, false)
		UnitLife.set_ratio(building_node, 1.0)
		var cache = map_root_get_model_cache()
		if cache != null:
			BuildingVisual.apply_phase(cache, building_node, order.building_id, BuildingVisual.Phase.IDLE)
	elif _map_root != null and _heightfield != null:
		var entry := build_entry_for(order.building_id, site_wc3, player_owner, _alloc_cn())
		_map_root.add_unit_instance(entry, _heightfield.as_dict_view())
		_refresh_dynamic_pathing()
	if _session != null:
		var stock := _session.stocks.get(player_owner) as PlayerStock
		if stock != null:
			var fmade: int = BuildingCatalog.get_food_made(order.building_id)
			if fmade > 0:
				stock.add_food_cap(fmade)
	unbind_hud_site()
	unregister_site(order, building_node)
	if _game_hud != null:
		_game_hud.clear_build_progress()
		_game_hud.set_status("完工：%s @ (%.0f, %.0f)" % [order.building_id, site_wc3.x, site_wc3.y])
	if _resync_health_bars.is_valid():
		_resync_health_bars.call()
	construction_completed.emit(order, site_wc3, player_owner)


func on_construction_cancelled(order: BuildOrder) -> void:
	clear_pinned_ghost()
	if order != null:
		var key := construction_key(order)
		if _active_construction.has(key):
			var rec: Dictionary = _active_construction[key]
			var cn := int(rec.get("cn", -1))
			var building_node: Node3D = rec.get("node") as Node3D
			if cn >= 0 and _map_root != null:
				_map_root.remove_unit_instance(cn)
				_refresh_dynamic_pathing()
			_active_construction.erase(key)
			unregister_site(order, building_node)
	unbind_hud_site()
	if _game_hud != null:
		_game_hud.clear_build_progress()
	if _resync_health_bars.is_valid():
		_resync_health_bars.call()
	construction_cancelled.emit(order)


func _on_construction_paused(paused: bool, key: String) -> void:
	if not _active_construction.has(key):
		return
	var rec: Dictionary = _active_construction[key]
	var node: Node3D = rec.get("node") as Node3D
	if node == null or not is_instance_valid(node):
		return
	_apply_construction_paused(node, str(rec.get("building_id", "")), paused)


func _on_construction_progress(elapsed: float, total: float, ratio: float, key: String) -> void:
	if not _active_construction.has(key):
		return
	var rec: Dictionary = _active_construction[key]
	var node: Node3D = rec.get("node") as Node3D
	if node == null or not is_instance_valid(node):
		return
	UnitLife.set_ratio(node, maxf(ratio, 0.05))
	construction_progress.emit(key, ratio, elapsed, total)
	_update_hud_if_relevant(key, ratio, elapsed, total)


func _apply_construction_paused(building: Node3D, building_id: String, paused: bool) -> void:
	if building == null:
		return
	if _find_anim_player.is_valid():
		var ap := _find_anim_player.call(building) as AnimationPlayer
		if ap != null:
			ap.speed_scale = 0.0 if paused else 1.0
	for n in building.find_children("*", "GPUParticles3D", true, false):
		(n as GPUParticles3D).emitting = not paused
	for n2 in building.find_children("*", "CPUParticles3D", true, false):
		(n2 as CPUParticles3D).emitting = not paused
	if not paused and not building_id.is_empty():
		var cache = map_root_get_model_cache()
		if cache != null:
			BuildingVisual.apply_phase(cache, building, building_id, BuildingVisual.Phase.BIRTH)


func _make_way_for_construction(order: BuildOrder, building_node: Node3D, site: BuildSite) -> void:
	if order == null or _map_root == null or _pathing == null:
		return
	var layer := _map_root.get_unit_layer()
	if layer == null:
		return
	var exclude: Array = []
	if building_node != null:
		exclude.append(building_node)
	if order.builder != null:
		exclude.append(order.builder)
	if site != null:
		for b in site.active_builders():
			exclude.append(b)
	var blockers: Array[Node3D] = BuildFootprintClearance.collect_blockers(
		layer, order.building_id, order.site_wc3, _pathing, _crowd_query, exclude
	)
	if blockers.is_empty():
		return
	var aabb: Rect2 = BuildFootprintClearance.footprint_aabb_wc3(
		order.building_id, order.site_wc3, _pathing
	)
	for unit in blockers:
		if unit == null or not is_instance_valid(unit):
			continue
		var tid := str(unit.get_meta("unit_data", {}).get("typeId", ""))
		var pos := Wc3Coords.godot_to_wc3_xy(unit.global_position)
		var goal: Vector2 = BuildFootprintClearance.resolve_outside(
			unit, tid, pos, order.site_wc3, aabb, _path_query, _crowd_query
		)
		if goal == Vector2.INF:
			continue
		if _command_router != null:
			_command_router.issue_move_to_wc3([unit], goal, UnitOrder.Source.UNKNOWN)
		elif _ensure_navigator.is_valid():
			var nav := _ensure_navigator.call(unit) as UnitNavigator
			if nav != null:
				nav.go_to_wc3(goal)


func map_root_get_model_cache() -> MapModelCache:
	if _map_root == null:
		return null
	if _map_root.has_method("get_model_cache"):
		return _map_root.call("get_model_cache") as MapModelCache
	return null


func _refresh_dynamic_pathing() -> void:
	if _refresh_pathing.is_valid():
		_refresh_pathing.call()


## HUD 工地：刷新选中或主动取消时调用。
func sync_hud_for_selection(primary_getter: Callable) -> void:
	if _game_hud == null or not primary_getter.is_valid():
		return
	var primary: Node3D = primary_getter.call() as Node3D
	if primary == null:
		unbind_hud_site()
		if _game_hud != null:
			_game_hud.clear_build_progress()
		return
	if UnitLife.is_under_construction(primary):
		var r := UnitLife.ratio(primary)
		var d: Dictionary = primary.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if _game_hud.has_method("clear_train_queue"):
			_game_hud.clear_train_queue()
		_game_hud.set_build_progress(true, r, "建造 %s %d%%" % [tid, int(round(r * 100.0))])
		unbind_hud_site()
		return
	var bc := primary.get_node_or_null("BuildController") as BuildController
	var site: BuildSite = bc.current_site() if bc != null else null
	if is_instance_valid(site) and site.is_active():
		if _game_hud.has_method("clear_train_queue"):
			_game_hud.clear_train_queue()
		bind_hud_site(site)
		var total := site.total()
		var ratio := 0.0 if total <= 0.0 else clampf(site.elapsed() / total, 0.0, 1.0)
		var order := site.current_order()
		var bid := order.building_id if order != null else ""
		_game_hud.set_build_progress(true, ratio, "建造 %s %d%%" % [bid, int(round(ratio * 100.0))])
		return
	unbind_hud_site()
	_game_hud.clear_build_progress()
	if _game_hud.has_method("clear_train_queue"):
		_game_hud.clear_train_queue()


func bind_hud_site(site: BuildSite) -> void:
	if site == null or site == _hud_site:
		return
	unbind_hud_site()
	_hud_site = site
	if not site.progress_changed.is_connected(_on_hud_site_progress):
		site.progress_changed.connect(_on_hud_site_progress)


func unbind_hud_site() -> void:
	if _hud_site != null and is_instance_valid(_hud_site):
		if _hud_site.progress_changed.is_connected(_on_hud_site_progress):
			_hud_site.progress_changed.disconnect(_on_hud_site_progress)
	_hud_site = null


func _on_hud_site_progress(elapsed: float, total: float, ratio: float) -> void:
	if _game_hud == null:
		return
	var bid := ""
	if _hud_site != null:
		var order := _hud_site.current_order()
		if order != null:
			bid = order.building_id
	var caption := "建造 %s %d%%" % [bid, int(round(ratio * 100.0))]
	if total > 0.0:
		caption += " · %.0f/%.0fs" % [elapsed, total]
	_game_hud.set_build_progress(true, ratio, caption)


func _update_hud_if_relevant(key: String, ratio: float, elapsed: float, total: float) -> void:
	# HUD 实时刷新：仅在 _hud_site 绑定的 key 上调一次。
	if _hud_site == null or _game_hud == null:
		return
	var site_order := _hud_site.current_order()
	if site_order == null or construction_key(site_order) != key:
		return
	var bid := str(site_order.building_id)
	var caption := "建造 %s %d%%" % [bid, int(round(ratio * 100.0))]
	if total > 0.0:
		caption += " · %.0f/%.0fs" % [elapsed, total]
	_game_hud.set_build_progress(true, ratio, caption)


## ───────────────── 放置 / 瞄准 ─────────────────


func is_build_targeting() -> bool:
	return _placement != null and _placement.is_active()


func current_placement_building_id() -> String:
	if _placement == null:
		return ""
	return _placement.current_building_id()


func is_placement_valid() -> bool:
	if _placement == null:
		return false
	return _placement.is_valid()


func begin_placement(building_id: String, screen_pos: Vector2, confirm_armed: bool) -> bool:
	if not BuildingCatalog.is_building(building_id):
		if _game_hud:
			_game_hud.set_status("未知建筑 %s" % building_id)
		return false
	_ensure_placement_objects()
	_ensure_ghost_node(building_id)
	_placement.begin(building_id)
	_confirm_armed = confirm_armed
	_last_screen_pos = screen_pos
	_placement.update_screen(screen_pos)
	_apply_ghost_to_screen()
	return true


func update_placement_screen(screen_pos: Vector2) -> void:
	if _placement == null:
		return
	_last_screen_pos = screen_pos
	_placement.update_screen(screen_pos)
	_apply_ghost_to_screen()


func cancel_placement() -> void:
	if _placement == null:
		return
	_placement.cancel()
	_confirm_armed = false
	clear_pinned_ghost()
	emit_placement_cancelled()


func commit_placement(screen_pos: Vector2, selected_getter: Callable, missing_required: Array, can_afford: bool) -> int:
	if _placement == null or not _placement.is_active():
		return 0
	_last_screen_pos = screen_pos
	_placement.update_screen(screen_pos)
	if not _placement.is_valid():
		if _game_hud:
			_game_hud.set_status("无法在此处建造（合法位置？）")
		return 0
	var bid := _placement.current_building_id()
	var site := _placement.current_site_wc3()
	if not can_afford:
		cancel_placement()
		return 0
	if not missing_required.is_empty():
		cancel_placement()
		return 0
	if not _placement.commit():
		return 0
	_confirm_armed = false
	var peasants: Array = []
	if selected_getter.is_valid():
		peasants = selected_getter.call()
	if _command_router == null:
		cancel_placement()
		return 0
	var peasants2: Array = _command_router.filter_peasants(peasants)
	var n := _command_router.issue_build(peasants2, bid, site, UnitOrder.Source.TARGETING)
	emit_placement_committed(bid, site)
	if n <= 0:
		clear_pinned_ghost()
		if _game_hud:
			_game_hud.set_status("建造下令失败（需选中空闲农民）")
		return n
	pin_site_ghost(bid, site)
	if _game_hud:
		_game_hud.set_status("建造：农民前往工地")
	return n


func pin_site_ghost(building_id: String, site_wc3: Vector2) -> void:
	_ensure_ghost_node(building_id)
	if _ghost == null:
		return
	_site_ghost_pinned = true
	var sample := PlacementRules.sample_footprint(building_id, site_wc3, _pathing)
	_ghost.update_from_sample(sample, _pathing, _heightfield, site_wc3)
	_ghost.set_valid(true)
	_ghost.set_pinned_style(true)
	_ghost.set_visible_preview(true)


func clear_pinned_ghost() -> void:
	_site_ghost_pinned = false
	if _ghost != null:
		_ghost.set_pinned_style(false)
		_ghost.set_visible_preview(false)


func _apply_ghost_to_screen() -> void:
	if _placement == null or _ghost == null:
		return
	if _site_ghost_pinned and not _placement.is_active():
		return
	if not _placement.is_active():
		return
	var site := _placement.current_site_wc3()
	if site == Vector2.INF:
		_ghost.set_visible_preview(false)
		return
	_ghost.set_visible_preview(true)
	_ghost.update_from_sample(
		_placement.current_footprint_sample(),
		_pathing,
		_heightfield,
		site
	)


func _ensure_placement_objects() -> void:
	if _placement == null:
		_placement = BuildPlacementController.new()
		_placement.configure(
			_get_ground_hit_callable(),
			Callable(self, "_heightfield_ref"),
			Callable(self, "_pathing_ref"),
			Callable(self, "_cell_reservation_ref")
		)
		_placement.placement_changed.connect(_on_placement_changed)
		_placement.placement_cancelled.connect(_on_placement_cancelled)
		_placement.placement_committed.connect(_on_placement_committed)


func _ensure_ghost_node(building_id: String) -> void:
	if _ghost == null:
		_ghost = BuildPlacementGhost.new()
		_ghost.name = "BuildPlacementGhost"
		if _map_root != null:
			_map_root.add_child(_ghost)
		else:
			add_child(_ghost)
	if _map_root != null:
		_ghost.configure(_map_root.get_model_cache(), _map_root.get_id_catalog())
	_ghost.set_building(building_id)


func _on_placement_changed(bid: String, site: Vector2, valid: bool) -> void:
	if _ghost != null and _placement != null and _placement.is_active():
		_apply_ghost_to_screen()
	placement_changed.emit(bid, site, valid)


func _on_placement_cancelled() -> void:
	_confirm_armed = false
	if not _site_ghost_pinned and _ghost != null:
		_ghost.set_visible_preview(false)
	placement_cancelled_notice.emit()


func _on_placement_committed(_bid: String, _site: Vector2) -> void:
	_confirm_armed = false


func emit_placement_committed(bid: String, site: Vector2) -> void:
	placement_committed.emit(bid, site)


func emit_placement_cancelled() -> void:
	placement_cancelled_notice.emit()


## 测试 / 验收：当前是否允许提交（避免按 _confirm_armed 后立刻同帧点击）。
func is_confirm_armed() -> bool:
	return _confirm_armed


func set_confirm_armed(v: bool) -> void:
	_confirm_armed = v