class_name CommandRouter
extends RefCounted

## 命令层入口：合法 UnitOrder → 可移动单位 → UnitNavigator / HarvestController。
## 不读 InputEvent；输入由 GameDirector 解析目标后调用本类。
##
## 右键智能 `issue_smart`：调度 SmartHandlerRegistry（能力 × 目标）。
## 优先级：送回/采集/加入建造 → 集结 → 移动。新能力加 Handler，勿改本类 match。

signal stop_issued(count: int)
signal move_issued(moved: int, failed: int, goal_wc3: Vector2)
signal harvest_issued(count: int)
signal return_issued(count: int)
signal smart_issued(summary: Dictionary)
signal build_issued(count: int) ## F2-3: 建造令下发给 N 个 peasant
signal train_issued(unit_id: String) ## F2-6: 训练令下给建筑
signal research_issued(upgrade_id: String) ## F8: 研究令下给建筑

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
## Callable(unit: Node3D) -> AttackController
var _ensure_attack: Callable = Callable()				## 确保攻击控制器
## Callable(site_wc3: Vector2, building_id: String) -> BuildSite
var _find_build_site: Callable = Callable()				## 查找建筑站点
## Callable(building_node: Node3D) -> BuildSite
var _find_build_site_by_node: Callable = Callable()		## 查找建筑站点

## 配置
func configure(
	path_query: PathQuery,
	crowd_query: UnitCrowdQuery,
	ensure_navigator: Callable,
	ensure_harvest: Callable = Callable(),
	ensure_build: Callable = Callable(),
	session: GameSession = null,
	find_build_site: Callable = Callable(),
	find_build_site_by_node: Callable = Callable(),
	ensure_attack: Callable = Callable()
) -> void:
	_path_query = path_query
	_crowd_query = crowd_query
	_session = session
	_ensure_navigator = ensure_navigator
	_ensure_harvest = ensure_harvest
	_ensure_build = ensure_build
	_ensure_attack = ensure_attack
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


## 本地玩家 owner（无 Session 时 0）。
func local_owner_id() -> int:
	if _session != null:
		return int(_session.local_player)
	return 0


## 过滤本地玩家可控单位（可选 ≠ 可控；系统令勿经此过滤）。
## 已死亡 / 离场（尸体）一律排除，避免对尸体下移动令。
func filter_controllable(selected: Array) -> Array[Node3D]:
	var want := local_owner_id()
	var out: Array[Node3D] = []
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		if not CombatQuery.is_alive_in_world(node):
			continue
		if CombatQuery.is_controllable(node, want):
			out.append(node)
	return out


func is_unit_controllable(node: Node3D) -> bool:
	if node == null or not CombatQuery.is_alive_in_world(node):
		return false
	return CombatQuery.is_controllable(node, local_owner_id())


## 过滤可接受移动/停止的单位（跳过建筑、可训建筑、无效/死亡节点）。
func filter_movers(selected: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		if not CombatQuery.is_alive_in_world(node):
			continue
		# 可训建筑 / 建造中训练建筑 一律不进移动池（避免主城右键被当成移动）
		if BuildingRally.can_set_rally(node):
			continue
		var d: Dictionary = node.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if BuildingVisual.is_building(tid) or BuildingCatalog.is_building(tid):
			continue
		if not CommandButtonCatalog.get_shared().get_trains(tid).is_empty():
			continue
		out.append(node)
	return out


## 过滤可设集结点的建筑。
func filter_rally_buildings(selected: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in selected:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var node := n as Node3D
		if BuildingRally.can_set_rally(node):
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
		_abort_patrol(node)
		_abort_attack(node)
		_clear_hold(node)
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


## 保持原位：停步 + Hold；有武器则 AttackController 仅打射程内。
func issue_hold(selected: Array, source: int = UnitOrder.Source.UNKNOWN) -> int:
	var movers := filter_movers(selected)
	var order := UnitOrder.hold(source)
	var n := 0
	for node in movers:
		_abort_harvest(node)
		_abort_build_leave(node)
		_abort_patrol(node)
		_yield_unit_ai(node)
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
		node.set_meta("hold_position", true)
		if CombatQuery.has_weapon(node) and _ensure_attack.is_valid():
			var ac := _ensure_attack.call(node) as AttackController
			if ac != null:
				ac.start_hold()
		else:
			_abort_attack(node)
		n += 1
	return n


## 顶盾开关。未研究 / 无 Adef → 跳过。不取消移动（原作：顶盾下可走，只减速）。
func issue_defend(selected: Array, active: bool) -> int:
	var stock: PlayerStock = null
	if _session != null:
		stock = _session.local_stock()
	if stock == null or not stock.has_upgrade(DefendController.UPGRADE_ID):
		return 0
	var n := 0
	for node in filter_movers(selected):
		if not DefendController.unit_has_abil(node):
			continue
		var dc := DefendController.of(node)
		if dc == null:
			dc = DefendController.new()
			dc.name = "DefendController"
			node.add_child(dc)
		dc.set_active(active)
		if _ensure_navigator.is_valid():
			var nav: UnitNavigator = _ensure_navigator.call(node) as UnitNavigator
			if nav != null:
				nav.speed_mul = dc.speed_mul()
		n += 1
	return n


func any_defending(units: Array) -> bool:
	for n in units:
		if n is Node3D and DefendController.is_defending(n as Node3D):
			return true
	return false


## 攻击移动：AttackController 索敌 + 走向目标点。
func issue_attack_move(
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
	if movers.is_empty() or goal_center_wc3 == Vector2.INF:
		return result
	if not _ensure_attack.is_valid():
		return issue_move_to_wc3(selected, goal_center_wc3, source)
	var radii := PackedFloat32Array()
	for node in movers:
		_abort_harvest(node)
		_abort_build_leave(node)
		_abort_patrol(node)
		_yield_unit_ai(node)
		_clear_hold(node)
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
		var order := UnitOrder.attack_move(slot, source)
		var q := queue_for(node)
		if q:
			q.set_current(order)
		node.set_meta("attack_move", true)
		var ac := _ensure_attack.call(node) as AttackController
		if ac != null and ac.start_attack_move(slot):
			moved += 1
		else:
			failed += 1
	result["moved"] = moved
	result["failed"] = failed
	return result


## 指定目标攻击：AttackController 追击并出手。
func issue_attack_target(
	selected: Array,
	target: Node3D,
	source: int = UnitOrder.Source.UNKNOWN
) -> int:
	if target == null or not is_instance_valid(target):
		return 0
	if not _ensure_attack.is_valid():
		return 0
	var movers := filter_movers(selected)
	var n_ok := 0
	for node in movers:
		if not CombatQuery.is_valid_attack_target(node, target):
			continue
		if not CombatQuery.has_weapon(node):
			continue
		_abort_harvest(node)
		_abort_build_leave(node)
		_abort_patrol(node)
		_yield_unit_ai(node)
		_clear_hold(node)
		node.set_meta("attack_move", false)
		var order := UnitOrder.attack(target, source)
		var q := queue_for(node)
		if q:
			q.set_current(order)
		var ac := _ensure_attack.call(node) as AttackController
		if ac != null and ac.start_attack(target):
			n_ok += 1
	return n_ok


## 巡逻：当前位置 ↔ goal。
## 群体：走 UnitMoveSlots.assign_goals 给每个 mover 散开落点，避免重叠卡死。
func issue_patrol(
	selected: Array,
	goal_center_wc3: Vector2,
	source: int = UnitOrder.Source.UNKNOWN
) -> Dictionary:
	var movers := filter_movers(selected)
	var result := {"moved": 0, "failed": 0, "goal_wc3": goal_center_wc3, "movers": movers}
	if movers.is_empty() or goal_center_wc3 == Vector2.INF:
		return result
	if not _ensure_navigator.is_valid():
		return result
	# 群体落点散开：与 issue_attack_move / issue_move_to_wc3 一致
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
		_abort_harvest(node)
		_abort_build_leave(node)
		_abort_attack(node)
		_clear_hold(node)
		node.set_meta("attack_move", false)
		var order := UnitOrder.patrol(slot, source)
		var q := queue_for(node)
		if q:
			q.set_current(order)
		var pc := _ensure_patrol(node)
		if pc != null and pc.begin(slot):
			moved += 1
		else:
			failed += 1
			if q:
				q.set_current(UnitOrder.stop(source))
	result["moved"] = moved
	result["failed"] = failed
	return result


func _ensure_patrol(node: Node3D) -> PatrolController:
	if node == null:
		return null
	var existing := node.get_node_or_null("PatrolController") as PatrolController
	if existing != null:
		existing.configure(_ensure_navigator)
		return existing
	var pc := PatrolController.new()
	pc.name = "PatrolController"
	pc.configure(_ensure_navigator)
	node.add_child(pc)
	return pc


func _abort_patrol(node: Node3D) -> void:
	if node == null:
		return
	var pc := node.get_node_or_null("PatrolController") as PatrolController
	if pc != null:
		pc.cancel()


func _abort_attack(node: Node3D) -> void:
	if node == null:
		return
	_yield_unit_ai(node)
	var ac := node.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()


func _yield_unit_ai(node: Node3D) -> void:
	var ai := UnitAI.of(node)
	if ai != null:
		ai.yield_to_player()


func _clear_hold(node: Node3D) -> void:
	if node != null and node.has_meta("hold_position"):
		node.remove_meta("hold_position")


## 智能交互：同一 SmartTarget → Handler 按优先级认领并执行。
## 返回 { ok, kind, harvested, returned, moved, failed, rallied, built, goal_wc3 }。
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
		"rallied": 0,
		"built": 0,
		"goal_wc3": Vector2.INF,
	}
	if target == null:
		return empty
	var movers := filter_movers(selected)
	var rally_bldgs := filter_rally_buildings(selected)
	if movers.is_empty() and rally_bldgs.is_empty():
		return empty
	var out := empty.duplicate()
	out["kind"] = target.kind_name()
	out["goal_wc3"] = target.goal_wc3
	for h in SmartHandlerRegistry.all_sorted():
		if not h.applies_to(target):
			continue
		var claimed: Dictionary = h.claim(movers, rally_bldgs, target, self)
		var cm: Array = claimed.get("movers", [])
		var cr: Array = claimed.get("rally", [])
		if cm.is_empty() and cr.is_empty():
			continue
		_merge_smart_partial(out, h.execute(cm, cr, target, source, self))
	out["ok"] = (
		int(out["harvested"]) > 0
		or int(out["returned"]) > 0
		or int(out["moved"]) > 0
		or int(out["failed"]) > 0
		or int(out["rallied"]) > 0
		or int(out["built"]) > 0
	)
	if out["ok"]:
		smart_issued.emit(out)
	return out


func _merge_smart_partial(out: Dictionary, part: Dictionary) -> void:
	if part.is_empty():
		return
	for k in ["harvested", "returned", "moved", "failed", "rallied", "built"]:
		out[k] = int(out.get(k, 0)) + int(part.get(k, 0))


## 对可训建筑写入集结 meta（按目标 Kind）。返回实际写入成功数。
func issue_rally_subset(buildings: Array[Node3D], target: SmartTarget) -> int:
	if target == null or target.goal_wc3 == Vector2.INF:
		return 0
	var n := 0
	for b in buildings:
		if b == null or not is_instance_valid(b):
			continue
		match target.kind:
			SmartTarget.Kind.GOLD_MINE:
				BuildingRally.set_gold_mine(b, target.node, target.goal_wc3)
			SmartTarget.Kind.TREE:
				BuildingRally.set_tree(b, target.tree_cn, target.goal_wc3)
			_:
				BuildingRally.set_ground(b, target.goal_wc3)
		if BuildingRally.has_rally(b):
			n += 1
	return n


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
		_abort_patrol(node)
		_abort_attack(node)
		_clear_hold(node)
		if node.has_meta("attack_move"):
			node.remove_meta("attack_move")
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
	var rt := GoldMineRuntime.ensure(mine)
	if rt == null or rt.is_depleted():
		return 0
	if not _ensure_harvest.is_valid():
		return 0
	var peasants := filter_peasants(selected)
	var order := UnitOrder.harvest_gold(mine, source)
	var lane_count := maxi(peasants.size(), 1)
	var n := 0
	var lane := 0
	for node in peasants:
		_abort_attack(node)
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
		_abort_attack(node)
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
func split_can_harvest(movers: Array[Node3D]) -> Dictionary:
	var special: Array = []
	var fallback: Array = []
	for node in movers:
		if HarvestController.is_peasant(node):
			special.append(node)
		else:
			fallback.append(node)
	return {"special": special, "fallback": fallback}


## 能向该建筑送回负重 vs 仅移动。
func split_can_return_to(movers: Array[Node3D], building: Node3D) -> Dictionary:
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


func issue_move_subset(
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


## F2-6：建筑训练单位。building 是已建好的 Barracks/Altar/TownHall 等 Node3D。
## 行为：校验竖切 Trains + Requires + 扣金木 + 预占 fused + 挂 TrainQueue + enqueue。
## 完工由 TrainQueue.training_completed 通知（Director 刷单位）；取消退款并由 Director 释人口。
## 队列上限 = TrainQueue.MAX_QUEUE（原作 7）。
func issue_train(building: Node3D, unit_id: String) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if UnitLife.is_under_construction(building):
		return false
	if not is_unit_controllable(building):
		return false
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return false
	var d: Dictionary = building.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	var trains := TechPresence.filter_vertical_trains(
		building_id, CommandButtonCatalog.get_shared().get_trains(building_id)
	)
	if trains.find(uid) < 0:
		return false
	var owner: int = int(d.get("owner", 0))
	var unit_host: Node = building.get_parent()
	var owned := TechPresence.collect_owned_buildings(unit_host, owner)
	var missing := TechPresence.missing_requires(
		owned, UnitRequiresCatalog.get_shared().get_requires(uid)
	)
	if not missing.is_empty():
		return false
	if TechPresence.is_hero_id(uid):
		if (
			TechPresence.count_heroes_with_queues(unit_host, owner)
			>= TechPresence.MAX_HEROES_PER_PLAYER
		):
			return false
	var time_sec: float = BuildingCatalog.get_build_time(uid)
	var gold: int = BuildingCatalog.get_gold_cost(uid)
	var lumber: int = BuildingCatalog.get_lumber_cost(uid)
	var food: int = BuildingCatalog.get_food_used(uid)
	if time_sec <= 0.0 or (gold <= 0 and lumber <= 0):
		return false
	var stock: PlayerStock = null
	if _session != null:
		stock = _session.local_stock()
	if stock != null:
		if food > 0 and not stock.can_afford_food(food):
			return false
		if not stock.try_spend(gold, lumber):
			return false
		if food > 0:
			stock.add_food_used(food)
	var pos: Dictionary = d.get("position", {})
	var site_wc3: Vector2 = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var queue: TrainQueue = building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		building.add_child(queue)
	if queue.is_full():
		_refund_train_spend(stock, gold, lumber, food)
		return false
	if not queue.enqueue(uid, time_sec, gold, lumber, food, site_wc3, owner):
		_refund_train_spend(stock, gold, lumber, food)
		return false
	train_issued.emit(uid)
	return true


## F8：建筑研究科技。无人口；完工不刷单位，由 Director 写入 PlayerStock.grant_upgrade。
func issue_research(building: Node3D, upgrade_id: String) -> bool:
	if building == null or not is_instance_valid(building):
		return false
	if UnitLife.is_under_construction(building):
		return false
	if not is_unit_controllable(building):
		return false
	var uid := upgrade_id.strip_edges()
	if uid.is_empty() or not TechPresence.is_upgrade_id(uid):
		return false
	var d: Dictionary = building.get_meta("unit_data", {})
	var building_id := str(d.get("typeId", "")).strip_edges()
	var researches := TechPresence.filter_vertical_researches(
		building_id, CommandButtonCatalog.get_shared().get_researches(building_id)
	)
	if researches.find(uid) < 0:
		return false
	var owner: int = int(d.get("owner", 0))
	var unit_host: Node = building.get_parent()
	var stock: PlayerStock = null
	if _session != null:
		stock = _session.local_stock()
	if stock != null and stock.has_upgrade(uid):
		return false
	if TechPresence.is_upgrade_queued(unit_host, owner, uid):
		return false
	var time_sec := TechPresence.upgrade_time(uid)
	var gold := TechPresence.upgrade_gold(uid)
	var lumber := TechPresence.upgrade_lumber(uid)
	if time_sec <= 0.0 or (gold <= 0 and lumber <= 0):
		return false
	if stock != null:
		if not stock.try_spend(gold, lumber):
			return false
	var pos: Dictionary = d.get("position", {})
	var site_wc3: Vector2 = Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
	var queue: TrainQueue = building.get_node_or_null("TrainQueue") as TrainQueue
	if queue == null:
		queue = TrainQueue.new()
		queue.name = "TrainQueue"
		building.add_child(queue)
	if queue.is_full():
		_refund_train_spend(stock, gold, lumber, 0)
		return false
	if not queue.enqueue(uid, time_sec, gold, lumber, 0, site_wc3, owner):
		_refund_train_spend(stock, gold, lumber, 0)
		return false
	research_issued.emit(uid)
	return true


func _refund_train_spend(stock: PlayerStock, gold: int, lumber: int, food: int) -> void:
	if stock == null:
		return
	if gold > 0:
		stock.add_gold(gold)
	if lumber > 0:
		stock.add_lumber(lumber)
	if food > 0:
		stock.add_food_used(-food)


## F2-3：选中农民对工地 wc3_xy 发起 BUILD 令。
## 原作：框选多农民下建造 → 仅 1 人响应并扣首单造价；半成品出现后，其余需右键工地才帮工。
## 右键半成品 / 点到已有活跃工地 → issue_join_build（可多人）。
## 人族：建造中再下新建造令 → 可打断换工地。
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
	# 已有活跃工地 → 选中农民全体 join（等同右键半成品帮工）
	var existing: BuildSite = _find_site_at(site_wc3, building_id)
	if existing != null and existing.is_active():
		return issue_join_build_site(peasants, existing, building_id, site_wc3, source, 99, true)
	var primary: Node3D = null
	var bc: BuildController = null
	for node in peasants:
		if not (node is Node3D):
			continue
		if not HarvestController.is_peasant(node):
			continue
		var candidate: BuildController = _ensure_build.call(node) as BuildController
		if candidate == null:
			continue
		if candidate.is_active():
			if not candidate.can_reassign_build():
				continue
			candidate.leave_or_abort()
			if candidate.is_active():
				continue
		primary = node as Node3D
		bc = candidate
		break
	if bc == null or primary == null:
		return 0
	if _ensure_navigator.is_valid():
		_ensure_navigator.call(primary)
	var order: BuildOrder = BuildOrder.create(building_id, site_wc3, primary)
	if not bc.start_build(order):
		return 0
	# 多选其余人不动；帮工只走右键 / issue_join_build
	build_issued.emit(1)
	return 1


## 对未完工建筑 join：派空闲农民；max_count 限制人数（1=点选增派，99=多选全派）。
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
	return issue_join_build_site(selected, site, bid, site_wc3, source, 99, true)


func issue_join_build_site(
	peasants: Array,
	site: BuildSite,
	building_id: String,
	site_wc3: Vector2,
	_source: int = UnitOrder.Source.PANEL,
	max_count: int = 1,
	do_emit: bool = true
) -> int:
	if site == null or not site.is_active() or not _ensure_build.is_valid():
		return 0
	var issued := 0
	var limit := maxi(max_count, 1)
	for node in peasants:
		if issued >= limit:
			break
		if not (node is Node3D):
			continue
		if not HarvestController.is_peasant(node):
			continue
		var bc: BuildController = _ensure_build.call(node) as BuildController
		if bc == null:
			continue
		if bc.is_active():
			if not bc.can_reassign_build():
				continue
			if site.active_builders().has(node):
				continue
			if bc.current_site() == site:
				continue
			bc.leave_or_abort()
			if bc.is_active():
				continue
		elif site.active_builders().has(node):
			continue
		if _ensure_navigator.is_valid():
			_ensure_navigator.call(node)
		if bc.start_join(site, building_id, site_wc3):
			issued += 1
	if issued > 0 and do_emit:
		build_issued.emit(issued)
	return issued


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
