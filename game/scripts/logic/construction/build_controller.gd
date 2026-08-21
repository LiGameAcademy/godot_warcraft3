class_name BuildController
extends Node

## 农民建造控制器（人族）：
## IDLE → MOVING（走向 footprint 外侧）→ BUILDING（工地施工）→ IDLE
## 离开工地 → 从 BuildSite 移除（0 人则暂停）；不自动取消整单。

signal state_changed(state: int)
signal build_started(order: BuildOrder)
signal build_cancelled(order: BuildOrder)
signal build_completed(order: BuildOrder, site_wc3: Vector2, owner: int)
signal build_joined(site: BuildSite, builder: Node3D)


const STATE_IDLE := 0
const STATE_MOVING := 1
const STATE_BUILDING := 2
const STATE_CANCELLED := 3

const CANCEL_REFUND_RATIO := 0.75
## 站在 footprint 外沿外再偏半格（贴着施工，勿站太远）
const OUTSIDE_MARGIN_CELLS := 0.45


var _order: BuildOrder = null
var _state: int = STATE_IDLE
var _session: GameSession = null
var _pathing: Wc3PathingMap = null
var _cell_reservation: PathCellReservation = null
var _peasant: Node3D = null
var _site: BuildSite = null
## join 模式：不扣首单费，只加入已有工地
var _joining_site: BuildSite = null
## 协助：只走向工地，到位后等半成品（不自己开坑）
var _assist_only: bool = false
var _approach_wc3: Vector2 = Vector2.INF
var _profile: ConstructionProfile = null
var _strategy: IConstructionStrategy = null
var _profile_catalog: ConstructionProfileCatalog = null
var _last_cancelled: BuildOrder = null
## Director 注入：Callable(building_id, site_wc3) -> BuildSite
var find_site_at: Callable = Callable()


func _ready() -> void:
	_peasant = get_parent() as Node3D
	_profile_catalog = ConstructionProfileCatalog.new()
	_profile = _profile_catalog.for_race(_peasant_race())
	_strategy = HumanConstructionStrategy.new()
	set_process(false)


func _peasant_race() -> String:
	if _peasant == null:
		return "human"
	var d: Dictionary = _peasant.get_meta("unit_data", {})
	return str(d.get("race", "human")).to_lower()


func configure(session: GameSession, pathing: Wc3PathingMap, cell_reservation: PathCellReservation = null) -> void:
	_session = session
	_pathing = pathing
	_cell_reservation = cell_reservation


func is_active() -> bool:
	return _state == STATE_MOVING or _state == STATE_BUILDING


## 人族：建造中可接新建造令打断换工地；兽/灵占坑不可。
func can_reassign_build() -> bool:
	if _profile == null:
		return true
	return (
		_profile.profile_id == "human"
		or _profile.builder_slot_policy == ConstructionProfile.SlotPolicy.MANY_VISIBLE
	)


func is_building() -> bool:
	return _state == STATE_BUILDING


func current_order() -> BuildOrder:
	return _order


func current_site() -> BuildSite:
	return _site if _site != null else _joining_site


## 首单：扣费 + 走向外侧。BuildSite 等到位后创建（原作：半成品出现后才可 Powerbuild join）。
func start_build(order: BuildOrder) -> bool:
	if _state != STATE_IDLE:
		return false
	if order == null or order.builder == null:
		return false
	if not _validate_and_spend(order):
		return false
	_joining_site = null
	_order = order
	_order.state = BuildOrder.STATE_MOVING
	_state = STATE_MOVING
	_assist_only = false
	_abort_other_orders()
	_approach_wc3 = _compute_approach(_order.site_wc3, _order.building_id)
	_go_to_approach()
	set_process(true)
	state_changed.emit(_state)
	return true


## 协助接近（工地尚未创建）：走到外沿等半成品再 join。
## 不扣费；不自己创建 BuildSite。
## 原作多选建造不会自动走这条；保留给特殊指令 / 调试，正常帮工走 start_join。
func start_assist_approach(building_id: String, site_wc3: Vector2) -> bool:
	if _state != STATE_IDLE:
		return false
	if _profile != null and not _profile.supports_multi_builder():
		return false
	if building_id.is_empty():
		return false
	_joining_site = null
	_site = null
	_assist_only = true
	_order = BuildOrder.create(building_id, site_wc3, _peasant)
	_order.build_time_sec = BuildingCatalog.get_build_time(building_id)
	_order.state = BuildOrder.STATE_MOVING
	_state = STATE_MOVING
	_abort_other_orders()
	_approach_wc3 = _compute_approach(site_wc3, building_id)
	_go_to_approach()
	set_process(true)
	state_changed.emit(_state)
	return true


## 加入已有工地（再次下达建造 / 右键半成品）：不扣首单费。
func start_join(site: BuildSite, building_id: String, site_wc3: Vector2) -> bool:
	if _state != STATE_IDLE or site == null or not site.is_active():
		return false
	if _profile != null and not _profile.supports_multi_builder():
		return false
	_joining_site = site
	_assist_only = false
	_order = BuildOrder.create(building_id, site_wc3, _peasant)
	_order.build_time_sec = site.total()
	_order.state = BuildOrder.STATE_MOVING
	_state = STATE_MOVING
	_abort_other_orders()
	_approach_wc3 = _compute_approach(site_wc3, building_id)
	_go_to_approach()
	set_process(true)
	state_changed.emit(_state)
	return true


## 工人被调走：离开工地（不拆建筑）；若是 MOVING 中的首单未开工则退款取消。
func leave_or_abort() -> void:
	if _state == STATE_BUILDING:
		_leave_site_keep_building()
		return
	if _state == STATE_MOVING:
		if _joining_site != null or _assist_only:
			_clear_moving_join()
		else:
			cancel()


func cancel() -> bool:
	if _order == null or _state == STATE_CANCELLED:
		return false
	if _state != STATE_MOVING and _state != STATE_BUILDING:
		return false
	# join / 协助中取消：只离开，不退首单（未扣）
	if (_joining_site != null or _assist_only) and _state == STATE_MOVING:
		_clear_moving_join()
		return true
	if _joining_site != null and _state == STATE_BUILDING:
		_leave_site_keep_building()
		return true
	var ratio: float = CANCEL_REFUND_RATIO
	if _profile != null:
		ratio = _profile.cancel_refund_ratio
	var refund_g: int = int(round(float(_order.gold_spent) * ratio))
	var refund_l: int = int(round(float(_order.lumber_spent) * ratio))
	if _session != null:
		var stock: PlayerStock = _session.local_stock()
		if stock != null:
			stock.add_gold(refund_g)
			stock.add_lumber(refund_l)
	_order.state = BuildOrder.STATE_CANCELLED
	_last_cancelled = _order
	_state = STATE_CANCELLED
	set_process(false)
	_set_work_anim(false)
	_dispose_owned_site()
	var cancelled_order: BuildOrder = _order
	_order = null
	_joining_site = null
	state_changed.emit(_state)
	build_cancelled.emit(cancelled_order)
	return true


func _clear_moving_join() -> void:
	_state = STATE_IDLE
	_order = null
	_joining_site = null
	_assist_only = false
	_approach_wc3 = Vector2.INF
	set_process(false)
	_set_work_anim(false)
	state_changed.emit(_state)


func _leave_site_keep_building() -> void:
	var site := _site if _site != null else _joining_site
	if site != null and _peasant != null:
		site.remove_builder(_peasant)
	_set_work_anim(false)
	if _profile != null and _profile.hides_builder() and _peasant != null:
		_peasant.visible = true
	if _joining_site != null and _joining_site.build_completed.is_connected(_on_join_site_completed):
		_joining_site.build_completed.disconnect(_on_join_site_completed)
	# 首单创建的工地：脱离本节点，交给场景续命（Director registry 持有）
	if _site != null:
		if _site.build_completed.is_connected(_on_site_completed):
			_site.build_completed.disconnect(_on_site_completed)
		var host := get_tree().get_first_node_in_group("build_sites_host") as Node
		if host != null and _site.get_parent() != host:
			_site.reparent(host)
		_site = null
	_joining_site = null
	_assist_only = false
	_order = null
	_state = STATE_IDLE
	set_process(false)
	state_changed.emit(_state)


func _on_join_site_completed(_order_done: BuildOrder, _site_wc3: Vector2, _player_owner: int) -> void:
	_set_work_anim(false)
	if _joining_site != null:
		if _joining_site.build_completed.is_connected(_on_join_site_completed):
			_joining_site.build_completed.disconnect(_on_join_site_completed)
		if _peasant != null:
			_joining_site.remove_builder(_peasant)
	_joining_site = null
	_assist_only = false
	_order = null
	_state = STATE_IDLE
	set_process(false)
	state_changed.emit(_state)


func _process(_delta: float) -> void:
	if _order == null or _peasant == null:
		return
	# 协助：持续尝试挂上已创建的工地
	if _assist_only and _joining_site == null:
		_try_resolve_assist_site()
	if _state != STATE_MOVING:
		return
	var cur: Vector2 = Wc3Coords.godot_to_wc3_xy(_peasant.global_position)
	var target := _approach_wc3 if _approach_wc3 != Vector2.INF else _order.site_wc3
	var arrive := _arrive_dist(_order.building_id)
	if cur.distance_to(target) <= arrive:
		_on_arrived()


func _try_resolve_assist_site() -> void:
	if not find_site_at.is_valid() or _order == null:
		return
	# 与 Director._find_build_site(site_wc3, building_id) 参数顺序一致
	var site: BuildSite = find_site_at.call(_order.site_wc3, _order.building_id) as BuildSite
	if site == null or not site.is_active():
		return
	_joining_site = site
	_assist_only = false
	var cur: Vector2 = Wc3Coords.godot_to_wc3_xy(_peasant.global_position)
	var target := _approach_wc3 if _approach_wc3 != Vector2.INF else _order.site_wc3
	if cur.distance_to(target) <= _arrive_dist(_order.building_id):
		_on_arrived()


func _on_arrived() -> void:
	if _order == null:
		return
	# 协助：半成品尚未出现 → 停在外沿继续等（不自己开坑）
	if _assist_only and _joining_site == null:
		_try_resolve_assist_site()
		if _joining_site == null:
			var nav_wait: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
			if nav_wait != null:
				nav_wait.stop()
			return
	var nav: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
	_face_build_site()
	_state = STATE_BUILDING
	_order.state = BuildOrder.STATE_BUILDING
	set_process(false)
	if _peasant != null and _profile != null and _profile.hides_builder():
		_peasant.visible = false

	if _joining_site != null:
		_site = null
		_assist_only = false
		if not _joining_site.add_builder(_peasant):
			_clear_moving_join()
			return
		if not _joining_site.build_completed.is_connected(_on_join_site_completed):
			_joining_site.build_completed.connect(_on_join_site_completed)
		build_joined.emit(_joining_site, _peasant)
		_set_work_anim(true)
		state_changed.emit(_state)
		return

	# 首单：到位后创建工地
	_assist_only = false
	_site = BuildSite.new()
	_site.configure_session(_session)
	add_child(_site)
	_site.start(_order, _owner_of_peasant())
	if not _site.build_completed.is_connected(_on_site_completed):
		_site.build_completed.connect(_on_site_completed)
	_strategy.on_order_accepted(_site, _peasant)
	_strategy.on_builder_arrived(_site, _peasant)
	_site.add_builder(_peasant)
	_set_work_anim(true)
	state_changed.emit(_state)
	build_started.emit(_order)


## 面朝工地中心（与 UnitNavigator 前进轴约定一致：yaw = atan2(dy, dx)）。
func _face_build_site() -> void:
	if _peasant == null or _order == null:
		return
	var from := Wc3Coords.godot_to_wc3_xy(_peasant.global_position)
	var dir := _order.site_wc3 - from
	if dir.length_squared() < 1.0:
		return
	dir = dir.normalized()
	_peasant.rotation.y = atan2(dir.y, dir.x)


func _on_site_completed(order: BuildOrder, site_wc3: Vector2, player_owner: int) -> void:
	# 人口由 Director 统一加（避免首工离开后漏加 / 双重加）
	_strategy.on_complete(_site)
	_set_work_anim(false)
	_dispose_owned_site()
	_order = null
	_joining_site = null
	_state = STATE_IDLE
	state_changed.emit(_state)
	build_completed.emit(order, site_wc3, player_owner)


func _validate_and_spend(order: BuildOrder) -> bool:
	if _session == null:
		return false
	if not BuildingCatalog.is_building(order.building_id):
		return false
	if not PlacementRules.can_build_at(order.building_id, order.site_wc3, _pathing, []):
		return false
	var g: int = BuildingCatalog.get_gold_cost(order.building_id)
	var l: int = BuildingCatalog.get_lumber_cost(order.building_id)
	var stock: PlayerStock = _session.local_stock()
	if stock == null or not stock.try_spend(g, l):
		return false
	order.gold_spent = g
	order.lumber_spent = l
	order.build_time_sec = BuildingCatalog.get_build_time(order.building_id)
	return true


func _abort_other_orders() -> void:
	if _peasant == null:
		return
	var hc: HarvestController = _peasant.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()


func _owner_of_peasant() -> int:
	if _peasant == null:
		return 0
	var d: Dictionary = _peasant.get_meta("unit_data", {})
	return int(d.get("owner", 0))


func _dispose_owned_site() -> void:
	if _site != null:
		_strategy.on_cancel(_site)
		if _site.build_completed.is_connected(_on_site_completed):
			_site.build_completed.disconnect(_on_site_completed)
		for b in _site.active_builders():
			_site.remove_builder(b)
		_site.cancel()
		_site.queue_free()
		_site = null
	if _peasant != null and not _peasant.visible and _profile != null and _profile.hides_builder():
		_peasant.visible = true


func _compute_approach(site_wc3: Vector2, building_id: String) -> Vector2:
	var fp: Vector2i = PlacementRules.get_footprint(building_id)
	if fp.x <= 0:
		fp = Vector2i(1, 1)
	if fp.y <= 0:
		fp = Vector2i(1, fp.x)
	var cs := Wc3Coords.PATHING_CELL
	var half := Vector2(float(fp.x) * 0.5, float(fp.y) * 0.5) * cs
	var margin := OUTSIDE_MARGIN_CELLS * cs
	var from := site_wc3
	if _peasant != null:
		from = Wc3Coords.godot_to_wc3_xy(_peasant.global_position)
	var dir := from - site_wc3
	if dir.length_squared() < 1.0:
		dir = Vector2(1.0, 0.0)
	dir = dir.normalized()
	# 落到 footprint 外轴对齐盒边缘
	var sx := half.x + margin
	var sy := half.y + margin
	var tx := sx / maxf(absf(dir.x), 1e-4)
	var ty := sy / maxf(absf(dir.y), 1e-4)
	var t := minf(tx, ty)
	var preferred := site_wc3 + dir * t
	# 贴着已有建筑时外沿常落在 NO_WALK 上 → 吸附脚印外最近可走格
	return _snap_approach_walkable(preferred, site_wc3, half + Vector2(margin, margin))


## 发走位；无 Navigator 时仅靠距离判定（可能已在到达半径内）。
func _go_to_approach() -> void:
	if _peasant == null or _approach_wc3 == Vector2.INF:
		return
	var nav: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav == null:
		push_warning("BuildController: 农民无 UnitNavigator，无法走位建造")
		return
	if nav.go_to_wc3(_approach_wc3):
		return
	# 寻路失败：再外扩一圈可走点
	var alt := _snap_approach_walkable(_approach_wc3, _order.site_wc3 if _order != null else _approach_wc3, Vector2(64, 64))
	if alt != _approach_wc3:
		_approach_wc3 = alt
		nav.go_to_wc3(_approach_wc3)


## preferred 不可走或仍在 footprint 内时，螺旋找脚印外可走格。
func _snap_approach_walkable(preferred: Vector2, site_wc3: Vector2, half_ext: Vector2) -> Vector2:
	if _pathing == null or not _pathing.is_valid():
		return preferred
	var aabb := Rect2(site_wc3 - half_ext, half_ext * 2.0)
	if _pathing.can_walk_at(preferred.x, preferred.y) and not aabb.has_point(preferred):
		return preferred
	var c0 := _pathing.world_to_cell(preferred.x, preferred.y)
	var best := preferred
	var best_d2 := INF
	for r in range(0, 20):
		var found := false
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var center := _pathing.cell_center_wc3(c0.x + dx, c0.y + dy)
				if not _pathing.can_walk_at(center.x, center.y):
					continue
				if aabb.has_point(center):
					continue
				var d2 := preferred.distance_squared_to(center)
				if d2 < best_d2:
					best_d2 = d2
					best = center
					found = true
		if found:
			return best
	return preferred


func _arrive_dist(building_id: String) -> float:
	var fp: Vector2i = PlacementRules.get_footprint(building_id)
	var cs := Wc3Coords.PATHING_CELL
	# 略紧：贴着外沿即可开工，避免站得过远空挥
	return maxf(float(maxi(fp.x, fp.y)) * cs * 0.22, 18.0)


func _set_work_anim(on: bool) -> void:
	if _peasant == null:
		return
	var u := Unit.of(_peasant)
	if u == null:
		return
	u.set_building_work(on)
