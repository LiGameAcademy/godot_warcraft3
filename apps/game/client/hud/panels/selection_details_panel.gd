class_name SelectionDetailsPanel
extends MarginContainer

## 中栏选中详情：肖像 / 血蓝 / 属性 / 多选条 / 建造与训练队列 / Buff。
## 只消费 SelectionInfoBuilder 展示数据，发出多选与取消训练意图。

signal multi_select_clicked(instance_id: int)
signal train_queue_cancel(slot_index: int)

const _TRAIN_SLOT_SIZE := 40
const _TRAIN_MAX_SLOTS := 7
const _HERO_LEVEL_BORDER := "UI/Buttons/HeroLevel/HeroLevel-Border.png"

@onready var _unit_name: Label = %UnitName
@onready var _unit_hp: Label = %UnitHp
@onready var _attack_chip: Node = %AttackChip
@onready var _armor_chip: Node = %ArmorChip
@onready var _special_lines: Label = %SpecialLines
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
@onready var _info_frame: PanelContainer = %InfoFrame

var _icon_cache: HudIconCache = HudIconCache.new()
var _train_slot_sig: String = ""
var _portrait_bar_mode: String = "none"


func _ready() -> void:
	_apply_panel_style()


## 响应式：底栏中央详情区宽度与高度。
func apply_layout(width: float, height: float, margin: float) -> void:
	var w := maxf(width, 200.0)
	var h := maxf(height, 120.0)
	var m := maxf(margin, 4.0)
	custom_minimum_size = Vector2(w, 0.0)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -w * 0.5
	offset_right = w * 0.5
	offset_top = -h
	offset_bottom = -m


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


func set_unit_info(unit_name: String, hp: int, hp_max: int) -> void:
	if _unit_name:
		_unit_name.text = unit_name if not unit_name.is_empty() else "—"
	_set_resource_bar(_portrait_hp_row, _portrait_hp, _portrait_hp_label, hp, hp_max, true)
	_set_resource_bar(_portrait_mana_row, _portrait_mana, _portrait_mana_label, 0, 0, false)


func configure_portrait(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	if _portrait != null:
		_portrait.configure(cache, catalog)


func update_portrait_timed_life(left: float, total: float) -> void:
	if _portrait_bar_mode != "timed_life":
		return
	_set_timed_life_bar(left, total)


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
		var icon: Texture2D = _icon_cache.load_icon(str(d.get("icon", "")))
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


func _train_slots_signature(slots: Array, cap: int) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i in range(cap):
		if i < slots.size():
			parts.append(str((slots[i] as Dictionary).get("unit_id", "")))
		else:
			parts.append("")
	return "|".join(parts)


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
		var tex: Texture2D = _icon_cache.load_icon(icon_path) if not icon_path.is_empty() else null
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
		var tex: Texture2D = _icon_cache.load_icon(icon_path) if not icon_path.is_empty() else null
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


func _apply_panel_style() -> void:
	if _info_frame == null:
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
	_info_frame.add_theme_stylebox_override("panel", sb)
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
