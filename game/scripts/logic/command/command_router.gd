class_name CommandRouter
extends RefCounted

## 命令层入口：合法 UnitOrder → 可移动单位 → UnitNavigator / HarvestController。
## 不读 InputEvent；输入由 GameDirector 解析后调用本类。

signal stop_issued(count: int)
signal move_issued(moved: int, failed: int, goal_wc3: Vector2)
signal harvest_issued(count: int)
signal return_issued(count: int)

const META_ORDER_QUEUE := "order_queue"

var _path_query: PathQuery = null
var _crowd_query: UnitCrowdQuery = null
## Callable(unit: Node3D) -> UnitNavigator
var _ensure_navigator: Callable = Callable()
## Callable(unit: Node3D) -> HarvestController
var _ensure_harvest: Callable = Callable()


func configure(
	path_query: PathQuery,
	crowd_query: UnitCrowdQuery,
	ensure_navigator: Callable,
	ensure_harvest: Callable = Callable()
) -> void:
	_path_query = path_query
	_crowd_query = crowd_query
	_ensure_navigator = ensure_navigator
	_ensure_harvest = ensure_harvest


func queue_for(unit: Node) -> OrderQueue:
	if unit == null:
		return null
	# Godot：get_meta(name, null) 的 null 会被当成「未提供默认值」而报错。
	if unit.has_meta(META_ORDER_QUEUE):
		var q: Variant = unit.get_meta(META_ORDER_QUEUE)
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


func filter_peasants(selected: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in filter_movers(selected):
		if HarvestController.is_peasant(n):
			out.append(n)
	return out


func any_moving(units: Array) -> bool:
	for n in units:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var nav := (n as Node3D).get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null and nav.is_moving():
			return true
	return false


func any_harvesting(units: Array) -> bool:
	for n in units:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var hc := (n as Node3D).get_node_or_null("HarvestController") as HarvestController
		if hc != null and hc.is_active():
			return true
	return false


func any_carrying(units: Array) -> bool:
	for n in units:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var hc := (n as Node3D).get_node_or_null("HarvestController") as HarvestController
		if hc != null and hc.is_carrying():
			return true
	return false


func any_returning(units: Array) -> bool:
	for n in units:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var hc := (n as Node3D).get_node_or_null("HarvestController") as HarvestController
		if hc == null or not hc.is_active():
			continue
		if hc.get_state() == HarvestController.State.MOVE_TO_DROPOFF:
			return true
	return false


func issue_stop(selected: Array, source: int = UnitOrder.Source.UNKNOWN) -> int:
	var movers := filter_movers(selected)
	var order := UnitOrder.stop(source)
	var n_stop := 0
	for node in movers:
		_abort_harvest(node)
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
		_abort_harvest(node)
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


## 选中农民对金矿开始采金循环。
func issue_harvest_gold(
	selected: Array,
	mine: Node3D,
	source: int = UnitOrder.Source.UNKNOWN
) -> int:
	if mine == null or not is_instance_valid(mine):
		return 0
	if not _ensure_harvest.is_valid():
		return 0
	var peasants := filter_peasants(selected)
	var order := UnitOrder.harvest_gold(mine, source)
	var lane_count := maxi(peasants.size(), 1)
	var n := 0
	var lane := 0
	for node in peasants:
		var q := queue_for(node)
		if q:
			q.set_current(order)
		var hc := _ensure_harvest.call(node) as HarvestController
		if hc == null:
			continue
		# 打断当前移动再采
		var nav := node.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
		# 多选同时下令：按车道弧形散开在矿口
		if hc.start_harvest_gold(mine, lane, lane_count):
			n += 1
		lane += 1
	if n > 0:
		harvest_issued.emit(n)
	return n


## 负资源农民送回最近可接收建筑。
func issue_return_goods(
	selected: Array,
	source: int = UnitOrder.Source.UNKNOWN
) -> int:
	if not _ensure_harvest.is_valid():
		return 0
	var peasants := filter_peasants(selected)
	var order := UnitOrder.return_goods(source)
	var n := 0
	for node in peasants:
		var hc_existing := node.get_node_or_null("HarvestController") as HarvestController
		if hc_existing == null or not hc_existing.is_carrying():
			continue
		var q := queue_for(node)
		if q:
			q.set_current(order)
		var hc := _ensure_harvest.call(node) as HarvestController
		if hc == null:
			continue
		var nav := node.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
		if hc.start_return_goods():
			n += 1
	if n > 0:
		return_issued.emit(n)
	return n


func _abort_harvest(node: Node3D) -> void:
	if node == null:
		return
	var hc := node.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
