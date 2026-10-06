class_name AbilitiesModule
extends Node
const FxScene: GDScript = preload("res://packages/gameplay/presentation/ability_fx_scene.gd")

## 对局内技能编排：cast ctx / runtime / 瞄准 / HUD 反馈 / 范围预览。
## 由总管注入地图、战斗管线与选择回调；不依赖 GameDirector 类型。

var ctx_factory: AbilityCastContextFactory = null
var hud: AbilityHudFeedback = null
var runtime: AbilityRuntimeRegistry = null
var targeting: AbilityTargetingService = null

var _map_root: MapLoader
var _heightfield: Wc3Heightfield
var _path_query: PathQuery
var _crowd_query: UnitCrowdQuery
var _command_router: CommandRouter
var _damage_pipeline: DamagePipeline
var _projectile_service: ProjectileService

var _alloc_creation_number: Callable
var _ensure_unit_ai: Callable
var _spawn_summon: Callable
var _unit_host: Callable
var _teleport_unit_wc3: Callable
var _kill_unit: Callable
var _get_primary: Callable
var _pick_at: Callable
var _ground_at_screen: Callable
var _clear_rival_targeting: Callable
var _on_targeting_changed: Callable
var _set_status: Callable
var _refresh_command_card: Callable
var _refresh_pathing: Callable
var _resync_health_bars: Callable
var _sync_selection_info: Callable
var _last_screen_pos: Callable

var _preview_decal: BlizzardAreaDecal = null
var _preview_tinted: Array = []
var _preview_tint_goal := Vector2.INF
var _preview_tint_radius: float = 0.0
var _pending_abil_id: String = ""
var _targeting_active: bool = false


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as MapLoader
	_heightfield = deps.get("heightfield") as Wc3Heightfield
	_path_query = deps.get("path_query") as PathQuery
	_crowd_query = deps.get("crowd_query") as UnitCrowdQuery
	_command_router = deps.get("command_router") as CommandRouter
	_damage_pipeline = deps.get("damage_pipeline") as DamagePipeline
	_projectile_service = deps.get("projectile_service") as ProjectileService
	_alloc_creation_number = deps.get("alloc_creation_number", Callable()) as Callable
	_ensure_unit_ai = deps.get("ensure_unit_ai", Callable()) as Callable
	_spawn_summon = deps.get("spawn_summon", Callable()) as Callable
	_unit_host = deps.get("unit_host", Callable()) as Callable
	_teleport_unit_wc3 = deps.get("teleport_unit_wc3", Callable()) as Callable
	_kill_unit = deps.get("kill_unit", Callable()) as Callable
	_get_primary = deps.get("get_primary", Callable()) as Callable
	_pick_at = deps.get("pick_at", Callable()) as Callable
	_ground_at_screen = deps.get("ground_at_screen", Callable()) as Callable
	_clear_rival_targeting = deps.get("clear_rival_targeting", Callable()) as Callable
	_on_targeting_changed = deps.get("on_targeting_changed", Callable()) as Callable
	_set_status = deps.get("set_status", Callable()) as Callable
	_refresh_command_card = deps.get("refresh_command_card", Callable()) as Callable
	_refresh_pathing = deps.get("refresh_pathing", Callable()) as Callable
	_resync_health_bars = deps.get("resync_health_bars", Callable()) as Callable
	_sync_selection_info = deps.get("sync_selection_info", Callable()) as Callable
	_last_screen_pos = deps.get("last_screen_pos", Callable()) as Callable
	_ensure_services()
	if _map_root != null:
		# Keep recurring spell scenes in memory before gameplay begins.
		for id: String in ["AHbz", "AHmt"]:
			FxScene.warm_for_ability(id, _map_root.get_model_cache())


func shutdown() -> void:
	FxScene.clear()
	clear_preview()
	ctx_factory = null
	hud = null
	runtime = null
	targeting = null
	_map_root = null
	_heightfield = null
	_path_query = null
	_crowd_query = null
	_command_router = null
	_damage_pipeline = null
	_projectile_service = null
	_alloc_creation_number = Callable()
	_ensure_unit_ai = Callable()
	_spawn_summon = Callable()
	_unit_host = Callable()
	_teleport_unit_wc3 = Callable()
	_kill_unit = Callable()
	_get_primary = Callable()
	_pick_at = Callable()
	_ground_at_screen = Callable()
	_clear_rival_targeting = Callable()
	_on_targeting_changed = Callable()
	_set_status = Callable()
	_refresh_command_card = Callable()
	_refresh_pathing = Callable()
	_resync_health_bars = Callable()
	_sync_selection_info = Callable()
	_last_screen_pos = Callable()


func _exit_tree() -> void:
	shutdown()


func tick(delta: float) -> void:
	if runtime != null:
		runtime.tick_all_units(delta)


func ensure_unit(unit: Node3D) -> void:
	if runtime != null:
		runtime.ensure_unit(unit)


func ensure_hero_passives(unit: Node3D) -> void:
	if runtime != null:
		runtime.ensure_hero_passives(unit)


func ui_state_for(primary: Node3D) -> Dictionary:
	if hud == null:
		return {}
	return hud.build_command_card_state(primary, Callable(self, "ensure_unit"))


func cast_context() -> Dictionary:
	if ctx_factory != null:
		return ctx_factory.build()
	return {}


func begin_targeting(abil_id: String, source: int) -> void:
	if targeting != null:
		targeting.begin_targeting(abil_id, source)


func cancel_targeting() -> void:
	if targeting != null:
		targeting.cancel()


func issue_self(abil_id: String, source: int) -> bool:
	if targeting == null:
		return false
	return targeting.issue_self(abil_id, source)


func issue_at_unit_screen(screen_pos: Vector2, source: int) -> bool:
	if targeting == null:
		return false
	return targeting.issue_at_unit_screen(screen_pos, source)


func issue_at_screen(screen_pos: Vector2, source: int) -> bool:
	if targeting == null:
		return false
	return targeting.issue_at_screen(screen_pos, source)


func pending_abil_id() -> String:
	if targeting != null:
		return targeting.pending_abil_id()
	return _pending_abil_id


func is_targeting() -> bool:
	return _targeting_active


func set_targeting(active: bool, abil_id: String = "") -> void:
	if targeting == null:
		_notify_targeting_changed(active, abil_id)
		return
	if active:
		targeting.begin_targeting(abil_id, UnitOrder.Source.PANEL)
	else:
		targeting.cancel()


func clear_caster_orders(caster: Node3D) -> void:
	if caster == null or not is_instance_valid(caster) or _command_router == null:
		return
	var q := _command_router.queue_for(caster)
	if q != null:
		q.clear()


func channel_interrupt_check(caster: Node3D) -> bool:
	if caster == null or not is_instance_valid(caster) or _command_router == null:
		return false
	var q := _command_router.queue_for(caster)
	if q == null or q.is_idle():
		return false
	var o: UnitOrder = q.current
	if o == null:
		return false
	if o.source == UnitOrder.Source.UNIT_AI:
		return false
	match o.kind:
		UnitOrder.Kind.MOVE, UnitOrder.Kind.STOP, UnitOrder.Kind.HOLD:
			return true
		UnitOrder.Kind.ATTACK, UnitOrder.Kind.ATTACK_MOVE, UnitOrder.Kind.PATROL:
			return true
		UnitOrder.Kind.HARVEST_GOLD, UnitOrder.Kind.HARVEST_LUMBER:
			return true
		UnitOrder.Kind.RETURN_GOODS, UnitOrder.Kind.BUILD:
			return true
		UnitOrder.Kind.ABILITY:
			var ctrl := AbilityCastController.of(caster)
			if ctrl != null and (
				ctrl.is_channeling() or ctrl.is_approaching() or ctrl.is_cast_delaying()
			):
				var pending := str(o.ability_id).strip_edges()
				if not pending.is_empty() and pending == ctrl.channeling_abil_id():
					return false
			return true
	return false


func interrupt_channels(units: Array) -> void:
	for u in units:
		if not (u is Node3D) or not is_instance_valid(u):
			continue
		var acc := AbilityCastController.of(u as Node3D)
		if acc != null and (acc.is_channeling() or acc.is_cast_delaying()):
			acc.cancel_cast()


func update_preview(screen_pos: Vector2) -> void:
	var abil_id := _pending_abil_id.strip_edges()
	if not _targeting_active or _map_root == null:
		clear_preview()
		return
	if abil_id != "AHbz" and abil_id != "AHmt":
		clear_preview()
		return
	var primary: Node3D = _get_primary.call() as Node3D if _get_primary.is_valid() else null
	if primary == null:
		return
	var hit: Vector3 = _ground_at_screen.call(screen_pos) if _ground_at_screen.is_valid() else Vector3.INF
	if hit == Vector3.INF:
		return
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal := Vector2(hit.x * inv, -hit.z * inv)
	var radius: float
	var tint_goal := goal
	var do_tint := false
	var preview_color := BlizzardAreaDecal.DEFAULT_COLOR
	if abil_id == "AHbz":
		var lv := AbilityCatalog.level_for(primary, "AHbz")
		var ab := AbilityCatalog.data("AHbz")
		radius = ab.area_at(lv) if ab != null else 200.0
		do_tint = true
	else:
		radius = MassTeleportPresenter.DEST_PREVIEW_RADIUS_WC3
		preview_color = MassTeleportPresenter.DEST_COLOR
	if _preview_decal == null or not is_instance_valid(_preview_decal):
		_preview_decal = BlizzardAreaDecal.spawn_preview(
			_map_root, goal, radius, _heightfield, preview_color
		)
	else:
		_preview_decal.set_tint(preview_color)
		_preview_decal.reposition(goal, radius, _heightfield)
	if do_tint:
		_refresh_preview_tints(primary, tint_goal, radius)
	else:
		_clear_preview_tints()


func clear_preview() -> void:
	if _preview_decal != null and is_instance_valid(_preview_decal):
		_preview_decal.queue_free()
	_preview_decal = null
	_clear_preview_tints()
	_preview_tint_goal = Vector2.INF
	_preview_tint_radius = 0.0


func _ensure_services() -> void:
	if ctx_factory == null:
		ctx_factory = AbilityCastContextFactory.new()
	ctx_factory.configure({
		"map_root": _map_root,
		"heightfield": _heightfield,
		"damage_pipeline": _damage_pipeline,
		"projectile_service": _projectile_service,
		"path_query": _path_query,
		"crowd_query": _crowd_query,
		"alloc_creation_number": _alloc_creation_number,
		"ensure_unit_ai": _ensure_unit_ai,
		"spawn_summon": _spawn_summon,
		"unit_host": _unit_host,
		"channel_interrupt_check": Callable(self, "channel_interrupt_check"),
		"teleport_unit_wc3": _teleport_unit_wc3,
		"kill_unit": _kill_unit,
		"clear_caster_orders": Callable(self, "clear_caster_orders"),
	})
	if hud == null:
		hud = AbilityHudFeedback.new()
	hud.configure(_set_status)
	if runtime == null:
		runtime = AbilityRuntimeRegistry.new()
	runtime.configure({
		"unit_host": _unit_host,
		"ctx_factory": ctx_factory,
		"map_root": _map_root,
	})
	if targeting == null:
		targeting = AbilityTargetingService.new()
	targeting.configure({
		"get_primary": _get_primary,
		"pick_at": _pick_at,
		"ground_at_screen": _ground_at_screen,
		"ensure_runtime": Callable(self, "ensure_unit"),
		"build_ctx": Callable(self, "cast_context"),
		"on_cast_resolved": Callable(self, "_on_cast_resolved"),
		"clear_rival_targeting": _clear_rival_targeting,
		"on_targeting_changed": Callable(self, "_notify_targeting_changed"),
		"hud": hud,
		"refresh_command_card": _refresh_command_card,
		"on_blizzard_preview": Callable(self, "_preview_from_last_screen"),
	})


func _on_cast_resolved(result: Dictionary, abil_id: String) -> void:
	if hud != null:
		hud.on_cast_resolved(result, abil_id)
	if AbilityHudFeedback.should_refresh_world(result):
		if _refresh_pathing.is_valid():
			_refresh_pathing.call()
		if _resync_health_bars.is_valid():
			_resync_health_bars.call()
		if _sync_selection_info.is_valid():
			_sync_selection_info.call()
	if _refresh_command_card.is_valid():
		_refresh_command_card.call()


func _notify_targeting_changed(active: bool, abil_id: String) -> void:
	_targeting_active = active
	_pending_abil_id = abil_id.strip_edges() if active else ""
	if not active:
		clear_preview()
	if _on_targeting_changed.is_valid():
		_on_targeting_changed.call(active, abil_id)


func _preview_from_last_screen() -> void:
	var pos: Vector2 = _last_screen_pos.call() if _last_screen_pos.is_valid() else Vector2.ZERO
	update_preview(pos)


func _refresh_preview_tints(caster: Node3D, goal: Vector2, radius: float) -> void:
	var host: Node = _unit_host.call() if _unit_host.is_valid() else null
	if host == null or caster == null:
		_clear_preview_tints()
		return
	_preview_tint_goal = goal
	_preview_tint_radius = radius
	var next: Array = CombatQuery.units_blizzard_victims_in_radius(host, caster, goal, radius)
	var next_ids: Dictionary = {}
	for n in next:
		if n is Node3D and is_instance_valid(n):
			next_ids[(n as Node3D).get_instance_id()] = n
	for old in _preview_tinted:
		if not (old is Node3D) or not is_instance_valid(old):
			continue
		var oid := (old as Node3D).get_instance_id()
		if not next_ids.has(oid):
			UnitSpellTint.clear(old as Node3D)
	var tint := Color(0.38, 0.78, 1.0, 0.42)
	_preview_tinted.clear()
	for id in next_ids.keys():
		var node: Node3D = next_ids[id] as Node3D
		if not node.has_meta(UnitSpellTint.META_SAVED):
			UnitSpellTint.apply(node, tint)
		_preview_tinted.append(node)


func _clear_preview_tints() -> void:
	UnitSpellTint.clear_many(_preview_tinted)
	_preview_tinted.clear()
