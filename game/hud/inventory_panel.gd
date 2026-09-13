class_name InventoryPanel
extends PanelContainer

## 独立六格背包表现；逻辑信号更新槽位，局部低频刷新冷却文字。
signal use_requested(slot: int)
signal drop_requested(slot: int)
signal swap_requested(a: int, b: int)
var inventory: Inventory
var buttons: Array[Button] = []
var marked: int = -1
var _elapsed: float = 0.0
var _icons: Dictionary = {}

func _ready() -> void:
	add_to_group("world_input_blockers")
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "英雄背包"
	column.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 3
	column.add_child(grid)
	for i in range(Inventory.CAPACITY):
		var b := Button.new()
		b.custom_minimum_size = Vector2(66, 52)
		b.expand_icon = true
		b.add_theme_constant_override("icon_max_width", 28)
		b.add_theme_font_size_override("font_size", 12)
		b.focus_mode = Control.FOCUS_NONE
		b.gui_input.connect(_on_slot_input.bind(i))
		grid.add_child(b)
		buttons.append(b)
	var hint := Label.new()
	hint.text = "左键使用 · 右键丢弃\nShift 点两格交换"
	hint.add_theme_font_size_override("font_size", 11)
	column.add_child(hint)
	visible = false
	set_process(false)

func bind_inventory(inv: Inventory) -> void:
	if is_instance_valid(inventory) and inventory.changed.is_connected(refresh):
		inventory.changed.disconnect(refresh)
	inventory = inv
	marked = -1
	visible = inv != null
	set_process(inv != null)
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
		b.modulate = Color(1.0, 0.8, 0.35) if marked == i else Color.WHITE
		b.text = "%d\n空" % (i + 1)
		b.icon = null
		b.tooltip_text = "空槽位"
		if item == null:
			continue
		var path := ItemCatalog.icon(item.type_id)
		if not path.is_empty():
			if not _icons.has(path):
				_icons[path] = RuntimeAssets.load_texture(RuntimeAssets.resolve(path))
			b.icon = _icons[path] as Texture2D
		var cd := inventory.cooldown_remaining(i)
		var suffix := "×%d" % item.charges if item.charges > 0 else "装备"
		if ItemCatalog.effect(item.type_id) == null:
			suffix = "待实现"
		b.text = "%d · %s" % [i + 1, "%ds" % int(ceil(cd)) if cd > 0.0 else suffix]
		b.tooltip_text = ItemCatalog.tooltip(item.type_id) + "\n左键使用 / 右键丢弃 / Shift 点两格交换"

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.2:
		_elapsed = 0.0
		refresh()

func _on_slot_input(event: InputEvent, slot: int) -> void:
	if not event is InputEventMouseButton or not event.pressed:
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
