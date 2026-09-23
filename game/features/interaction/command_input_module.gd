class_name CommandInputModule
extends Node

## 命令输入下发：瞄准确认后的 issue_*、begin_* 瞄准启动、智能右键 / 队形移动。
## 互斥瞄准状态仍由 InteractionModule 持有；SmartTarget 解析仍由 SmartCommandModule。
## 本模块不持有 GameDirector 类型。

var _command_router: CommandRouter
var _unit_selector: Node
var _path_query: PathQuery
var _tree_registry: TreeRegistry
var _interaction: InteractionModule
var _smart: SmartCommandModule
var _game_hud: Node

var _ground_at_screen: Callable
var _get_selected: Callable
var _interrupt_channels: Callable
var _refresh_command_card: Callable
var _spawn_move_confirm: Callable
var _flash_cursor_move: Callable
var _sync_rally_flag: Callable
var _ensure_navigator: Callable
var _is_gold_mine: Callable
var _is_harvestable_tree: Callable
var _tree_cn_of: Callable
var _local_stock: Callable
var _is_controllable: Callable


func configure(deps: Dictionary) -> void:
	_command_router = deps.get("command_router") as CommandRouter
	_unit_selector = deps.get("unit_selector") as Node
	_path_query = deps.get("path_query") as PathQuery
	_tree_registry = deps.get("tree_registry") as TreeRegistry
	_interaction = deps.get("interaction") as InteractionModule
	_smart = deps.get("smart_command") as SmartCommandModule
	_game_hud = deps.get("game_hud") as Node
	_ground_at_screen = deps.get("ground_at_screen", Callable()) as Callable
	_get_selected = deps.get("get_selected", Callable()) as Callable
	_interrupt_channels = deps.get("interrupt_channels", Callable()) as Callable
	_refresh_command_card = deps.get("refresh_command_card", Callable()) as Callable
	_spawn_move_confirm = deps.get("spawn_move_confirm", Callable()) as Callable
	_flash_cursor_move = deps.get("flash_cursor_move", Callable()) as Callable
	_sync_rally_flag = deps.get("sync_rally_flag", Callable()) as Callable
	_ensure_navigator = deps.get("ensure_navigator", Callable()) as Callable
	_is_gold_mine = deps.get("is_gold_mine", Callable()) as Callable
	_is_harvestable_tree = deps.get("is_harvestable_tree", Callable()) as Callable
	_tree_cn_of = deps.get("tree_cn_of", Callable()) as Callable
	_local_stock = deps.get("local_stock", Callable()) as Callable
	_is_controllable = deps.get("is_controllable", Callable()) as Callable


func shutdown() -> void:
	_command_router = null
	_unit_selector = null
	_path_query = null
	_tree_registry = null
	_interaction = null
	_smart = null
	_game_hud = null
	_ground_at_screen = Callable()
	_get_selected = Callable()
	_interrupt_channels = Callable()
	_refresh_command_card = Callable()
	_spawn_move_confirm = Callable()
	_flash_cursor_move = Callable()
	_sync_rally_flag = Callable()
	_ensure_navigator = Callable()
	_is_gold_mine = Callable()
	_is_harvestable_tree = Callable()
	_tree_cn_of = Callable()
	_local_stock = Callable()
	_is_controllable = Callable()


func _exit_tree() -> void:
	shutdown()


## 处理移动/攻击/巡逻/采集/集结瞄准态的鼠标键。返回 true 表示已消费事件。
func try_handle_aim_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton) or not is_instance_valid(_interaction):
		return false
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return false
	var aim := _interaction.current_aim()
	match aim:
		InteractionModule.Aim.MOVE:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if issue_move_at_screen(mb.position, UnitOrder.Source.TARGETING):
					_do_flash_cursor_move()
				else:
					_cancel_basic_aim()
				return true
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_basic_aim()
				return true
		InteractionModule.Aim.ATTACK:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				issue_attack_at_screen(mb.position, UnitOrder.Source.TARGETING)
				_cancel_basic_aim()
				return true
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_basic_aim()
				return true
		InteractionModule.Aim.PATROL:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				if issue_patrol_at_screen(mb.position, UnitOrder.Source.TARGETING):
					_do_flash_cursor_move()
				else:
					_cancel_basic_aim()
				return true
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_basic_aim()
				return true
		InteractionModule.Aim.HARVEST:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				issue_harvest_at_screen(mb.position, UnitOrder.Source.TARGETING)
				_cancel_basic_aim()
				return true
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_basic_aim()
				return true
		InteractionModule.Aim.RALLY:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				issue_set_rally_at_screen(mb.position, UnitOrder.Source.TARGETING)
				_cancel_basic_aim()
				return true
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_cancel_basic_aim()
				return true
	return false


## 右键智能 / Shift+RMB 队形。返回 true 表示已消费。
func try_handle_smart_rmb(event: InputEvent, enable_move_command: bool) -> bool:
	if not (event is InputEventMouseButton):
		return false
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_RIGHT or not mb.pressed:
		return false
	if mb.shift_pressed and enable_move_command:
		if issue_group_move_command(mb.position, FormationFollow.FORMATION_RECT):
			return true
	if issue_smart_at_screen(mb.position, UnitOrder.Source.SMART_RMB):
		return true
	return false


func issue_stop(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or _unit_selector == null:
		return false
	var selected: Array = _selected()
	_do_interrupt(selected)
	var n_stop := _command_router.issue_stop(selected, source)
	if n_stop > 0:
		_set_status("停止 · %d 单位" % n_stop)
	_do_refresh_card()
	return n_stop > 0


func issue_hold(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or _unit_selector == null:
		return false
	var selected: Array = _selected()
	_do_interrupt(selected)
	var n := _command_router.issue_hold(selected, source)
	if n > 0:
		_set_status("保持原位 · %d 单位" % n)
	else:
		_set_status("保持原位：无可用单位")
	_do_refresh_card()
	return n > 0


func try_toggle_defend(_source: int = UnitOrder.Source.UNKNOWN) -> void:
	if _command_router == null:
		return
	var stock: PlayerStock = null
	if _local_stock.is_valid():
		stock = _local_stock.call() as PlayerStock
	if stock == null or not stock.has_upgrade(DefendController.UPGRADE_ID):
		_set_status("需要研究：%s" % TechPresence.display_name(DefendController.UPGRADE_ID))
		return
	var selected := _selected()
	if selected.is_empty():
		return
	var primary: Node3D = null
	if _unit_selector != null and _unit_selector.has_method("get_primary"):
		primary = _unit_selector.call("get_primary") as Node3D
	var want := not DefendController.is_defending(primary)
	var n := _command_router.issue_defend(selected, want)
	if n <= 0:
		_set_status("顶盾：无可用步兵")
	elif want:
		_set_status("顶盾开启 · %d 单位" % n)
	else:
		_set_status("停止顶盾 · %d 单位" % n)
	_do_refresh_card()


func issue_attack_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or _unit_selector == null:
		return false
	var selected: Array = _selected()
	if selected.is_empty():
		return false
	var picked: Node3D = null
	if _unit_selector.has_method("pick_at"):
		picked = _unit_selector.call("pick_at", screen_pos) as Node3D
	if picked != null and CombatQuery.any_can_attack(selected, picked):
		var n := _command_router.issue_attack_target(selected, picked, source)
		if n > 0:
			_set_status("攻击 · %d 单位" % n)
		else:
			_set_status("攻击：无合法目标")
		_do_refresh_card()
		return n > 0
	var hit := _ground_hit(screen_pos)
	if hit == Vector3.INF:
		_set_status("攻击：未点到地面或目标")
		return false
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var result := _command_router.issue_attack_move(selected, goal_center, source)
	var moved: int = int(result.get("moved", 0))
	if moved > 0:
		_do_spawn_confirm(goal_center, MoveConfirmFx.Kind.ATTACK)
	if moved > 0:
		_set_status(
			"攻击移动 → (%.0f, %.0f) · %d 单位" % [goal_center.x, goal_center.y, moved]
		)
	else:
		_set_status("攻击移动：无法到达")
	_do_refresh_card()
	return moved > 0


func issue_patrol_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or _unit_selector == null or _path_query == null:
		return false
	var selected: Array = _selected()
	if selected.is_empty():
		return false
	var hit := _ground_hit(screen_pos)
	if hit == Vector3.INF:
		_set_status("巡逻：未点到地面")
		return false
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var result := _command_router.issue_patrol(selected, goal_center, source)
	var moved: int = int(result.get("moved", 0))
	if moved > 0:
		_do_spawn_confirm(goal_center)
	if moved > 0:
		_set_status(
			"巡逻 ↔ (%.0f, %.0f) · %d 单位" % [goal_center.x, goal_center.y, moved]
		)
	else:
		_set_status("巡逻：无法开始")
	_do_refresh_card()
	return moved > 0


func issue_smart_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _unit_selector == null or _command_router == null or not is_instance_valid(_smart):
		return false
	var selected: Array = _selected()
	if selected.is_empty():
		return false
	var target := _smart.resolve_smart_target(screen_pos, selected)
	if target == null or target.goal_wc3 == Vector2.INF:
		_set_status("命令：未点到有效目标")
		return false
	var result := _command_router.issue_smart(selected, target, source)
	if not bool(result.get("ok", false)):
		if not _command_router.filter_rally_buildings(selected).is_empty():
			_set_status("集结点：未能设置（目标无效？）")
		return false
	var goal: Vector2 = result.get("goal_wc3", Vector2.INF)
	var moved := int(result.get("moved", 0))
	var rallied := int(result.get("rallied", 0))
	if moved > 0:
		_do_flash_cursor_move()
		if goal != Vector2.INF:
			_do_spawn_confirm(goal)
	if rallied > 0 and _sync_rally_flag.is_valid():
		_sync_rally_flag.call()
	_set_status(_smart.format_smart_status(result))
	_do_refresh_card()
	return true


func issue_set_rally_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _unit_selector == null or not is_instance_valid(_smart):
		return false
	var selected: Array = _selected()
	var buildings: Array[Node3D] = []
	for n in selected:
		if n is Node3D and BuildingRally.can_set_rally(n as Node3D):
			buildings.append(n as Node3D)
	if buildings.is_empty():
		return false
	var target := _smart.resolve_smart_target(screen_pos, selected)
	if target == null or target.goal_wc3 == Vector2.INF:
		_set_status("集结点：未点到有效地点")
		return false
	for b in buildings:
		apply_rally_from_smart(b, target)
	if _sync_rally_flag.is_valid():
		_sync_rally_flag.call()
	var src := "面板" if source == UnitOrder.Source.PANEL or source == UnitOrder.Source.TARGETING else "右键"
	match target.kind:
		SmartTarget.Kind.GOLD_MINE:
			_set_status("集结点 → 金矿（%s）" % src)
		SmartTarget.Kind.TREE:
			_set_status("集结点 → 树木（%s）" % src)
		_:
			_set_status(
				"集结点 → (%.0f, %.0f)（%s）" % [target.goal_wc3.x, target.goal_wc3.y, src]
			)
	return true


func apply_rally_from_smart(building: Node3D, target: SmartTarget) -> void:
	if building == null or target == null:
		return
	match target.kind:
		SmartTarget.Kind.GOLD_MINE:
			BuildingRally.set_gold_mine(building, target.node, target.goal_wc3)
		SmartTarget.Kind.TREE:
			BuildingRally.set_tree(building, target.tree_cn, target.goal_wc3)
		_:
			BuildingRally.set_ground(building, target.goal_wc3)


func issue_move_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or _unit_selector == null or _path_query == null:
		return false
	var selected: Array = _selected()
	if selected.is_empty():
		return false
	var hit := _ground_hit(screen_pos)
	if hit == Vector3.INF:
		_set_status("移动：未点到地面")
		return true
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var result := _command_router.issue_move_to_wc3(selected, goal_center, source)
	var moved: int = int(result.get("moved", 0))
	var failed: int = int(result.get("failed", 0))
	if moved > 0:
		_do_spawn_confirm(goal_center)
	if moved > 0:
		_set_status(
			"移动 → (%.0f, %.0f) · %d 单位（已散开落点）" % [goal_center.x, goal_center.y, moved]
		)
	elif failed > 0:
		_set_status("无法到达 (%.0f, %.0f)" % [goal_center.x, goal_center.y])
	elif _command_router.filter_movers(selected).is_empty():
		_set_status("选中无可用移动单位（建筑？）")
	_do_refresh_card()
	return moved > 0 or failed > 0


func issue_group_move_command(
	screen_pos: Vector2,
	formation: String,
	spacing: float = 64.0
) -> bool:
	if _unit_selector == null or _path_query == null:
		return false
	if not _unit_selector.has_method("get_primary"):
		return false
	var selected: Array = _selected()
	if selected.is_empty():
		return false
	var primary: Node3D = _unit_selector.call("get_primary") as Node3D
	if primary == null or not _can_control(primary) or not selected.has(primary):
		primary = selected[0] as Node3D
	var hit := _ground_hit(screen_pos)
	if hit == Vector3.INF:
		_set_status("队形移动：未点到地面")
		return true
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal_center := Vector2(hit.x * inv, -hit.z * inv)
	var movers: Array = []
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if BuildingVisual.is_building(tid):
			continue
		movers.append(node)
	if movers.is_empty():
		_set_status("选中无可用移动单位（建筑？）")
		return true
	var leader: Node3D = primary
	var leader_pos := Vector2(
		leader.global_position.x * inv, -leader.global_position.z * inv
	)
	var slots: PackedVector2Array = FormationFollow.slot_positions(
		leader_pos, 0.0, movers.size(), formation, spacing
	)
	var moved := 0
	var failed := 0
	for i in range(movers.size()):
		var node: Node3D = movers[i]
		var nav: UnitNavigator = null
		if _ensure_navigator.is_valid():
			nav = _ensure_navigator.call(node) as UnitNavigator
		if nav == null:
			continue
		var goal: Vector2
		if node == leader:
			goal = goal_center
		else:
			var offset: Vector2 = slots[i] - slots[0]
			goal = goal_center + offset
		if nav.go_to_wc3(goal):
			moved += 1
		else:
			failed += 1
	if moved > 0:
		_do_spawn_confirm(goal_center)
	if moved > 0:
		_set_status(
			"队形移动 [%s] → (%.0f, %.0f) · %d 单位" % [formation, goal_center.x, goal_center.y, moved]
		)
	elif failed > 0:
		_set_status("队形移动：无法到达 (%.0f, %.0f)" % [goal_center.x, goal_center.y])
	return moved > 0 or failed > 0


func issue_harvest_at_screen(screen_pos: Vector2, source: int) -> bool:
	if _command_router == null or _unit_selector == null:
		return false
	var selected: Array = _selected()
	var peasants := _command_router.filter_peasants(selected)
	if peasants.is_empty():
		_set_status("采集：无农民")
		return false
	if _unit_selector.has_method("pick_at"):
		var picked: Node3D = _unit_selector.call("pick_at", screen_pos) as Node3D
		if picked != null and _gold_mine(picked):
			var n := _command_router.issue_harvest_gold(peasants, picked, source)
			if n > 0:
				_set_status("采集金币 · %d 农民" % n)
			_do_refresh_card()
			return n > 0
		if picked != null and _harvestable_tree(picked):
			var cn := _tree_cn(picked)
			if cn >= 0:
				if is_instance_valid(_smart):
					_smart.flash_tree_target(cn)
				var nl := _command_router.issue_harvest_lumber(peasants, cn, source)
				if nl > 0:
					_set_status("采集木材 · %d 农民" % nl)
				_do_refresh_card()
				return nl > 0
	if _tree_registry != null:
		var cn2 := _tree_registry.pick_cn_at_screen(screen_pos)
		if cn2 >= 0:
			if is_instance_valid(_smart):
				_smart.flash_tree_target(cn2)
			var nl2 := _command_router.issue_harvest_lumber(peasants, cn2, source)
			if nl2 > 0:
				_set_status("采集木材 · %d 农民" % nl2)
			_do_refresh_card()
			return nl2 > 0
	_set_status("采集：请点金矿或树木")
	return false


func issue_return_goods(source: int = UnitOrder.Source.UNKNOWN) -> bool:
	if _command_router == null or _unit_selector == null:
		return false
	var selected: Array = _selected()
	var n := _command_router.issue_return_goods(selected, source)
	if n > 0:
		_set_status("送回资源 · %d 农民" % n)
	else:
		_set_status("送回：无负重农民")
	_do_refresh_card()
	return n > 0


func begin_move_targeting(source: int) -> void:
	var selected: Array = _selected()
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		_set_status("移动：无可用单位")
		return
	_do_interrupt(selected)
	if is_instance_valid(_interaction):
		_interaction.begin_aim(InteractionModule.Aim.MOVE)
	var src := "面板" if source == UnitOrder.Source.PANEL else "热键 M"
	_set_status("移动瞄准（%s）· 左键指定地点 · Esc 取消" % src)


func begin_attack_targeting(source: int) -> void:
	var selected: Array = _selected()
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		_set_status("攻击：无可用单位")
		return
	if is_instance_valid(_interaction):
		_interaction.begin_aim(InteractionModule.Aim.ATTACK)
	var src := "面板" if source == UnitOrder.Source.PANEL else "热键 A"
	_set_status("攻击瞄准（%s）· 左键单位/地面 · Esc 取消" % src)


func begin_patrol_targeting(source: int) -> void:
	var selected: Array = _selected()
	if _command_router == null or _command_router.filter_movers(selected).is_empty():
		_set_status("巡逻：无可用单位")
		return
	if is_instance_valid(_interaction):
		_interaction.begin_aim(InteractionModule.Aim.PATROL)
	var src := "面板" if source == UnitOrder.Source.PANEL else "热键 P"
	_set_status("巡逻瞄准（%s）· 左键指定另一端 · Esc 取消" % src)


func begin_harvest_targeting(source: int) -> void:
	var selected: Array = _selected()
	if _command_router == null or _command_router.filter_peasants(selected).is_empty():
		_set_status("采集：无农民")
		return
	if is_instance_valid(_interaction):
		_interaction.begin_aim(InteractionModule.Aim.HARVEST)
	var src := "面板" if source == UnitOrder.Source.PANEL else "热键 G"
	_set_status("采集瞄准（%s）· 左键点金矿 · Esc 取消" % src)


func begin_rally_targeting(source: int) -> void:
	var selected: Array = _selected()
	var any := false
	for n in selected:
		if n is Node3D and BuildingRally.can_set_rally(n as Node3D):
			any = true
			break
	if not any:
		_set_status("集结点：请选中可训练建筑")
		return
	if is_instance_valid(_interaction):
		_interaction.begin_aim(InteractionModule.Aim.RALLY)
	var src := "面板" if source == UnitOrder.Source.PANEL else "热键"
	_set_status("集结瞄准（%s）· 左键点地面/金矿/树 · Esc 取消" % src)


func is_basic_aiming() -> bool:
	if not is_instance_valid(_interaction):
		return false
	var a := _interaction.current_aim()
	return (
		a == InteractionModule.Aim.MOVE
		or a == InteractionModule.Aim.ATTACK
		or a == InteractionModule.Aim.PATROL
		or a == InteractionModule.Aim.HARVEST
		or a == InteractionModule.Aim.RALLY
	)


func _cancel_basic_aim() -> void:
	if is_instance_valid(_interaction):
		_interaction.cancel_aim()


func _selected() -> Array:
	if _get_selected.is_valid():
		return _get_selected.call() as Array
	return []


func _ground_hit(screen_pos: Vector2) -> Vector3:
	if _ground_at_screen.is_valid():
		return _ground_at_screen.call(screen_pos) as Vector3
	return Vector3.INF


func _do_interrupt(units: Array) -> void:
	if _interrupt_channels.is_valid():
		_interrupt_channels.call(units)


func _do_refresh_card() -> void:
	if _refresh_command_card.is_valid():
		_refresh_command_card.call()


func _do_spawn_confirm(goal_wc3: Vector2, kind: int = MoveConfirmFx.Kind.MOVE) -> void:
	if _spawn_move_confirm.is_valid():
		_spawn_move_confirm.call(goal_wc3, kind)


func _do_flash_cursor_move() -> void:
	if _flash_cursor_move.is_valid():
		_flash_cursor_move.call()


func _gold_mine(node: Node) -> bool:
	if _is_gold_mine.is_valid():
		return bool(_is_gold_mine.call(node))
	return false


func _harvestable_tree(node: Node) -> bool:
	if _is_harvestable_tree.is_valid():
		return bool(_is_harvestable_tree.call(node))
	return false


func _tree_cn(node: Node) -> int:
	if _tree_cn_of.is_valid():
		return int(_tree_cn_of.call(node))
	return -1


func _can_control(node: Node3D) -> bool:
	if _is_controllable.is_valid():
		return bool(_is_controllable.call(node))
	return true


func _set_status(text: String) -> void:
	if _game_hud != null and _game_hud.has_method("set_status"):
		_game_hud.call("set_status", text)
