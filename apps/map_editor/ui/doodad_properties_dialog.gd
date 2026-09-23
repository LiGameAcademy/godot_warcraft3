extends ConfirmationDialog
signal applied(entry: Dictionary)
var document
var history: EditorCommandHistory
var _before: Dictionary = {}
var _initial: Dictionary = {}
var _fields: Dictionary = {}
var _heading: Label
func _ready() -> void:
	title = "树木 / 装饰物属性"
	min_size = Vector2i(420, 340)
	size = min_size
	get_ok_button().text = EditorI18n.t("EDITOR_DIALOG_OK")
	get_cancel_button().text = EditorI18n.t("EDITOR_DIALOG_CANCEL")
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(390, 270)
	add_child(box)
	_heading = Label.new()
	box.add_child(_heading)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for field in [["angle", "朝向（度）", 0.0, 359.99, 0.01], ["x", "X 缩放", 0.01, 100.0, 0.01], ["y", "Y 缩放", 0.01, 100.0, 0.01], ["z", "Z 缩放（高度）", 0.01, 100.0, 0.01], ["life", "生命值（%）", 0.0, 100.0, 1.0]]:
		var label := Label.new()
		label.text = field[1]
		grid.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = field[2]
		spin.max_value = field[3]
		spin.step = field[4]
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(spin)
		_fields[field[0]] = spin
	var hint := Label.new()
	hint.text = "生命值保存为地图属性；\n视觉预览暂不模拟死亡状态。"
	box.add_child(hint)
	confirmed.connect(_apply)
func open_for_entry(entry: Dictionary, catalog: Wc3IdCatalog) -> void:
	_before = entry.duplicate(true)
	var info := catalog.lookup(str(entry.get("id", "")))
	_heading.text = "%s [%s] · #%d" % [info.get("name", ""), entry.get("id", ""), entry.get("creationNumber", -1)]
	_fields.angle.value = fposmod(float(entry.get("angleDegrees", rad_to_deg(float(entry.get("angle", 0.0))))), 360.0)
	for axis in ["x", "y", "z"]:
		_fields[axis].value = float(entry.get("scale", {}).get(axis, 1.0))
	_fields.life.value = int(entry.get("life", 100))
	_initial = _values()
	popup_centered()
func _values() -> Dictionary:
	var values: Dictionary = {}
	for key in _fields:
		values[key] = _fields[key].value
	return values
func _apply() -> void:
	var after := _before.duplicate(true)
	var values := _values()
	if values.angle != _initial.angle:
		after.angleDegrees = values.angle
		after.angle = deg_to_rad(values.angle)
	for axis in ["x", "y", "z"]:
		if values[axis] != _initial[axis]:
			if not after.has("scale"):
				after.scale = {}
			after.scale[axis] = values[axis]
	if values.life != _initial.life:
		after.life = int(values.life)
	if after == _before:
		return
	if document.update_doodad_by_creation_number(int(after.creationNumber), after):
		if history != null:
			history.record(preload("res://documents/commands/doodad_edit_command.gd").make_modify([_before], [after], "Edit Doodad Props"))
		applied.emit(after)
