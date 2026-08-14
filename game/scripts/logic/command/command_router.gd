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
signal train_issued(unit_id: String) ## F2-6: 训练令下给建筑

const META_ORDER_QUEUE := "order_queue"

var _path_query: PathQuery = null
var _crowd_query: UnitCrowdQuery = null
var _session: GameSession = null
## Callable(unit: Node3D) -> UnitNavigator
var _ensure_navigator: Callable = Callable()
## Callable(unit: Node3D) -> HarvestController
var _ensure_harvest: Callable = Callable()
## Callable(unit: Node3D) -> BuildController（F2-3）
var _ensure_build: Callable = Callable()
## Callable(site_wc3: Vector2, building_id: String) -> BuildSite
var _find_build_site: Callable = Callable()
## Callable(building_node: Node3D) -> BuildSite
var _find_build_site_by_node: Callable = Callable()


func configure(
	path_query: PathQuery,
	crowd_query: UnitCrowdQuery,
	ensure_navigator: Callable,
	ensure_harvest: Callable = Callable(),
	ensure_build: Callable = Callable(),
	session: GameSession = null,
	find_build_site: Callable = Callable(),
	find_build_site_by_node: Callable = Callable()
) -> void:
	_path_query = path_query
	_crowd_query = crowd_query
	_session = session
	_ensure_navigator = ensure_navigator
	_ensure_harvest = ensure_harvest
	_ensure_build = ensure_build
	_find_build_site = find_build_site
	_find_build_site_by_node = find_build_site_by_node


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
		_abort_build_leave(node)
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
		SmartTarget.Kind.BUILD_SITE:
			var joined := issue_join_build(movers, target.node, source)
			out["built"] = joined
			if joined <= 0:
				var mr5 := _issue_move_subset(movers, target.goal_wc3, source)
				out["moved"] = int(mr5.get("moved", 0))
				out["failed"] = int(mr5.get("failed", 0))
			out["ok"] = joined > 0 or out["moved"] > 0 or out["failed"] > 0
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
		_abort_build_leave(node)
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


func _abort_build_leave(node: Node3D) -> void:
	if node == null:
		return
	var bc := node.get_node_or_null("BuildController") as BuildController
	if bc != null and bc.is_active():
		bc.leave_or_abort()


## F2-6：建筑训练单位。building 是已建好的 Barracks/Altar 等 Node3D。
## 行为：扣资源 + 挂 TrainQueue 子节点 + start。
## 完工由 TrainQueue.training_completed signal 通知（Director 订阅刷单位）。
## F2-6 简化：1 队列；fused 人口校验留 F3-F4。
func issue_train(building: Node3D, unit_id: String) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	# 资源 / 时间从 UnitBalance 读
	var time_sec: float = BuildingCatalog.get_build_time(unit_id)
	var gold: int = BuildingCatalog.get_gold_cost(unit_id)
	var lumber: int = BuildingCatalog.get_lumber_cost(unit_id)
	if time_sec <= 0.0 or (gold <= 0 and lumber <= 0):
		# 非可训单位（或中立单位无时间）
		return false
	# 资源扣减（需 router 持有 session）
	if _session != null:
		var stock: PlayerStock = _session.local_stock()
		if stock == null or not stock.try_spend(gold, lumber):
			return false
	else:
		# 兜底：未配 session 时不扣（验收集成时 F2-7 接 Director 配 session）
		pass
	# site/owner 从 building meta 读
	var d: Dictionary = building.get_meta("unit_data", {})
	var pos: Dictionary = d.get("position", {})
	var site_wc3: Vector2 = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var owner: int = int(d.get("owner", 0))
	# TrainQueue：复用已有（无则创建）；F2-6 简化：1 队列 = 已有则 noop
	var queue: TrainQueue = building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		building.add_child(queue)
	if queue.is_training():
		# 已训中：尝试退款刚扣的（WC3：训练进行中不能叠加）
		if _session != null:
			var s: PlayerStock = _session.local_stock()
			if s != null:
				s.add_gold(gold)
				s.add_lumber(lumber)
		return false
	if not queue.start(unit_id, time_sec, gold, lumber, site_wc3, owner):
		return false
	train_issued.emit(unit_id)
	return true


## F2-3：选中农民对工地 wc3_xy 发起 BUILD 令。
## peasant 已在 CommandRouter.filter_peasants 过滤（仅 hpea）。
## 契约：多选时只派 **1** 个农民开工（首单扣费）；其余不跟。
## 再次对同一工地下令 / 右键半成品 → issue_join_build。
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
	# 若该坐标已有活跃工地 → 改为 join（每次只再派 1 人）
	var existing: BuildSite = _find_site_at(site_wc3, building_id)
	if existing != null and existing.is_active():
		return issue_join_build_site(peasants, existing, building_id, site_wc3, source)
	var primary: Node3D = null
	var bc: BuildController = null
	for node in peasants:
		if not (node is Node3D):
			continue
		var candidate: BuildController = _ensure_build.call(node) as BuildController
		if candidate == null or candidate.is_active():
			continue
		primary = node as Node3D
		bc = candidate
		break
	if bc == null or primary == null:
		return 0
	var order: BuildOrder = BuildOrder.create(building_id, site_wc3, primary)
	if not bc.start_build(order):
		return 0
	build_issued.emit(1)
	return 1


## 对未完工建筑 join：选中农民里每次只派 1 个空闲的。
func issue_join_build(
	selected: Array,
	building_node: Node3D,
	source: int = UnitOrder.Source.SMART_RMB
) -> int:
	if building_node == null or not is_instance_valid(building_node):
		return 0
	if not UnitLife.is_under_construction(building_node):
		return 0
	var d: Dictionary = building_node.get_meta("unit_data", {})
	var bid := str(d.get("typeId", ""))
	var pos: Dictionary = d.get("position", {})
	var site_wc3 := Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var site: BuildSite = _find_site_for_building_node(building_node)
	if site == null or not site.is_active():
		return 0
	return issue_join_build_site(selected, site, bid, site_wc3, source)


func issue_join_build_site(
	peasants: Array,
	site: BuildSite,
	building_id: String,
	site_wc3: Vector2,
	source: int = UnitOrder.Source.PANEL
) -> int:
	if site == null or not site.is_active() or not _ensure_build.is_valid():
		return 0
	for node in peasants:
		if not (node is Node3D):
			continue
		if not HarvestController.is_peasant(node):
			continue
		var bc: BuildController = _ensure_build.call(node) as BuildController
		if bc == null or bc.is_active():
			continue
		# 已在此工地
		if site.active_builders().has(node):
			continue
		if bc.start_join(site, building_id, site_wc3):
			build_issued.emit(1)
			return 1
	return 0


func _find_site_at(site_wc3: Vector2, building_id: String) -> BuildSite:
	if _find_build_site.is_valid():
		return _find_build_site.call(site_wc3, building_id) as BuildSite
	return null


func _find_site_for_building_node(building_node: Node3D) -> BuildSite:
	if _find_build_site_by_node.is_valid():
		return _find_build_site_by_node.call(building_node) as BuildSite
	return null


## 多选离开工地（建筑保留；MOVING 首单未开工则退款取消）。
func cancel_build(units: Array) -> Dictionary:
	var cancelled := 0
	for u in units:
		var node := u as Node3D
		if node == null or not is_instance_valid(node):
			continue
		var bc := node.get_node_or_null("BuildController") as BuildController
		if bc != null and bc.is_active():
			bc.leave_or_abort()
			cancelled += 1
	return {"cancelled": cancelled}
