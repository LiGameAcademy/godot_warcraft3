class_name BuildController
extends Node

## 农民建造控制器。挂在 peasant 子节点（与 UnitNavigator 平级）。
##
## 状态机：IDLE → MOVING → BUILDING → DONE / CANCELLED
##
## 流程：
## 1. start_build(order)：_validate_and_spend → 扣资源 → 调 UnitNavigator.go_to_wc3 → STATE_MOVING
## 2. 到位：hide peasant → attach BuildSite → STATE_BUILDING + build_started.emit
## 3. BuildSite timer 跑完：build_completed.emit → Director 刷建筑 + 人口
## 4. cancel：退款 50%（CANCEL_REFUND_RATIO）；同步 _dispose_site
##
## 到达判定由本类 _process 监听 peasant.global_position 距 site < 32 wc3（1 格）。
## 不引入 arrived 信号依赖。

signal state_changed(state: int)
signal build_started(order: BuildOrder)
signal build_cancelled(order: BuildOrder)
## F2-5 新增：工地 timer 跑完；Director 刷建筑 + 人口
signal build_completed(order: BuildOrder, site_wc3: Vector2, owner: int)


const STATE_IDLE := 0
const STATE_MOVING := 1
const STATE_BUILDING := 2
const STATE_CANCELLED := 3

## 距工地中心 < 该阈值视为到达（WC3 单位；≈ 1 pathing cell）
const ARRIVE_DIST_WC3 := 32.0
## 取消退款比例（WC3 行为：50% 退）
const CANCEL_REFUND_RATIO := 0.5


var _order: BuildOrder = null
var _state: int = STATE_IDLE
## 配置（Director 在 _setup_build_router 时注入；运行时可能为空，需 fallback）
var _session: GameSession = null
var _pathing: Wc3PathingMap = null
## 父节点：peasant Node3D
var _peasant: Node3D = null
## F2-5：建造期间持有的 BuildSite（timer 推进）
var _site: BuildSite = null
## cancel 时记录的最近被取消 order（供 build_cancelled signal 透传）
var _last_cancelled: BuildOrder = null


func _ready() -> void:
	_peasant = get_parent() as Node3D
	set_process(false)


func configure(session: GameSession, pathing: Wc3PathingMap) -> void:
	_session = session
	_pathing = pathing


## 当前是否正在建造（防止重入）。
func is_active() -> bool:
	return _state == STATE_MOVING or _state == STATE_BUILDING


func current_order() -> BuildOrder:
	return _order


## 接受 BUILD Order。返回 true = 资源已扣 + 已开始走位。
func start_build(order: BuildOrder) -> bool:
	if _state != STATE_IDLE:
		return false
	if order == null or order.builder == null:
		return false
	if not _validate_and_spend(order):
		return false
	_order = order
	_order.state = BuildOrder.STATE_MOVING
	_state = STATE_MOVING
	# 打断采集/移动
	_abort_other_orders()
	# 走向工地
	var nav: UnitNavigator = _peasant.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.go_to_wc3(_order.site_wc3)
	set_process(true)
	state_changed.emit(_state)
	return true


## 取消建造：退款 50%，peasant 释放；同步取消 BuildSite。
func cancel() -> bool:
	if _order == null or _state == STATE_CANCELLED:
		return false
	if _state != STATE_MOVING and _state != STATE_BUILDING:
		return false
	var refund_g: int = int(round(float(_order.gold_spent) * CANCEL_REFUND_RATIO))
	var refund_l: int = int(round(float(_order.lumber_spent) * CANCEL_REFUND_RATIO))
	if _session != null:
		var stock: PlayerStock = _session.local_stock()
		if stock != null:
			stock.add_gold(refund_g)
			stock.add_lumber(refund_l)
	_order.state = BuildOrder.STATE_CANCELLED
	_last_cancelled = _order
	_state = STATE_CANCELLED
	set_process(false)
	_dispose_site()
	# peasant 恢复可被命令（仍存在，不删）
	var cancelled_order: BuildOrder = _order
	_order = null
	state_changed.emit(_state)
	build_cancelled.emit(cancelled_order)
	return true


func _process(_delta: float) -> void:
	if _state != STATE_MOVING or _order == null or _peasant == null:
		return
	var cur: Vector2 = Wc3Coords.godot_to_wc3_xy(_peasant.global_position)
	if cur.distance_to(_order.site_wc3) <= ARRIVE_DIST_WC3:
		_on_arrived()


func _on_arrived() -> void:
	if _order == null:
		return
	_state = STATE_BUILDING
	_order.state = BuildOrder.STATE_BUILDING
	set_process(false)
	# 隐藏 peasant（工地幼体模型后续接；F2-5 简化：直接隐藏）
	if _peasant != null:
		_peasant.visible = false
	# 启动 BuildSite 接管 timer
	_site = BuildSite.new()
	add_child(_site)
	_site.start(_order, _owner_of_peasant())
	_site.build_completed.connect(_on_site_completed)
	state_changed.emit(_state)
	# 旧 signal 保留（外部用：F2-7 验收剧本 / HUD 进度条订阅）
	build_started.emit(_order)


func _on_site_completed(order: BuildOrder, site_wc3: Vector2, owner: int) -> void:
	# 人口变化：Farm +6，Altar/Barracks 0
	if _session != null:
		var stock: PlayerStock = _session.local_stock()
		if stock != null:
			var fmade: int = BuildingCatalog.get_food_made(order.building_id)
			if fmade > 0:
				stock.add_food_cap(fmade)
	# 完工后：清 BuildSite + 保留 peasant（Director 决定删 / 变工地 / 后续）
	_dispose_site()
	_order = null
	_state = STATE_IDLE
	state_changed.emit(_state)
	build_completed.emit(order, site_wc3, owner)


## 资源 + 选址校验。任何失败 → 不扣资源 + 返回 false。
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


func _dispose_site() -> void:
	if _site != null:
		if _site.build_completed.is_connected(_on_site_completed):
			_site.build_completed.disconnect(_on_site_completed)
		_site.cancel()
		_site.queue_free()
		_site = null
