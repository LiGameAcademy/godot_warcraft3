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
## 站在 footprint 外沿外再偏一格
const OUTSIDE_MARGIN_CELLS := 0.85


var _order: BuildOrder = null
var _state: int = STATE_IDLE
var _session: GameSession = null
var _pathing: Wc3PathingMap = null
var _cell_reservation: PathCellReservation = null
var _peasant: Node3D = null
var _site: BuildSite = null
## join 模式：不扣首单费，只加入已有工地
var _joining_site: BuildSite = null
var _approach_wc3: Vector2 = Vector2.INF
var _profile: ConstructionProfile = null
var _strategy: IConstructionStrategy = null
var _profile_catalog: ConstructionProfileCatalog = null
var _last_cancelled: BuildOrder = null


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


func is_building() -> bool:
	return _state == STATE_BUILDING


func current_order() -> BuildOrder:
	return _order


func current_site() -> BuildSite:
	return _site if _site != null else _joining_site


## 首单：扣费 + 走向外侧。
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
	_abort_other_orders()
	_approach_wc3 = _compute_approach(_order.site_wc3, _order.building_id)
	var nav: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.go_to_wc3(_approach_wc3)
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
	_order = BuildOrder.create(building_id, site_wc3, _peasant)
	_order.build_time_sec = site.total()
	_order.state = BuildOrder.STATE_MOVING
	_state = STATE_MOVING
	_abort_other_orders()
	_approach_wc3 = _compute_approach(site_wc3, building_id)
	var nav: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.go_to_wc3(_approach_wc3)
	set_process(true)
	state_changed.emit(_state)
	return true


## 工人被调走：离开工地（不拆建筑）；若是 MOVING 中的首单未开工则退款取消。
func leave_or_abort() -> void:
	if _state == STATE_BUILDING:
		_leave_site_keep_building()
		return
	if _state == STATE_MOVING:
		if _joining_site != null:
			_clear_moving_join()
		else:
			cancel()


func cancel() -> bool:
	if _order == null or _state == STATE_CANCELLED:
		return false
	if _state != STATE_MOVING and _state != STATE_BUILDING:
		return false
	# join 中取消：只离开，不退首单（未扣）
	if _joining_site != null and _state == STATE_MOVING:
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
	_order = null
	_state = STATE_IDLE
	set_process(false)
	state_changed.emit(_state)


func _process(_delta: float) -> void:
	if _state != STATE_MOVING or _order == null or _peasant == null:
		return
	var cur: Vector2 = Wc3Coords.godot_to_wc3_xy(_peasant.global_position)
	var target := _approach_wc3 if _approach_wc3 != Vector2.INF else _order.site_wc3
	var arrive := _arrive_dist(_order.building_id)
	if cur.distance_to(target) <= arrive:
		_on_arrived()


func _on_arrived() -> void:
	if _order == null:
		return
	# 停步
	var nav: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
	_state = STATE_BUILDING
	_order.state = BuildOrder.STATE_BUILDING
	set_process(false)
	if _peasant != null and _profile != null and _profile.hides_builder():
		_peasant.visible = false

	if _joining_site != null:
		_site = null
		if not _joining_site.add_builder(_peasant):
			_clear_moving_join()
			return
		if not _joining_site.build_completed.is_connected(_on_join_site_completed):
			_joining_site.build_completed.connect(_on_join_site_completed)
		build_joined.emit(_joining_site, _peasant)
		_set_work_anim(true)
		state_changed.emit(_state)
		return

	# 首单：创建工地
	_site = BuildSite.new()
	_site.configure_session(_session)
	add_child(_site)
	_site.start(_order, _owner_of_peasant())
	_site.build_completed.connect(_on_site_completed)
	_strategy.on_order_accepted(_site, _peasant)
	_strategy.on_builder_arrived(_site, _peasant)
	_site.add_builder(_peasant)
	_set_work_anim(true)
	state_changed.emit(_state)
	build_started.emit(_order)


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
	return site_wc3 + dir * t


func _arrive_dist(building_id: String) -> float:
	var fp: Vector2i = PlacementRules.get_footprint(building_id)
	var cs := Wc3Coords.PATHING_CELL
	return maxf(float(maxi(fp.x, fp.y)) * cs * 0.35, 24.0)


func _set_work_anim(on: bool) -> void:
	if _peasant == null:
		return
	var vis := _peasant.get_node_or_null("UnitVisual") as UnitVisual
	if vis != null:
		vis.set_building_work(on)
