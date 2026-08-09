class_name BuildController
extends Node

## 农民建造控制器。挂在 peasant 子节点（与 UnitNavigator 平级）。
##
## 职责（F2-3）：
## - start_build(order)：验证 + 扣资源 + 走位
## - 到位：emit build_started → F2-5 接管 timer / 模型替换
## - cancel：退款 50%（WC3 行为；P1）
##
## 跟 UnitNavigator 关系：调 navigator.go_to_wc3(site)；
## 到达判定由本类 _process 监听 peasant.global_position 距 site < 32 wc3（1 格）。
## 不引入 arrived 信号依赖。

signal state_changed(state: int)
## F2-5 接：开始 timer 推进 + 模型替换为工地幼体
signal build_started(order: BuildOrder)
## 已退款（30% 损耗）；peasant 重新可被命令
signal build_cancelled(order: BuildOrder)


const STATE_IDLE := 0
const STATE_MOVING := 1
const STATE_BUILDING := 2
const STATE_CANCELLED := 3

## 距工地中心 < 该阈值视为到达（WC3 单位；≈ 1 pathing cell）
const ARRIVE_DIST_WC3 := 32.0
## 取消退款比例（WC3 行为：50% 退；这里按 0.5 系数）
const CANCEL_REFUND_RATIO := 0.5


var _order: BuildOrder = null
var _state: int = STATE_IDLE
## 配置（Director 在 _setup_build_router 时注入；运行时可能为空，需 fallback）
var _session: GameSession = null
var _pathing: Wc3PathingMap = null
## 保证 BuildController 是 Node 子节点：父节点是 peasant Node3D
var _peasant: Node3D = null


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


## 取消建造：退款 50%，peasant 释放。
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
	_state = STATE_CANCELLED
	set_process(false)
	build_cancelled.emit(_order)
	# peasant 恢复可被命令（仍存在，不删）
	_order = null
	state_changed.emit(_state)
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
	state_changed.emit(_state)
	# F2-5 接：开始 timer 推进
	build_started.emit(_order)


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


## 打断当前采集 / 移动订单，让 peasant 专心建造。
func _abort_other_orders() -> void:
	if _peasant == null:
		return
	var hc: HarvestController = _peasant.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
	# Navigator 自然会接受新的 go_to_wc3 调用，无需显式 stop
