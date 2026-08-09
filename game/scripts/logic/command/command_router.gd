class_name CommandRouter
extends RefCounted

## 命令层入口：合法 UnitOrder → 可移动单位 → UnitNavigator / HarvestController。
## 不读 InputEvent；输入由 GameDirector 解析目标后调用本类。
## 右键智能：issue_smart(SmartTarget) — 全体下发，按单位能力匹配动作（不能则降级 Move）。

signal stop_issued(count: int)
signal move_issued(moved: int, failed: int, goal_wc3: Vector2)
signal harvest_issued(count: int)
signal return_issued(count: int)
signal smart_issued(summary: Dictionary)
signal build_issued(count: int) ## F2-3: 建造令下发给 N 个 peasant

const META_ORDER_QUEUE := "order_queue"

var _path_query: PathQuery = null
var _crowd_query: UnitCrowdQuery = null
## Callable(unit: Node3D) -> UnitNavigator
var _ensure_navigator: Callable = Callable()
## Callable(unit: Node3D) -> HarvestController
var _ensure_harvest: Callable = Callable()
## Callable(unit: Node3D) -> BuildController（F2-3）
var _ensure_build: Callable = Callable()


func configure(
	path_query: PathQuery,
	crowd_query: UnitCrowdQuery,
	ensure_navigator: Callable,
	ensure_harvest: Callable = Callable(),
	ensure_build: Callable = Callable()
) -> void:
	_path_query = path_query
	_crowd_query = crowd_query
	_ensure_navigator = ensure_navigator
	_ensure_harvest = ensure_harvest
	_ensure_build = ensure_build


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


## 智能交互：同一 SmartTarget 广播给框选单位，各自按能力匹配具体 Order。
## 返回 { ok, kind, harvested, returned, moved, failed, goal_wc3 }。
func issue_smart(
	selected: Array,
	target: SmartTarget,
	source: int = UnitOrder.Source.UNKNOWN
) -> Dictionary:
	var empty := {
		"ok": false,
		"kind": "",
		"harvested": 0,
		"returned": 0,
		"moved": 0,
		"failed": 0,
		"goal_wc3": Vector2.INF,
	}
	if target == null:
		return empty
	var movers := filter_movers(selected)
	if movers.is_empty():
		return empty
	var out := empty.duplicate()
	out["kind"] = target.kind_name()
	out["goal_wc3"] = target.goal_wc3
	match target.kind:
		SmartTarget.Kind.GROUND:
			var mr := _issue_move_subset(movers, target.goal_wc3, source)
			out["moved"] = int(mr.get("moved", 0))
			out["failed"] = int(mr.get("failed", 0))
			out["ok"] = out["moved"] > 0 or out["failed"] > 0
		SmartTarget.Kind.GOLD_MINE:
			var parts := _split_can_harvest(movers)
			out["harvested"] = issue_harvest_gold(parts["special"], target.node, source)
			var mr2 := _issue_move_subset(parts["fallback"], target.goal_wc3, source)
			out["moved"] = int(mr2.get("moved", 0))
			out["failed"] = int(mr2.get("failed", 0))
			out["ok"] = out["harvested"] > 0 or out["moved"] > 0 or out["failed"] > 0
		SmartTarget.Kind.TREE:
			var parts_t := _split_can_harvest(movers)
			out["harvested"] = issue_harvest_lumber(parts_t["special"], target.tree_cn, source)
			var mr3 := _issue_move_subset(parts_t["fallback"], target.goal_wc3, source)
			out["moved"] = int(mr3.get("moved", 0))
			out["failed"] = int(mr3.get("failed", 0))
			out["ok"] = out["harvested"] > 0 or out["moved"] > 0 or out["failed"] > 0
		SmartTarget.Kind.DROPOFF:
			var parts_d := _split_can_return_to(movers, target.node)
			out["returned"] = issue_return_goods(parts_d["special"], source, target.node)
			var mr4 := _issue_move_subset(parts_d["fallback"], target.goal_wc3, source)
			out["moved"] = int(mr4.get("moved", 0))
			out["failed"] = int(mr4.get("failed", 0))
			out["ok"] = out["returned"] > 0 or out["moved"] > 0 or out["failed"] > 0
		_:
			return empty
	if out["ok"]:
		smart_issued.emit(out)
	return out


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


## 选中农民对树木开始伐木循环（可多人同砍；按车道散开，满则改砍附近树）。
func issue_harvest_lumber(
	selected: Array,
	creation_number: int,
	source: int = UnitOrder.Source.UNKNOWN
) -> int:
	if creation_number < 0 or not _ensure_harvest.is_valid():
		return 0
	var peasants := filter_peasants(selected)
	var order := UnitOrder.harvest_lumber(creation_number, source)
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
		var nav := node.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
		hc.set_lumber_lanes(lane, lane_count)
		if hc.start_harvest_lumber(creation_number):
			n += 1
		lane += 1
	if n > 0:
		harvest_issued.emit(n)
	return n


## 负资源农民送回；preferred_dropoff 为右键点中的主城/伐木场（可选）。
func issue_return_goods(
	selected: Array,
	source: int = UnitOrder.Source.UNKNOWN,
	preferred_dropoff: Node3D = null
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
		var mask := _carry_mask_of(hc_existing)
		if preferred_dropoff != null and is_instance_valid(preferred_dropoff):
			if not ReceiveResources.can_receive(preferred_dropoff, mask):
				continue
			if not _same_owner(node, preferred_dropoff):
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
		if hc.start_return_goods(preferred_dropoff):
			n += 1
	if n > 0:
		return_issued.emit(n)
	return n


func _carry_mask_of(hc: HarvestController) -> int:
	if hc == null:
		return int(ReceiveResources.Kind.NONE)
	if hc.carry_gold() > 0:
		return int(ReceiveResources.Kind.GOLD)
	if hc.carry_lumber() > 0:
		return int(ReceiveResources.Kind.LUMBER)
	return int(ReceiveResources.Kind.NONE)


func _same_owner(a: Node, b: Node) -> bool:
	if a == null or b == null:
		return false
	var da: Dictionary = a.get_meta("unit_data", {})
	var db: Dictionary = b.get_meta("unit_data", {})
	return int(da.get("owner", -1)) == int(db.get("owner", -2))


## 能采（农民）vs 仅移动。远期可换成 UnitCapability。
func _split_can_harvest(movers: Array[Node3D]) -> Dictionary:
	var special: Array = []
	var fallback: Array = []
	for node in movers:
		if HarvestController.is_peasant(node):
			special.append(node)
		else:
			fallback.append(node)
	return {"special": special, "fallback": fallback}


## 能向该建筑送回负重 vs 仅移动。
func _split_can_return_to(movers: Array[Node3D], building: Node3D) -> Dictionary:
	var special: Array = []
	var fallback: Array = []
	for node in movers:
		if not HarvestController.is_peasant(node):
			fallback.append(node)
			continue
		var hc := node.get_node_or_null("HarvestController") as HarvestController
		if hc == null or not hc.is_carrying():
			fallback.append(node)
			continue
		var mask := _carry_mask_of(hc)
		if (
			building != null
			and is_instance_valid(building)
			and ReceiveResources.can_receive(building, mask)
			and _same_owner(node, building)
		):
			special.append(node)
		else:
			fallback.append(node)
	return {"special": special, "fallback": fallback}


func _issue_move_subset(
	units: Array,
	goal_wc3: Vector2,
	source: int
) -> Dictionary:
	if units.is_empty() or goal_wc3 == Vector2.INF:
		return {"moved": 0, "failed": 0, "goal_wc3": goal_wc3}
	return issue_move_to_wc3(units, goal_wc3, source)


func _abort_harvest(node: Node3D) -> void:
	if node == null:
		return
	var hc := node.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()


## F2-3：选中农民对工地 wc3_xy 发起 BUILD 令。
## peasant 已在 CommandRouter.filter_peasants 过滤（仅 hpea）。
## 返回实际开工的 peasant 数。
func issue_build(
	peasants: Array,
	building_id: String,
	site_wc3: Vector2,
	source: int = UnitOrder.Source.PANEL
) -> int:
	if not _ensure_build.is_valid():
		return 0
	if not BuildingCatalog.is_building(building_id):
		return 0
	var n: int = 0
	for node in peasants:
		var bc: BuildController = _ensure_build.call(node) as BuildController
		if bc == null:
			continue
		var order: UnitOrder = UnitOrder.build(building_id, site_wc3, source)
		order.target_id = node.get_instance_id() if node != null else 0
		order.builder = node
		if bc.start_build(order):
			n += 1
	if n > 0:
		build_issued.emit(n)
	return n


## F2-3：取消指定 peasant 的当前建造（一般用于右键取消或死亡）。
## 当前简化：Director 直接持有 peasant 引用时可调 peasant 节点的 BuildController.cancel()。
## 保留本入口为后续中央化取消（多选取消）做准备。
