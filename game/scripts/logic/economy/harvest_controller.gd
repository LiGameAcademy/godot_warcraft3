class_name HarvestController
extends Node

## 农民采集「订单 AI」：HarvestGold / HarvestLumber 自动循环。
## 金矿：进矿隐藏 → 出矿空位 → 交货。树木：站桩砍（Ahar.Dur1）→ 负木 → 交货。

signal state_changed(state: int)
## 负重变化：resource_id 见 CarrySlot（""=空）。
signal carry_changed(resource_id: String, amount: int)
signal deposited(gold: int, lumber: int)

enum State {
	IDLE = 0,
	MOVE_TO_MINE = 1,
	WAIT_IN_QUEUE = 2,
	IN_MINE = 3,
	MOVE_TO_DROPOFF = 4,
	MOVE_TO_TREE = 5,
	CHOPPING = 6,
}

const GOLD_MINE_TYPE := "ngol"
const WORKER_PEASANT := "hpea"
## 金矿贴边：路径 snap 后的放宽半径。
const ENTER_MINE_MAX_WC3 := 280.0
const QUEUE_SLOT_ARRIVE_WC3 := 48.0
## 到达个人交货点即交金。
const DROPOFF_GOAL_ARRIVE_WC3 := 72.0
## 主城 collision 外余量（勿用 pathTex 半宽，否则交货点离城太远）。
const DROPOFF_APPROACH_MARGIN_WC3 := 40.0
const DROPOFF_MARGIN_WC3 := 64.0
const DEFAULT_BUILDING_RADIUS_WC3 := 176.0
const MAX_DROPOFF_REPATH := 1
## 回矿途中寻路失败可重试；对齐 WC3：Harvest 订单持续，不因一次 path fail 中断。
const MAX_MINE_REPATH := 8
## 靠近出矿口/个人入矿点。
const MINE_PORTAL_ARRIVE_WC3 := 72.0
## 贴个人砍位即可开砍（勿用过大到达半径，否则离树很远也开砍）。
const TREE_GOAL_ARRIVE_WC3 := 40.0
## 环树站位：默认半径；实际用 min(此值, Ahar.Rng1*0.82)。
const TREE_STAND_RADIUS_WC3 := 96.0
const TREE_SLOT_ANGLE_DEG := 34.0
const TREE_MAX_REPATH := 3
## 贴树微抖超过该秒数：在射程内→当成功开砍；否则→改砍邻树。
const TREE_JITTER_SEC := 0.55
const TREE_JITTER_MOVE_EPS_WC3 := 14.0
## 出矿/接近点互斥间距（农民 collision≈16，略放宽）。
const SLOT_SEP_WC3 := 52.0
## 环树砍位间距：≥ 农民直径×2，站桩互斥。
const TREE_SLOT_SEP_WC3 := 80.0
const EXIT_LATERAL_STEP_WC3 := 40.0
const EXIT_ALONG_STEP_WC3 := 32.0

var _state: int = State.IDLE
var _mine: Node3D = null
var _mine_rt: GoldMineRuntime = null
## 伐木目标 creationNumber；-1 = 无
var _tree_cn: int = -1
var _dropoff: Node3D = null
## 右键指定的交货建筑（优先于自动最近搜索）。
var _forced_dropoff: Node3D = null
## 本趟个人交货接近点。
var _dropoff_goal_wc3: Vector2 = Vector2.INF
## 本趟出矿落点 / 回矿接近点。
var _mine_portal_wc3: Vector2 = Vector2.INF
## 本农民矿口候位（仅首趟散开 / 排队）。
var _wait_goal_wc3: Vector2 = Vector2.INF
## 本趟伐木接近点（防每帧重寻路）。
var _tree_goal_wc3: Vector2 = Vector2.INF
var _tree_repath_cooldown: float = 0.0
var _tree_repath_count: int = 0
## 处理 path_failed / 改砍时禁止同步再入（go_to 失败会立刻 emit）。
var _handling_tree_path_fail: bool = false
var _tree_jitter_sec: float = 0.0
var _tree_jitter_anchor_wc3: Vector2 = Vector2.INF
var _dropoff_repath: int = 0
var _mine_repath: int = 0
var _lane_index: int = 0
var _lane_count: int = GoldMineRuntime.DEFAULT_LANE_COUNT
## 首趟多选：先散开再进矿。
var _use_scatter_approach: bool = true
## 单一资源槽：类型 + 数量；采到异类时整槽替换（丢弃旧负重）。
var _carry: CarrySlot = CarrySlot.new()
var _dwell_left: float = 0.0
var _chop_left: float = 0.0
var _gold_per_trip: int = 10
## Ahar.DataB：木材容量（攒满再交货）。
var _lumber_capacity: int = 10
## Ahar.DataA：每击木材（=对树伤害）。
var _lumber_per_hit: int = 1
## Ahar.Dur1：每击间隔。
var _chop_sec: float = 1.1
## Ahar.DataA：对树伤害。
var _chop_damage: float = 1.0
## Ahar.Rng1：采集射程（须站进此距离才开砍）。
var _chop_range_wc3: float = 116.0
var _ensure_navigator: Callable = Callable()
var _get_stock: Callable = Callable()
var _get_unit_host: Callable = Callable()
var _get_path_query: Callable = Callable()
var _get_crowd: Callable = Callable()
var _get_tree_registry: Callable = Callable()
var _active: bool = false
var _mine_repath_cooldown: float = 0.0


func configure(
	ensure_navigator: Callable,
	get_stock: Callable,
	get_unit_host: Callable,
	get_path_query: Callable = Callable(),
	get_crowd: Callable = Callable(),
	get_tree_registry: Callable = Callable()
) -> void:
	_ensure_navigator = ensure_navigator
	_get_stock = get_stock
	_get_unit_host = get_unit_host
	_get_path_query = get_path_query
	_get_crowd = get_crowd
	_get_tree_registry = get_tree_registry
	_load_ahar_params()


func is_active() -> bool:
	return _active and _state != State.IDLE


func get_state() -> int:
	return _state


func carry_id() -> String:
	return "" if _carry.is_empty() else _carry.id


func carry_amount() -> int:
	return 0 if _carry.is_empty() else _carry.amount


func carry_gold() -> int:
	return _carry.gold()


func carry_lumber() -> int:
	return _carry.lumber()


func is_carrying() -> bool:
	return not _carry.is_empty()


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
	_interrupt_chop_stance()
	_release_tree_claim()
	_tree_cn = -1
	if mine != null and is_instance_valid(mine):
		_mine = mine
	if _mine == null or not is_instance_valid(_mine):
		return false
	if not GoldMineRuntime.is_gold_mine(_mine):
		return false
	_mine_rt = GoldMineRuntime.ensure(_mine)
	if _mine_rt == null:
		return false
	if _mine_rt.is_depleted():
		return false
	_lane_index = maxi(lane_index, 0)
	_lane_count = maxi(lane_count, 1)
	_mine_portal_wc3 = Vector2.INF
	_dropoff_goal_wc3 = Vector2.INF
	_wait_goal_wc3 = Vector2.INF
	_update_queue_direction()
	_cache_corridor_goals()
	_connect_mine_signals()
	_set_harvest_ghost(true)
	# 仅负同类（金）时先交货；负木不交货，出矿时 gather 丢弃旧木
	if _carry.id == CarrySlot.ID_GOLD and _carry.amount > 0:
		_use_scatter_approach = false
		_active = true
		_go_dropoff()
		return true
	_use_scatter_approach = true
	_active = true
	_set_state(State.MOVE_TO_MINE)
	return _go_mine_approach()


## 多选下令时的环树车道（在 start_harvest_lumber 前调用）。
func set_lumber_lanes(lane_index: int, lane_count: int) -> void:
	_lane_index = maxi(lane_index, 0)
	_lane_count = maxi(lane_count, 1)


## 开始伐木。先赴下令目标树；到不了交互位后再改砍邻树（贴近原作）。
func start_harvest_lumber(creation_number: int) -> bool:
	_load_ahar_params()
	var reg := _tree_registry()
	if reg == null or creation_number < 0:
		return false
	if not reg.is_alive(creation_number):
		return false
	# 打断金矿循环
	var body := _body()
	if _mine_rt != null and is_instance_valid(_mine_rt) and body != null:
		if _mine_rt.is_inside(body):
			_mine_rt.cancel_inside(body)
		else:
			_mine_rt.leave_queue(body)
		_disconnect_mine_signals()
	_mine = null
	_mine_rt = null
	# 重下伐木令：必须退出砍伐姿态，否则会边播 Attack Lumber 边走路/交货
	_interrupt_chop_stance()
	_release_tree_claim()
	# 勿在下令时 promote：MM hide 后若 GLB 姿态不对会像「树瞬间消失」
	_tree_goal_wc3 = Vector2.INF
	_tree_repath_cooldown = 0.0
	_tree_repath_count = 0
	_dropoff_goal_wc3 = Vector2.INF
	# 伐木不用采金幽灵：保留 soft 分离 + 占格，避免多人叠成一团
	_set_harvest_ghost(false)
	if body != null and _ensure_navigator.is_valid():
		_ensure_navigator.call(body)
	_wire_nav_path_failed(true)
	_active = true
	_tree_cn = creation_number
	_tree_jitter_sec = 0.0
	_tree_jitter_anchor_wc3 = Vector2.INF
	# 再点树：立刻去砍（负金/负木都不先交货；采到木时 gather 丢弃旧负重）
	# 原作：先绑定并走向下令树，不在寻路前因「没空位」改砍邻树
	_bind_ordered_tree_goal(body)
	_set_state(State.MOVE_TO_TREE)
	set_process(true)
	if body != null and _try_begin_chop_if_ready(body):
		return true
	# 接受伐木令：先赴下令树；到不了由 path_failed / approach 改砍邻树
	if _go_tree_approach():
		return true
	# 首趟失败且未能改砍 → 干净收工（勿留半激活状态像「拒单」）
	abort()
	return false


## 送回资源。preferred_dropoff：右键点中的主城/伐木场；null 则找最近可收建筑。
func start_return_goods(preferred_dropoff: Node3D = null) -> bool:
	if not is_carrying():
		return false
	_interrupt_chop_stance()
	_forced_dropoff = null
	if preferred_dropoff != null and is_instance_valid(preferred_dropoff):
		var mask := _carry.receive_mask()
		if mask != int(ReceiveResources.Kind.NONE) and ReceiveResources.can_receive(
			preferred_dropoff, mask
		):
			_forced_dropoff = preferred_dropoff
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
	_wire_nav_path_failed(false)
	_release_tree_claim()
	if not _active and _state == State.IDLE:
		_enter_world()
		return
	_active = false
	_dwell_left = 0.0
	_chop_left = 0.0
	_set_chop_visual(false)
	_tree_cn = -1
	_tree_goal_wc3 = Vector2.INF
	_tree_repath_cooldown = 0.0
	_tree_repath_count = 0
	_dropoff = null
	_forced_dropoff = null
	_dropoff_goal_wc3 = Vector2.INF
	_mine_portal_wc3 = Vector2.INF
	_wait_goal_wc3 = Vector2.INF
	_dropoff_repath = 0
	_mine_repath = 0
	_mine_repath_cooldown = 0.0
	_use_scatter_approach = true
	_enter_world()
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
	if _tree_repath_cooldown > 0.0:
		_tree_repath_cooldown = maxf(0.0, _tree_repath_cooldown - delta)
	match _state:
		State.MOVE_TO_MINE:
			_tick_move_to_mine()
		State.WAIT_IN_QUEUE:
			_tick_wait_in_queue()
		State.IN_MINE:
			_tick_in_mine(delta)
		State.MOVE_TO_DROPOFF:
			_tick_move_to_dropoff()
		State.MOVE_TO_TREE:
			_tick_move_to_tree(delta)
		State.CHOPPING:
			_tick_chopping(delta)
		_:
			set_process(false)


func _tick_move_to_mine() -> void:
	if not _mine_valid() or _mine_rt.is_depleted():
		abort()
		return
	var body := _body()
	if body == null:
		abort()
		return
	# 贴矿即可抢槽：矿里人出来时不必等导航停稳
	if _dist_wc3(body, _mine) <= ENTER_MINE_MAX_WC3:
		_connect_mine_signals()
		if _mine_rt.queue_index(body) < 0:
			_mine_rt.enqueue(body)
		if _mine_rt.try_enter(body):
			_mine_repath = 0
			_begin_inside_mine()
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
	# 运金循环：优先认个人入矿接近点
	if not _use_scatter_approach:
		if _mine_portal_wc3 != Vector2.INF:
			if cur.distance_to(_mine_portal_wc3) <= MINE_PORTAL_ARRIVE_WC3:
				return true
		return _dist_wc3(body, _mine) <= ENTER_MINE_MAX_WC3
	if _mine_portal_wc3 != Vector2.INF:
		if cur.distance_to(_mine_portal_wc3) <= MINE_PORTAL_ARRIVE_WC3:
			return true
	if _wait_goal_wc3 != Vector2.INF:
		if cur.distance_to(_wait_goal_wc3) <= QUEUE_SLOT_ARRIVE_WC3:
			return true
	# 已贴矿：允许进/排队（portal 已缓存时也要认，否则会空等在矿边）
	return _dist_wc3(body, _mine) <= ENTER_MINE_MAX_WC3


func _issue_mine_path(body: Node3D) -> bool:
	_ensure_walkable_start(body)
	# 首趟才散开；第一次送矿起一律走统一出矿门
	if _use_scatter_approach:
		return _path_to_wait_slot(body)
	return _path_to_mine_portal(body)


func _tick_wait_in_queue() -> void:
	if not _mine_valid() or _mine_rt.is_depleted():
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
	if not _dropoff_can_take():
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
	# 进矿：暂时移出游戏世界（不可见 / 不参与选择 / 不占寻路）
	if body != null:
		WorldMembership.exit(body)
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
	# 出矿写入金：异类负重整槽丢弃（如负木进矿）
	_carry.set_resource(CarrySlot.ID_GOLD, taken)
	# 先写上金袋（仍隐藏），显示时就已是负金外观
	if taken > 0:
		_apply_carry_visual(true)
	# 出矿：选朝主城、可贴矿、无占用的落点，再显示并去交货
	_place_at_free_mine_exit(body)
	_enter_world()
	_apply_carry_visual(true)
	_emit_carry_changed()
	if taken <= 0:
		# 矿空：停止采集循环
		_active = false
		_set_harvest_ghost(false)
		_set_state(State.IDLE)
		set_process(false)
		return
	_use_scatter_approach = false
	_dropoff_goal_wc3 = Vector2.INF
	_go_dropoff()
	_apply_carry_visual(true)


func _do_deposit() -> void:
	if not _dropoff_can_take():
		if not _resolve_dropoff():
			return
		_go_dropoff()
		return
	var body := _body()
	if body == null:
		return
	var nav := _nav()
	if nav != null:
		nav.stop()
	var stock: PlayerStock = null
	if _get_stock.is_valid():
		stock = _get_stock.call() as PlayerStock
	var deposited_amt := ReceiveResources.deposit(
		_dropoff, stock, _carry.gold(), _carry.lumber()
	)
	var g := int(deposited_amt.get("gold", 0))
	var l := int(deposited_amt.get("lumber", 0))
	_carry.clear()
	_forced_dropoff = null
	_dropoff_repath = 0
	_mine_repath = 0
	_use_scatter_approach = false
	_mine_portal_wc3 = Vector2.INF
	# 交货瞬间摘掉金袋（force + 0 blend）
	_apply_carry_visual(true)
	_emit_carry_changed()
	if g > 0 or l > 0:
		deposited.emit(g, l)
	if not _active:
		_set_harvest_ghost(false)
		_set_state(State.IDLE)
		set_process(false)
		return
	# 优先 resume 伐木，再 resume 采金
	var reg := _tree_registry()
	if _tree_cn >= 0 and reg != null:
		if not reg.is_alive(_tree_cn):
			# 原树已倒：交货后才换邻树
			_tree_cn = _resolve_tree_target(-1, -1)
		if _tree_cn >= 0 and reg.is_alive(_tree_cn):
			_ensure_walkable_start(body)
			_tree_repath_count = 0
			_tree_repath_cooldown = 0.0
			_tree_goal_wc3 = Vector2.INF
			_bind_ordered_tree_goal(body)
			_set_state(State.MOVE_TO_TREE)
			set_process(true)
			if _can_start_chop(body):
				_begin_chopping()
			else:
				_go_tree_approach()
			_apply_carry_visual(true)
			return
		_tree_cn = -1
	if _mine != null and is_instance_valid(_mine):
		_mine_rt = GoldMineRuntime.ensure(_mine)
		if _mine_rt == null or _mine_rt.is_depleted():
			_active = false
			_set_harvest_ghost(false)
			_set_state(State.IDLE)
			set_process(false)
			return
		_ensure_walkable_start(body)
		_set_state(State.MOVE_TO_MINE)
		set_process(true)
		if not _go_mine_approach():
			_mine_repath_cooldown = 0.15
		_apply_carry_visual(true)
		return
	_active = false
	_set_harvest_ghost(false)
	_set_state(State.IDLE)
	set_process(false)


func _go_mine_approach() -> bool:
	if not _mine_valid() or _mine_rt.is_depleted():
		return false
	_mine_rt = GoldMineRuntime.ensure(_mine)
	_connect_mine_signals()
	_update_queue_direction()
	if _mine_portal_wc3 == Vector2.INF or _wait_goal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	_set_state(State.MOVE_TO_MINE)
	set_process(true)
	var body := _body()
	if body == null:
		return false
	_ensure_walkable_start(body)
	# 首趟散开；之后找空闲入矿接近点
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


func _set_harvest_ghost(on: bool, keep_separation: bool = false) -> void:
	var nav := _nav()
	if nav != null and nav.has_method("set_harvest_ghost"):
		nav.call("set_harvest_ghost", on, keep_separation)
	elif nav != null:
		nav.enable_separation = (not on) or keep_separation


func _go_dropoff() -> void:
	if not _resolve_dropoff():
		abort()
		return
	# 确保有出矿参考点；交货点本趟现场算
	if _mine_portal_wc3 == Vector2.INF:
		_cache_corridor_goals()
	_dropoff_repath = 0
	_interrupt_chop_stance()
	_release_tree_claim()
	# 仅负金走幽灵走廊；负木保留分离
	_set_harvest_ghost(
		_carry.id == CarrySlot.ID_GOLD,
		_carry.id == CarrySlot.ID_LUMBER
	)
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
	# 固定出矿瞬移点（贴矿）；交货/回矿接近点本趟现场算
	var mine_half := _mine_rt.mine_radius_wc3()
	var hall_half := _footprint_half_wc3(_dropoff)
	var portals := _mine_rt.shared_corridor_portals(
		_dropoff, pq, mine_half, hall_half
	)
	if portals.is_empty():
		return
	_mine_portal_wc3 = portals.get("mine", wait_goal) as Vector2
	# 不在这里写死交货点，留给个人 approach


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
	## 回矿：找朝向自己一侧、空闲的入矿接近点。
	if body == null or not _mine_valid():
		return false
	var goal := _pick_free_approach_wc3(body, _mine)
	if goal == Vector2.INF:
		goal = _compute_approach_goal(body, _mine)
	_mine_portal_wc3 = goal
	return _go_to_wc3(goal)


func _place_at_free_mine_exit(body: Node3D) -> void:
	## 出矿：在矿外缘朝主城一侧，选可走且无其他单位占用的点。
	if body == null or not _mine_valid():
		return
	if _dropoff == null or not is_instance_valid(_dropoff):
		_resolve_dropoff_from_mine()
	var exit_pt := _pick_free_mine_exit_wc3(body)
	if exit_pt == Vector2.INF:
		# 兜底：走廊矿端（可能叠人，但保证能出）
		_cache_corridor_goals()
		exit_pt = _mine_portal_wc3
	if exit_pt == Vector2.INF:
		return
	_mine_portal_wc3 = exit_pt
	_place_at_wc3(body, exit_pt)


func _path_to_dropoff_approach(body: Node3D) -> bool:
	## 送矿：找主城侧空闲交货接近点。
	if body == null or _dropoff == null:
		return false
	var goal := _pick_free_approach_wc3(body, _dropoff)
	if goal == Vector2.INF:
		goal = _compute_approach_goal(body, _dropoff)
	_dropoff_goal_wc3 = goal
	return _go_to_wc3(goal)


func _pick_free_mine_exit_wc3(body: Node3D) -> Vector2:
	if not _mine_valid():
		return Vector2.INF
	var mine_xy := Wc3Coords.godot_to_wc3_xy(_mine.global_position)
	var hall_xy := mine_xy + Vector2(0.0, -400.0)
	if _dropoff != null and is_instance_valid(_dropoff):
		hall_xy = Wc3Coords.godot_to_wc3_xy(_dropoff.global_position)
	var to_hall := hall_xy - mine_xy
	if to_hall.length_squared() < 1.0:
		to_hall = Vector2(0.0, -1.0)
	var dir := to_hall.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var along0 := _mine_rt.mine_radius_wc3() + GoldMineRuntime.MINE_EXIT_MARGIN_WC3
	var pq := _path_query()
	var best := Vector2.INF
	var best_score := INF
	# 优先：更靠近主城（along 小、|lateral| 小），且可走、空闲
	for ring in range(0, 5):
		var along := along0 + float(ring) * EXIT_ALONG_STEP_WC3
		for lat_i in range(-5, 6):
			var lat := float(lat_i) * EXIT_LATERAL_STEP_WC3
			var raw := mine_xy + dir * along + perp * lat
			var p := _snap_walkable_wc3(raw)
			if p == Vector2.INF:
				continue
			if not _is_slot_free_wc3(p, body):
				continue
			# 分：距主城 + 横向惩罚（同距时偏中间）
			var score := p.distance_to(hall_xy) + absf(lat) * 0.2 + float(ring) * 8.0
			if score < best_score:
				best_score = score
				best = p
		if best != Vector2.INF and ring >= 1:
			break
	if best != Vector2.INF:
		return best
	# 放宽：只要可走（允许略挤）
	if pq != null and pq.has_method("snap_along_dir_walkable"):
		var sm: Dictionary = pq.call(
			"snap_along_dir_walkable", mine_xy, dir, along0, 16
		)
		if bool(sm.get("ok", false)):
			return sm["wc3"] as Vector2
	return Vector2.INF


func _pick_free_approach_wc3(body: Node3D, target: Node3D) -> Vector2:
	if body == null or target == null:
		return Vector2.INF
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	var center := Wc3Coords.godot_to_wc3_xy(target.global_position)
	# 交货/入矿都用 collision，不用 pathTex 半宽（主城 16x16 半宽≈256，会离城太远）
	var radius := _building_radius_wc3(target)
	if _mine_valid() and target == _mine:
		radius = _mine_rt.mine_radius_wc3()
	var delta := from - center
	if delta.length_squared() < 1.0:
		delta = Vector2(0.0, -1.0)
	var outward := delta.normalized()
	var perp := Vector2(-outward.y, outward.x)
	var margin := DROPOFF_APPROACH_MARGIN_WC3
	if _mine_valid() and target == _mine:
		margin = GoldMineRuntime.MINE_EXIT_MARGIN_WC3 + 24.0
	var along0 := maxf(radius, 32.0) + margin
	var best := Vector2.INF
	var best_score := INF
	for ring in range(0, 4):
		var along := along0 + float(ring) * EXIT_ALONG_STEP_WC3
		for lat_i in range(-4, 5):
			var lat := float(lat_i) * EXIT_LATERAL_STEP_WC3
			var raw := center + outward * along + perp * lat
			var p := _snap_walkable_wc3(raw)
			if p == Vector2.INF:
				continue
			if not _is_slot_free_wc3(p, body):
				continue
			# 偏向贴建筑 + 离自己近
			var score := (
				center.distance_to(p) * 1.2
				+ from.distance_to(p) * 0.35
				+ absf(lat) * 0.25
				+ float(ring) * 10.0
			)
			if score < best_score:
				best_score = score
				best = p
		if best != Vector2.INF:
			break
	if best != Vector2.INF:
		return best
	return _compute_approach_goal(body, target)


func _snap_walkable_wc3(raw: Vector2) -> Vector2:
	var pq := _path_query()
	if pq == null:
		return raw
	if pq.has_method("can_walk_wc3") and bool(pq.call("can_walk_wc3", raw.x, raw.y)):
		return raw
	if pq.has_method("snap_to_walkable"):
		var snap: Dictionary = pq.call("snap_to_walkable", raw.x, raw.y, 6)
		if bool(snap.get("ok", false)):
			return snap["wc3"] as Vector2
	return Vector2.INF


func _is_slot_free_wc3(pos_wc3: Vector2, body: Node3D) -> bool:
	var crowd := _crowd()
	if crowd == null:
		return true
	if crowd.has_method("is_slot_free"):
		return bool(crowd.call("is_slot_free", pos_wc3, body, SLOT_SEP_WC3))
	return true


func _crowd() -> UnitCrowdQuery:
	if _get_crowd.is_valid():
		return _get_crowd.call() as UnitCrowdQuery
	return null


func _on_mine_slot_available() -> void:
	if not _active:
		return
	# 候位中或仍在走近矿：矿空立刻抢（不必等导航停）
	if _state != State.WAIT_IN_QUEUE and _state != State.MOVE_TO_MINE:
		return
	var body := _body()
	if body == null or not _mine_valid():
		return
	if _dist_wc3(body, _mine) > ENTER_MINE_MAX_WC3:
		return
	if _mine_rt.queue_index(body) < 0:
		_mine_rt.enqueue(body)
	if _mine_rt.try_enter(body):
		_begin_inside_mine()


func _connect_mine_signals() -> void:
	if _mine_rt == null:
		return
	if not _mine_rt.slot_available.is_connected(_on_mine_slot_available):
		_mine_rt.slot_available.connect(_on_mine_slot_available)
	if not _mine_rt.depleted.is_connected(_on_mine_depleted):
		_mine_rt.depleted.connect(_on_mine_depleted)


func _disconnect_mine_signals() -> void:
	if _mine_rt == null or not is_instance_valid(_mine_rt):
		return
	if _mine_rt.slot_available.is_connected(_on_mine_slot_available):
		_mine_rt.slot_available.disconnect(_on_mine_slot_available)
	if _mine_rt.depleted.is_connected(_on_mine_depleted):
		_mine_rt.depleted.disconnect(_on_mine_depleted)


func _on_mine_depleted() -> void:
	# 刚掏空矿的人还在出矿/交货；只停候矿与走近矿的人。
	if _state == State.WAIT_IN_QUEUE or _state == State.MOVE_TO_MINE:
		abort()


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
	# 与接近点同用 collision，勿用 pathTex 半宽（否则「能交」圈离城过远）
	return _building_radius_wc3(building) + DROPOFF_MARGIN_WC3


func _dropoff_can_take() -> bool:
	if _dropoff == null or not is_instance_valid(_dropoff):
		return false
	var mask: int = _carry.receive_mask()
	if mask == int(ReceiveResources.Kind.NONE):
		mask = int(ReceiveResources.Kind.GOLD)
	return ReceiveResources.can_receive(_dropoff, mask)


func _resolve_dropoff() -> bool:
	var mask: int = _carry.receive_mask()
	if mask == int(ReceiveResources.Kind.NONE):
		mask = int(ReceiveResources.Kind.GOLD)
	# 右键指定的交货点优先（须能收当前负重）
	if _forced_dropoff != null and is_instance_valid(_forced_dropoff):
		if ReceiveResources.can_receive(_forced_dropoff, mask):
			_dropoff = _forced_dropoff
			return true
		_forced_dropoff = null
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
	var margin := DROPOFF_APPROACH_MARGIN_WC3
	if _mine_valid() and target == _mine:
		radius = _mine_rt.mine_radius_wc3()
		margin = GoldMineRuntime.MINE_EXIT_MARGIN_WC3 + 24.0
	var pq := _path_query()
	if pq != null and pq.has_method("approach_point_wc3"):
		var snap: Dictionary = pq.call(
			"approach_point_wc3", from, center, radius, margin, 16
		)
		if bool(snap.get("ok", false)):
			return snap["wc3"] as Vector2
	var delta := from - center
	if delta.length_squared() < 1.0:
		delta = Vector2(0.0, -1.0)
	return center + delta.normalized() * (radius + margin)


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


func _enter_world() -> void:
	WorldMembership.enter(_body())


func _emit_carry_changed() -> void:
	if _carry.is_empty():
		carry_changed.emit("", 0)
	else:
		carry_changed.emit(_carry.id, _carry.amount)


func _apply_carry_visual(force: bool = false) -> void:
	var body := _body()
	if body == null:
		return
	var vis := Unit.of(body)
	if vis == null:
		return
	var rid := "" if _carry.is_empty() else _carry.id
	match rid:
		CarrySlot.ID_GOLD:
			vis.set_carry(Unit.Carry.GOLD, force)
		CarrySlot.ID_LUMBER:
			vis.set_carry(Unit.Carry.LUMBER, force)
		_:
			vis.set_carry(Unit.Carry.NONE, force)


func _set_chop_visual(active: bool) -> void:
	var body := _body()
	if body == null:
		return
	var vis := Unit.of(body)
	if vis == null:
		return
	vis.set_chopping(active)


func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)


func _tick_move_to_tree(delta: float) -> void:
	var reg := _tree_registry()
	if reg == null:
		abort()
		return
	if _tree_cn < 0 or not reg.is_alive(_tree_cn):
		_tree_cn = _resolve_tree_target(-1, -1)
		_tree_repath_count = 0
		_tree_jitter_sec = 0.0
		if _tree_cn < 0:
			abort()
			return
	var body := _body()
	if body == null:
		abort()
		return
	# 进射程且贴个人砍位 → 站桩（先确保不与他人叠位）
	if _try_begin_chop_if_ready(body):
		_tree_jitter_sec = 0.0
		return
	# 贴树微抖：位移几乎为 0 持续超过阈值 → 射程内当成功，否则改砍
	if _update_tree_jitter(body, delta):
		return
	var nav := _nav()
	if nav != null and nav.is_moving():
		return
	# 导航已停但离砍位仍远：视为到不了 → 立刻改砍邻树（WC3 式）
	if _tree_goal_wc3 != Vector2.INF:
		var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
		if cur.distance_to(_tree_goal_wc3) > TREE_GOAL_ARRIVE_WC3 * 2.5:
			if _retarget_unreachable_tree():
				return
	if _tree_repath_cooldown > 0.0:
		return
	if _tree_repath_count >= TREE_MAX_REPATH:
		if _retarget_unreachable_tree():
			return
		if _try_begin_chop_if_ready(body):
			return
		abort()
		return
	if not _go_tree_approach():
		# path_failed 信号会改砍邻树；此处只冷却，避免双重 retarget 连跳两棵
		_tree_repath_cooldown = 0.25
		if _tree_repath_count >= TREE_MAX_REPATH:
			_retarget_unreachable_tree()


## 返回 true=本帧已处理（开砍或改砍）。
func _update_tree_jitter(body: Node3D, delta: float) -> bool:
	if body == null or delta <= 0.0:
		return false
	var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
	if _tree_jitter_anchor_wc3 == Vector2.INF:
		_tree_jitter_anchor_wc3 = cur
		_tree_jitter_sec = 0.0
		return false
	if cur.distance_to(_tree_jitter_anchor_wc3) > TREE_JITTER_MOVE_EPS_WC3:
		_tree_jitter_anchor_wc3 = cur
		_tree_jitter_sec = 0.0
		return false
	# 仅在树附近才累计（远处正常走不算抖）
	if _dist_to_tree_wc3(body) > _chop_range_wc3 * 1.35:
		_tree_jitter_sec = 0.0
		return false
	_tree_jitter_sec += delta
	if _tree_jitter_sec < TREE_JITTER_SEC:
		return false
	_tree_jitter_sec = 0.0
	_tree_jitter_anchor_wc3 = Vector2.INF
	var nav := _nav()
	if nav != null and nav.is_moving():
		nav.stop()
	if _dist_to_tree_wc3(body) <= _chop_range_wc3 + 24.0:
		# 成功：强制进入开砍互斥流程
		if _try_begin_chop_if_ready(body):
			return true
		# 射程内但互斥失败时 _try 可能已改砍/挪位
		return true
	return _retarget_unreachable_tree()


func _tick_chopping(delta: float) -> void:
	var reg := _tree_registry()
	if reg == null or _tree_cn < 0 or not reg.is_alive(_tree_cn):
		_set_chop_visual(false)
		if _carry.id == CarrySlot.ID_LUMBER and _carry.amount > 0:
			_go_dropoff()
		else:
			_tree_cn = _resolve_tree_target(-1, -1)
			if _tree_cn < 0:
				abort()
			else:
				_set_state(State.MOVE_TO_TREE)
				_tree_repath_cooldown = 0.0
				_tree_repath_count = 0
				_go_tree_approach()
		return
	_chop_left -= delta
	if _chop_left > 0.0:
		return
	# 一击：伤树 DataA + 攒木 DataA；满 DataB 才交货（原作多击满负荷）
	# gather：若此前负金，此处整槽替换为木（丢弃旧负重）
	reg.apply_damage(_tree_cn, _chop_damage, self)
	_carry.gather(CarrySlot.ID_LUMBER, _lumber_per_hit, _lumber_capacity)
	_apply_carry_visual(true)
	_emit_carry_changed()
	if _carry.is_full(_lumber_capacity):
		_set_chop_visual(false)
		_go_dropoff()
		return
	# 树被这击砍倒且未满负荷：有木就送，否则换树
	if not reg.is_alive(_tree_cn):
		_set_chop_visual(false)
		if _carry.id == CarrySlot.ID_LUMBER and _carry.amount > 0:
			_go_dropoff()
		else:
			_tree_cn = _resolve_tree_target(-1, -1)
			if _tree_cn < 0:
				abort()
			else:
				_set_state(State.MOVE_TO_TREE)
				_tree_repath_count = 0
				_go_tree_approach()
		return
	_chop_left = _chop_sec
	_set_chop_visual(true)


## 打断砍伐站桩（重下令 / 改采金 / 交货前）。
func _interrupt_chop_stance() -> void:
	_chop_left = 0.0
	_set_chop_visual(false)


## 到位且不叠人则开砍；叠人则先滑到空位或改砍邻树。
func _try_begin_chop_if_ready(body: Node3D) -> bool:
	if body == null or not _can_start_chop(body):
		return false
	var nav := _nav()
	if nav != null and nav.is_moving():
		nav.stop()
	if not _ensure_exclusive_chop_stance(body):
		return true  # 已改去空位/邻树，本帧勿再 approach
	_begin_chopping()
	return true


## 开砍站位互斥：当前位置被占则挪到同树空位；同树无空则改砍邻树。
func _ensure_exclusive_chop_stance(body: Node3D) -> bool:
	var reg := _tree_registry()
	if body == null or reg == null or _tree_cn < 0:
		return true
	var body_id := body.get_instance_id()
	var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
	if _is_tree_slot_free_wc3(cur, body, _tree_cn, body_id):
		reg.claim_chop_slot(_tree_cn, body_id, cur, TREE_SLOT_SEP_WC3)
		_tree_goal_wc3 = cur
		return true
	var free := _pick_tree_chop_slot(body, _tree_cn)
	if free != Vector2.INF:
		reg.claim_chop_slot(_tree_cn, body_id, free, TREE_SLOT_SEP_WC3)
		_tree_goal_wc3 = free
		_tree_repath_count = 0
		_tree_repath_cooldown = 0.0
		_set_state(State.MOVE_TO_TREE)
		_go_to_wc3(free)
		return false
	# 这棵树交互位已满 → 视为无法到达交互位置，改砍邻树
	_retarget_unreachable_tree()
	return false


func _begin_chopping() -> void:
	if _state == State.CHOPPING:
		return
	var nav := _nav()
	if nav != null:
		nav.stop()
	_chop_left = _chop_sec
	_set_state(State.CHOPPING)
	set_process(true)
	# 面向树（与 UnitNavigator 前进轴约定一致）
	var body := _body()
	var reg := _tree_registry()
	if body != null and reg != null and _tree_cn >= 0:
		var tp := reg.get_pos_wc3(_tree_cn)
		var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
		var dir := tp - from
		if dir.length_squared() > 1.0:
			body.rotation.y = atan2(dir.y, dir.x)
	# Attack Lumber（须在 nav.stop→Stand 之后）
	_set_chop_visual(true)


## 绑定下令树的接近点：优先互斥空位；没有也算几何接近点（先走过去）。
func _bind_ordered_tree_goal(body: Node3D) -> void:
	var reg := _tree_registry()
	if reg == null or _tree_cn < 0:
		return
	var slot := Vector2.INF
	if body != null:
		slot = _pick_tree_chop_slot(body, _tree_cn)
		if slot != Vector2.INF:
			reg.claim_chop_slot(_tree_cn, body.get_instance_id(), slot, TREE_SLOT_SEP_WC3)
		else:
			# 没空位：仍赴该树（原作先移动，到不了再换）
			slot = _pick_tree_approach_any(body, _tree_cn)
	_tree_goal_wc3 = slot


func _go_tree_approach() -> bool:
	var body := _body()
	var reg := _tree_registry()
	if body == null or reg == null or _tree_cn < 0:
		return false
	if _try_begin_chop_if_ready(body):
		return true
	var body_id := body.get_instance_id()
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	# 复用个人砍位；过远或被占再重选（仍只针对当前树，不提前换树）
	var goal := _tree_goal_wc3
	var need_new := goal == Vector2.INF or from.distance_to(goal) > _chop_range_wc3 * 1.8
	if not need_new and not _is_tree_slot_free_wc3(goal, body, _tree_cn, body_id):
		need_new = true
	if need_new:
		goal = _pick_tree_chop_slot(body, _tree_cn)
		if goal != Vector2.INF:
			reg.claim_chop_slot(_tree_cn, body_id, goal, TREE_SLOT_SEP_WC3)
		else:
			# 首趟可走几何点；若已尝试过仍无空位，交给失败/到位互斥逻辑改砍
			goal = _pick_tree_approach_any(body, _tree_cn)
		if goal == Vector2.INF:
			return false
		_tree_goal_wc3 = goal
	_tree_repath_count += 1
	_tree_repath_cooldown = 0.5
	if _go_to_wc3(goal):
		return true
	# go_to 失败会同步发 path_failed → 可能已改砍邻树；仍在伐木则算接受订单
	return _active and _state == State.MOVE_TO_TREE and _tree_cn >= 0


func _can_start_chop(body: Node3D) -> bool:
	if body == null:
		return false
	# 硬约束：必须在 Ahar.Rng1 内，禁止「远处开砍」
	if _dist_to_tree_wc3(body) > _chop_range_wc3 + 8.0:
		return false
	var cur := Wc3Coords.godot_to_wc3_xy(body.global_position)
	if _tree_goal_wc3 != Vector2.INF:
		if cur.distance_to(_tree_goal_wc3) <= TREE_GOAL_ARRIVE_WC3:
			return true
	return _dist_to_tree_wc3(body) <= _chop_range_wc3 * 0.92


func _dist_to_tree_wc3(body: Node3D) -> float:
	var reg := _tree_registry()
	if body == null or reg == null or _tree_cn < 0:
		return INF
	var tp := reg.get_pos_wc3(_tree_cn)
	if tp == Vector2.INF:
		return INF
	return Wc3Coords.godot_to_wc3_xy(body.global_position).distance_to(tp)


## 首选树有空位则用；否则附近可站位的活树。
## exclude_cn / exclude：到不了的树不再选。
func _resolve_tree_target(
	preferred_cn: int, exclude_cn: int = -1, exclude: Dictionary = {}
) -> int:
	var reg := _tree_registry()
	var body := _body()
	if reg == null or body == null:
		return -1
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	var body_id := body.get_instance_id()
	if (
		preferred_cn >= 0
		and preferred_cn != exclude_cn
		and not exclude.has(preferred_cn)
		and reg.is_alive(preferred_cn)
	):
		var slot0 := _pick_tree_chop_slot(body, preferred_cn)
		if slot0 != Vector2.INF and reg.claim_chop_slot(preferred_cn, body_id, slot0, TREE_SLOT_SEP_WC3):
			_tree_cn = preferred_cn
			_tree_goal_wc3 = slot0
			return preferred_cn
	var search_r := 900.0
	Wc3DefStore.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := Wc3DefStore.get_row(AbilityDataDef.TABLE_NAME, "Ahar") as AbilityDataDef
	if ab != null and ab.area1 > 0.0:
		search_r = ab.area1
	var candidates: Array[int] = reg.list_near_cn(from, search_r)
	for cn in candidates:
		var cni := int(cn)
		if cni == preferred_cn or cni == exclude_cn or exclude.has(cni):
			continue
		if not reg.is_alive(cni):
			continue
		var slot := _pick_tree_chop_slot(body, cni)
		if slot == Vector2.INF:
			continue
		if reg.claim_chop_slot(cni, body_id, slot, TREE_SLOT_SEP_WC3):
			_tree_cn = cni
			_tree_goal_wc3 = slot
			return cni
	# 无互斥空位：不再强行叠到同一点，停工或由上层 abort
	return -1


## 当前树到不了 → 排除后改砍邻树（可连试多棵）。成功则已发起 approach。
func _retarget_unreachable_tree() -> bool:
	var tried: Dictionary = {}
	if _tree_cn >= 0:
		tried[_tree_cn] = true
	_release_tree_claim()
	_set_state(State.MOVE_TO_TREE)
	set_process(true)
	# 改砍寻路时吞掉嵌套 path_failed，由本循环连试邻树
	var prev_handling := _handling_tree_path_fail
	_handling_tree_path_fail = true
	var ok := false
	for _i in range(6):
		var next := _resolve_tree_target(-1, -1, tried)
		if next < 0:
			break
		tried[next] = true
		_tree_cn = next
		_tree_repath_count = 0
		_tree_repath_cooldown = 0.0
		_tree_jitter_sec = 0.0
		_tree_jitter_anchor_wc3 = Vector2.INF
		# resolve 已 claim 并写好 goal；勿再 bind 成几何点冲掉空位
		if _go_tree_approach_quiet():
			ok = true
			break
		_release_tree_claim()
	_handling_tree_path_fail = prev_handling
	return ok


## 赴指定树（不触发改砍）；用于改砍循环内试路。
func _go_tree_approach_quiet() -> bool:
	var body := _body()
	var reg := _tree_registry()
	if body == null or reg == null or _tree_cn < 0:
		return false
	if _try_begin_chop_if_ready(body):
		return true
	var goal := _tree_goal_wc3
	if goal == Vector2.INF:
		goal = _pick_tree_approach_any(body, _tree_cn)
		_tree_goal_wc3 = goal
	if goal == Vector2.INF:
		return false
	_tree_repath_count += 1
	_tree_repath_cooldown = 0.5
	return _go_to_wc3(goal)


func _on_nav_path_failed(_reason: String) -> void:
	# 赴树途中失败 → 立刻改砍邻树（勿吞第一次 path_failed）
	if _handling_tree_path_fail:
		return
	if not _active or _state != State.MOVE_TO_TREE:
		return
	_handling_tree_path_fail = true
	var ok := _retarget_unreachable_tree()
	_handling_tree_path_fail = false
	if not ok:
		# 无邻树可改：结束伐木，避免空转
		abort()


func _wire_nav_path_failed(on: bool) -> void:
	var nav := _nav()
	if nav == null:
		return
	if on:
		if not nav.path_failed.is_connected(_on_nav_path_failed):
			nav.path_failed.connect(_on_nav_path_failed)
	elif nav.path_failed.is_connected(_on_nav_path_failed):
		nav.path_failed.disconnect(_on_nav_path_failed)


func _release_tree_claim() -> void:
	var reg := _tree_registry()
	var body := _body()
	if reg == null or body == null:
		return
	reg.release_chop_claims_for(body.get_instance_id())


## 环树扇形互斥站位（要求空位）。
func _pick_tree_chop_slot(body: Node3D, tree_cn: int) -> Vector2:
	return _pick_tree_ring_slot(body, tree_cn, true)


## 环树几何接近点（不检查空位；用于「先赴下令树」）。
func _pick_tree_approach_any(body: Node3D, tree_cn: int) -> Vector2:
	return _pick_tree_ring_slot(body, tree_cn, false)


func _pick_tree_ring_slot(body: Node3D, tree_cn: int, require_free: bool) -> Vector2:
	var reg := _tree_registry()
	if body == null or reg == null or tree_cn < 0:
		return Vector2.INF
	var center := reg.get_pos_wc3(tree_cn)
	if center == Vector2.INF:
		return Vector2.INF
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	var body_id := body.get_instance_id()
	var outward := from - center
	if outward.length_squared() < 1.0:
		outward = Vector2(0.0, -1.0)
	else:
		outward = outward.normalized()
	var base_ang := outward.angle()
	var n := maxi(_lane_count, 1)
	var mid := float(n - 1) * 0.5
	var lane_ang := base_ang + deg_to_rad(TREE_SLOT_ANGLE_DEG) * (float(_lane_index) - mid)
	var stand_r := minf(TREE_STAND_RADIUS_WC3, _chop_range_wc3 * 0.82)
	stand_r = maxf(stand_r, 64.0)
	var step := deg_to_rad(TREE_SLOT_ANGLE_DEG)
	var angles: Array[float] = [lane_ang]
	for i in range(1, 10):
		angles.append(lane_ang + step * float(i))
		angles.append(lane_ang - step * float(i))
	var best := Vector2.INF
	var best_score := INF
	for ring in range(0, 3):
		var r := stand_r + float(ring) * 20.0
		if r > _chop_range_wc3 - 4.0:
			break
		for ang in angles:
			var raw := center + Vector2(cos(ang), sin(ang)) * r
			var p := _snap_walkable_wc3(raw)
			if p == Vector2.INF:
				continue
			if center.distance_to(p) > _chop_range_wc3:
				continue
			if require_free and not _is_tree_slot_free_wc3(p, body, tree_cn, body_id):
				continue
			var score := (
				absf(angle_difference(ang, lane_ang)) * 40.0
				+ from.distance_to(p) * 0.25
				+ float(ring) * 12.0
			)
			if score < best_score:
				best_score = score
				best = p
		if best != Vector2.INF:
			break
	return best


func _is_tree_slot_free_wc3(
	pos_wc3: Vector2,
	body: Node3D,
	tree_cn: int = -1,
	body_id: int = 0
) -> bool:
	var reg := _tree_registry()
	if reg != null and tree_cn >= 0:
		if not reg.is_chop_slot_free(tree_cn, pos_wc3, body_id, TREE_SLOT_SEP_WC3):
			return false
	var crowd := _crowd()
	if crowd == null:
		return true
	if crowd.has_method("is_slot_free"):
		return bool(crowd.call("is_slot_free", pos_wc3, body, TREE_SLOT_SEP_WC3))
	return true


func _tree_registry() -> TreeRegistry:
	if _get_tree_registry.is_valid():
		return _get_tree_registry.call() as TreeRegistry
	return null


func _load_ahar_params() -> void:
	Wc3DefStore.ensure_table(AbilityDataDef.TABLE_NAME)
	var ab := Wc3DefStore.get_row(AbilityDataDef.TABLE_NAME, "Ahar") as AbilityDataDef
	if ab == null:
		return
	# Ahar：DataA=对树伤害(=每击木材) DataB=木材容量 DataC=金子容量 Dur1=每击间隔 Rng1=射程
	if ab.data_a1 > 0.0:
		_chop_damage = ab.data_a1
		_lumber_per_hit = maxi(1, int(round(ab.data_a1)))
	if ab.data_b1 > 0.0:
		_lumber_capacity = maxi(1, int(round(ab.data_b1)))
	if ab.data_c1 > 0.0:
		_gold_per_trip = maxi(1, int(round(ab.data_c1)))
	if ab.dur1 > 0.0:
		_chop_sec = ab.dur1
	if ab.rng1 > 0.0:
		_chop_range_wc3 = ab.rng1


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
