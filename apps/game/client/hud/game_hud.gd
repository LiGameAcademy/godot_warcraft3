class_name GameHud
extends CanvasLayer

## 现代底栏 HUD 外壳：组装各功能面板，转发展示 API 与操作意图。
## 面板职责见 docs/design/game/HUD_WIDGET_CATALOG.md。

signal command_pressed(slot: int)
signal command_action(action_id: String)
signal command_action_rclick(action_id: String)
signal minimap_clicked(uv: Vector2)
signal multi_select_clicked(instance_id: int)
signal train_queue_cancel(slot_index: int)
signal item_use(slot: int)
signal item_drop(slot: int)
signal item_swap(a: int, b: int)

var inventory_panel: InventoryPanel

@export var map_dir: String = "res://assets/map-parsed/echoisles"
## 底栏高度偏好占比；实际会被 HudLayout 按视口夹紧（小窗不会超过约 26%）。
@export var console_height_ratio: float = 0.2
@export var show_dev_hint: bool = true

@onready var _resource_bar: ResourceBar = %ResourceBar
@onready var _activity_feed: ActivityFeedPanel = %ActivityFeedPanel
@onready var _minimap_dock: MinimapDock = %MinimapDock
@onready var _selection: SelectionDetailsPanel = %SelectionDetailsPanel
@onready var _command_panel: CommandPanel = %CommandPanel
@onready var _command_dock: Control = $Root/MarginContainer3
@onready var _status: Label = %DebugStatusLabel
@onready var _hint: Label = %HintLabel

var _layout_metrics: HudLayout.Metrics = null


func _ready() -> void:
	_wire_panel_signals()
	inventory_panel = InventoryPanel.new()
	inventory_panel.name = "InventoryPanel"
	$Root.add_child(inventory_panel)
	inventory_panel.use_requested.connect(func(slot: int) -> void: item_use.emit(slot))
	inventory_panel.use_requested.connect(_emit_intent_use)
	inventory_panel.drop_requested.connect(func(slot: int) -> void: item_drop.emit(slot))
	inventory_panel.drop_requested.connect(_emit_intent_drop)
	inventory_panel.swap_requested.connect(func(a: int, b: int) -> void: item_swap.emit(a, b))
	inventory_panel.swap_requested.connect(_emit_intent_swap)
	if _command_panel != null:
		_command_panel.resized.connect(_layout_inventory_panel)
	call_deferred("_layout_inventory_panel")
	if _hint:
		_hint.visible = show_dev_hint
	set_resources(0, 0, 0, 0)
	set_selection_info(SelectionInfoBuilder.build_empty())
	clear_build_progress()
	clear_train_queue()
	clear_activity_feed()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)
	if not map_dir.is_empty():
		setup_minimap_map(map_dir)
	## M1：注册为 UiManager Surface（见 docs/design/game/UI_FRAMEWORK.md）。
	var ui_mgr := get_node_or_null("/root/UiManager")
	if ui_mgr != null and ui_mgr.has_method("register_surface"):
		ui_mgr.call("register_surface", &"match_hud", self)


func _wire_panel_signals() -> void:
	if _command_panel != null:
		if not _command_panel.command_pressed.is_connected(_on_command_pressed):
			_command_panel.command_pressed.connect(_on_command_pressed)
		if not _command_panel.command_action.is_connected(_on_command_action):
			_command_panel.command_action.connect(_on_command_action)
		if not _command_panel.command_action_rclick.is_connected(_on_command_action_rclick):
			_command_panel.command_action_rclick.connect(_on_command_action_rclick)
	if _minimap_dock != null and not _minimap_dock.clicked.is_connected(_on_minimap_clicked):
		_minimap_dock.clicked.connect(_on_minimap_clicked)
	if _selection != null:
		if not _selection.multi_select_clicked.is_connected(_on_multi_select_clicked):
			_selection.multi_select_clicked.connect(_on_multi_select_clicked)
		if not _selection.train_queue_cancel.is_connected(_on_train_queue_cancel):
			_selection.train_queue_cancel.connect(_on_train_queue_cancel)


## Director：注入 heightfield / 单位层 / 相机，并加载 war3mapMap。
func configure_minimap(
	map_directory: String,
	heightfield: Wc3Heightfield,
	unit_host: Node,
	camera: Camera3D,
	camera_rig: Node3D,
	local_player: int = 0,
	catalog: Wc3IdCatalog = null
) -> void:
	if not map_directory.is_empty():
		map_dir = map_directory
	if _minimap_dock == null:
		return
	_minimap_dock.configure(
		map_dir, heightfield, unit_host, camera, camera_rig, local_player, catalog
	)


func setup_minimap_map(map_directory: String) -> bool:
	if _minimap_dock == null:
		return false
	return _minimap_dock.load_from_map_dir(map_directory)


## 视口变化时重算底栏：小窗缩小面板，限制底栏占比，避免互相重叠。
func _apply_responsive_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_layout_metrics = HudLayout.compute(vp, console_height_ratio)
	var m := _layout_metrics
	if _resource_bar != null:
		_resource_bar.apply_layout(m.resource_w, m.resource_h, m.margin)
	if _minimap_dock != null:
		_minimap_dock.apply_layout(m.minimap_side, m.margin)
	if _selection != null:
		_selection.apply_layout(m.selection_w, m.bottom_h, m.margin)
	if _command_panel != null:
		_command_panel.apply_layout(m.command_w, m.command_btn)
	if _command_dock != null:
		_command_dock.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		_command_dock.offset_left = -(m.command_w + m.margin)
		_command_dock.offset_right = -m.margin
		_command_dock.offset_top = -m.bottom_h
		_command_dock.offset_bottom = -m.margin
	if _activity_feed != null:
		var feed_bottom := m.margin + m.minimap_side + m.gap
		var feed_max_h := clampf(vp.y * 0.22, 80.0, 220.0)
		_activity_feed.apply_layout(m.activity_w, feed_bottom, m.margin, feed_max_h)
	if inventory_panel != null:
		inventory_panel.apply_layout(m.inventory_w, m.inventory_h)
	_layout_inventory_panel()
	if _hint:
		_hint.offset_top = -m.bottom_h - 28.0
		_hint.offset_bottom = -m.bottom_h - 8.0
		_hint.offset_left = m.margin + m.minimap_side + m.gap
	if _status:
		_status.offset_top = -m.bottom_h - 52.0
		_status.offset_bottom = -m.bottom_h - 32.0
		_status.offset_left = m.margin + m.minimap_side + m.gap
		_status.visible = show_dev_hint


func set_resources(gold: int, lumber: int, food: int, food_max: int) -> void:
	if _resource_bar != null:
		_resource_bar.set_resources(gold, lumber, food, food_max)


func bind_inventory(inv: Inventory, is_read_only: bool = false) -> void:
	if inventory_panel != null:
		inventory_panel.bind_inventory(inv, is_read_only)
		call_deferred("_layout_inventory_panel")


func _layout_inventory_panel() -> void:
	if inventory_panel == null or _command_panel == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	var m := _layout_metrics
	var inv_w := m.inventory_w if m != null else 144.0
	var inv_h := m.inventory_h if m != null else 260.0
	var margin := m.margin if m != null else 12.0
	inventory_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	inventory_panel.offset_left = -(inv_w + margin)
	inventory_panel.offset_right = -margin
	inventory_panel.offset_bottom = _command_panel.get_global_rect().position.y - h - 10.0
	inventory_panel.offset_top = inventory_panel.offset_bottom - inv_h
	if inventory_panel.has_method("apply_layout"):
		inventory_panel.apply_layout(inv_w, inv_h)


func bind_stock(stock) -> void:
	if stock == null:
		return
	if not stock.changed.is_connected(_on_stock_changed):
		stock.changed.connect(_on_stock_changed)
	_on_stock_changed(stock)


func _on_stock_changed(stock) -> void:
	if stock == null:
		return
	set_resources(stock.gold, stock.lumber, stock.food_used, stock.food_cap)


func set_unit_info(unit_name: String, hp: int, hp_max: int) -> void:
	if _selection != null:
		_selection.set_unit_info(unit_name, hp, hp_max)


func set_selection_info(info: Dictionary) -> void:
	if _selection != null:
		_selection.set_selection_info(info)


func prepare_portraits(type_ids: PackedStringArray, owner_id: int) -> void:
	if _selection != null:
		await _selection.prepare_portraits(type_ids, owner_id)


func configure_portrait(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	if _selection != null:
		_selection.configure_portrait(cache, catalog)


func update_portrait_timed_life(left: float, total: float) -> void:
	if _selection != null:
		_selection.update_portrait_timed_life(left, total)


func update_portrait_vitals(hp: int, hp_max: int, mana: int, mana_max: int) -> void:
	if _selection != null:
		_selection.update_portrait_vitals(hp, hp_max, mana, mana_max)


func update_buff_strip(entries: Array) -> void:
	if _selection != null:
		_selection.update_buff_strip(entries)


func update_combat_stat_chips(attack: Dictionary, armor: Dictionary) -> void:
	if _selection != null:
		_selection.update_combat_stat_chips(attack, armor)


func set_build_progress(visible_on: bool, ratio: float = 0.0, caption: String = "") -> void:
	if _selection != null:
		_selection.set_build_progress(visible_on, ratio, caption)


func clear_build_progress() -> void:
	if _selection != null:
		_selection.clear_build_progress()


func set_activity_feed(entries: Array) -> void:
	if _activity_feed != null:
		_activity_feed.set_entries(entries)


func clear_activity_feed() -> void:
	if _activity_feed != null:
		_activity_feed.clear_entries()


func set_train_queue(slots: Array, filled: int = -1, max_slots: int = 7) -> void:
	if _selection != null:
		_selection.set_train_queue(slots, filled, max_slots)


func clear_train_queue() -> void:
	if _selection != null:
		_selection.clear_train_queue()


func set_command_labels(labels: PackedStringArray) -> void:
	if _command_panel != null:
		_command_panel.set_command_labels(labels)


func clear_command_labels() -> void:
	if _command_panel != null:
		_command_panel.clear_command_labels()


func set_command_card(entries: Array) -> void:
	if _command_panel != null:
		_command_panel.set_command_card(entries)


func update_command_card_dynamic(entries: Array) -> void:
	if _command_panel != null:
		_command_panel.update_command_card_dynamic(entries)


func set_command_executing(action_id: String, executing: bool) -> void:
	if _command_panel != null:
		_command_panel.set_command_executing(action_id, executing)


func set_status(text: String) -> void:
	if _status:
		_status.text = text
		_status.visible = show_dev_hint and not text.is_empty()


## 玩法反馈（资源不够等）：命令面板上方浮字；debug 状态栏仍受 show_dev_hint 控制。
func show_command_tip(text: String) -> void:
	if text.is_empty():
		return
	if _status:
		_status.text = text
		_status.visible = show_dev_hint
	if _command_panel != null:
		_command_panel.show_tip(text)


## region ========== UiSurface（UiManager） ==========


func surface_id() -> StringName:
	return &"match_hud"


func push_status(text: String) -> void:
	set_status(text)


func show_tip(text: String) -> void:
	show_command_tip(text)


func push_command_card(entries: Array) -> void:
	set_command_card(entries)


func push_resources(vm: Dictionary) -> void:
	if vm.is_empty():
		return
	set_resources(
		int(vm.get("gold", 0)),
		int(vm.get("lumber", 0)),
		int(vm.get("food_used", 0)),
		int(vm.get("food_cap", 0))
	)


func push_selection(vm: Dictionary) -> void:
	if vm.is_empty():
		return
	set_selection_info(vm)


## endregion


func set_portrait_texture(_tex: Texture2D) -> void:
	pass


func set_minimap_texture(tex: Texture2D) -> void:
	if _minimap_dock != null:
		_minimap_dock.set_background_texture(tex)


func _on_command_pressed(slot: int) -> void:
	command_pressed.emit(slot)


func _on_command_action(action_id: String) -> void:
	command_action.emit(action_id)
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.COMMAND, {"action_id": action_id})


func _on_command_action_rclick(action_id: String) -> void:
	command_action_rclick.emit(action_id)
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.COMMAND_RCLICK, {"action_id": action_id})


func _on_minimap_clicked(uv: Vector2) -> void:
	minimap_clicked.emit(uv)
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.MINIMAP_CLICK, {"uv": uv})


func _on_multi_select_clicked(instance_id: int) -> void:
	multi_select_clicked.emit(instance_id)
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.MULTI_SELECT, {"instance_id": instance_id})


func _on_train_queue_cancel(slot_index: int) -> void:
	train_queue_cancel.emit(slot_index)
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.TRAIN_CANCEL, {"slot_index": slot_index})


func _emit_intent_use(slot: int) -> void:
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.ITEM_USE, {"slot": slot})


func _emit_intent_drop(slot: int) -> void:
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.ITEM_DROP, {"slot": slot})


func _emit_intent_swap(a: int, b: int) -> void:
	if is_instance_valid(UiManager):
		UiManager.emit_intent(UiIntent.ITEM_SWAP, {"a": a, "b": b})
