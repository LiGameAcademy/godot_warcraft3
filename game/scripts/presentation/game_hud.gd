class_name GameHud
extends CanvasLayer

## 现代底栏 HUD（AOE4 向）：左小地图 / 中信息 / 右命令格。暂不复刻 WC3 Console。

signal command_pressed(slot: int)
signal command_action(action_id: String)
signal command_action_rclick(action_id: String)
signal minimap_clicked(uv: Vector2)
## 多选条点击：instance_id → Director 设 primary
signal multi_select_clicked(instance_id: int)
## 训练队列槽点击取消：slot_index
signal train_queue_cancel(slot_index: int)

@export var map_dir: String = "res://assets/map-parsed/echoisles"
@export var console_height_ratio: float = 0.2
@export var show_dev_hint: bool = true

@onready var _gold_label: Label = %GoldValue
@onready var _lumber_label: Label = %LumberValue
@onready var _food_label: Label = %FoodValue
@onready var _unit_name: Label = %UnitName
@onready var _unit_hp: Label = %UnitHp
@onready var _attack_chip: Node = %AttackChip
@onready var _armor_chip: Node = %ArmorChip
@onready var _special_lines: Label = %SpecialLines
@onready var _portrait_host: Control = %PortraitHost
@onready var _portrait: UnitPortraitView = %UnitPortraitView
@onready var _portrait_hp: ProgressBar = %PortraitHpBar
@onready var _portrait_mana: ProgressBar = %PortraitManaBar
@onready var _portrait_hp_row: Control = %PortraitHpRow
@onready var _portrait_mana_row: Control = %PortraitManaRow
@onready var _portrait_hp_label: Label = %PortraitHpLabel
@onready var _portrait_mana_label: Label = %PortraitManaLabel
@onready var _portrait_xp_row: Control = %PortraitXpRow
@onready var _portrait_xp: ProgressBar = %PortraitXpBar
@onready var _portrait_xp_label: Label = %PortraitXpLabel
@onready var _multi_strip: HBoxContainer = %MultiSelectStrip
@onready var _build_row: Control = %BuildProgressRow
@onready var _build_bar: ProgressBar = %BuildProgressBar
@onready var _build_label: Label = %BuildProgressLabel
@onready var _train_row: Control = %TrainQueueRow
@onready var _train_title: Label = %TrainQueueTitle
@onready var _train_count: Label = %TrainQueueCount
@onready var _train_active_row: Control = %TrainActiveRow
@onready var _train_active_icon: Button = %TrainActiveIcon
@onready var _train_active_bar: ProgressBar = %TrainActiveBar
@onready var _train_active_label: Label = %TrainActiveLabel
@onready var _train_strip: HBoxContainer = %TrainQueueStrip
@onready var _train_hint: Label = %TrainQueueHint
@onready var _buff_strip: UnitBuffStrip = %UnitBuffStrip
@onready var _minimap: GameMinimap = %Minimap
@onready var _command_grid: GridContainer = %CommandGrid
@onready var _command_panel: Control = $Root/MarginContainer3/CommandPanel
@onready var _command_title: Label = $Root/MarginContainer3/CommandPanel/Inner/CommandTitle
@onready var _center_host: Control = $Root/MarginContainer2
@onready var _status: Label = %DebugStatusLabel
@onready var _hint: Label = %HintLabel
@onready var _bottom: Control = $Root/MarginContainer3

## slot → action_id（空=无动作）
var _slot_action_ids: PackedStringArray = PackedStringArray()
var _icon_cache: Dictionary = {} ## path → Texture2D
const _TRAIN_SLOT_SIZE := 40
const _TRAIN_MAX_SLOTS := 7
## 上次建槽用的 unit_id 序列；组成未变时只刷进度，避免每帧重建导致点不中
var _train_slot_sig: String = ""
## portrait_bar_mode：none / hero_xp / timed_life（与 SelectionInfoBuilder 一致）
var _portrait_bar_mode: String = "none"
const _HERO_LEVEL_BORDER := "UI/Buttons/HeroLevel/HeroLevel-Border.png"


func _ready() -> void:
	_style_command_panel()
	_style_center_panel()
	_wire_command_buttons()
	_wire_minimap_input()
	if _hint:
		_hint.visible = show_dev_hint
	set_resources(0, 0, 0, 0)
	set_selection_info(SelectionInfoBuilder.build_empty())
	clear_build_progress()
	clear_train_queue()
	_apply_bottom_height()
	get_viewport().size_changed.connect(_apply_bottom_height)
	if not map_dir.is_empty():
		setup_minimap_map(map_dir)


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
	if _minimap == null:
		return
	_minimap.configure(heightfield, unit_host, camera, camera_rig, local_player, catalog)
	setup_minimap_map(map_dir)


func setup_minimap_map(map_directory: String) -> bool:
	if _minimap == null:
		return false
	return _minimap.load_from_map_dir(map_directory)


func _apply_bottom_height() -> void:
	if _bottom == null:
		return
	var h := get_viewport().get_visible_rect().size.y
	_bottom.offset_top = -h * console_height_ratio
	if _hint:
		_hint.offset_top = _bottom.offset_top - 28.0
		_hint.offset_bottom = _bottom.offset_top - 8.0
	if _status:
		_status.offset_top = _bottom.offset_top - 52.0
		_status.offset_bottom = _bottom.offset_top - 32.0
		_status.visible = show_dev_hint


func set_resources(gold: int, lumber: int, food: int, food_max: int) -> void:
	if _gold_label:
		_gold_label.text = str(gold)
	if _lumber_label:
		_lumber_label.text = str(lumber)
	if _food_label:
		_food_label.text = "%d/%d" % [food, food_max]


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
	## 兼容旧调用；完整态请用 set_selection_info。
	if _unit_name:
		_unit_name.text = unit_name if not unit_name.is_empty() else "—"
	_set_resource_bar(_portrait_hp_row, _portrait_hp, _portrait_hp_label, hp, hp_max, true)
	_set_resource_bar(_portrait_mana_row, _portrait_mana, _portrait_mana_label, 0, 0, false)


## 中栏完整刷新。info 见 SelectionInfoBuilder / docs/design/game/HUD.md。
func set_selection_info(info: Dictionary) -> void:
	if info.is_empty():
		info = SelectionInfoBuilder.build_empty()
	var mode := str(info.get("mode", "empty"))
	var display := str(info.get("display_name", "—"))
	var hp := int(info.get("hp", 0))
	var hp_max := int(info.get("hp_max", 0))
	var mana := int(info.get("mana", 0))
	var mana_max := int(info.get("mana_max", 0))
	if _unit_name:
		_unit_name.text = display if not display.is_empty() else "—"
	# 生命/魔法数值叠在肖像条上，不再单独列一行
	if _unit_hp:
		_unit_hp.visible = false
		_unit_hp.text = ""
	_set_resource_bar(
		_portrait_hp_row, _portrait_hp, _portrait_hp_label, hp, hp_max, mode != "empty"
	)
	_set_resource_bar(
		_portrait_mana_row,
		_portrait_mana,
		_portrait_mana_label,
		mana,
		mana_max,
		mana_max > 0 and mode != "empty"
	)
	var is_hero := bool(info.get("is_hero", false))
	var hl := int(info.get("hero_level", 1))
	var xp_in := int(info.get("hero_xp_in_level", 0))
	var xp_need := int(info.get("hero_xp_need", 1))
	var at_max := bool(info.get("hero_at_max_level", false))
	var bar_mode := str(info.get("portrait_bar_mode", "none")).strip_edges()
	_portrait_bar_mode = bar_mode
	# 经验/限时条常驻占位，英雄与普通单位详情高度一致
	if _portrait_xp_row != null:
		if mode == "empty":
			_portrait_xp_row.visible = false
		elif bar_mode == "timed_life":
			_style_portrait_bar_timed()
			_set_timed_life_bar(
				float(info.get("timed_life_left", 0.0)),
				float(info.get("timed_life_total", 1.0))
			)
		elif bar_mode == "hero_xp" and is_hero:
			_style_portrait_bar_hero()
			if at_max:
				_set_resource_bar(_portrait_xp_row, _portrait_xp, _portrait_xp_label, 1, 1, true)
				if _portrait_xp_label:
					_portrait_xp_label.text = "Lv %d · MAX" % hl
			else:
				_set_resource_bar(
					_portrait_xp_row, _portrait_xp, _portrait_xp_label, xp_in, xp_need, true
				)
				if _portrait_xp_label:
					_portrait_xp_label.text = "Lv %d · %d / %d" % [hl, xp_in, xp_need]
		else:
			_reserve_portrait_bar_slot()
	if _attack_chip and _attack_chip.has_method("set_stat"):
		if mode == "empty":
			_attack_chip.call("clear")
		else:
			var atk_info: Variant = info.get("attack", {})
			if typeof(atk_info) == TYPE_DICTIONARY and not (atk_info as Dictionary).is_empty():
				_attack_chip.call("set_stat", atk_info)
			else:
				_attack_chip.call("clear")
	if _armor_chip and _armor_chip.has_method("set_stat"):
		if mode == "empty":
			_armor_chip.call("clear")
		else:
			var arm_info: Variant = info.get("armor", {})
			if typeof(arm_info) == TYPE_DICTIONARY and not (arm_info as Dictionary).is_empty():
				_armor_chip.call("set_stat", arm_info)
			else:
				_armor_chip.call("clear")
	if _special_lines:
		var specials: PackedStringArray = info.get("special_lines", PackedStringArray()) as PackedStringArray
		if specials == null:
			specials = PackedStringArray()
		_special_lines.text = "\n".join(specials)
		# 常驻两行高度（英雄属性 + 移动 / 普通仅移动），避免切换跳动
		_special_lines.custom_minimum_size = Vector2(0, 32)
		_special_lines.visible = mode != "empty"
	var tid := str(info.get("portrait_type_id", ""))
	var owner_id := int(info.get("owner_id", 0))
	if mode == "empty" or tid.is_empty():
		if _portrait != null:
			_portrait.clear_portrait()
	elif _portrait != null:
		_portrait.show_type(tid, owner_id)
	_refresh_multi_strip(info.get("multi", []) as Array, mode == "multi")
	var buffs: Array = info.get("buffs", []) as Array
	if buffs == null:
		buffs = []
	update_buff_strip(buffs)
	var hint := str(info.get("status_hint", ""))
	if not hint.is_empty() and _status:
		# 不覆盖更具体的 Director 状态时：仅空/默认时写入
		pass


func configure_portrait(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	if _portrait != null:
		_portrait.configure(cache, catalog)


func _set_resource_bar(
	row: Control, bar: ProgressBar, label: Label, cur: int, mx: int, show_bar: bool
) -> void:
	var on := show_bar and mx > 0
	if row:
		row.visible = on
	if bar == null:
		return
	bar.visible = on
	if not on:
		if label:
			label.text = ""
		return
	bar.max_value = 100.0
	bar.value = 100.0 * float(cur) / float(maxi(mx, 1))
	if label:
		label.text = "%d/%d" % [cur, mx]


## 限时单位条：选中期间由 Director 每帧刷新。
func update_portrait_timed_life(left: float, total: float) -> void:
	if _portrait_bar_mode != "timed_life":
		return
	_set_timed_life_bar(left, total)


## 肖像生命/魔法条：选中期间由 Director 每帧刷新（不重建整栏）。
func update_portrait_vitals(hp: int, hp_max: int, mana: int, mana_max: int) -> void:
	_set_resource_bar(_portrait_hp_row, _portrait_hp, _portrait_hp_label, hp, hp_max, hp_max > 0)
	_set_resource_bar(
		_portrait_mana_row, _portrait_mana, _portrait_mana_label, mana, mana_max, mana_max > 0
	)


func update_buff_strip(entries: Array) -> void:
	if _buff_strip == null:
		return
	_buff_strip.set_entries(entries)


func update_combat_stat_chips(attack: Dictionary, armor: Dictionary) -> void:
	if _attack_chip and _attack_chip.has_method("set_stat"):
		if attack.is_empty():
			_attack_chip.call("clear")
		else:
			_attack_chip.call("set_stat", attack)
	if _armor_chip and _armor_chip.has_method("set_stat"):
		if armor.is_empty():
			_armor_chip.call("clear")
		else:
			_armor_chip.call("set_stat", armor)


func _reserve_portrait_bar_slot() -> void:
	if _portrait_xp_row == null:
		return
	_portrait_xp_row.visible = true
	_clear_hero_level_border_style()
	if _portrait_xp:
		_portrait_xp.visible = false
		_portrait_xp.value = 0
	if _portrait_xp_label:
		_portrait_xp_label.text = ""


func _set_timed_life_bar(left: float, total: float) -> void:
	var mx := maxf(total, 0.001)
	var cur := clampf(left, 0.0, mx)
	_set_resource_bar(
		_portrait_xp_row,
		_portrait_xp,
		_portrait_xp_label,
		int(round(cur)),
		int(round(mx)),
		true
	)
	if _portrait_xp_label:
		_portrait_xp_label.text = "剩余 %ds" % maxi(int(ceil(cur)), 0)


func _style_portrait_bar_hero() -> void:
	_style_resource_bar(_portrait_xp, Color(0.92, 0.78, 0.22), Color(0.12, 0.10, 0.06))
	_apply_hero_level_border_style()


func _style_portrait_bar_timed() -> void:
	# WC3 限时单位：紫色调（与英雄经验金条区分）
	_style_resource_bar(_portrait_xp, Color(0.58, 0.32, 0.92), Color(0.10, 0.08, 0.14))
	_clear_hero_level_border_style()


func _apply_hero_level_border_style() -> void:
	if _portrait_xp == null:
		return
	var logical := _HERO_LEVEL_BORDER
	var path := RuntimeAssets.converted_path(logical)
	if not RuntimeAssets.file_exists(path):
		return
	var tex := RuntimeAssets.load_texture(logical)
	if tex == null:
		return
	var fill_sb := StyleBoxTexture.new()
	fill_sb.texture = tex
	fill_sb.texture_margin_left = 2.0
	fill_sb.texture_margin_top = 2.0
	fill_sb.texture_margin_right = 2.0
	fill_sb.texture_margin_bottom = 2.0
	fill_sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	fill_sb.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	_portrait_xp.add_theme_stylebox_override("background", fill_sb)


func _clear_hero_level_border_style() -> void:
	if _portrait_xp == null:
		return
	_portrait_xp.remove_theme_stylebox_override("background")


func _set_bar(bar: ProgressBar, cur: int, mx: int, show_bar: bool) -> void:
	## 兼容旧路径；新代码走 _set_resource_bar。
	_set_resource_bar(null, bar, null, cur, mx, show_bar)

func _refresh_multi_strip(entries: Array, show_strip: bool) -> void:
	if _multi_strip == null:
		return
	for c in _multi_strip.get_children():
		c.queue_free()
	_multi_strip.visible = show_strip and not entries.is_empty()
	if not _multi_strip.visible:
		return
	var shown := 0
	const MAX_ICONS := 16
	for e in entries:
		if shown >= MAX_ICONS:
			var more := Label.new()
			more.text = "+%d" % (entries.size() - shown)
			more.add_theme_font_size_override("font_size", 11)
			_multi_strip.add_child(more)
			break
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d := e as Dictionary
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(36, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = str(d.get("tooltip", ""))
		var icon := _load_icon(str(d.get("icon", "")))
		btn.icon = icon
		btn.expand_icon = true
		if icon == null:
			btn.text = str(d.get("type_id", "?")).substr(0, 3)
		var is_pri := bool(d.get("is_primary", false))
		btn.modulate = Color(1.15, 1.05, 0.55) if is_pri else Color(0.85, 0.85, 0.88)
		var iid := int(d.get("instance_id", 0))
		btn.pressed.connect(_on_multi_strip_pressed.bind(iid))
		_multi_strip.add_child(btn)
		shown += 1


func _on_multi_strip_pressed(instance_id: int) -> void:
	multi_select_clicked.emit(instance_id)


## 建造进度（中栏）；ratio 0..1。visible=false 时隐藏整行。
func set_build_progress(visible_on: bool, ratio: float = 0.0, caption: String = "") -> void:
	if _build_row:
		_build_row.visible = visible_on
	if not visible_on:
		return
	var r := clampf(ratio, 0.0, 1.0)
	if _build_bar:
		_build_bar.value = r * 100.0
	if _build_label:
		if caption.is_empty():
			_build_label.text = "建造 %d%%" % int(round(r * 100.0))
		else:
			_build_label.text = caption


func clear_build_progress() -> void:
	set_build_progress(false)


## 训练队列：
## 上行 = 当前生产图标 + 长进度条；
## 下行 = 排队槽（不含当前在训，避免与上行重复）。
## slots=[{unit_id, icon, progress, active, remaining_sec, tooltip}, ...]（[0]=在训）
func set_train_queue(slots: Array, filled: int = -1, max_slots: int = _TRAIN_MAX_SLOTS) -> void:
	if _train_row == null:
		return
	_train_row.visible = true
	var cap := clampi(max_slots, 1, _TRAIN_MAX_SLOTS)
	var n_filled := filled if filled >= 0 else slots.size()
	n_filled = clampi(n_filled, 0, cap)
	if _train_count:
		_train_count.text = "%d/%d" % [n_filled, cap]
	if _train_title:
		_train_title.text = "训练"
	if _train_hint:
		_train_hint.visible = n_filled > 0
		_train_hint.text = "点击图标取消 · 全额退款"

	var active: Dictionary = {}
	if not slots.is_empty():
		active = slots[0] as Dictionary
	_update_train_active_row(active)

	# 下行只展示排队（跳过 slots[0]）；槽位索引仍对应 TrainQueue.cancel_at
	var waiting: Array = []
	for i in range(1, slots.size()):
		waiting.append(slots[i])
	var wait_cap := maxi(cap - 1, 0)
	var sig := _train_slots_signature(waiting, wait_cap)
	if sig != _train_slot_sig or _train_strip == null or _train_strip.get_child_count() != wait_cap:
		_train_slot_sig = sig
		_rebuild_train_strip(waiting, wait_cap, 1)
	else:
		_refresh_train_strip_styles(waiting, wait_cap)


func clear_train_queue() -> void:
	_train_slot_sig = ""
	if _train_row:
		_train_row.visible = false
	if _train_active_icon:
		_train_active_icon.icon = null
		_train_active_icon.text = ""
		_train_active_icon.disabled = true
	if _train_active_bar:
		_train_active_bar.value = 0.0
	if _train_active_label:
		_train_active_label.text = ""
	if _train_strip == null:
		return
	while _train_strip.get_child_count() > 0:
		var c := _train_strip.get_child(0)
		_train_strip.remove_child(c)
		c.queue_free()


func _train_slots_signature(slots: Array, cap: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in range(cap):
		if i < slots.size():
			parts.append(str((slots[i] as Dictionary).get("unit_id", "")))
		else:
			parts.append("")
	return "|".join(parts)


## cancel_index_base：排队槽对应 TrainQueue 下标起点（通常 1，0 留给上行在训）。
func _rebuild_train_strip(slots: Array, cap: int, cancel_index_base: int = 0) -> void:
	if _train_strip == null:
		return
	while _train_strip.get_child_count() > 0:
		var c := _train_strip.get_child(0)
		_train_strip.remove_child(c)
		c.queue_free()
	for i in range(cap):
		var data: Dictionary = slots[i] if i < slots.size() else {}
		_train_strip.add_child(_make_train_slot(cancel_index_base + i, data, false))


func _refresh_train_strip_styles(slots: Array, cap: int) -> void:
	if _train_strip == null:
		return
	for i in range(mini(cap, _train_strip.get_child_count())):
		var host := _train_strip.get_child(i) as PanelContainer
		if host == null:
			continue
		var data: Dictionary = slots[i] if i < slots.size() else {}
		var active := bool(data.get("active", false))
		var has_unit := not str(data.get("unit_id", "")).is_empty()
		var sb := StyleBoxFlat.new()
		if active:
			sb.bg_color = Color(0.18, 0.14, 0.06, 0.95)
			sb.border_color = Color(0.95, 0.72, 0.22, 1.0)
			sb.set_border_width_all(2)
		elif has_unit:
			sb.bg_color = Color(0.12, 0.13, 0.15, 0.92)
			sb.border_color = Color(0.55, 0.58, 0.52, 0.85)
			sb.set_border_width_all(1)
		else:
			sb.bg_color = Color(0.08, 0.09, 0.1, 0.55)
			sb.border_color = Color(0.35, 0.38, 0.36, 0.45)
			sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		host.add_theme_stylebox_override("panel", sb)


func _update_train_active_row(active: Dictionary) -> void:
	var has := not active.is_empty() and (
		not str(active.get("unit_id", "")).is_empty() or not str(active.get("icon", "")).is_empty()
	)
	if _train_active_row:
		_train_active_row.visible = has
	if not has:
		return
	if _train_active_bar:
		_style_train_active_bar(_train_active_bar)
		_train_active_bar.value = clampf(float(active.get("progress", 0.0)), 0.0, 1.0) * 100.0
	var rem := float(active.get("remaining_sec", 0.0))
	var name_s := str(active.get("name", "")).strip_edges()
	if name_s.is_empty():
		name_s = str(active.get("unit_id", ""))
	if _train_active_label:
		_train_active_label.text = "%s · 剩余 %.0fs" % [name_s, rem]
	if _train_active_icon:
		_train_active_icon.disabled = false
		_train_active_icon.focus_mode = Control.FOCUS_NONE
		_train_active_icon.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_train_active_icon.tooltip_text = str(active.get("tooltip", "点击取消"))
		var icon_path := str(active.get("icon", ""))
		var tex := _load_icon(icon_path) if not icon_path.is_empty() else null
		if tex != null:
			_train_active_icon.icon = tex
			_train_active_icon.expand_icon = true
			_train_active_icon.text = ""
		else:
			_train_active_icon.icon = null
			_train_active_icon.text = name_s.substr(0, 3)
		if not _train_active_icon.pressed.is_connected(_on_train_active_icon_pressed):
			_train_active_icon.pressed.connect(_on_train_active_icon_pressed)


func _on_train_active_icon_pressed() -> void:
	train_queue_cancel.emit(0)


func _make_train_slot(index: int, data: Dictionary, show_mini_progress: bool = false) -> Control:
	var host := PanelContainer.new()
	host.custom_minimum_size = Vector2(_TRAIN_SLOT_SIZE, _TRAIN_SLOT_SIZE)
	host.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	var active := bool(data.get("active", false))
	var has_unit := not str(data.get("unit_id", "")).is_empty() or not str(data.get("icon", "")).is_empty()
	if active:
		sb.bg_color = Color(0.18, 0.14, 0.06, 0.95)
		sb.border_color = Color(0.95, 0.72, 0.22, 1.0)
		sb.set_border_width_all(2)
	elif has_unit:
		sb.bg_color = Color(0.12, 0.13, 0.15, 0.92)
		sb.border_color = Color(0.55, 0.58, 0.52, 0.85)
		sb.set_border_width_all(1)
	else:
		sb.bg_color = Color(0.08, 0.09, 0.1, 0.55)
		sb.border_color = Color(0.35, 0.38, 0.36, 0.45)
		sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	host.add_theme_stylebox_override("panel", sb)

	var stack := Control.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(stack)

	if has_unit:
		var btn := Button.new()
		btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = str(data.get("tooltip", "点击取消"))
		var icon_path := str(data.get("icon", ""))
		var tex := _load_icon(icon_path) if not icon_path.is_empty() else null
		if tex != null:
			btn.icon = tex
			btn.expand_icon = true
			btn.text = ""
		else:
			btn.text = str(data.get("unit_id", "?")).substr(0, 3)
		btn.pressed.connect(_on_train_slot_pressed.bind(index))
		stack.add_child(btn)
		if show_mini_progress and active:
			var bar := ProgressBar.new()
			bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			bar.offset_top = -6
			bar.offset_bottom = 0
			bar.min_value = 0.0
			bar.max_value = 100.0
			bar.value = clampf(float(data.get("progress", 0.0)), 0.0, 1.0) * 100.0
			bar.show_percentage = false
			bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_style_train_progress_bar(bar)
			stack.add_child(bar)
	else:
		var empty := Label.new()
		empty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty.text = "·"
		empty.add_theme_color_override("font_color", Color(0.4, 0.42, 0.4, 0.6))
		empty.add_theme_font_size_override("font_size", 14)
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(empty)
	return host


func _style_train_active_bar(bar: ProgressBar) -> void:
	if bar == null:
		return
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.1, 0.92)
	bg.set_corner_radius_all(4)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.45, 0.4, 0.25, 0.7)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.88, 0.62, 0.14, 0.95)
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


func _style_train_progress_bar(bar: ProgressBar) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.05, 0.75)
	bg.set_corner_radius_all(0)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.95, 0.75, 0.2, 1.0)
	fill.set_corner_radius_all(0)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)


func _on_train_slot_pressed(index: int) -> void:
	train_queue_cancel.emit(index)


func _style_center_panel() -> void:
	if _center_host == null:
		return
	var panel := _center_host.get_node_or_null("InfoFrame") as PanelContainer
	if panel == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.08, 0.11, 0.9)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.45, 0.5, 0.55, 0.7)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", sb)
	if _unit_name:
		_unit_name.add_theme_font_size_override("font_size", 16)
		_unit_name.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	if _unit_hp:
		_unit_hp.visible = false
	if _attack_chip and _attack_chip.get_node_or_null("%ValueLabel") is Label:
		(_attack_chip.get_node("%ValueLabel") as Label).add_theme_color_override(
			"font_color", Color(0.9, 0.82, 0.55)
		)
	if _armor_chip and _armor_chip.get_node_or_null("%ValueLabel") is Label:
		(_armor_chip.get_node("%ValueLabel") as Label).add_theme_color_override(
			"font_color", Color(0.7, 0.78, 0.9)
		)
	if _special_lines:
		_special_lines.add_theme_color_override("font_color", Color(0.75, 0.75, 0.72))
	if _build_bar:
		_build_bar.min_value = 0.0
		_build_bar.max_value = 100.0
		_build_bar.show_percentage = false
		_build_bar.custom_minimum_size = Vector2(0, 14)
	if _train_active_bar:
		_style_train_active_bar(_train_active_bar)
	_style_resource_bar(_portrait_hp, Color(0.2, 0.55, 0.22), Color(0.12, 0.14, 0.12))
	_style_resource_bar(_portrait_mana, Color(0.25, 0.4, 0.85), Color(0.1, 0.12, 0.18))
	_style_portrait_bar_hero()


func _style_resource_bar(bar: ProgressBar, fill: Color, bg: Color) -> void:
	if bar == null:
		return
	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.show_percentage = false
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = bg
	bg_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg_sb)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill
	fill_sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill_sb)


## 兼容旧调用：仅文字标签。
func set_command_labels(labels: PackedStringArray) -> void:
	var card: Array[Dictionary] = []
	card.resize(12)
	for i in range(12):
		var e: Dictionary = {}
		if i < labels.size() and not str(labels[i]).is_empty():
			e["id"] = "slot_%d" % i
			e["text"] = str(labels[i])
			e["tooltip"] = str(labels[i])
			e["enabled"] = true
		card[i] = e
	set_command_card(card)


func clear_command_labels() -> void:
	set_command_card([])


## entries：长度最多 12；每项 Dictionary：
## id / text / tooltip / icon / icon_disabled / hotkey_label / executing / enabled
func set_command_card(entries: Array) -> void:
	if _command_grid == null:
		return
	_slot_action_ids = PackedStringArray()
	_slot_action_ids.resize(_command_grid.get_child_count())
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		var entry: Dictionary = {}
		if i < entries.size() and entries[i] is Dictionary:
			entry = entries[i] as Dictionary
		_apply_command_button(btn, i, entry)


## 只刷新执行中态（避免整卡重建闪烁）。
func set_command_executing(action_id: String, executing: bool) -> void:
	if _command_grid == null or action_id.is_empty():
		return
	for i in range(_command_grid.get_child_count()):
		if i >= _slot_action_ids.size():
			break
		if str(_slot_action_ids[i]) != action_id:
			continue
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		_set_button_executing(btn, executing)
		if action_id == "move":
			btn.tooltip_text = _plain_tooltip(_move_tooltip(executing))
			# 有图标时不盖「执行中」字，只靠 modulate 高亮
			if btn.icon == null:
				btn.text = "执行中" if executing else ""
			else:
				btn.text = ""
		break


func set_status(text: String) -> void:
	## DEBUG：不进详情面板；写到顶栏旁 DebugStatusLabel / HintLabel。
	if _status:
		_status.text = text
		_status.visible = show_dev_hint and not text.is_empty()


## 命令面板上方飘字（资源不够等）；DEBUG 状态栏同步。
func show_command_tip(text: String) -> void:
	set_status(text)
	if _command_panel == null:
		return
	var tip := _command_panel.get_node_or_null("CommandFloatTip") as Label
	if tip == null:
		tip = Label.new()
		tip.name = "CommandFloatTip"
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.add_theme_color_override("font_color", Color(1.0, 0.35, 0.28))
		tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		tip.add_theme_constant_override("outline_size", 4)
		tip.set_anchors_preset(Control.PRESET_CENTER_TOP)
		tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
		tip.offset_top = -28.0
		tip.offset_bottom = -4.0
		_command_panel.add_child(tip)
	tip.text = text
	tip.modulate = Color(1, 1, 1, 1)
	tip.visible = true
	var tw := tip.create_tween()
	tw.set_parallel(true)
	tw.tween_property(tip, "modulate:a", 0.0, 1.35).set_delay(0.55)
	tw.tween_property(tip, "offset_top", -48.0, 1.35).set_delay(0.55)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(tip):
			tip.visible = false
			tip.offset_top = -28.0
	)


func set_portrait_texture(_tex: Texture2D) -> void:
	## 已改用 3D UnitPortraitView；保留空实现以免旧调用报错。
	pass


func set_minimap_texture(tex: Texture2D) -> void:
	if _minimap != null:
		_minimap.set_background_texture(tex)


func _apply_command_button(btn: Button, slot: int, entry: Dictionary) -> void:
	var action_id := str(entry.get("id", "")).strip_edges()
	_slot_action_ids[slot] = action_id
	var enabled := bool(entry.get("enabled", not action_id.is_empty()))
	var passive := bool(entry.get("passive", false)) or action_id.begins_with("passive:")
	if action_id.is_empty():
		btn.text = ""
		btn.icon = null
		btn.disabled = true
		btn.tooltip_text = ""
		btn.modulate = Color(1, 1, 1, 0.55)
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_set_button_auto_cast(btn, false, false)
		_set_button_level_badge(btn, 0)
		_set_button_cooldown(btn, 0.0)
		btn.set_meta("_cmd_blocked", false)
		btn.set_meta("_passive_cmd", false)
		return
	# 被动 / 软禁用（法力不足、冷却、科技未满足）：
	# 不置 Button.disabled —— Godot 灰显按钮悬停时常压掉完整 tooltip。
	# 视觉靠 DIS 图标；点击在 gui_input 里拦。
	var soft_blocked := (not enabled) and not passive
	var cd_ratio := clampf(float(entry.get("cooldown_ratio", 0.0)), 0.0, 1.0)
	var keep_icon_on_cd := bool(entry.get("keep_icon_on_cd", false)) and cd_ratio > 0.0
	btn.disabled = false
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.focus_mode = Control.FOCUS_ALL
	btn.tooltip_text = _plain_tooltip(str(entry.get("tooltip", "")))
	var executing := bool(entry.get("executing", false))
	var auto_cast := bool(entry.get("auto_cast", false))
	var autocast_capable := bool(entry.get("autocast_capable", false))
	var text := str(entry.get("text", ""))
	var icon_rel := str(entry.get("icon", ""))
	# 冷却：保留彩色 Art + 扇形遮罩；其它软禁用仍走 DIS
	if soft_blocked and not keep_icon_on_cd:
		var dis := str(entry.get("icon_disabled", ""))
		if not dis.is_empty():
			icon_rel = dis
	var icon := _load_icon(icon_rel)
	btn.icon = icon
	btn.expand_icon = true
	if icon != null and (text.is_empty() or text == "执行中"):
		btn.text = ""
	else:
		if executing and text.is_empty() and not passive:
			text = "执行中"
		btn.text = text
	_set_button_executing(btn, executing and not passive)
	_set_button_auto_cast(btn, auto_cast, autocast_capable)
	_set_button_level_badge(btn, int(entry.get("badge_level", 0)))
	_set_button_cooldown(btn, cd_ratio)
	btn.modulate = Color.WHITE
	btn.set_meta("_passive_cmd", passive)
	btn.set_meta("_cmd_blocked", soft_blocked)


func _set_button_level_badge(btn: Button, level: int) -> void:
	if btn == null:
		return
	var badge := btn.get_node_or_null("LevelBadge") as Label
	if level <= 0:
		if badge != null:
			badge.visible = false
		return
	if badge == null:
		badge = Label.new()
		badge.name = "LevelBadge"
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size", 12)
		badge.add_theme_color_override("font_color", Color(1, 0.95, 0.55))
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		badge.add_theme_constant_override("outline_size", 3)
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -18.0
		badge.offset_top = -16.0
		badge.offset_right = -2.0
		badge.offset_bottom = -2.0
		btn.add_child(badge)
	badge.text = str(level)
	badge.visible = true


func _set_button_cooldown(btn: Button, ratio: float) -> void:
	if btn == null:
		return
	var overlay := btn.get_node_or_null("CooldownOverlay") as Control
	var r := clampf(ratio, 0.0, 1.0)
	if r <= 0.001:
		if overlay != null and overlay.has_method("set_cooldown_ratio"):
			overlay.call("set_cooldown_ratio", 0.0)
		return
	if overlay == null:
		# 新建 class_name 后首轮编译可能尚未进全局缓存；用脚本实例化
		var script := load("res://game/hud/cooldown_button_overlay.gd") as GDScript
		if script == null:
			return
		overlay = script.new() as Control
		if overlay == null:
			return
		overlay.name = "CooldownOverlay"
		overlay.z_index = 12
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(overlay)
		overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		overlay.offset_left = 0.0
		overlay.offset_top = 0.0
		overlay.offset_right = 0.0
		overlay.offset_bottom = 0.0
	if overlay.has_method("set_cooldown_ratio"):
		overlay.call("set_cooldown_ratio", r)


func _set_button_auto_cast(btn: Button, active: bool, capable: bool = false) -> void:
	if btn == null:
		return
	var state := 0
	if capable:
		state = 2 if active else 1
	if int(btn.get_meta("_ac_state", -1)) == state:
		return
	btn.set_meta("_ac_state", state)
	# 去掉金框 StyleBox 方案；状态只由独立覆盖层表达
	btn.add_theme_stylebox_override("normal", _make_cmd_stylebox(
		Color(0.14, 0.15, 0.2, 1.0), Color(0.55, 0.44, 0.2)
	))
	btn.add_theme_stylebox_override("hover", _make_cmd_stylebox(
		Color(0.22, 0.2, 0.14, 1.0), Color(0.85, 0.7, 0.28)
	))
	btn.add_theme_stylebox_override("focus", _make_cmd_stylebox(
		Color(0.22, 0.2, 0.14, 1.0), Color(0.85, 0.7, 0.28)
	))
	var overlay := btn.get_node_or_null("AutocastOverlay") as AutocastButtonOverlay
	if overlay == null:
		overlay = AutocastButtonOverlay.new()
		overlay.name = "AutocastOverlay"
		overlay.z_index = 10
		btn.add_child(overlay)
	overlay.set_autocast_state(capable, active)
	# 清理旧 ColorRect 角标（若有）
	var legacy := btn.get_node_or_null("AutoCastCorners") as Control
	if legacy != null:
		legacy.queue_free()


func _make_autocast_corner_overlay() -> Control:
	## 兼容残留调用；新路径用 AutocastButtonOverlay。
	return AutocastButtonOverlay.new()


func _set_button_executing(btn: Button, executing: bool) -> void:
	# 对齐原作：进行中命令格高亮
	btn.modulate = Color(1.15, 1.05, 0.55) if executing else Color.WHITE


func _move_tooltip(executing: bool) -> String:
	var body := "移动 (M)\n命令单位移动到指定地点。"
	if executing:
		return body + "\n当前：执行中"
	return body


func _plain_tooltip(raw: String) -> String:
	return CommandCard.plain_tooltip(raw)


func _load_icon(rel_or_res: String) -> Texture2D:
	# asset-converted 有 .gdignore，不能 ResourceLoader.load；走磁盘 Image → Texture2D。
	if rel_or_res.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel_or_res)
	if _icon_cache.has(path):
		return _icon_cache[path] as Texture2D
	var tex := RuntimeAssets.load_texture(path)
	if tex != null:
		_icon_cache[path] = tex
	return tex


## 临时美化：深色面板 + 金边命令格（日后可换 WC3 Console 皮）。
func _style_command_panel() -> void:
	if _command_panel:
		var panel_sb := StyleBoxFlat.new()
		panel_sb.bg_color = Color(0.06, 0.07, 0.1, 0.94)
		panel_sb.set_border_width_all(2)
		panel_sb.border_color = Color(0.62, 0.48, 0.2, 0.95)
		panel_sb.set_corner_radius_all(6)
		panel_sb.content_margin_left = 10
		panel_sb.content_margin_right = 10
		panel_sb.content_margin_top = 8
		panel_sb.content_margin_bottom = 10
		panel_sb.shadow_color = Color(0, 0, 0, 0.45)
		panel_sb.shadow_size = 6
		_command_panel.add_theme_stylebox_override("panel", panel_sb)
	if _command_title:
		_command_title.add_theme_color_override("font_color", Color(0.92, 0.82, 0.45))
		_command_title.add_theme_font_size_override("font_size", 14)
		_command_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if _command_grid == null:
		return
	_command_grid.add_theme_constant_override("h_separation", 6)
	_command_grid.add_theme_constant_override("v_separation", 6)
	var normal := _make_cmd_stylebox(Color(0.14, 0.15, 0.2, 1.0), Color(0.55, 0.44, 0.2))
	var hover := _make_cmd_stylebox(Color(0.22, 0.2, 0.14, 1.0), Color(0.85, 0.7, 0.28))
	var pressed := _make_cmd_stylebox(Color(0.28, 0.24, 0.12, 1.0), Color(1.0, 0.85, 0.35))
	var disabled := _make_cmd_stylebox(Color(0.1, 0.1, 0.12, 0.85), Color(0.28, 0.28, 0.3))
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		btn.custom_minimum_size = Vector2(52, 52)
		btn.add_theme_stylebox_override("normal", normal)
		btn.add_theme_stylebox_override("hover", hover)
		btn.add_theme_stylebox_override("pressed", pressed)
		btn.add_theme_stylebox_override("disabled", disabled)
		btn.add_theme_stylebox_override("focus", hover)
		btn.add_theme_color_override("font_color", Color(0.95, 0.9, 0.55))
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.65))
		btn.add_theme_color_override("font_disabled_color", Color(0.45, 0.45, 0.48))
		btn.add_theme_font_size_override("font_size", 11)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		btn.expand_icon = true
		btn.clip_text = true


func _make_cmd_stylebox(bg: Color, border: Color, border_w: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _wire_command_buttons() -> void:
	if _command_grid == null:
		return
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn == null:
			continue
		if not btn.gui_input.is_connected(_on_command_gui_input):
			btn.gui_input.connect(_on_command_gui_input.bind(i))


func _on_command_gui_input(event: InputEvent, slot: int) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if slot < 0 or slot >= _slot_action_ids.size():
		return
	var btn: Button = null
	if slot < _command_grid.get_child_count():
		btn = _command_grid.get_child(slot) as Button
	var action_id := str(_slot_action_ids[slot]).strip_edges()
	if action_id.is_empty():
		return
	# 被动光环：只展示，不发命令
	if action_id.begins_with("passive:") or (btn != null and bool(btn.get_meta("_passive_cmd", false))):
		return
	# 软禁用（法力不足 / 冷却 / 科技）：仍允许右键切换自动施法；左键施法拦截。
	var blocked := btn != null and (
		btn.disabled or bool(btn.get_meta("_cmd_blocked", false))
	)
	if blocked:
		if mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		if int(btn.get_meta("_ac_state", 0)) < 1:
			return
	if mb.button_index == MOUSE_BUTTON_LEFT:
		command_pressed.emit(slot)
		command_action.emit(action_id)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		command_action_rclick.emit(action_id)
	get_viewport().set_input_as_handled()


func _wire_minimap_input() -> void:
	if _minimap == null:
		return
	if not _minimap.clicked.is_connected(_on_game_minimap_clicked):
		_minimap.clicked.connect(_on_game_minimap_clicked)


func _on_game_minimap_clicked(uv: Vector2) -> void:
	minimap_clicked.emit(uv)
