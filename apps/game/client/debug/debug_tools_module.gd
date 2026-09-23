class_name DebugToolsModule
extends Node

## 开发调试：GM 面板 / 性能叠层挂接，以及英雄等级与测试道具动作。
## 不持有 GameDirector 类型；依赖经 configure 注入。

var _map_root: MapLoader
var _host_parent: Node
var _game_hud: Node
var _unit_selector: Node
var _gm_panel: CanvasLayer = null
var _perf_overlay: PerfOverlay = null

var _ensure_caster: Callable
var _refresh_command_card: Callable
var _sync_selection_info: Callable
var _get_primary: Callable
var _is_controllable: Callable
var _set_status: Callable
var _spawn_test_kit: Callable
var _on_inventory_changed: Callable
var _kill_unit: Callable
var _spawn_near: Callable


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as MapLoader
	_host_parent = deps.get("host_parent") as Node
	_game_hud = deps.get("game_hud") as Node
	_unit_selector = deps.get("unit_selector") as Node
	_ensure_caster = deps.get("ensure_caster", Callable()) as Callable
	_refresh_command_card = deps.get("refresh_command_card", Callable()) as Callable
	_sync_selection_info = deps.get("sync_selection_info", Callable()) as Callable
	_get_primary = deps.get("get_primary", Callable()) as Callable
	_is_controllable = deps.get("is_controllable", Callable()) as Callable
	_set_status = deps.get("set_status", Callable()) as Callable
	_spawn_test_kit = deps.get("spawn_test_kit", Callable()) as Callable
	_on_inventory_changed = deps.get("on_inventory_changed", Callable()) as Callable
	_kill_unit = deps.get("kill_unit", Callable()) as Callable
	_spawn_near = deps.get("spawn_near", Callable()) as Callable


func shutdown() -> void:
	_map_root = null
	_host_parent = null
	_game_hud = null
	_unit_selector = null
	_gm_panel = null
	_perf_overlay = null
	_ensure_caster = Callable()
	_refresh_command_card = Callable()
	_sync_selection_info = Callable()
	_get_primary = Callable()
	_is_controllable = Callable()
	_set_status = Callable()
	_spawn_test_kit = Callable()
	_on_inventory_changed = Callable()
	_kill_unit = Callable()
	_spawn_near = Callable()


func _exit_tree() -> void:
	shutdown()


func ensure_gm_panel() -> void:
	if _host_parent == null:
		return
	if _gm_panel != null and is_instance_valid(_gm_panel):
		return
	var existing := _host_parent.get_node_or_null("GmDebugPanel") as CanvasLayer
	if existing != null:
		_gm_panel = existing
		return
	var gm: CanvasLayer = GmDebugPanel.new()
	gm.name = "GmDebugPanel"
	_gm_panel = gm
	# _ready 期间父节点 blocked，必须延迟挂接
	_host_parent.add_child.call_deferred(gm)


func ensure_perf_overlay() -> void:
	if _host_parent == null:
		return
	if _perf_overlay != null and is_instance_valid(_perf_overlay):
		return
	var existing := _host_parent.get_node_or_null(PerfOverlay.NODE_NAME) as PerfOverlay
	if existing != null:
		_perf_overlay = existing
		return
	_perf_overlay = PerfOverlay.ensure_on(_host_parent)


func toggle_gm_panel() -> void:
	ensure_gm_panel()
	if _gm_panel == null or not is_instance_valid(_gm_panel):
		return
	if not _gm_panel.is_inside_tree():
		_gm_panel.call_deferred("set_open", true)
	elif _gm_panel.has_method("toggle"):
		_gm_panel.call("toggle")
	if _game_hud != null and _gm_panel.is_inside_tree() and _game_hud.has_method("set_status"):
		_game_hud.call(
			"set_status",
			"GM 面板：%s（` / F4）" % ("开" if _gm_panel.visible else "关")
		)


func toggle_perf_overlay() -> void:
	ensure_perf_overlay()
	if _perf_overlay == null or not is_instance_valid(_perf_overlay):
		return
	_perf_overlay.toggle()
	if _game_hud != null and _game_hud.has_method("set_status"):
		_game_hud.call(
			"set_status",
			"性能叠层：%s（F3）" % ("开" if _perf_overlay.is_overlay_enabled() else "关")
		)


## —— GM：英雄等级 / 技能 ——


func primary_hero() -> Node3D:
	if _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return null
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		return null
	var tid := str(primary.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if not TechPresence.is_hero_id(tid):
		_status("GM：请先选中英雄")
		return null
	if _ensure_caster.is_valid():
		_ensure_caster.call(primary)
	return primary


func hero_level_up() -> void:
	var hero := primary_hero()
	if hero == null:
		return
	var lv := AbilityCatalog.hero_level_of(hero)
	if lv >= HeroProgression.MAX_HERO_LEVEL:
		_status("GM：已满级 %d" % lv)
		return
	HeroProgression.set_level(hero, lv + 1)
	UnitMana.sync_hero_max(hero)
	_refresh_ui()
	_status("GM：英雄等级 → %d（技能点 %d）" % [
		AbilityCatalog.hero_level_of(hero),
		HeroSkill.points_available(hero),
	])


func hero_max_level() -> void:
	var hero := primary_hero()
	if hero == null:
		return
	HeroProgression.set_level(hero, HeroProgression.MAX_HERO_LEVEL)
	UnitMana.sync_hero_max(hero)
	_refresh_ui()
	_status("GM：英雄等级 → %d（技能点 %d）" % [
		HeroProgression.MAX_HERO_LEVEL,
		HeroSkill.points_available(hero),
	])


## 用 1 点自动学第一个可学技能（或升级已有）。
func hero_learn_one_point() -> void:
	var hero := primary_hero()
	if hero == null:
		return
	if HeroSkill.points_available(hero) <= 0:
		_status("GM：无技能点（先升级）")
		return
	var tid := str(hero.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	for aid_v in AbilityCatalog.hero_ability_ids_for_unit(tid):
		var aid := str(aid_v).strip_edges()
		var check := HeroSkill.can_learn(hero, aid)
		if bool(check.get("ok", false)):
			var result := HeroSkill.learn(hero, aid)
			if _ensure_caster.is_valid():
				_ensure_caster.call(hero)
			_refresh_ui()
			var row := CommandButtonCatalog.get_shared().get_ability(aid)
			var name_s := str(row.get("name", aid)).strip_edges()
			_status("GM：学习 · %s Lv%d" % [name_s, int(result.get("level", 1))])
			return
	_status("GM：没有可学技能（等级门槛？）")


## 满级 + 该英雄全部技能升到最高。
func hero_unlock_all_skills() -> void:
	var hero := primary_hero()
	if hero == null:
		return
	HeroProgression.set_level(hero, HeroProgression.MAX_HERO_LEVEL)
	UnitMana.sync_hero_max(hero)
	var tid := str(hero.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	HeroSkill.ensure_levels_meta(hero)
	var levels: Dictionary = {}
	for aid_v in AbilityCatalog.hero_ability_ids_for_unit(tid):
		var aid := str(aid_v).strip_edges()
		if aid.is_empty():
			continue
		var ab := AbilityCatalog.data(aid)
		var max_lv := 3
		if ab != null:
			max_lv = ab.clamp_level(ab.levels)
		levels[aid] = max_lv
	hero.set_meta(AbilityCatalog.META_ABILITY_LEVELS, levels)
	if _ensure_caster.is_valid():
		_ensure_caster.call(hero)
	_refresh_ui()
	_status("GM：满级 + 全技能解锁（%d 个）" % levels.size())


## —— GM：物品测试 ——


func item_test_kit() -> void:
	if _spawn_test_kit.is_valid():
		_spawn_test_kit.call()


func item_test_vitals() -> void:
	var unit := _primary_unit()
	if not _controllable(unit) or Inventory.of(unit) == null:
		_ability_status("请先选中己方英雄")
		return
	UnitLife.set_life(unit, maxf(1.0, UnitLife.get_max_life(unit) * 0.3))
	UnitMana.spend(unit, UnitMana.get_mana(unit) * 0.7)
	if _on_inventory_changed.is_valid():
		_on_inventory_changed.call()
	_ability_status("测试：英雄生命与魔法降至约 30%")


func item_test_death() -> void:
	var unit := _primary_unit()
	if _controllable(unit) and Inventory.of(unit) != null:
		if _kill_unit.is_valid():
			_kill_unit.call(unit)
		_ability_status("测试：英雄阵亡，请在祭坛复活后检查背包")


func item_test_creep() -> void:
	var unit := _primary_unit()
	if not _controllable(unit):
		return
	if not _spawn_near.is_valid():
		return
	var creep: Node3D = _spawn_near.call(
		unit, "nogr", 12, Vector2(280.0, 0.0),
		{
			"life_override": 20.0,
			"entry_extras": {
				"droppedItemSets": [[{"id": "phea", "chance": 100}], [{"id": "rde1", "chance": 100}]],
			},
		}
	) as Node3D
	if creep != null:
		_ability_status("测试野怪已生成：击杀应掉落生命药水和守护指环")


func _primary_unit() -> Node3D:
	if _get_primary.is_valid():
		return _get_primary.call() as Node3D
	return null


func _controllable(unit: Node3D) -> bool:
	if _is_controllable.is_valid():
		return bool(_is_controllable.call(unit))
	return false


func _status(text: String) -> void:
	if _game_hud != null and _game_hud.has_method("set_status"):
		_game_hud.call("set_status", text)


func _ability_status(text: String) -> void:
	if _set_status.is_valid():
		_set_status.call(text)
	else:
		_status(text)


func _refresh_ui() -> void:
	if _refresh_command_card.is_valid():
		_refresh_command_card.call()
	if _sync_selection_info.is_valid():
		_sync_selection_info.call()


func apply_hall_phase(phase: int) -> bool:
	if _map_root == null:
		return false
	var layer := _map_root.get_unit_layer()
	if layer == null:
		return false
	var cache: MapModelCache = null
	if _map_root.has_method("get_model_cache"):
		cache = _map_root.get_model_cache()
	for c in layer.get_children():
		if not (c is Node3D):
			continue
		var d: Dictionary = (c as Node).get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if tid != "htow" and tid != "hkee" and tid != "hcas":
			continue
		if cache != null:
			BuildingVisual.apply_phase(cache, c, tid, phase)
		return true
	return false
