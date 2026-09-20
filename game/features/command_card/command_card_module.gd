class_name CommandCardModule
extends Node

## 对局命令卡协调：刷卡、热键、二级建造/英雄菜单、action 分发。
## 命令执行（移动/训练/瞄准）经 Callable 注入；不持有 GameDirector 类型。

var _game_hud: Node
var _unit_selector: Node
var _command_router: CommandRouter
var _session: GameSession
var _enable_move_command: bool = true

var _unit_host: Callable
var _local_stock: Callable
var _is_controllable: Callable
var _is_gold_mine: Callable
var _ability_ui_state_for: Callable
var _get_selected: Callable
var _unbind_hud_build_site: Callable
var _cancel_aim_rivals: Callable
var _ensure_caster: Callable

var _begin_move: Callable
var _issue_stop: Callable
var _issue_hold: Callable
var _begin_attack: Callable
var _begin_patrol: Callable
var _begin_harvest: Callable
var _issue_return_goods: Callable
var _issue_call_to_arms: Callable
var _begin_rally: Callable
var _try_toggle_defend: Callable
var _begin_ability: Callable
var _issue_self_ability: Callable
var _begin_build: Callable
var _try_train: Callable
var _try_revive: Callable
var _try_research: Callable

var _card_supports_move: bool = false
var _card_is_peasant: bool = false
var _last_move_executing: bool = false
var _last_harvest_ui: Dictionary = {}
var _last_ability_ui: Dictionary = {}
var _card_hotkey_actions: Dictionary = {}
var _build_menu_open: bool = false
var _hero_skill_menu_open: bool = false
var _cd_hud_acc: float = 0.0


func configure(deps: Dictionary) -> void:
	_game_hud = deps.get("game_hud") as Node
	_unit_selector = deps.get("unit_selector") as Node
	_command_router = deps.get("command_router") as CommandRouter
	_session = deps.get("session") as GameSession
	_enable_move_command = bool(deps.get("enable_move_command", true))
	_unit_host = deps.get("unit_host", Callable()) as Callable
	_local_stock = deps.get("local_stock", Callable()) as Callable
	_is_controllable = deps.get("is_controllable", Callable()) as Callable
	_is_gold_mine = deps.get("is_gold_mine", Callable()) as Callable
	_ability_ui_state_for = deps.get("ability_ui_state_for", Callable()) as Callable
	_get_selected = deps.get("get_selected", Callable()) as Callable
	_unbind_hud_build_site = deps.get("unbind_hud_build_site", Callable()) as Callable
	_cancel_aim_rivals = deps.get("cancel_aim_rivals", Callable()) as Callable
	_ensure_caster = deps.get("ensure_caster", Callable()) as Callable
	_begin_move = deps.get("begin_move", Callable()) as Callable
	_issue_stop = deps.get("issue_stop", Callable()) as Callable
	_issue_hold = deps.get("issue_hold", Callable()) as Callable
	_begin_attack = deps.get("begin_attack", Callable()) as Callable
	_begin_patrol = deps.get("begin_patrol", Callable()) as Callable
	_begin_harvest = deps.get("begin_harvest", Callable()) as Callable
	_issue_return_goods = deps.get("issue_return_goods", Callable()) as Callable
	_issue_call_to_arms = deps.get("issue_call_to_arms", Callable()) as Callable
	_begin_rally = deps.get("begin_rally", Callable()) as Callable
	_try_toggle_defend = deps.get("try_toggle_defend", Callable()) as Callable
	_begin_ability = deps.get("begin_ability", Callable()) as Callable
	_issue_self_ability = deps.get("issue_self_ability", Callable()) as Callable
	_begin_build = deps.get("begin_build", Callable()) as Callable
	_try_train = deps.get("try_train", Callable()) as Callable
	_try_revive = deps.get("try_revive", Callable()) as Callable
	_try_research = deps.get("try_research", Callable()) as Callable


func shutdown() -> void:
	_card_hotkey_actions.clear()
	_last_harvest_ui.clear()
	_last_ability_ui.clear()
	_game_hud = null
	_unit_selector = null
	_command_router = null
	_session = null
	_unit_host = Callable()
	_local_stock = Callable()
	_is_controllable = Callable()
	_is_gold_mine = Callable()
	_ability_ui_state_for = Callable()
	_get_selected = Callable()
	_unbind_hud_build_site = Callable()
	_cancel_aim_rivals = Callable()
	_ensure_caster = Callable()
	_begin_move = Callable()
	_issue_stop = Callable()
	_issue_hold = Callable()
	_begin_attack = Callable()
	_begin_patrol = Callable()
	_begin_harvest = Callable()
	_issue_return_goods = Callable()
	_issue_call_to_arms = Callable()
	_begin_rally = Callable()
	_try_toggle_defend = Callable()
	_begin_ability = Callable()
	_issue_self_ability = Callable()
	_begin_build = Callable()
	_try_train = Callable()
	_try_revive = Callable()
	_try_research = Callable()


func _exit_tree() -> void:
	shutdown()


func is_build_menu_open() -> bool:
	return _build_menu_open


func is_hero_skill_menu_open() -> bool:
	return _hero_skill_menu_open


func is_peasant_card() -> bool:
	return _card_is_peasant


func supports_move() -> bool:
	return _card_supports_move


func close_submenus() -> void:
	_build_menu_open = false
	_hero_skill_menu_open = false


## Esc：若二级面板开着则关闭并返回 true。
func handle_submenu_escape() -> bool:
	if _build_menu_open:
		set_build_menu_open(false)
		return true
	if _hero_skill_menu_open:
		set_hero_skill_menu_open(false)
		return true
	return false


## 热键：命中则分发并返回 true。
func try_hotkey(key: int) -> bool:
	if not _card_hotkey_actions.has(key):
		return false
	dispatch_action(str(_card_hotkey_actions[key]), UnitOrder.Source.HOTKEY)
	return true


func tick_cooldown_hud(delta: float) -> void:
	_cd_hud_acc += delta
	if _cd_hud_acc < 0.1:
		return
	_cd_hud_acc = 0.0
	if not _primary_has_ability_cd():
		return
	refresh()


func refresh() -> void:
	if _game_hud == null or not _card_supports_move or _unit_selector == null:
		return
	if not _unit_selector.has_method("get_selected"):
		return
	var selected: Array = _unit_selector.call("get_selected")
	var primary: Node3D = null
	if _unit_selector.has_method("get_primary"):
		primary = _unit_selector.call("get_primary") as Node3D
	var moving := false
	var carrying := false
	var harvesting := false
	var returning := false
	if _command_router != null:
		moving = _command_router.any_moving(selected)
		var primary_peasants: Array = []
		if primary != null:
			primary_peasants = _command_router.filter_peasants([primary])
		_card_is_peasant = not primary_peasants.is_empty()
		if _card_is_peasant:
			var peasants := _command_router.filter_peasants(selected)
			carrying = _command_router.any_carrying(peasants)
			harvesting = _command_router.any_harvesting(peasants)
			returning = _command_router.any_returning(peasants)
	else:
		_card_is_peasant = false
	_last_move_executing = moving
	_last_harvest_ui = {
		"peasant": _card_is_peasant,
		"carrying": carrying,
		"harvesting": harvesting,
		"returning": returning,
		"moving": moving,
	}
	if _card_is_peasant:
		_apply_peasant_command_card(selected, moving, carrying, harvesting, returning)
	else:
		_build_menu_open = false
		var tid := primary_type_id(selected)
		if tid.is_empty():
			_apply_command_card(CommandCard.basic_locomotion(moving))
		elif BuildingCatalog.is_building(tid) and not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
			var primary_b: Node3D = null
			if _unit_selector != null and _unit_selector.has_method("get_primary"):
				primary_b = _unit_selector.call("get_primary") as Node3D
			apply_building_train_card(primary_b, tid)
		else:
			var state := {
				"move_executing": moving,
				"include_locomotion": true,
				"owned_buildings": owned_buildings_for_local(),
				"researched": researched_for_local(),
				"defend_active": _primary_defend_active(),
				"hero_skill_menu_open": _hero_skill_menu_open,
				"militia_active": tid == "hmil",
			}
			if primary != null and _ability_ui_state_for.is_valid():
				state.merge(_ability_ui_state_for.call(primary), true)
			_apply_command_card(CommandCard.for_unit(tid, state))


func refresh_move_executing_ui() -> void:
	if not _card_supports_move or _game_hud == null or _unit_selector == null:
		return
	if not _unit_selector.has_method("get_selected"):
		return
	var selected: Array = _unit_selector.call("get_selected")
	var moving := false
	var carrying := false
	var harvesting := false
	var returning := false
	var is_peasant := false
	var primary: Node3D = null
	if _unit_selector.has_method("get_primary"):
		primary = _unit_selector.call("get_primary") as Node3D
	if _command_router != null and primary != null:
		is_peasant = not _command_router.filter_peasants([primary]).is_empty()
	_card_is_peasant = is_peasant
	var is_hero := false
	if primary != null:
		var ptid := str(primary.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
		is_hero = TechPresence.is_hero_id(ptid)
	var ab_ui := {}
	if is_hero and _ability_ui_state_for.is_valid():
		ab_ui = _ability_ui_state_for.call(primary)
	if _command_router != null:
		moving = _command_router.any_moving(selected)
		if is_peasant:
			var peasants := _command_router.filter_peasants(selected)
			carrying = _command_router.any_carrying(peasants)
			harvesting = _command_router.any_harvesting(peasants)
			returning = _command_router.any_returning(peasants)
	var snap := {
		"peasant": is_peasant,
		"carrying": carrying,
		"harvesting": harvesting,
		"returning": returning,
		"moving": moving,
	}
	if snap == _last_harvest_ui and moving == _last_move_executing and ab_ui == _last_ability_ui:
		return
	_last_move_executing = moving
	_last_harvest_ui = snap
	_last_ability_ui = ab_ui.duplicate(true)
	if is_peasant:
		_apply_peasant_command_card(selected, moving, carrying, harvesting, returning)
	elif is_hero:
		refresh()
	else:
		_game_hud.set_command_executing(CommandCard.ACTION_MOVE, moving)


## 选中变化后的命令卡分支（inventory / interaction / 血条由总管编排）。
func on_selection_changed(primary: Node3D, selected: Array) -> void:
	close_submenus()
	if _game_hud == null:
		return
	if primary == null or selected.is_empty():
		_card_supports_move = false
		_card_is_peasant = false
		clear_hotkeys()
		_call_unbind_build_site()
		_game_hud.set_selection_info(SelectionInfoBuilder.build_empty())
		_game_hud.clear_build_progress()
		if _game_hud.has_method("clear_train_queue"):
			_game_hud.clear_train_queue()
		_game_hud.clear_command_labels()
		_game_hud.set_status("未选中")
		return
	var d: Dictionary = primary.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "?"))
	if tid == "ngol" or (_is_gold_mine.is_valid() and bool(_is_gold_mine.call(primary))):
		_card_supports_move = false
		_card_is_peasant = false
		_call_unbind_build_site()
		_game_hud.clear_build_progress()
		if _game_hud.has_method("clear_train_queue"):
			_game_hud.clear_train_queue()
		_game_hud.clear_command_labels()
		var gold_left := int(d.get("goldAmount", -1))
		var rt := GoldMineRuntime.ensure(primary)
		if rt != null:
			gold_left = rt.remaining_gold
		elif gold_left < 0:
			gold_left = 12500
		_game_hud.set_status("金矿 · 剩余 %d 金" % gold_left)
		return
	if not _controllable(primary):
		_card_supports_move = false
		_card_is_peasant = false
		clear_hotkeys()
		_call_unbind_build_site()
		_game_hud.clear_build_progress()
		if _game_hud.has_method("clear_train_queue"):
			_game_hud.clear_train_queue()
		_game_hud.clear_command_labels()
		if not CombatQuery.is_alive_in_world(primary):
			_game_hud.set_status("已选 %s · 已阵亡（不可控制）" % tid)
		else:
			var oid := CombatQuery.owner_of(primary)
			if CombatQuery.is_neutral_owner(oid):
				_game_hud.set_status("已选 %s · 中立（不可控制）" % tid)
			else:
				_game_hud.set_status("已选 %s · 敌方（不可控制）" % tid)
		return
	if not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
		_card_supports_move = false
		_card_is_peasant = false
		apply_building_train_card(primary, tid)
		if UnitLife.is_under_construction(primary):
			_game_hud.set_status("建造中：%s · 可设集结点" % tid)
		else:
			_game_hud.set_status("已选 %s · 训练见命令卡" % tid)
	elif _command_router != null and not _command_router.filter_movers(selected).is_empty():
		_card_supports_move = true
		refresh()
		if _card_is_peasant:
			_game_hud.set_status("已选 %s · 农民命令卡（采集/交回/建造热键见按钮）" % tid)
		else:
			_game_hud.set_status("已选 %s · 移动/停止见命令卡" % tid)
	else:
		_card_supports_move = false
		_card_is_peasant = false
		clear_hotkeys()
		_game_hud.clear_command_labels()
		if UnitLife.is_under_construction(primary):
			_game_hud.set_status("建造中：%s" % tid)
		else:
			_game_hud.set_status("已选 %s" % tid)


func apply_building_train_card(building: Node3D, tid: String) -> void:
	var owner_id := 0
	if _session != null:
		owner_id = int(_session.local_player)
	var under := building != null and UnitLife.is_under_construction(building)
	var host: Node = null
	if _unit_host.is_valid():
		host = _unit_host.call() as Node
	var state := {
		"include_locomotion": false,
		"owned_buildings": owned_buildings_for_local(),
		"researched": researched_for_local(),
		"hero_slots_full": (
			TechPresence.count_heroes_with_queues(host, owner_id)
			>= TechPresence.MAX_HEROES_PER_PLAYER
		),
		"hide_trains": under,
		"dead_heroes": HeroDeathRegistry.dead_heroes(owner_id),
	}
	if building != null and not under:
		var q := building.get_node_or_null("TrainQueue") as TrainQueue
		if q != null and q.is_training():
			state["training_unit"] = q.current_unit()
			state["train_queue"] = q.snapshot()
	_apply_command_card(CommandCard.for_unit(tid, state))


func set_build_menu_open(open: bool) -> void:
	if _build_menu_open == open:
		if open:
			refresh()
		return
	_build_menu_open = open
	if open:
		if _cancel_aim_rivals.is_valid():
			_cancel_aim_rivals.call()
	refresh()
	if _game_hud:
		if open:
			_game_hud.set_status("建造：选择建筑 · Esc/取消 返回")
		elif _card_is_peasant:
			_game_hud.set_status("已选农民 · 建造见命令卡")


func set_hero_skill_menu_open(open: bool) -> void:
	if _hero_skill_menu_open == open:
		if open:
			refresh()
		return
	_hero_skill_menu_open = open
	if open:
		if _cancel_aim_rivals.is_valid():
			_cancel_aim_rivals.call()
		_build_menu_open = false
	refresh()
	if _game_hud and open:
		_game_hud.set_status("英雄技能 · 点击学习 · Esc/取消 返回")


func try_learn_hero_skill(abil_id: String) -> void:
	if _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	if primary == null or not _controllable(primary):
		return
	var check := HeroSkill.can_learn(primary, abil_id)
	if not bool(check.get("ok", false)):
		if _game_hud:
			_game_hud.set_status(str(check.get("reason", "无法学习")))
		return
	var result := HeroSkill.learn(primary, abil_id)
	if _game_hud:
		var row := CommandButtonCatalog.get_shared().get_ability(abil_id)
		var name_s := str(row.get("name", abil_id)).strip_edges()
		if bool(result.get("ok", false)):
			_game_hud.set_status("学习 · %s Lv%d" % [name_s, int(result.get("level", 1))])
		else:
			_game_hud.set_status(str(result.get("reason", "无法学习")))
	if bool(result.get("ok", false)):
		set_hero_skill_menu_open(false)
	else:
		refresh()


func dispatch_action_rclick(action_id: String) -> void:
	if not action_id.begins_with(CommandCard.ACTION_ABILITY_PREFIX):
		return
	var abil_id := action_id.substr(CommandCard.ACTION_ABILITY_PREFIX.length()).strip_edges()
	if not AbilityAutoCast.supports(abil_id):
		if _game_hud:
			_game_hud.set_status("该技能不支持自动施法切换")
		return
	if _unit_selector == null:
		return
	var selected: Array = []
	if _get_selected.is_valid():
		selected = _get_selected.call()
	if selected.is_empty():
		return
	var n_toggled := 0
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var u := n as Node3D
		if _ensure_caster.is_valid():
			_ensure_caster.call(u)
		AbilityAutoCast.toggle(u, abil_id)
		n_toggled += 1
	if n_toggled <= 0:
		return
	if _game_hud:
		var on := false
		if _unit_selector.has_method("get_primary"):
			var pri: Node3D = _unit_selector.call("get_primary") as Node3D
			if pri != null and _controllable(pri):
				on = AbilityAutoCast.is_enabled(pri, abil_id)
		var row := CommandButtonCatalog.get_shared().get_ability(abil_id)
		var name_s := str(row.get("name", abil_id)).strip_edges()
		_game_hud.set_status("%s · 自动施法 %s" % [name_s, "开" if on else "关"])
	refresh()


func dispatch_action(action_id: String, source: int = UnitOrder.Source.PANEL) -> void:
	match action_id:
		CommandCard.ACTION_MOVE:
			if _enable_move_command and _begin_move.is_valid():
				_begin_move.call(source)
		CommandCard.ACTION_STOP:
			if _enable_move_command and _issue_stop.is_valid():
				_issue_stop.call(source)
		CommandCard.ACTION_HOLD:
			if _enable_move_command and _issue_hold.is_valid():
				_issue_hold.call(source)
		CommandCard.ACTION_ATTACK:
			if _enable_move_command and _begin_attack.is_valid():
				_begin_attack.call(source)
		CommandCard.ACTION_PATROL:
			if _enable_move_command and _begin_patrol.is_valid():
				_begin_patrol.call(source)
		CommandCard.ACTION_HARVEST_GOLD:
			if _begin_harvest.is_valid():
				_begin_harvest.call(source)
		CommandCard.ACTION_RETURN_GOODS:
			if _issue_return_goods.is_valid():
				_issue_return_goods.call(source)
		CommandCard.ACTION_OPEN_BUILD:
			if _card_is_peasant:
				set_build_menu_open(true)
		CommandCard.ACTION_CLOSE_BUILD:
			set_build_menu_open(false)
		CommandCard.ACTION_OPEN_HERO_SKILLS:
			set_hero_skill_menu_open(true)
		CommandCard.ACTION_CLOSE_HERO_SKILLS:
			set_hero_skill_menu_open(false)
		CommandCard.ACTION_CALL_TO_ARMS:
			if _issue_call_to_arms.is_valid():
				_issue_call_to_arms.call(source)
		CommandCard.ACTION_SET_RALLY:
			if _begin_rally.is_valid():
				_begin_rally.call(source)
		CommandCard.ACTION_DEFEND:
			if _try_toggle_defend.is_valid():
				_try_toggle_defend.call(source)
		_:
			if action_id.begins_with(CommandCard.ACTION_ABILITY_PREFIX):
				var aid := action_id.substr(CommandCard.ACTION_ABILITY_PREFIX.length())
				if AbilityCatalog.target_kind(aid) == AbilityCatalog.TARGET_SELF:
					if _issue_self_ability.is_valid():
						_issue_self_ability.call(aid, source)
				elif _begin_ability.is_valid():
					_begin_ability.call(aid, source)
				return
			if action_id.begins_with(CommandCard.ACTION_BUILD_PREFIX):
				var bid := action_id.substr(CommandCard.ACTION_BUILD_PREFIX.length())
				if _begin_build.is_valid():
					_begin_build.call(bid, source)
				return
			if action_id.begins_with(CommandCard.ACTION_TRAIN_PREFIX):
				var uid := action_id.substr(CommandCard.ACTION_TRAIN_PREFIX.length())
				if _try_train.is_valid():
					_try_train.call(uid)
				return
			if action_id.begins_with(CommandCard.ACTION_REVIVE_PREFIX):
				var rid := action_id.substr(CommandCard.ACTION_REVIVE_PREFIX.length())
				if _try_revive.is_valid():
					_try_revive.call(rid)
				return
			if action_id.begins_with(CommandCard.ACTION_RESEARCH_PREFIX):
				var rid2 := action_id.substr(CommandCard.ACTION_RESEARCH_PREFIX.length())
				if _try_research.is_valid():
					_try_research.call(rid2)
				return
			if action_id.begins_with(CommandCard.ACTION_LEARN_PREFIX):
				var lid := action_id.substr(CommandCard.ACTION_LEARN_PREFIX.length())
				try_learn_hero_skill(lid)
				return
			if _game_hud:
				_game_hud.set_status("指令：%s（未实现）" % action_id)


func owned_buildings_for_local() -> Dictionary:
	var owner_id := 0
	if _session != null:
		owner_id = int(_session.local_player)
	var host: Node = null
	if _unit_host.is_valid():
		host = _unit_host.call() as Node
	return TechPresence.collect_owned_buildings(host, owner_id)


func researched_for_local() -> Dictionary:
	if not _local_stock.is_valid():
		return {}
	var stock: PlayerStock = _local_stock.call() as PlayerStock
	if stock == null:
		return {}
	return stock.upgrade_map()


func primary_type_id(_selected: Array = []) -> String:
	if _unit_selector != null and _unit_selector.has_method("get_primary"):
		var p: Node3D = _unit_selector.call("get_primary") as Node3D
		if p != null and is_instance_valid(p):
			var d: Dictionary = p.get_meta("unit_data", {})
			return str(d.get("typeId", "")).strip_edges()
	if not _selected.is_empty() and _selected[0] is Node3D:
		var d2: Dictionary = (_selected[0] as Node3D).get_meta("unit_data", {})
		return str(d2.get("typeId", "")).strip_edges()
	return ""


func clear_hotkeys() -> void:
	_card_hotkey_actions.clear()


func _apply_command_card(card: Array) -> void:
	if _game_hud != null:
		_game_hud.set_command_card(card)
	_card_hotkey_actions.clear()
	for e in card:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var id := str(d.get("id", "")).strip_edges()
		var hk := int(d.get("hotkey", 0))
		if id.is_empty() or hk == 0:
			continue
		if not bool(d.get("enabled", true)):
			continue
		_card_hotkey_actions[hk] = id


func _apply_peasant_command_card(
	selected: Array,
	moving: bool,
	carrying: bool,
	harvesting: bool,
	returning: bool
) -> void:
	var worker_tid := primary_type_id(selected)
	if worker_tid.is_empty():
		worker_tid = "hpea"
	var build_ids := _build_building_ids(worker_tid)
	_apply_command_card(
		CommandCard.for_unit(
			worker_tid,
			{
				"move_executing": moving,
				"carrying": carrying,
				"harvest_executing": harvesting and not carrying,
				"return_executing": returning,
				"building_ids": build_ids,
				"can_afford": _build_unlocked_flags(build_ids),
				"build_disabled_reasons": _build_disabled_reasons(build_ids),
				"building_executing": _build_executing_flags(build_ids),
				"build_menu_open": _build_menu_open,
				"worker_race": "human",
				"militia_active": worker_tid == "hmil",
			}
		)
	)


func _build_building_ids(worker_type_id: String = "hpea") -> PackedStringArray:
	var allow := PackedStringArray()
	for bid in BuildingCatalog.VERTICAL_BUILDING_IDS:
		allow.append(str(bid))
	return CommandButtonCatalog.get_shared().filter_builds(worker_type_id, allow)


func _build_unlocked_flags(building_ids: PackedStringArray) -> PackedInt32Array:
	var owned := owned_buildings_for_local()
	var req_cat := UnitRequiresCatalog.get_shared()
	var arr := PackedInt32Array()
	for bid in building_ids:
		var missing := TechPresence.missing_requires(owned, req_cat.get_requires(str(bid)))
		arr.append(0 if not missing.is_empty() else 1)
	return arr


func _build_disabled_reasons(building_ids: PackedStringArray) -> PackedStringArray:
	var owned := owned_buildings_for_local()
	var req_cat := UnitRequiresCatalog.get_shared()
	var arr := PackedStringArray()
	for bid in building_ids:
		var missing := TechPresence.missing_requires(owned, req_cat.get_requires(str(bid)))
		arr.append(TechPresence.requires_tip(missing) if not missing.is_empty() else "")
	return arr


func _build_executing_flags(building_ids: PackedStringArray) -> PackedInt32Array:
	var arr := PackedInt32Array()
	for _bid in building_ids:
		arr.append(0)
	return arr


func _primary_defend_active() -> bool:
	if _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return false
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	return DefendController.is_defending(primary)


func _primary_has_ability_cd() -> bool:
	if _unit_selector == null or not _unit_selector.has_method("get_primary"):
		return false
	var primary := _unit_selector.call("get_primary") as Node3D
	if primary == null or not is_instance_valid(primary):
		return false
	if not primary.has_meta(AbilityCooldowns.META_CD):
		return false
	var raw: Variant = primary.get_meta(AbilityCooldowns.META_CD)
	return raw is Dictionary and not (raw as Dictionary).is_empty()


func _controllable(node: Node) -> bool:
	if _is_controllable.is_valid():
		return bool(_is_controllable.call(node))
	return false


func _call_unbind_build_site() -> void:
	if _unbind_hud_build_site.is_valid():
		_unbind_hud_build_site.call()
