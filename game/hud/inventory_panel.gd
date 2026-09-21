class_name InventoryPanel
extends PanelContainer

## 英雄六格背包（Present）。方格 tile + 图标 + 次数角标 + 冷却扇形。
signal use_requested(slot: int)
signal drop_requested(slot: int)
signal swap_requested(a: int, b: int)

const SLOT_SIZE := Vector2(56, 56)
const GRID_COLS := 2 ## WC3 原作背包为 2×3

var inventory: Inventory
## true：仅展示（选中敌方/中立英雄）；禁止使用/丢弃/交换。
var read_only: bool = false
var buttons: Array[Button] = []
var overlays: Array[CooldownButtonOverlay] = []
var charge_labels: Array[Label] = []
var marked: int = -1
var _elapsed: float = 0.0
var _icons: Dictionary = {}
var _heading: Label
var _hint: Label


func _ready() -> void:
	add_to_group("world_input_blockers")
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_panel_style()
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	_heading = Label.new()
	_heading.text = "物品栏"
	_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_heading.add_theme_font_size_override("font_size", 13)
	_heading.add_theme_color_override("font_color", Color(0.92, 0.82, 0.45))
	column.add_child(_heading)
	var grid := GridContainer.new()
	grid.columns = GRID_COLS
	grid.add_theme_constant_override("h_separation", 5)
	grid.add_theme_constant_override("v_separation", 5)
	column.add_child(grid)
	var normal := _make_slot_style(Color(0.12, 0.13, 0.17, 1.0), Color(0.5, 0.4, 0.18))
	var hover := _make_slot_style(Color(0.2, 0.18, 0.12, 1.0), Color(0.85, 0.7, 0.28))
	var pressed := _make_slot_style(Color(0.26, 0.22, 0.1, 1.0), Color(1.0, 0.85, 0.35))
	var marked_sb := _make_slot_style(Color(0.28, 0.22, 0.1, 1.0), Color(1.0, 0.78, 0.25))
	for i in range(Inventory.CAPACITY):
		var b := Button.new()
		b.custom_minimum_size = SLOT_SIZE
		b.expand_icon = true
		b.clip_text = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_constant_override("icon_max_width", 44)
		b.add_theme_font_size_override("font_size", 1)
		b.add_theme_stylebox_override("normal", normal)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_stylebox_override("pressed", pressed)
		b.add_theme_stylebox_override("focus", marked_sb)
		b.add_theme_stylebox_override("disabled", normal)
		b.gui_input.connect(_on_slot_input.bind(i))
		grid.add_child(b)
		buttons.append(b)
		var overlay := CooldownButtonOverlay.new()
		overlay.name = "Cooldown"
		b.add_child(overlay)
		overlays.append(overlay)
		var charges := Label.new()
		charges.name = "Charges"
		charges.mouse_filter = Control.MOUSE_FILTER_IGNORE
		charges.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		charges.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		charges.add_theme_font_size_override("font_size", 12)
		charges.add_theme_color_override("font_color", Color(1.0, 0.95, 0.7))
		charges.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		charges.add_theme_constant_override("outline_size", 3)
		charges.set_anchors_preset(Control.PRESET_FULL_RECT)
		charges.offset_left = 2.0
		charges.offset_top = 2.0
		charges.offset_right = -3.0
		charges.offset_bottom = -2.0
		b.add_child(charges)
		charge_labels.append(charges)
	_hint = Label.new()
	_hint.text = "左键使用 · 右键丢弃\nShift+左键交换"
	_hint.add_theme_font_size_override("font_size", 10)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.68, 0.55, 0.9))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_hint)
	visible = false
	set_process(false)


func bind_inventory(inv: Inventory, is_read_only: bool = false) -> void:
	if is_instance_valid(inventory) and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	inventory = inv
	read_only = is_read_only and inv != null
	marked = -1
	visible = inv != null
	set_process(inv != null)
	if _hint != null:
		_hint.text = (
			"观察中（不可操作）"
			if read_only
			else "左键使用 · 右键丢弃\nShift+左键交换"
		)
	if inv != null:
		inv.changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_instance_valid(inventory):
		visible = false
		set_process(false)
		return
	for i in range(buttons.size()):
		var item := inventory.item_at(i)
		var b := buttons[i]
		var overlay := overlays[i]
		var charges := charge_labels[i]
		b.modulate = Color(1.15, 1.05, 0.75) if marked == i else Color.WHITE
		b.text = ""
		b.icon = null
		b.tooltip_text = "空槽位"
		charges.visible = false
		overlay.set_cooldown_ratio(0.0)
		if item == null:
			continue
		var path := ItemCatalog.icon(item.type_id)
		if not path.is_empty():
			if not _icons.has(path):
				_icons[path] = RuntimeAssets.load_texture(RuntimeAssets.resolve(path))
			b.icon = _icons[path] as Texture2D
		var cd := inventory.cooldown_remaining(i)
		var cool := 0.0
		var ab := ItemCatalog.effect(item.type_id)
		if ab != null:
			cool = maxf(ab.cool_at(1), 0.001)
		if cd > 0.0 and cool > 0.0:
			overlay.set_cooldown_ratio(clampf(cd / cool, 0.0, 1.0))
		if item.charges > 0:
			charges.text = str(item.charges)
			charges.visible = true
		elif ItemCatalog.effect(item.type_id) == null:
			charges.text = "?"
			charges.visible = true
		var tip := ItemCatalog.tooltip(item.type_id)
		if read_only:
			b.tooltip_text = tip + "\n观察中（不可操作）"
		else:
			b.tooltip_text = tip + "\n左键使用 / 右键丢弃 / Shift 点两格交换"


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.15:
		_elapsed = 0.0
		refresh()


func _on_slot_input(event: InputEvent, slot: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if read_only:
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		marked = -1
		drop_requested.emit(slot)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.shift_pressed:
			if marked < 0:
				marked = slot
			else:
				swap_requested.emit(marked, slot)
				marked = -1
			refresh()
		else:
			marked = -1
			use_requested.emit(slot)
		accept_event()


func _apply_panel_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.94)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.62, 0.48, 0.2, 0.95)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 5
	add_theme_stylebox_override("panel", sb)


func _make_slot_style(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(2)
	sb.border_color = border
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb
