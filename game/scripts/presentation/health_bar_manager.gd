class_name HealthBarManager
extends CanvasLayer

## 全局头顶血条（Present）。跟随 MapUnitLayer 单位/建筑；读 UnitLife，不写战斗逻辑。
## 默认常显；GM 可关。关闭后按住 Alt 临时显示。
## 挂点：`Wc3ModelScene.overhead_anchor()`（OverHead Ref）→ 骨骼回退 → AABB 顶。

const BAR_W := 52.0
const BAR_H := 6.0
const Y_BIAS := 0.12
const SKIP_META := {
	"SelectionRing": true,
	"DeathDropRing": true,
}
## 无 OverHead Ref 时的骨骼名回退（MDX→GLTF 常见）
const BONE_CANDIDATES := [
	"Bone_Head",
	"Bone_Overhead",
	"Overhead",
	"Head",
	"bone_head",
	"Bone Head",
]


@export var always_show: bool = true
@export var show_when_damaged: bool = true
@export var show_when_selected: bool = true
@export var show_under_construction: bool = true
@export var damaged_threshold: float = 0.995

var _camera: Camera3D = null
var _unit_host: Node = null
var _root: Control = null
## instance_id → { bar, fill, bg, node, bone_idx, skeleton }
var _entries: Dictionary = {}
## instance_id → true（当前选中）
var _selected: Dictionary = {}
## Alt 按住临时显示（always_show=false 时）
var _alt_hold_show: bool = false


func _ready() -> void:
	layer = 8
	_ensure_root()
	set_process(true)


func configure(camera: Camera3D, unit_host: Node) -> void:
	_camera = camera
	_unit_host = unit_host
	_ensure_root()
	resync()


func set_always_show(on: bool) -> void:
	always_show = on


func set_alt_hold_show(on: bool) -> void:
	_alt_hold_show = on


func is_always_show() -> bool:
	return always_show


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
		else:
			_refresh_attach_entry(_entries[id], n)
	var stale: Array = []
	for id in _entries.keys():
		if not alive.has(id):
			stale.append(id)
	for id in stale:
		_free_entry(int(id))


func _process(_delta: float) -> void:
	if _camera == null or _unit_host == null or _root == null:
		return
	if Engine.get_process_frames() % 15 == 0:
		resync()
	for id in _entries.keys():
		var e: Dictionary = _entries[id]
		var node := _safe_node3d(e.get("node"))
		var bar := e.get("bar") as Control
		if bar != null and not is_instance_valid(bar):
			bar = null
		if node == null or bar == null:
			_free_entry(int(id))
			continue
		if not node.is_visible_in_tree() or not node.visible:
			bar.visible = false
			continue
		var want := _should_show(node, int(id))
		bar.visible = want
		if not want:
			continue
		var world := _bar_world_pos(e, node)
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
	if not WorldMembership.is_in_world(node):
		return false
	if UnitLife.get_life(node) <= 0.0:
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
	if not WorldMembership.is_in_world(node) or UnitLife.get_life(node) <= 0.0:
		return false
	# 常显，或 GM 关闭时常按 Alt 临时显示
	if always_show or Input.is_key_pressed(KEY_ALT) or _alt_hold_show:
		return true
	if show_under_construction and UnitLife.is_under_construction(node):
		return true
	if show_when_selected and _selected.has(id):
		return true
	if show_when_damaged and UnitLife.ratio(node) < damaged_threshold:
		return true
	return false


func _safe_node3d(v: Variant) -> Node3D:
	if v is Object and is_instance_valid(v) and v is Node3D:
		return v as Node3D
	return null


func _safe_skeleton(v: Variant) -> Skeleton3D:
	if v is Object and is_instance_valid(v) and v is Skeleton3D:
		return v as Skeleton3D
	return null


func _refresh_attach_entry(e: Dictionary, node: Node3D) -> void:
	var resolved := _resolve_attach(node)
	e["attach"] = resolved.get("attach")
	e["skeleton"] = resolved.get("skeleton")
	e["bone_idx"] = int(resolved.get("bone_idx", -1))


func _bar_world_pos(e: Dictionary, node: Node3D) -> Vector3:
	var sk := _safe_skeleton(e.get("skeleton"))
	var bone_idx: int = int(e.get("bone_idx", -1))
	var attach := _safe_node3d(e.get("attach"))
	# 建条时模型可能未就绪；缺挂点则懒解析一次
	if attach == null and sk == null:
		_refresh_attach_entry(e, node)
		attach = _safe_node3d(e.get("attach"))
		sk = _safe_skeleton(e.get("skeleton"))
		bone_idx = int(e.get("bone_idx", -1))
	# OverHead Ref 优先于骨骼
	if attach != null:
		return attach.global_position + Vector3(0.0, Y_BIAS, 0.0)
	if sk != null and bone_idx >= 0:
		return sk.to_global(sk.get_bone_global_pose(bone_idx).origin) + Vector3(0.0, Y_BIAS, 0.0)
	var h := _estimate_height(node)
	return node.global_position + Vector3(0.0, h + Y_BIAS, 0.0)


func _resolve_attach(node: Node3D) -> Dictionary:
	# 1) bake OverHead Ref（经 Wc3ModelScene 门面；单位实体本身通常没有 overhead_anchor）
	var scene := Wc3ModelScene.find_on(node)
	if scene != null:
		var oh := scene.overhead_anchor()
		if oh != null and is_instance_valid(oh):
			return {"attach": oh, "skeleton": null, "bone_idx": -1}
	# 2) 节点自身即门面（少见）
	if node != null and node.has_method("overhead_anchor"):
		var from_api: Variant = node.call("overhead_anchor")
		if from_api is Node3D:
			return {"attach": from_api as Node3D, "skeleton": null, "bone_idx": -1}
	# 3) BoneAttachment3D（旧资产回退）
	for c in node.find_children("*", "BoneAttachment3D", true, false):
		var ba := c as BoneAttachment3D
		if ba == null:
			continue
		var bn := str(ba.bone_name)
		for cand in BONE_CANDIDATES:
			if bn == cand or bn.to_lower().contains("head") or bn.to_lower().contains("overhead"):
				return {"attach": ba, "skeleton": null, "bone_idx": -1}
	# 4) Skeleton 按名
	for c in node.find_children("*", "Skeleton3D", true, false):
		var sk := c as Skeleton3D
		if sk == null:
			continue
		for cand in BONE_CANDIDATES:
			var idx := sk.find_bone(cand)
			if idx >= 0:
				return {"attach": null, "skeleton": sk, "bone_idx": idx}
		for i in range(sk.get_bone_count()):
			var nm := sk.get_bone_name(i).to_lower()
			if nm.contains("overhead") or nm.ends_with("head") or nm.contains("bone_head"):
				return {"attach": null, "skeleton": sk, "bone_idx": i}
	return {"attach": null, "skeleton": null, "bone_idx": -1}


func _estimate_height(node: Node3D) -> float:
	var aabb := AABB()
	var first := true
	for c in node.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var nm := str(vi.name)
		if SKIP_META.has(nm) or nm.begins_with("DamageFloat"):
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
	var attach_info := _resolve_attach(node)
	return {
		"node": node,
		"bar": bar,
		"fill": fill,
		"bg": bg,
		"attach": attach_info.get("attach"),
		"skeleton": attach_info.get("skeleton"),
		"bone_idx": int(attach_info.get("bone_idx", -1)),
	}


func _apply_fill(e: Dictionary, r: float) -> void:
	var fill := e.get("fill") as ColorRect
	if fill == null or not is_instance_valid(fill):
		return
	r = clampf(r, 0.0, 1.0)
	fill.size.x = maxf((BAR_W - 2.0) * r, 0.0)
	var node := _safe_node3d(e.get("node"))
	if node == null:
		return
	if UnitLife.is_under_construction(node):
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
	var bar := e.get("bar") as Control
	if bar != null and is_instance_valid(bar):
		bar.queue_free()
	_entries.erase(id)
