class_name PathDebugModule
extends Node

## 选中单位寻路折线调试绘制。表现节点 PathDebugDraw 由本模块持有。

var _map_root: Node
var _heightfield: Wc3Heightfield
var _unit_selector: Node
var _enabled: bool = true
var _draw: PathDebugDraw = null


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as Node
	_heightfield = deps.get("heightfield") as Wc3Heightfield
	_unit_selector = deps.get("unit_selector") as Node
	if deps.has("enabled"):
		_enabled = bool(deps["enabled"])


func shutdown() -> void:
	if _draw != null and is_instance_valid(_draw):
		_draw.queue_free()
	_draw = null
	_map_root = null
	_heightfield = null
	_unit_selector = null


func _exit_tree() -> void:
	shutdown()


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if _draw != null and is_instance_valid(_draw):
		_draw.set_enabled(_enabled)


func is_enabled() -> bool:
	return _enabled


func ensure_draw() -> void:
	if _map_root == null:
		return
	if _draw != null and is_instance_valid(_draw):
		_draw.setup(_heightfield)
		_draw.set_enabled(_enabled)
		return
	_draw = PathDebugDraw.new()
	_draw.name = "PathDebugDraw"
	_map_root.add_child(_draw)
	_draw.setup(_heightfield)
	_draw.set_enabled(_enabled)


func tick(_delta: float = 0.0) -> void:
	if not _enabled:
		return
	if _draw == null or not is_instance_valid(_draw):
		return
	if _unit_selector == null or not _unit_selector.has_method("get_selected"):
		return
	if not _draw.has_method("redraw"):
		return
	var paths: Array = []
	var selected: Array = _unit_selector.call("get_selected")
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var nav := (n as Node3D).get_node_or_null("UnitNavigator")
		if nav == null or not nav.has_method("get_remaining_waypoints_wc3"):
			continue
		if not bool(nav.call("is_moving")):
			continue
		var pts: Array = nav.call("get_remaining_waypoints_wc3")
		if pts.is_empty():
			continue
		var inv := 1.0 / Wc3Coords.WORLD_SCALE
		var body := n as Node3D
		var cur := Vector2(body.global_position.x * inv, -body.global_position.z * inv)
		var full: Array = [cur]
		for p in pts:
			full.append(p)
		paths.append({"points": full})
	_draw.call("redraw", paths)
