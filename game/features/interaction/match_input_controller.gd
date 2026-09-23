class_name MatchInputController
extends Node
signal path_debug_toggle_requested
var last_screen_pos := Vector2.ZERO
var _commands: CommandInputModule
var _interaction: InteractionModule
var _abilities: AbilitiesModule
var _build: BuildModule
var _card: CommandCardModule
var _debug: DebugToolsModule
var _feedback: InteractionFeedback
var unit_selector: Node
var game_hud: GameHud
var _commit_build: Callable
var _cancel_build: Callable
var _ability_targeting_svc: AbilityTargetingService:
	get:
		return _abilities.targeting if is_instance_valid(_abilities) else null

func configure(deps: Dictionary) -> void:
	_commands = deps.get("commands") as CommandInputModule
	_interaction = deps.get("interaction") as InteractionModule
	_abilities = deps.get("abilities") as AbilitiesModule
	_build = deps.get("build") as BuildModule
	_card = deps.get("card") as CommandCardModule
	_debug = deps.get("debug") as DebugToolsModule
	_feedback = deps.get("feedback") as InteractionFeedback
	unit_selector = deps.get("selector") as Node
	game_hud = deps.get("hud") as GameHud
	_commit_build = deps.get("commit_build", Callable()) as Callable
	_cancel_build = deps.get("cancel_build", Callable()) as Callable

func shutdown() -> void:
	configure({})
	last_screen_pos = Vector2.ZERO

func _exit_tree() -> void:
	shutdown()

func handle_input(event: InputEvent) -> void:
	if not is_instance_valid(_commands) or not is_instance_valid(_build):
		return
	# 背包点击交给 GUI，包括移动/技能瞄准期间，不把槽位当世界落点。
	if event is InputEventMouseButton and is_instance_valid(game_hud) and is_instance_valid(game_hud.inventory_panel):
		var panel := game_hud.inventory_panel
		if panel.is_visible_in_tree() and panel.get_global_rect().has_point(event.position):
			return
	# 移动/攻击/巡逻/采集/集结瞄准：左键下发、右键取消（须在 UnitSelector 之前拦截）
	if _commands.try_handle_aim_input(event):
		get_viewport().set_input_as_handled()
		return
	# 技能瞄准：左键点地/点单位施法
	if (is_instance_valid(_interaction) and _interaction.is_ability()) and event is InputEventMouseButton and _ability_targeting_svc != null:
		var mb_ab := event as InputEventMouseButton
		if mb_ab.pressed and mb_ab.button_index == MOUSE_BUTTON_LEFT:
			var abil_id := _ability_targeting_svc.pending_abil_id()
			var tk := AbilityCatalog.target_kind(abil_id)
			if tk == AbilityCatalog.TARGET_UNIT or tk == AbilityCatalog.TARGET_ALLY:
				_ability_targeting_svc.issue_at_unit_screen(mb_ab.position, UnitOrder.Source.TARGETING)
			else:
				_ability_targeting_svc.issue_at_screen(mb_ab.position, UnitOrder.Source.TARGETING)
			_ability_targeting_svc.cancel()
			get_viewport().set_input_as_handled()
			return
		if mb_ab.pressed and mb_ab.button_index == MOUSE_BUTTON_RIGHT:
			_ability_targeting_svc.cancel()
			get_viewport().set_input_as_handled()
			return
	# F2-4：建造瞄准 → 左键 commit / 右键 cancel / mousemove 跟手 ghost
	# 任何鼠标事件都记录最新位置，给 build_placement 跟手用
	if event is InputEventMouseMotion:
		last_screen_pos = (event as InputEventMouseMotion).position
		_build.update_last_screen_pos(last_screen_pos)
		if (is_instance_valid(_interaction) and _interaction.is_ability()):
			_abilities.update_preview(last_screen_pos)
		if _build.is_build_targeting():
			_build.set_confirm_armed(true)
			_build.update_placement_screen(last_screen_pos)
	if _build.is_build_targeting() and event is InputEventMouseButton:
		var mb_b := event as InputEventMouseButton
		if mb_b.pressed and mb_b.button_index == MOUSE_BUTTON_LEFT:
			# 点在 HUD/小地图上不提交；须先移动过鼠标再确认
			if not _build.is_confirm_armed() or _feedback.pointer_over_blocking_gui(last_screen_pos):
				get_viewport().set_input_as_handled()
				return
			_commit_build.call(mb_b.position)
			get_viewport().set_input_as_handled()
			return
		if mb_b.pressed and mb_b.button_index == MOUSE_BUTTON_RIGHT:
			_cancel_build.call()
			get_viewport().set_input_as_handled()
			return
	if unit_selector != null and unit_selector.has_method("handle_pointer_event"):
		if bool(unit_selector.call("handle_pointer_event", event)):
			get_viewport().set_input_as_handled()


func handle_unhandled(event: InputEvent, enable_move_command: bool, debug_building_fx_hotkeys: bool) -> void:
	if not is_instance_valid(_commands) or not is_instance_valid(_build):
		return
	# 移动/采集/建造瞄准：Esc 取消（落点已在 _input 处理）
	if (
		(
			_commands.is_basic_aiming()
			or (is_instance_valid(_interaction) and _interaction.is_ability())
			or _build.is_build_targeting()
		)
		and event is InputEventKey
		and event.pressed
		and not event.echo
	):
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_interaction.cancel_aim("escape")

			get_viewport().set_input_as_handled()
			return
	# 建造二级面板：Esc → 回主卡
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			if _card.handle_submenu_escape():
				get_viewport().set_input_as_handled()
				return
	# 右键智能 / Shift+RMB 队形
	if _commands.try_handle_smart_rmb(event, enable_move_command):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var ek := event as InputEventKey
		var key := ek.keycode
		var phys := ek.physical_keycode
		# 多选：Tab / Shift+Tab 切换当前选中（肖像 + 命令卡）
		if key == KEY_TAB or phys == KEY_TAB:
			if unit_selector != null and unit_selector.has_method("cycle_primary"):
				var step := -1 if ek.shift_pressed else 1
				if unit_selector.cycle_primary(step):
					get_viewport().set_input_as_handled()
					return
		# GM 面板：`（反引号）或 F4。F10 常被编辑器占用。
		if (
			key == KEY_QUOTELEFT
			or phys == KEY_QUOTELEFT
			or key == KEY_F4
			or phys == KEY_F4
		):
			_debug.toggle_gm_panel()
			get_viewport().set_input_as_handled()
			return
		# 命令卡热键（Catalog Tip/Hotkey；交回官方为 E）
		if _card.try_hotkey(key):
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F9:
			path_debug_toggle_requested.emit()
			get_viewport().set_input_as_handled()
			return
		if key == KEY_F3 or phys == KEY_F3:
			_debug.toggle_perf_overlay()
			get_viewport().set_input_as_handled()
			return
		if not debug_building_fx_hotkeys:
			return
		var phase := -1
		var label := ""
		match key:
			KEY_F6:
				phase = BuildingVisual.Phase.BIRTH
				label = "Birth（建造尘）"
			KEY_F7:
				phase = BuildingVisual.Phase.WORK
				label = "Stand Work（训练烟）"
			KEY_F8:
				phase = BuildingVisual.Phase.IDLE
				label = "Stand"
			_:
				return
		if _debug.apply_hall_phase(phase):
			if game_hud:
				game_hud.set_status("主城 FX → %s" % label)
			get_viewport().set_input_as_handled()
