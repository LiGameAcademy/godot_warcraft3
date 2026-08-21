class_name UnitAI
extends Node

## 单位微观自主决策（Game Logic · ai）。
## 只决定「该不该打谁」；追击/出手/扣血交给 AttackController / DamagePipeline。
## U1：受击反击；U2：idle 在 acquire 内警戒索敌。
##
## 挂载：单位 Node3D 子节点（与 AttackController 同构）。默认仅可战斗单位；
## 采集循环不在本组件——见 HarvestController（订单执行层）。
##
## 后置接口（本阶段空实现 / 恒等，勿删）：营地 camp_id、睡眠/苏醒、昼夜 aggro 倍率。

signal state_changed(state: int)
signal profile_changed(profile: int)
signal sleep_changed(asleep: bool)
signal camp_bound(camp_id: StringName)

const NODE_NAME := "UnitAI"
## 与 CommandRouter.META_ORDER_QUEUE 同键（避免 ai → command 硬依赖）。
const META_ORDER_QUEUE := "order_queue"
## idle 索敌节流（秒）；约 6–7Hz，避免全图每帧扫。
const ACQUIRE_INTERVAL_SEC := 0.15

enum Profile {
	PASSIVE = 0, ## 不主动索敌、默认不反击（小动物等）
	CAMP_CREEP = 1, ## 中立野怪：受击反击 + idle acquire（U1/U2）
	PLAYER_MILITARY = 2, ## P1：闲置士兵同构警戒
}

enum State {
	IDLE = 0, ## 可听受击 / 可索敌
	ENGAGED = 1, ## 已把进攻意图交给 AttackController
	RETURNING = 2, ## P1：回锚点
	SLEEPING = 3, ## 夜间睡觉（后置；醒着时不用此态）
}

var _profile: int = Profile.PASSIVE
var _state: int = State.IDLE
## 生成时锚点（WC3 XY）；P1 leash / 回营用。
var home_wc3: Vector2 = Vector2.INF
## 所属营地（空 = 未入营）。全图 camp 表后置写入；助攻/leash 读此 id。
var camp_id: StringName = &""
## Callable() -> bool：当前是否被玩家（或非 UNIT_AI）订单占用。
var _is_player_occupied: Callable = Callable()
## Callable(unit: Node3D) -> AttackController；U1+ 发 Attack 时 ensure。
var _ensure_attack: Callable = Callable()
## Callable() -> Node：单位宿主（索敌扫子树）；U2 用。
var _unit_host: Callable = Callable()
## Callable() -> float：昼夜等对 acquire 的倍率（默认视作 1.0）。
var _aggro_range_mult: Callable = Callable()
## AI 是否持有当前进攻意图（与 AttackController.is_active 解耦，便于 yield）。
var _owns_engagement: bool = false
## 是否处于睡眠表现/逻辑（可与 State.SLEEPING 同步；后置规则写入）。
var _asleep: bool = false
## 为 true 时 `notify_time_of_day` 才会改睡眠态（未接昼夜系统前保持 false）。
var sleep_rules_enabled: bool = false
var _acquire_cd: float = 0.0


func configure(
	is_player_occupied: Callable = Callable(),
	ensure_attack: Callable = Callable(),
	unit_host: Callable = Callable(),
	aggro_range_mult: Callable = Callable()
) -> void:
	_is_player_occupied = is_player_occupied
	_ensure_attack = ensure_attack
	_unit_host = unit_host
	_aggro_range_mult = aggro_range_mult
	_refresh_process()


## 从单位根取已挂的 UnitAI（无则 null）。
static func of(body: Node) -> UnitAI:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(NODE_NAME) as UnitAI


## 按 owner / 武器选默认 Profile（入场 ensure 用；U0-2 接线）。
static func default_profile_for(body: Node) -> int:
	if body == null or not CombatQuery.has_weapon(body):
		return Profile.PASSIVE
	if CombatQuery.is_neutral_owner(CombatQuery.owner_of(body)):
		return Profile.CAMP_CREEP
	return Profile.PASSIVE


func get_profile() -> int:
	return _profile


func set_profile(profile: int) -> void:
	if _profile == profile:
		return
	_profile = profile
	profile_changed.emit(profile)
	_refresh_process()


func get_state() -> int:
	return _state


func is_engaged() -> bool:
	return _state == State.ENGAGED and _owns_engagement


## Profile 是否允许受击反击（U1）。睡觉中仍可 true——伤害应能叫醒（见 try_wake）。
func wants_retaliate() -> bool:
	return _profile_retaliates()


## Profile 是否允许 idle 警戒索敌（U2）；睡觉时 false。
func wants_idle_acquire() -> bool:
	return _profile_idle_acquires() and not is_asleep()


func captures_home_from_body() -> void:
	var body := _body()
	if body == null:
		return
	home_wc3 = Wc3Coords.godot_to_wc3_xy(body.global_position)


## 绑定营地。`home` 非 INF 时同时更新锚点。Camp 注册表后置实现。
func bind_camp(id: StringName, home: Vector2 = Vector2.INF) -> void:
	var changed := camp_id != id
	camp_id = id
	if home != Vector2.INF:
		home_wc3 = home
	if changed:
		camp_bound.emit(camp_id)


func clear_camp() -> void:
	bind_camp(&"")


func has_camp() -> bool:
	return camp_id != &""


## 有效索敌半径 = 武器 acquire × 昼夜倍率（后置注入 `_aggro_range_mult`）。
func effective_acquire_range_wc3() -> float:
	var body := _body()
	if body == null:
		return 0.0
	return CombatQuery.acquire_range_wc3(body) * _aggro_mult()


func is_asleep() -> bool:
	return _asleep or _state == State.SLEEPING


## 数据层：单位是否允许睡眠（UnitData.canSleep）。无表则 false。
func can_sleep_by_data() -> bool:
	var body := _body()
	if body == null:
		return false
	var tid := CombatQuery.type_id_of(body)
	if tid.is_empty():
		return false
	var store := _def_store()
	if store == null:
		return false
	store.ensure_table(UnitDataDef.TABLE_NAME)
	var row := store.get_row(UnitDataDef.TABLE_NAME, tid) as UnitDataDef
	return row != null and row.can_sleep


## 强制设睡眠（测试 / 后置昼夜控制器）。会清 AI 进攻意图。
func set_asleep(asleep: bool) -> void:
	var was := is_asleep()
	_asleep = asleep
	if asleep:
		_owns_engagement = false
		_set_state(State.SLEEPING)
	elif _state == State.SLEEPING:
		_set_state(State.IDLE)
	if was != is_asleep():
		sleep_changed.emit(is_asleep())
	_refresh_process()


## 昼夜时钟入口。未 `sleep_rules_enabled` 时 no-op，避免未接环境系统时误睡。
func notify_time_of_day(is_day: bool) -> void:
	if not sleep_rules_enabled:
		return
	if not can_sleep_by_data():
		if is_asleep():
			set_asleep(false)
		return
	# 夜间睡、白天醒（WC3 中立常见）；细则后置可改。
	set_asleep(not is_day)


## 受击/助攻叫醒。返回是否从睡→醒。
func try_wake() -> bool:
	if not is_asleep():
		return false
	set_asleep(false)
	return true


## 同营友方接敌（助攻入口，后置）。P0 no-op。
func notify_camp_ally_engaged(_target: Node3D) -> void:
	pass


## 玩家（或其它非 AI）命令占用单位：清 AI 意图。Router abort Attack 仍由命令层负责。
func yield_to_player() -> void:
	_owns_engagement = false
	_acquire_cd = 0.0
	if _state == State.SLEEPING:
		_refresh_process()
		return
	_set_state(State.IDLE)
	_refresh_process()


## 对目标发起 AI 进攻（U1/U2 共用入口）。
func try_engage(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _player_occupied():
		return false
	return _issue_ai_attack(target)


## 受击反击（U1）：合法敌对来源 → Attack Order（source=UNIT_AI）。
func notify_damaged(result: Dictionary) -> void:
	if result.is_empty() or not bool(result.get("ok", false)):
		return
	var body := _body()
	if body == null or not WorldMembership.is_in_world(body):
		return
	if _life_of(body) <= 0.0:
		return
	try_wake()
	if not _profile_retaliates():
		return
	if _player_occupied():
		return
	var attacker: Node3D = result.get("attacker") as Node3D
	if attacker == null or not is_instance_valid(attacker):
		return
	if not CombatQuery.is_auto_acquire_target(body, attacker):
		return
	try_engage(attacker)


func _ready() -> void:
	_refresh_process()


func _process(delta: float) -> void:
	if _owns_engagement:
		_tick_engaged()
		return
	if not wants_idle_acquire():
		return
	if _player_occupied():
		return
	_acquire_cd -= delta
	if _acquire_cd > 0.0:
		return
	_acquire_cd = ACQUIRE_INTERVAL_SEC
	_tick_idle_acquire()


func _tick_idle_acquire() -> void:
	var body := _body()
	if body == null or not WorldMembership.is_in_world(body):
		return
	if not CombatQuery.has_weapon(body):
		return
	if not _unit_host.is_valid():
		return
	var host: Node = _unit_host.call() as Node
	if host == null:
		return
	var target := CombatQuery.find_acquire_target(body, host, effective_acquire_range_wc3())
	if target == null:
		return
	_issue_ai_attack(target)


func _tick_engaged() -> void:
	if _player_occupied():
		# 玩家已占单：意图让出（Attack 取消由 Router 负责）
		_owns_engagement = false
		if _state != State.SLEEPING:
			_set_state(State.IDLE)
		_refresh_process()
		return
	var ac := _attack_controller()
	if ac == null or not _ac_is_active(ac):
		_owns_engagement = false
		_clear_ai_order_if_ours()
		if _state != State.SLEEPING:
			_set_state(State.IDLE)
		_refresh_process()
		return


## 对目标发 AI Attack；成功则 ENGAGED。
func _issue_ai_attack(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _player_occupied():
		return false
	var body := _body()
	if body == null:
		return false
	if not CombatQuery.is_auto_acquire_target(body, target):
		return false
	var ac := _resolve_attack_controller()
	if ac == null:
		return false
	# Mode.ATTACK == 1；用字面量避免测试桩强依赖 AttackController 编译序
	if _ac_get_mode(ac) == 1 and _ac_get_target(ac) == target:
		_mark_engaged()
		_write_ai_attack_order(target)
		return true
	if not _ac_start_attack(ac, target):
		return false
	_write_ai_attack_order(target)
	_mark_engaged()
	return true


func _write_ai_attack_order(target: Node3D) -> void:
	var body := _body()
	if body == null or target == null:
		return
	var q: OrderQueue
	if body.has_meta(META_ORDER_QUEUE):
		var raw: Variant = body.get_meta(META_ORDER_QUEUE)
		q = raw as OrderQueue
	if q == null:
		q = OrderQueue.new()
		body.set_meta(META_ORDER_QUEUE, q)
	q.set_current(UnitOrder.attack(target, UnitOrder.Source.UNIT_AI))


func _clear_ai_order_if_ours() -> void:
	var body := _body()
	if body == null or not body.has_meta(META_ORDER_QUEUE):
		return
	var q := body.get_meta(META_ORDER_QUEUE) as OrderQueue
	if q == null or q.current == null:
		return
	if q.current.source == UnitOrder.Source.UNIT_AI:
		q.clear()


func _resolve_attack_controller() -> Node:
	var existing := _attack_controller()
	if existing != null:
		return existing
	if not _ensure_attack.is_valid():
		return null
	var body := _body()
	if body == null:
		return null
	return _ensure_attack.call(body) as Node


func _attack_controller() -> Node:
	var body := _body()
	if body == null:
		return null
	return body.get_node_or_null("AttackController")


func _ac_start_attack(ac: Node, target: Node3D) -> bool:
	if ac == null or not ac.has_method("start_attack"):
		return false
	return bool(ac.call("start_attack", target))


func _ac_get_mode(ac: Node) -> int:
	if ac != null and ac.has_method("get_mode"):
		return int(ac.call("get_mode"))
	return 0


func _ac_get_target(ac: Node) -> Node3D:
	if ac != null and ac.has_method("get_target"):
		return ac.call("get_target") as Node3D
	return null


func _ac_is_active(ac: Node) -> bool:
	if ac != null and ac.has_method("is_active"):
		return bool(ac.call("is_active"))
	return false


func _refresh_process() -> void:
	set_process(wants_idle_acquire() or _owns_engagement)


func _profile_retaliates() -> bool:
	return _profile == Profile.CAMP_CREEP or _profile == Profile.PLAYER_MILITARY


func _profile_idle_acquires() -> bool:
	return _profile == Profile.CAMP_CREEP or _profile == Profile.PLAYER_MILITARY


func _player_occupied() -> bool:
	if _is_player_occupied.is_valid():
		return bool(_is_player_occupied.call())
	return false


func _aggro_mult() -> float:
	if _aggro_range_mult.is_valid():
		return maxf(float(_aggro_range_mult.call()), 0.0)
	return 1.0


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)


func _body() -> Node3D:
	return get_parent() as Node3D


## 读 life meta；未 ensure 时视为仍存活（入场由 Director 写 UnitLife）。
func _life_of(body: Node3D) -> float:
	if body == null:
		return 0.0
	if body.has_meta("life"):
		return float(body.get_meta("life"))
	return 1.0


## U1+ 内部：标记 AI 持有进攻意图（发令成功后调用）。
func _mark_engaged() -> void:
	_owns_engagement = true
	_asleep = false
	_set_state(State.ENGAGED)
	_refresh_process()
