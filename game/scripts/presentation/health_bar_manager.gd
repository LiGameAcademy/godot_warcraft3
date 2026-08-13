class_name HealthBarManager
extends CanvasLayer

## 全局头顶血条（Present）。跟随 MapUnitLayer 单位/建筑；读 UnitLife，不写战斗逻辑。
## 显隐：受伤 / 建造中 / 选中（可配置）。

const BAR_W := 52.0
const BAR_H := 6.0
const Y_BIAS := 0.4
const SKIP_META := {
	"SelectionRing": true,
	"DeathDropRing": true,
}

@export var show_when_damaged: bool = true
@export var show_when_selected: bool = true
@export var show_under_construction: bool = true
@export var damaged_threshold: float = 0.995

var _camera: Camera3D = null
var _unit_host: Node = null
var _root: Control = null
## instance_id → { bar: Control, fill: ColorRect, bg: ColorRect }
var _entries: Dictionary = {}
## instance_id → true（当前选中）
var _selected: Dictionary = {}


func _ready() -> void:
	layer = 8
	_ensure_root()
	set_process(true)


func configure(camera: Camera3D, unit_host: Node) -> void:
	_camera = camera
	_unit_host = unit_host
	_ensure_root()
	resync()


func set_selection(selected: Array) -> void:
	_selected.clear()
	for n in selected:
		if n is Node3D and is_instance_valid(n):
			_selected[(n as Node3D).get_instance_id()] = true


## 扫描单位层，为缺失条目建血条；清理已销毁节点。
func resync() -> void:
	if _unit_host == null:
		return
	var alive: Dictionary = {}
	for c in _unit_host.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if not _is_trackable(n):
			continue
		UnitLife.ensure(n)
		var id := n.get_instance_id()
		alive[id] = true
		if not _entries.has(id):
			_entries[id] = _make_bar(n)
	var stale: Array = []
	for id in _entries.keys():
		if not alive.has(id):
			stale.append(id)
	for id in stale:
		_free_entry(int(id))


func _process(_delta: float) -> void:
	if _camera == null or _unit_host == null or _root == null:
		return
	# 轻量：每帧跟位置；偶发补注册（建造刷出等）
	if Engine.get_process_frames() % 15 == 0:
		resync()
	for id in _entries.keys():
		var e: Dictionary = _entries[id]
		var node: Node3D = e.get("node") as Node3D
		var bar: Control = e.get("bar") as Control
		if node == null or not is_instance_valid(node) or bar == null:
			_free_entry(int(id))
			continue
		if not node.is_visible_in_tree() or not node.visible:
			bar.visible = false
			continue
		var want := _should_show(node, int(id))
		bar.visible = want
		if not want:
			continue
		var world := _bar_world_pos(node)
		if _camera.is_position_behind(world):
			bar.visible = false
			continue
		var screen := _camera.unproject_position(world)
		bar.position = screen - Vector2(BAR_W * 0.5, BAR_H + 4.0)
		_apply_fill(e, UnitLife.ratio(node))


func _ensure_root() -> void:
	if _root != null and is_instance_valid(_root):
		return
	_root = Control.new()
	_root.name = "Bars"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


func _is_trackable(node: Node3D) -> bool:
	if node == null:
		return false
	var d: Dictionary = node.get_meta("unit_data", {})
	if d.is_empty():
		return false
	var tid := str(d.get("typeId", ""))
	if tid.is_empty() or tid == "sloc":
		return false
	if bool(node.get_meta("is_placeholder", false)):
		return false
	return true


func _should_show(node: Node3D, id: int) -> bool:
	if show_under_construction and UnitLife.is_under_construction(node):
		return true
	if show_when_selected and _selected.has(id):
		return true
	if show_when_damaged and UnitLife.ratio(node) < damaged_threshold:
		return true
	return false


func _bar_world_pos(node: Node3D) -> Vector3:
	var h := _estimate_height(node)
	return node.global_position + Vector3(0.0, h + Y_BIAS, 0.0)


func _estimate_height(node: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var nm := str(vi.name)
		if SKIP_META.has(nm):
			continue
		var local := vi.get_aabb()
		var xf: Transform3D = node.global_transform.affine_inverse() * vi.global_transform
		var la := xf * local
		if first:
			aabb = la
			first = false
		else:
			aabb = aabb.merge(la)
	if first:
		var d: Dictionary = node.get_meta("unit_data", {})
		if bool(d.get("isBuilding", false)) or BuildingVisual.is_building(str(d.get("typeId", ""))):
			return 3.2
		return 1.4
	return maxf(aabb.end.y, 0.8)


func _make_bar(node: Node3D) -> Dictionary:
	var bar := Control.new()
	bar.name = "HpBar_%d" % node.get_instance_id()
	bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	bar.size = Vector2(BAR_W, BAR_H)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.visible = false
	var bg := ColorRect.new()
	bg.name = "Bg"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.1, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(bg)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2(1, 1)
	fill.size = Vector2(BAR_W - 2.0, BAR_H - 2.0)
	fill.color = Color(0.25, 0.85, 0.35, 0.95)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(fill)
	_root.add_child(bar)
	return {"node": node, "bar": bar, "fill": fill, "bg": bg}


func _apply_fill(e: Dictionary, r: float) -> void:
	var fill := e.get("fill") as ColorRect
	if fill == null:
		return
	r = clampf(r, 0.0, 1.0)
	fill.size.x = maxf((BAR_W - 2.0) * r, 0.0)
	if UnitLife.is_under_construction(e.get("node") as Node3D):
		fill.color = Color(0.35, 0.75, 1.0, 0.95)
	elif r > 0.55:
		fill.color = Color(0.25, 0.85, 0.35, 0.95)
	elif r > 0.3:
		fill.color = Color(0.95, 0.8, 0.2, 0.95)
	else:
		fill.color = Color(0.9, 0.25, 0.2, 0.95)


func _free_entry(id: int) -> void:
	if not _entries.has(id):
		return
	var e: Dictionary = _entries[id]
	var bar: Control = e.get("bar") as Control
	if bar != null and is_instance_valid(bar):
		bar.queue_free()
	_entries.erase(id)
