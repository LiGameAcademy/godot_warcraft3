class_name CommandPanel
extends PanelContainer

## 右下角 4×3 命令卡。只消费展示条目并发出操作意图。

signal command_pressed(slot: int)
signal command_action(action_id: String)
signal command_action_rclick(action_id: String)

@onready var _command_title: Label = %CommandTitle
@onready var _command_grid: GridContainer = %CommandGrid

## slot → action_id（空=无动作）
var _slot_action_ids: PackedStringArray = PackedStringArray()
var _icon_cache: HudIconCache = HudIconCache.new()


func _ready() -> void:
	_apply_panel_style()
	_wire_command_buttons()


var _layout_btn_size: float = 52.0


## 响应式：面板最小宽与命令格边长。
func apply_layout(panel_width: float, button_size: float) -> void:
	var w := maxf(panel_width, 176.0)
	_layout_btn_size = clampf(button_size, 40.0, 56.0)
	custom_minimum_size = Vector2(w, 0.0)
	if _command_grid == null:
		return
	for i in range(_command_grid.get_child_count()):
		var btn := _command_grid.get_child(i) as Button
		if btn != null:
			btn.custom_minimum_size = Vector2(_layout_btn_size, _layout_btn_size)


## 测试可注入：覆盖图标加载（不读磁盘）。
func set_icon_loader(loader: Callable) -> void:
	_icon_cache.load_override = loader


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


## 更新已有槽位的动态状态；布局变化必须走 set_command_card。
func update_command_card_dynamic(entries: Array) -> void:
	if _command_grid == null:
		return
	for i in range(mini(entries.size(), _command_grid.get_child_count())):
		var entry: Dictionary = entries[i]
		if i >= _slot_action_ids.size() or str(entry.get("id", "")) != str(_slot_action_ids[i]):
			return # Structural changes must use set_command_card.
	for i in range(mini(entries.size(), _command_grid.get_child_count())):
		var btn := _command_grid.get_child(i) as Button
		if btn != null and btn.get_meta("_command_entry", {}) != entries[i]:
			_apply_command_button(btn, i, entries[i])


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
			if btn.icon == null:
				btn.text = "执行中" if executing else ""
			else:
				btn.text = ""
		break


## 命令面板上方飘字（资源不够等）。
## 必须挂到 GameHud/Root：若挂到 MarginContainer，容器布局会把 Label 挤回格子里导致看不见。
func show_tip(text: String) -> void:
	if text.is_empty():
		return
	var host := _float_tip_host()
	## 清掉误挂在 MarginContainer 上的旧飘字（布局容器会把它挤没）。
	var dock := get_parent() as Control
	if dock != null and dock != host:
		var stray := dock.get_node_or_null("CommandFloatTip") as Label
		if stray != null:
			stray.queue_free()
	var tip := host.get_node_or_null("CommandFloatTip") as Label
	if tip == null:
		tip = Label.new()
		tip.name = "CommandFloatTip"
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.z_index = 80
		tip.add_theme_font_size_override("font_size", 16)
		tip.add_theme_color_override("font_color", Color(1.0, 0.35, 0.28))
		tip.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		tip.add_theme_constant_override("outline_size", 4)
		host.add_child(tip)
	if tip.has_meta("_float_tw"):
		var old_tw: Tween = tip.get_meta("_float_tw") as Tween
		if old_tw != null and old_tw.is_valid():
			old_tw.kill()
	tip.text = text
	tip.visible = true
	tip.modulate = Color(1, 1, 1, 1)
	tip.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	tip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	## 锚在命令面板顶边中心上方（用全局坐标，不受父布局影响）。
	var panel_rect := get_global_rect()
	tip.reset_size()
	var tip_w := maxf(tip.get_minimum_size().x, maxf(panel_rect.size.x, 160.0))
	var tip_h := maxf(tip.get_minimum_size().y, 22.0)
	tip.size = Vector2(tip_w, tip_h)
	tip.global_position = Vector2(
		panel_rect.position.x + panel_rect.size.x * 0.5 - tip_w * 0.5,
		panel_rect.position.y - tip_h - 10.0
	)
	var tw := tip.create_tween()
	tip.set_meta("_float_tw", tw)
	tw.set_parallel(true)
	tw.tween_property(tip, "modulate:a", 0.0, 1.45).set_delay(0.65)
	tw.tween_property(tip, "global_position:y", tip.global_position.y - 22.0, 1.45).set_delay(0.65)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(tip):
			tip.visible = false
	)


func _float_tip_host() -> Control:
	var n: Node = self
	while n != null:
		if n is CanvasLayer:
			var root := n.get_node_or_null("Root") as Control
			if root != null:
				return root
		n = n.get_parent()
	var p := get_parent() as Control
	return p if p != null else self


## 供无场景单测挂 GridContainer。
func attach_command_grid(grid: GridContainer) -> void:
	_command_grid = grid
	_wire_command_buttons()


func _load_icon(rel_or_res: String) -> Texture2D:
	return _icon_cache.load_icon(rel_or_res)


func _apply_command_button(btn: Button, slot: int, entry: Dictionary) -> void:
	btn.set_meta("_command_entry", entry.duplicate(true))
	var action_id := str(entry.get("id", "")).strip_edges()
	_slot_action_ids[slot] = action_id
	var enabled := bool(entry.get("enabled", not action_id.is_empty()))
	var passive := bool(entry.get("passive", false)) or action_id.begins_with("passive:")
	if action_id.is_empty():
		btn.text = ""
		btn.icon = null
		btn.remove_meta("_command_icon_path")
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
	if soft_blocked and not keep_icon_on_cd:
		var dis := str(entry.get("icon_disabled", ""))
		if not dis.is_empty():
			icon_rel = dis
	if str(btn.get_meta("_command_icon_path", "#uninitialized")) != icon_rel or (btn.icon == null and not icon_rel.is_empty()):
		btn.icon = _load_icon(icon_rel)
		btn.set_meta("_command_icon_path", icon_rel)
	var icon := btn.icon
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
		var script := load("res://client/hud/cooldown_button_overlay.gd") as GDScript
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
	var legacy := btn.get_node_or_null("AutoCastCorners") as Control
	if legacy != null:
		legacy.queue_free()


func _set_button_executing(btn: Button, executing: bool) -> void:
	btn.modulate = Color(1.15, 1.05, 0.55) if executing else Color.WHITE


func _move_tooltip(executing: bool) -> String:
	var body := "移动 (M)\n命令单位移动到指定地点。"
	if executing:
		return body + "\n当前：执行中"
	return body


func _plain_tooltip(raw: String) -> String:
	return CommandCard.plain_tooltip(raw)


func _apply_panel_style() -> void:
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
	add_theme_stylebox_override("panel", panel_sb)
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
		btn.custom_minimum_size = Vector2(_layout_btn_size, _layout_btn_size)
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
	if action_id.begins_with("passive:") or (btn != null and bool(btn.get_meta("_passive_cmd", false))):
		return
	var blocked := btn != null and (
		btn.disabled or bool(btn.get_meta("_cmd_blocked", false))
	)
	if blocked:
		if mb.button_index == MOUSE_BUTTON_LEFT:
			## 置灰格也要给反馈，避免「点了没反应」。
			var entry: Dictionary = {}
			if btn.has_meta("_command_entry"):
				entry = btn.get_meta("_command_entry") as Dictionary
			var reason := str(entry.get("disabled_reason", "")).strip_edges()
			if reason.is_empty():
				reason = "无法执行"
			show_tip(reason)
			get_viewport().set_input_as_handled()
			return
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
