class_name HarvestController
extends Node

## 农民采集「订单 AI」：一次 HarvestGold 命令下的自动循环。
## 首趟：矿口车道散开进矿；第一次出矿/送矿起：统一出矿门 ↔ 统一交货点固定走廊。
## 进矿只隐藏不改坐标；出矿瞬移到「矿上离主城最近点」。

signal state_changed(state: int)
signal carry_changed(gold: int, lumber: int)
signal deposited(gold: int, lumber: int)

enum State {
	IDLE = 0,
	MOVE_TO_MINE = 1,
	WAIT_IN_QUEUE = 2,
	IN_MINE = 3,
	MOVE_TO_DROPOFF = 4,
}

const GOLD_MINE_TYPE := "ngol"
const WORKER_PEASANT := "hpea"
## 金矿贴边：路径 snap 后的放宽半径。
const ENTER_MINE_MAX_WC3 := 280.0
const QUEUE_SLOT_ARRIVE_WC3 := 48.0
## 到达统一交货点即交金。
const DROPOFF_GOAL_ARRIVE_WC3 := 96.0
## 主城脚印外余量；交货半径 = footprint_half + margin（须能站在可走格上）。
const DROPOFF_MARGIN_WC3 := 64.0
const DEFAULT_BUILDING_RADIUS_WC3 := 176.0
const MAX_DROPOFF_REPATH := 1
## 回矿途中寻路失败可重试；对齐 WC3：Harvest 订单持续，不因一次 path fail 中断。
const MAX_MINE_REPATH := 8
## 靠近统一出矿门才可进矿/排队。
const MINE_PORTAL_ARRIVE_WC3 := 72.0

var _state: int = State.IDLE
var _mine: Node3D = null
var _mine_rt: GoldMineRuntime = null
var _dropoff: Node3D = null
## 统一交货点（主城上离矿最近，全员相同）。
var _dropoff_goal_wc3: Vector2 = Vector2.INF
## 统一出矿/回矿门（矿上离主城最近，全员相同）。
var _mine_portal_wc3: Vector2 = Vector2.INF
## 本农民矿口候位（仅首趟散开 / 排队，不参与运金轨迹）。
var _wait_goal_wc3: Vector2 = Vector2.INF
var _dropoff_repath: int = 0
var _mine_repath: int = 0
var _lane_index: int = 0
var _lane_count: int = GoldMineRuntime.DEFAULT_LANE_COUNT
## 首趟多选：先散开再进矿；之后走出矿门。
var _use_scatter_approach: bool = true
var _carry_gold: int = 0
var _carry_lumber: int = 0
var _dwell_left: float = 0.0
var _gold_per_trip: int = 10
var _ensure_navigator: Callable = Callable()
var _get_stock: Callable = Callable()
var _get_unit_host: Callable = Callable()
var _get_path_query: Callable = Callable()
var _was_visible: bool = true
var _active: bool = false
var _mine_repath_cooldown: float = 0.0


func configure(
	ensure_navigator: Callable,
	get_stock: Callable,
	get_unit_host: Callable,
	get_path_query: Callable = Callable()
) -> void:
	_ensure_navigator = ensure_navigator
	_get_stock = get_stock
	_get_unit_host = get_unit_host
	_get_path_query = get_path_query
	_load_ahar_params()


func is_active() -> bool:
	return _active and _state != State.IDLE


func get_state() -> int:
	return _state


func carry_gold() -> int:
	return _carry_gold


func carry_lumber() -> int:
	return _carry_lumber


func is_carrying() -> bool:
	return _carry_gold > 0 or _carry_lumber > 0


func remembered_mine() -> Node3D:
	if _mine != null and is_instance_valid(_mine):
		return _mine
	return null


## 开始采金。lane_index/lane_count：多农民同时下令时的矿口弧形散开。
func start_harvest_gold(
	mine: Node3D = null,
	lane_index: int = 0,
	lane_count: int = GoldMineRuntime.DEFAULT_LANE_COUNT
) -> bool:
	_load_ahar_params()
	if mine != null and is_instance_valid(mine):
		_mine = mine
	if _mine == null or not is_instance_valid(_mine):
		return false
	if not GoldMineRuntime.is_gold_mine(_mine):
		return false
	_mine_rt = GoldMineRuntime.ensure(_mine)
	if _mine_rt == null:
		return false
	_lane_index = maxi(lane_index, 0)
	_lane_count = maxi(lane_count, 1)
	_mine_portal_wc3 = Vector2.INF
	_dropoff_goal_wc3 = Vector2.INF
	_wait_goal_wc3 = Vector2.INF
	_update_queue_direction()
	_cache_corridor_goals()
	_set_harvest_ghost(true)
	if _carry_gold > 0:
		_use_scatter_approach = false
		_active = true
		_go_dropoff()
		return true
	_use_scatter_approach = true
	_active = true
	_set_state(State.MOVE_TO_MINE)
	return _go_mine_approach()


func start_return_goods() -> bool:
	if not is_carrying():
		return false
	_set_harvest_ghost(true)
	_active = true
	_go_dropoff()
	return true


func abort() -> void:
	var body := _body()
	if _mine_rt != null and is_instance_valid(_mine_rt):
		if body != null:
			if _mine_rt.is_inside(body):
				_mine_rt.cancel_inside(body)
			else:
				_mine_rt.leave_queue(body)
		_disconnect_mine_signals()
	_set_harvest_ghost(false)
	if not _active and _state == State.IDLE:
		_restore_visible()
		return
	_active = false
	_dwell_left = 0.0
	_dropoff = null
	_dropoff_goal_wc3 = Vector2.INF
	_mine_portal_wc3 = Vector2.INF
	_wait_goal_wc3 = Vector2.INF
	_dropoff_repath = 0
	_mine_repath = 0
	_mine_repath_cooldown = 0.0
	_use_scatter_approach = true
	_restore_visible()
	_set_state(State.IDLE)
	set_process(false)


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	if _mine_repath_cooldown > 0.0:
		_mine_repath_cooldown = maxf(0.0, _mine_repath_cooldown - delta)
	match _state:
		State.MOVE_TO_MINE:
			_tick_move_to_mine()
		State.WAIT_IN_QUEUE:
			_tick_wait_in_queue()
		State.IN_MINE:
			_tick_in_mine(delta)
		State.MOVE_TO_DROPOFF:
			_tick_move_to_dropoff()
		_:
			set_process(false)


func _tick_move_to_mine() -> void:
	if not _mine_valid():
		abort()
		return
	var body := _body()
	if body == null:
		abort()
		return
	var nav := _nav()
	if nav != null and nav.is_moving():
		return
	# 已靠近本车道矿门 / 候位 → 进矿或排队（对齐 WC3：走到矿再 harvest）
	if _near_mine_entry(body):
		_mine_repath = 0
		_try_enter_or_queue()
		return
	# 途中 stall / 寻路失败：重试，勿立刻 abort（否则交金后站在脚印里会假死）
	if _mine_repath_cooldown > 0.0:
		return
	if _issue_mine_path(body):
		_mine_repath = 0
		return
	_mine_repath += 1
	_mine_repath_cooldown = 0.25
	if _mine_repath >= MAX_MINE_REPATH:
		abort()


func _near_mine_entry(body: Node3D) -> bool:
	if body == null:
		return false
	var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
	# 运金循环中：只认统一出矿门（不再认首趟散开候位）
	if not _use_scatter_approach:
		if _mine_portal_wc3 != Vector2.INF:
			return cur.distance_to(_mine_portal_wc3) <= MINE_PORTAL_ARRIVE_WC3
		return _dist_wc3(body, _mine) <= ENTER_MINE_MAX_WC3
	if _mine_portal_wc3 != Vector2.INF:
		if cur.distance_to(_mine_portal_wc3) <= MINE_PORTAL_ARRIVE_WC3:
			return true
	if _wait_goal_wc3 != Vector2.INF:
		if cur.distance_to(_wait_goal_wc3) <= QUEUE_SLOT_ARRIVE_WC3:
			return true
	# 兜底：贴矿心且已在脚印外缘附近
	return _dist_wc3(body, _mine) <= ENTER_MINE_MAX_WC3 and _mine_portal_wc3 == Vector2.INF


func _issue_mine_path(body: Node3D) -> bool:
	_ensure_walkable_start(body)
	# 首趟才散开；第一次送矿起一律走统一出矿门
	if _use_scatter_approach:
		return _path_to_wait_slot(body)
	return _path_to_mine_portal(body)


func _tick_wait_in_queue() -> void:
	if not _mine_valid():
		abort()
		return
	var body := _body()
	if body == null:
		abort()
		return
	# 槽位空且自己是队首 → 进矿（FIFO 只定权，不挪候位）
	if _mine_rt.try_enter(body):
		_begin_inside_mine()
		return
	if _mine_rt.queue_index(body) < 0:
		_mine_rt.enqueue(body)
	var nav := _nav()
	if nav != null and nav.is_moving():
		return
	# 首趟：车道候位；运金循环：统一出矿门站岗
	var hold := _queue_hold_goal_wc3()
	if hold != Vector2.INF:
		var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
		if cur.distance_to(hold) > QUEUE_SLOT_ARRIVE_WC3:
			_path_to_queue_hold(body)


func _queue_hold_goal_wc3() -> Vector2:
	if _use_scatter_approach and _wait_goal_wc3 != Vector2.INF:
		return _wait_goal_wc3
	if _mine_portal_wc3 != Vector2.INF:
		return _mine_portal_wc3
	return _wait_goal_wc3


func _path_to_queue_hold(body: Node3D) -> bool:
	if _use_scatter_approach:
		return _path_to_wait_slot(body)
	return _path_to_mine_portal(body)


func _tick_in_mine(delta: float) -> void:
	_dwell_left -= delta
	if _dwell_left > 0.0:
		return
	_exit_mine_with_gold()


func _tick_move_to_dropoff() -> void:
	if _dropoff == null or not is_instance_valid(_dropoff):
		if not _resolve_dropoff():
			abort()
			return
		_go_dropoff()
		return
	var body := _body()
	if body == null:
		abort()
		return
	var nav := _nav()
	if nav != null and nav.is_moving():
		return
	# 已停下：优先交货，禁止「差一点就重寻路」造成抖动
	if _can_deposit_now(body):
		_do_deposit()
		return
	var hall_dist := _dist_wc3(body, _dropoff)
	var accept_r := _deposit_accept_radius_wc3(_dropoff)
	if hall_dist <= accept_r * 1.25:
		_do_deposit()
		return
	if _dropoff_goal_wc3 != Vector2.INF:
		var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
		if cur.distance_to(_dropoff_goal_wc3) <= DROPOFF_GOAL_ARRIVE_WC3 * 1.5:
			_do_deposit()
			return
	if _dropoff_repath >= MAX_DROPOFF_REPATH:
		if hall_dist <= accept_r * 1.5:
			_do_deposit()
		else:
			abort()
		return
	_dropoff_repath += 1
	if not _path_to_dropoff_approach(body):
		if _can_deposit_now(body) or hall_dist <= accept_r * 1.25:
			_do_deposit()
		else:
			abort()


func _try_enter_or_queue() -> void:
	var body := _body()
	if body == null or not _mine_valid():
		abort()
		return
	_update_queue_direction()
	# 先入队保证顺序，再尝试进矿（队空时可直接进）
	_mine_rt.enqueue(body)
	if _mine_rt.try_enter(body):
		_begin_inside_mine()
		return
	_connect_mine_signals()
	_set_state(State.WAIT_IN_QUEUE)
	set_process(true)
	_path_to_queue_hold(body)


func _begin_inside_mine() -> void:
	var body := _body()
	var nav := _nav()
	if nav != null:
		nav.stop()
	# 进矿：只隐藏，不改坐标（出矿时再瞬移到统一出矿点）
	if body != null:
		_was_visible = body.visible
		body.visible = false
	var dwell := GoldMineRuntime.DEFAULT_DWELL_SEC
	if _mine_rt != null:
		dwell = _mine_rt.dwell_sec
	_dwell_left = dwell
	_set_state(State.IN_MINE)
	set_process(true)


func _exit_mine_with_gold() -> void:
	var body := _body()
	var want := _gold_per_trip
	var taken := want
	if _mine_rt != null and is_instance_valid(_mine_rt) and body != null:
		taken = _mine_rt.exit_mine(body, want)
	_carry_gold = taken
	_carry_lumber = 0
	# 出矿：全员瞬移到「矿上离主城最近」的统一点，再显示并去交货
	_place_at_shared_exit(body)
	_restore_visible()
	_apply_carry_visual()
	carry_changed.emit(_carry_gold, _carry_lumber)
	if taken <= 0:
		# 矿空：停止采集循环
		_active = false
		_set_harvest_ghost(false)
		_set_state(State.IDLE)
		set_process(false)
		return
	# 第一次出矿起进入固定走廊模式（送矿/回矿都走统一出矿门）
	_use_scatter_approach = false
	_go_dropoff()


func _do_deposit() -> void:
	var body := _body()
	var nav := _nav()
	if nav != null:
		nav.stop()
	var stock: PlayerStock = null
	if _get_stock.is_valid():
		stock = _get_stock.call() as PlayerStock
	var deposited_amt := ReceiveResources.deposit(
		_dropoff, stock, _carry_gold, _carry_lumber
	)
	var g := int(deposited_amt.get("gold", 0))
	var l := int(deposited_amt.get("lumber", 0))
	_carry_gold = 0
	_carry_lumber = 0
	# 保留统一交货点，避免每趟重新 approach 导致路线漂移
	_dropoff_repath = 0
	_mine_repath = 0
	# 第一次送矿完成后：回矿只去统一出矿门，不再回首趟散开点
	_use_scatter_approach = false
	_apply_carry_visual()
	carry_changed.emit(0, 0)
	if g > 0 or l > 0:
		deposited.emit(g, l)
	if _mine != null and is_instance_valid(_mine) and _active:
		_mine_rt = GoldMineRuntime.ensure(_mine)
		# WC3：交金后自动 resume harvest 到「上次的矿」；先保证站在可走格再寻路
		_ensure_walkable_start(body)
		_set_state(State.MOVE_TO_MINE)
		set_process(true)
		if not _go_mine_approach():
			# 首帧失败不 abort：留在 MOVE_TO_MINE 由 tick 重试
			_mine_repath_cooldown = 0.15
	else:
		_active = false
		_set_harvest_ghost(false)
		_set_state(State.IDLE)
		set_process(false)


func _go_mine_approach() -> bool:
	if not _mine_valid():
		return false
	_mine_rt = GoldMineRuntime.ensure(_mine)
	_update_queue_direction()
	if _mine_portal_wc3 == Vector2.INF or _wait_goal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	_set_state(State.MOVE_TO_MINE)
	set_process(true)
	var body := _body()
	if body == null:
		return false
	_ensure_walkable_start(body)
	# 首趟多选散开；循环中走统一出矿门
	return _issue_mine_path(body)


func _ensure_walkable_start(body: Node3D) -> void:
	## 仅贴回固定走廊端点；禁止每趟 snap_to_open 造成落脚点漂移。
	if body == null:
		return
	var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
	if _is_walkable_wc3(cur):
		return
	if _dropoff_goal_wc3 != Vector2.INF and _state == State.MOVE_TO_MINE:
		_place_at_wc3(body, _dropoff_goal_wc3)
		return
	if _mine_portal_wc3 != Vector2.INF:
		_place_at_wc3(body, _mine_portal_wc3)


func _is_walkable_wc3(wc3: Vector2) -> bool:
	var pq := _path_query()
	if pq == null or not pq.has_method("can_walk_wc3"):
		return true
	return bool(pq.call("can_walk_wc3", wc3.x, wc3.y))


func _place_at_wc3(body: Node3D, wc3: Vector2) -> void:
	if body == null:
		return
	var nav := _nav()
	if nav != null:
		nav.stop()
	var g := Wc3Coords.wc3_xy_to_godot(wc3.x, wc3.y)
	body.global_position = Vector3(g.x, body.global_position.y, g.z)


func _set_harvest_ghost(on: bool) -> void:
	var nav := _nav()
	if nav != null and nav.has_method("set_harvest_ghost"):
		nav.call("set_harvest_ghost", on)
	elif nav != null:
		nav.enable_separation = not on


func _go_dropoff() -> void:
	if not _resolve_dropoff():
		abort()
		return
	if _dropoff_goal_wc3 == Vector2.INF or _mine_portal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	_dropoff_repath = 0
	_set_harvest_ghost(true)
	_set_state(State.MOVE_TO_DROPOFF)
	set_process(true)
	var body := _body()
	if body == null or not _path_to_dropoff_approach(body):
		abort()


func _cache_corridor_goals() -> void:
	if not _mine_valid():
		return
	_update_queue_direction()
	# 候位：按车道散开（仅首趟 / 排队，不参与运金）
	var wait_goal := _mine_rt.entrance_slot_wc3(_lane_index, _lane_count)
	var pq := _path_query()
	if pq != null and pq.has_method("snap_to_walkable"):
		var snap_w: Dictionary = pq.call("snap_to_walkable", wait_goal.x, wait_goal.y, 8)
		if bool(snap_w.get("ok", false)):
			wait_goal = snap_w["wc3"] as Vector2
	_wait_goal_wc3 = wait_goal
	if _dropoff == null or not is_instance_valid(_dropoff):
		_resolve_dropoff_from_mine()
	if _dropoff == null or not is_instance_valid(_dropoff):
		_mine_portal_wc3 = wait_goal
		return
	# 固定走廊：出矿贴金矿（collision）；交货用主城 pathTex 外缘
	var mine_half := _mine_rt.mine_radius_wc3()
	var hall_half := _footprint_half_wc3(_dropoff)
	var portals := _mine_rt.shared_corridor_portals(
		_dropoff, pq, mine_half, hall_half
	)
	if portals.is_empty():
		return
	_mine_portal_wc3 = portals.get("mine", wait_goal) as Vector2
	_dropoff_goal_wc3 = portals.get("hall", Vector2.INF) as Vector2


func _footprint_half_wc3(node: Node) -> float:
	## pathTex 半宽与 collision 取大，避免门落在脚印里导致左出生贴墙 abort。
	var coll := _building_radius_wc3(node)
	if node == null:
		return coll
	var d: Dictionary = node.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return coll
	Wc3DefStore.ensure_table(UnitDataDef.TABLE_NAME)
	var ud := Wc3DefStore.get_row(UnitDataDef.TABLE_NAME, tid) as UnitDataDef
	if ud == null:
		return coll
	var cells: Vector2i = Wc3IdCatalog.parse_path_tex_cells(ud.path_tex)
	if cells == Vector2i.ZERO:
		return coll
	var half := float(maxi(cells.x, cells.y)) * Wc3Coords.PATHING_CELL * 0.5
	return maxf(coll, half)


func _path_to_wait_slot(body: Node3D) -> bool:
	if body == null or not _mine_valid():
		return false
	if _wait_goal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	if _wait_goal_wc3 == Vector2.INF:
		return _path_to_approach(body, _mine)
	return _go_to_wc3(_wait_goal_wc3)


func _path_to_mine_portal(body: Node3D) -> bool:
	if body == null or not _mine_valid():
		return false
	if _mine_portal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	# 优先走固定回程路点（全员同一条）
	if _mine_rt != null:
		var wps: Array[Vector2] = _mine_rt.corridor_waypoints_to_mine()
		if not wps.is_empty():
			return _follow_fixed_waypoints(wps, _mine_portal_wc3)
	if _mine_portal_wc3 == Vector2.INF:
		return _path_to_wait_slot(body)
	return _go_to_wc3(_mine_portal_wc3)


func _place_at_shared_exit(body: Node3D) -> void:
	## 出矿瞬移：全员同一点 = 矿 footprint 上离主城最近的可走格。
	if body == null:
		return
	if _mine_portal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	if _mine_portal_wc3 == Vector2.INF:
		return
	_place_at_wc3(body, _mine_portal_wc3)


func _follow_fixed_waypoints(waypoints: Array, goal_hint: Vector2 = Vector2.INF) -> bool:
	if not _ensure_navigator.is_valid():
		return false
	var body := _body()
	if body == null:
		return false
	var nav := _ensure_navigator.call(body) as UnitNavigator
	if nav == null:
		return false
	nav.set_harvest_ghost(true)
	if nav.has_method("go_waypoints_wc3"):
		return bool(nav.call("go_waypoints_wc3", waypoints, goal_hint))
	if goal_hint != Vector2.INF:
		return nav.go_to_wc3(goal_hint)
	if not waypoints.is_empty() and waypoints[waypoints.size() - 1] is Vector2:
		return nav.go_to_wc3(waypoints[waypoints.size() - 1] as Vector2)
	return false


func _path_to_dropoff_approach(body: Node3D) -> bool:
	if body == null or _dropoff == null:
		return false
	if _dropoff_goal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	# 优先走固定去程路点（全员同一条，不再每趟 A* / snap）
	if _mine_rt != null:
		var wps: Array[Vector2] = _mine_rt.corridor_waypoints_to_hall()
		if not wps.is_empty():
			return _follow_fixed_waypoints(wps, _dropoff_goal_wc3)
	if _dropoff_goal_wc3 == Vector2.INF:
		var goal := _compute_approach_goal(body, _dropoff)
		_dropoff_goal_wc3 = goal
		return _go_to_wc3(goal)
	return _go_to_wc3(_dropoff_goal_wc3)


func _on_mine_slot_available() -> void:
	if not _active or _state != State.WAIT_IN_QUEUE:
		return
	var body := _body()
	if body == null or not _mine_valid():
		return
	if _mine_rt.try_enter(body):
		_begin_inside_mine()


func _connect_mine_signals() -> void:
	if _mine_rt == null:
		return
	if not _mine_rt.slot_available.is_connected(_on_mine_slot_available):
		_mine_rt.slot_available.connect(_on_mine_slot_available)


func _disconnect_mine_signals() -> void:
	if _mine_rt == null or not is_instance_valid(_mine_rt):
		return
	if _mine_rt.slot_available.is_connected(_on_mine_slot_available):
		_mine_rt.slot_available.disconnect(_on_mine_slot_available)


func _update_queue_direction() -> void:
	if not _mine_valid():
		return
	var body := _body()
	if body == null:
		return
	var mine_xy := Wc3Coords.godot_to_wc3_xy(_mine.global_position)
	# 朝最近交货建筑外推排队（没有则朝农民来向）
	var host: Node = null
	if _get_unit_host.is_valid():
		host = _get_unit_host.call() as Node
	var hall := ReceiveResources.find_nearest_dropoff(
		host, mine_xy, _owner_id(body), int(ReceiveResources.Kind.GOLD)
	)
	if hall != null:
		var hall_xy := Wc3Coords.godot_to_wc3_xy(hall.global_position)
		_mine_rt.set_queue_outward_from_to(mine_xy, hall_xy)
	else:
		var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
		_mine_rt.set_queue_outward_from_to(mine_xy, from)


func _can_deposit_now(body: Node3D) -> bool:
	if body == null or _dropoff == null:
		return false
	# 优先：到达共享/车道交货点（可走），避免站进 pathTex 内交金后回矿失败
	if _dropoff_goal_wc3 != Vector2.INF:
		var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
		if cur.distance_to(_dropoff_goal_wc3) <= DROPOFF_GOAL_ARRIVE_WC3:
			return true
	if _dist_wc3(body, _dropoff) <= _deposit_accept_radius_wc3(_dropoff):
		return true
	return false


func _deposit_accept_radius_wc3(building: Node) -> float:
	return _footprint_half_wc3(building) + DROPOFF_MARGIN_WC3


func _resolve_dropoff() -> bool:
	# 采金循环：以矿为锚找主城，保证所有农民同一交货建筑
	if _mine_valid():
		return _resolve_dropoff_from_mine()
	var body := _body()
	if body == null:
		return false
	var host: Node = null
	if _get_unit_host.is_valid():
		host = _get_unit_host.call() as Node
	var owner_id := _owner_id(body)
	var mask: int = ReceiveResources.Kind.NONE
	if _carry_gold > 0:
		mask = mask | int(ReceiveResources.Kind.GOLD)
	if _carry_lumber > 0:
		mask = mask | int(ReceiveResources.Kind.LUMBER)
	if mask == int(ReceiveResources.Kind.NONE):
		mask = int(ReceiveResources.Kind.GOLD)
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	_dropoff = ReceiveResources.find_nearest_dropoff(host, from, owner_id, mask)
	return _dropoff != null


func _resolve_dropoff_from_mine() -> bool:
	if not _mine_valid():
		return false
	var host: Node = null
	if _get_unit_host.is_valid():
		host = _get_unit_host.call() as Node
	var body := _body()
	var owner_id := _owner_id(body) if body != null else 0
	var mine_xy := Wc3Coords.godot_to_wc3_xy(_mine.global_position)
	_dropoff = ReceiveResources.find_nearest_dropoff(
		host, mine_xy, owner_id, int(ReceiveResources.Kind.GOLD)
	)
	return _dropoff != null


func _path_to_approach(body: Node3D, target: Node3D) -> bool:
	if body == null or target == null:
		return false
	var goal := _compute_approach_goal(body, target)
	return _go_to_wc3(goal)


func _compute_approach_goal(body: Node3D, target: Node3D) -> Vector2:
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	var center := Wc3Coords.godot_to_wc3_xy(target.global_position)
	var radius := _building_radius_wc3(target)
	var pq := _path_query()
	if pq != null and pq.has_method("approach_point_wc3"):
		var snap: Dictionary = pq.call(
			"approach_point_wc3", from, center, radius, 48.0, 16
		)
		if bool(snap.get("ok", false)):
			return snap["wc3"] as Vector2
	var delta := from - center
	if delta.length_squared() < 1.0:
		delta = Vector2(0.0, -1.0)
	return center + delta.normalized() * (radius + 48.0)


func _go_to_wc3(goal: Vector2) -> bool:
	if not _ensure_navigator.is_valid():
		return false
	var body := _body()
	if body == null:
		return false
	var nav := _ensure_navigator.call(body) as UnitNavigator
	if nav == null:
		return false
	if _active:
		nav.set_harvest_ghost(true)
	return nav.go_to_wc3(goal)


func _path_query() -> PathQuery:
	if _get_path_query.is_valid():
		return _get_path_query.call() as PathQuery
	return null


func _building_radius_wc3(node: Node) -> float:
	if node == null:
		return DEFAULT_BUILDING_RADIUS_WC3
	var d: Dictionary = node.get_meta("unit_data", {})
	var tid := str(d.get("typeId", "")).strip_edges()
	if tid.is_empty():
		return DEFAULT_BUILDING_RADIUS_WC3
	Wc3DefStore.ensure_table(UnitBalanceDef.TABLE_NAME)
	var bal := Wc3DefStore.get_row(UnitBalanceDef.TABLE_NAME, tid) as UnitBalanceDef
	if bal != null and bal.collision > 0.0:
		return bal.collision
	return DEFAULT_BUILDING_RADIUS_WC3


func _nav() -> UnitNavigator:
	var body := _body()
	if body == null:
		return null
	return body.get_node_or_null("UnitNavigator") as UnitNavigator


func _body() -> Node3D:
	return get_parent() as Node3D


func _mine_valid() -> bool:
	return _mine != null and is_instance_valid(_mine) and _mine_rt != null and is_instance_valid(_mine_rt)


func _restore_visible() -> void:
	var body := _body()
	if body != null:
		body.visible = true


func _apply_carry_visual() -> void:
	var body := _body()
	if body == null:
		return
	var vis := body.get_node_or_null("UnitVisual") as UnitVisual
	if vis == null:
		return
	if _carry_gold > 0:
		vis.set_carry(UnitVisual.Carry.GOLD)
	elif _carry_lumber > 0:
		vis.set_carry(UnitVisual.Carry.LUMBER)
	else:
		vis.set_carry(UnitVisual.Carry.NONE)


func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)


func _load_ahar_params() -> void:
	Wc3DefStore.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := Wc3DefStore.get_row(AbilityDataDef.TABLE_NAME, "Ahar") as AbilityDataDef
	if ab == null:
		return
	# DataB1=单次负金量；Dur1/Rng1 偏伐木语义，进矿时长见 GoldMineRuntime.dwell_sec
	if ab.data_b1 > 0.0:
		_gold_per_trip = int(ab.data_b1)


func _dist_wc3(a: Node3D, b: Node3D) -> float:
	var aa := Wc3Coords.godot_to_wc3_xy(a.global_position)
	var bb := Wc3Coords.godot_to_wc3_xy(b.global_position)
	return aa.distance_to(bb)


static func _owner_id(node: Node) -> int:
	var d: Dictionary = node.get_meta("unit_data", {})
	return int(d.get("owner", 0))


static func is_peasant(node: Node) -> bool:
	if node == null:
		return false
	var d: Dictionary = node.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges() == WORKER_PEASANT
