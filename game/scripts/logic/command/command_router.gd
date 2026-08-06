class_name CommandRouter
extends RefCounted

## 命令层入口：合法 UnitOrder → 可移动单位 → UnitNavigator。
## 不读 InputEvent；输入由 GameDirector 解析后调用本类。

signal stop_issued(count: int)
signal move_issued(moved: int, failed: int, goal_wc3: Vector2)

const META_ORDER_QUEUE := "order_queue"

var _path_query: PathQuery = null
var _crowd_query: UnitCrowdQuery = null
## Callable(unit: Node3D) -> UnitNavigator
var _ensure_navigator: Callable = Callable()


func configure(
	path_query: PathQuery,
	crowd_query: UnitCrowdQuery,
	ensure_navigator: Callable
) -> void:
	_path_query = path_query
	_crowd_query = crowd_query
	_ensure_navigator = ensure_navigator


func queue_for(unit: Node) -> OrderQueue:
	if unit == null:
		return null
	var q: Variant = unit.get_meta(META_ORDER_QUEUE, null)
	if q is OrderQueue:
		return q as OrderQueue
	var nq := OrderQueue.new()
	unit.set_meta(META_ORDER_QUEUE, nq)
	return nq


## 过滤可接受移动/停止的单位（跳过建筑、无效节点）。
func filter_movers(selected: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		var d: Dictionary = node.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if BuildingVisual.is_building(tid):
			continue
		out.append(node)
	return out


func any_moving(units: Array) -> bool:
	for n in units:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var nav := (n as Node3D).get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null and nav.is_moving():
			return true
	return false


func issue_stop(selected: Array, source: int = UnitOrder.Source.UNKNOWN) -> int:
	var movers := filter_movers(selected)
	var order := UnitOrder.stop(source)
	var n_stop := 0
	for node in movers:
		var q := queue_for(node)
		if q:
			q.set_current(order)
		var nav: UnitNavigator = null
		if _ensure_navigator.is_valid():
			nav = _ensure_navigator.call(node) as UnitNavigator
		else:
			nav = node.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
			n_stop += 1
	if n_stop > 0:
		stop_issued.emit(n_stop)
	return n_stop


## 群体散开落点后各自 A*。返回 { moved, failed, goal_wc3, movers }。
func issue_move_to_wc3(
	selected: Array,
	goal_center_wc3: Vector2,
	source: int = UnitOrder.Source.UNKNOWN
) -> Dictionary:
	var movers := filter_movers(selected)
	var result := {
		"moved": 0,
		"failed": 0,
		"goal_wc3": goal_center_wc3,
		"movers": movers,
	}
	if movers.is_empty() or _path_query == null:
		return result
	if not _ensure_navigator.is_valid():
		return result
	var radii := PackedFloat32Array()
	for node in movers:
		var r := 16.0
		if _crowd_query != null:
			r = _crowd_query.radius_for_unit(node)
		radii.append(r)
	var goals: PackedVector2Array = UnitMoveSlots.assign_goals(
		movers, radii, goal_center_wc3, _path_query
	)
	var moved := 0
	var failed := 0
	for i in range(movers.size()):
		var node: Node3D = movers[i]
		var slot: Vector2 = goals[i] if i < goals.size() else goal_center_wc3
		var order := UnitOrder.move(slot, source)
		var q := queue_for(node)
		if q:
			q.set_current(order)
		var nav := _ensure_navigator.call(node) as UnitNavigator
		if nav == null:
			failed += 1
			continue
		if nav.go_to_wc3(slot):
			moved += 1
		else:
			failed += 1
			if q:
				q.set_current(UnitOrder.stop(source))
	result["moved"] = moved
	result["failed"] = failed
	if moved > 0 or failed > 0:
		move_issued.emit(moved, failed, goal_center_wc3)
	return result
