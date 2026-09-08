class_name UnitAI
extends Node

## 单位微观自主决策（Game Logic · ai）。
## 只决定「该不该打谁」；追击/出手/扣血交给 AttackController / DamagePipeline。
## U1：受击反击；U2：idle 在 acquire 内警戒索敌；U4：CAMP_CREEP leash 归巢。
##
## 挂载：单位 Node3D 子节点（与 AttackController 同构）。默认仅可战斗单位；
## 采集循环不在本组件——见 HarvestController（订单执行层）。
##
## 后置接口（本阶段空实现 / 恒等，勿删）：营地 camp 表助攻、睡眠/苏醒、昼夜 aggro 倍率。

signal state_changed(state: int)
signal profile_changed(profile: int)
signal sleep_changed(asleep: bool)
signal camp_bound(camp_id: StringName)

const NODE_NAME := "UnitAI"
## 与 CommandRouter.META_ORDER_QUEUE 同键（避免 ai → command 硬依赖）。
const META_ORDER_QUEUE := "order_queue"
## idle 索敌节流（秒）；约 6–7Hz，避免全图每帧扫。
const ACQUIRE_INTERVAL_SEC := 0.15
## 默认追击上限（WC3 单位）；超出锚点则停攻回巢。竖切 800～1200。
const DEFAULT_LEASH_WC3 := 1000.0
## 回到锚点附近视为归巢完成。
const HOME_ARRIVE_WC3 := 64.0
## 仇恨表：受击加仇恨值；候选目标基础值（idle acquire 写入）。
const THREAT_PER_DAMAGE := 1.0
const THREAT_BASE_ACQUIRE := 0.1
## 仇恨每秒衰减（WC3 经典值 0.3）；≥0 时启用衰减。
const THREAT_DECAY_PER_SEC := 0.3
## 仇恨表 / 当前目标的"保留窗口"（秒）：上次 acquire 失败 / 脱离范围后多久允许重选同一目标。
## 防「刚脱离 1 帧又立刻选回来」的反复横跳。
const TARGET_HOLD_SEC := 1.5
## 切目标最小冷却（秒）：新目标锁定后短时间内不切。
const TARGET_SWAP_COOLDOWN_SEC := 0.25

enum Profile {
	PASSIVE = 0, ## 不主动索敌、默认不反击（小动物等）
	CAMP_CREEP = 1, ## 中立野怪：受击反击 + idle acquire + leash + 营地助攻
	TEAM_PLAYER = 2, ## 玩家军事单位：受击反击 + idle acquire + 盟友挨打参战（同 team_id）。
		## 与原 PLAYER_MILITARY 等价；保留别名 [member PLAYER_MILITARY]。
	REACTIVE = 3, ## 反应型（玩家辅助单位）：受击反击 + 盟友广播可拉；不主动 idle acquire。
	PLAYER_MILITARY = 2, ## 向后别名；新代码请用 TEAM_PLAYER
}

enum State {
	IDLE = 0, ## 可听受击 / 可索敌
	ENGAGED = 1, ## 已把进攻意图交给 AttackController
	RETURNING = 2, ## 超 leash 后回锚点
	SLEEPING = 3, ## 夜间睡觉（后置；醒着时不用此态）
}

var _profile: int = Profile.PASSIVE
var _state: int = State.IDLE
## 生成时锚点（WC3 XY）；leash / 回营用。
var home_wc3: Vector2 = Vector2.INF
## 追击半径（距 home）；≤0 关闭 leash。
var leash_wc3: float = DEFAULT_LEASH_WC3
## 所属营地（空 = 未入营）。全图 camp 表后置写入；助攻读此 id。
var camp_id: StringName = &""
## Callable() -> bool：当前是否被玩家（或非 UNIT_AI）订单占用。
var _is_player_occupied: Callable = Callable()
## Callable(unit: Node3D) -> AttackController；U1+ 发 Attack 时 ensure。
var _ensure_attack: Callable = Callable()
## Callable(unit: Node3D) -> UnitNavigator；归巢走位。
var _ensure_navigator: Callable = Callable()
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
## 仇恨表：attacker instance_id → 仇恨值。仅记录对此单位有威胁的敌对 Node3D。
## 写入：受击 (`add_threat`) + idle acquire 候选（基础值 0.1）。
## 衰减：每帧按 THREAT_DECAY_PER_SEC 衰减；≤0 移除。
var _threat: Dictionary = {}
## 切目标冷却：上次 _pick_target / try_engage 成功后到现在的秒数。
## 防 acquire 抖动——刚换目标 0.25s 内不让再切（除非受击反击强制）。
var _swap_cd: float = 0.0
## 当前锁定目标（最近一次 `_pick_target` 选定）。用于「sticky」语义：
## 只要这个目标还存活且仍敌对，就不重新 acquire。
var _locked_target: Node3D = null
## 锁定时刻（msec 时间戳）；超 TARGET_HOLD_SEC 后允许被新候选覆盖。
var _locked_at_msec: int = 0


func configure(
	is_player_occupied: Callable = Callable(),
	ensure_attack: Callable = Callable(),
	unit_host: Callable = Callable(),
	aggro_range_mult: Callable = Callable(),
	ensure_navigator: Callable = Callable()
) -> void:
	_is_player_occupied = is_player_occupied
	_ensure_attack = ensure_attack
	_unit_host = unit_host
	_aggro_range_mult = aggro_range_mult
	_ensure_navigator = ensure_navigator
	_refresh_process()


## 从单位根取已挂的 UnitAI（无则 null）。
static func of(body: Node) -> UnitAI:
	if body == null or not is_instance_valid(body):
		return null
	return body.get_node_or_null(NODE_NAME) as UnitAI


## 按 owner / 武器选默认 Profile（入场 ensure 用；U0-2 接线）。
## - 中立可战斗 → CAMP_CREEP（营地 leash / 营友助攻）。
## - 玩家可战斗 → REACTIVE（受击反击 + 盟友广播可拉；不 idle acquire 避免抢玩家命令）。
## - 其它 → PASSIVE。
## 注：TEAMPlayer 待补「玩家显式命令时压制 idle acquire」边界后再切默认；见 UNIT_AI.md §4.4 / §4.2c。
static func default_profile_for(body: Node) -> int:
	if body == null or not CombatQuery.has_weapon(body):
		return Profile.PASSIVE
	if CombatQuery.is_neutral_owner(CombatQuery.owner_of(body)):
		return Profile.CAMP_CREEP
	return Profile.REACTIVE


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


## Profile 是否允许 idle 警戒索敌（U2）；睡觉 / 归巢途中 false。
func wants_idle_acquire() -> bool:
	return _profile_idle_acquires() and not is_asleep() and _state != State.RETURNING


## 是否允许「盟友挨打」广播拉自己参战（CAMP_CREEP / TEAM_PLAYER / REACTIVE）。
## 仅在 IDLE 时被广播；玩家显式占用或正在 RETURNING 时不拉。
func allows_ally_engage() -> bool:
	if is_asleep():
		return false
	if _state == State.RETURNING:
		return false
	if _player_occupied():
		return false
	if _state == State.SLEEPING:
		return false
	return (
		_profile == Profile.CAMP_CREEP
		or _profile == Profile.TEAM_PLAYER
		or _profile == Profile.REACTIVE
	)


## 是否启用营地 leash（仅 CAMP_CREEP + 有效锚点 + leash>0）。
func uses_leash() -> bool:
	return (
		_profile == Profile.CAMP_CREEP
		and home_wc3 != Vector2.INF
		and leash_wc3 > 0.0
	)


## 当前距 home 是否已超 leash（供自测 / 调试）。
func is_beyond_leash() -> bool:
	return uses_leash() and _dist_from_home_wc3() > leash_wc3


## 自身 home 兜底：若已注册到营地（camp_id）则取 TeamRegistry.home_of；
## 否则退化为出生点（保留旧 UnitAI 行为）。
## 同时把 camp_id 写回 UnitAI.camp_id，便于后续 ThreatTable / 调试引用。
## 幂等：可由 _ensure_unit_ai（首挂时）和 _wire_all_unit_ai（cluster_and_bind 后）多次调用。
func captures_home_from_body() -> void:
	var body := _body()
	if body == null:
		return
	var reg := TeamRegistry.get_for(self)
	if reg != null:
		var gid := reg.group_of(body)
		if not gid.is_empty() and reg.is_camp(gid):
			var home := reg.home_of(gid)
			if home != Vector2.INF:
				home_wc3 = home
				camp_id = StringName(gid)
				if leash_wc3 <= 0.0 or leash_wc3 == DEFAULT_LEASH_WC3:
					leash_wc3 = TeamRegistry.CAMP_LEASH_WC3
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


## 同营/同团队友接敌：走 TeamRegistry.notify_ally_engaged 做统一广播。
## - 营地：全成员均可拉（营地即整队）。
## - 玩家 team：仅触发源已 ENGAGED / 受击时才拉，避免闲站自动接战。
## 不再按 owner 全图遍历——TeamRegistry 已按 group_id 索引。
const ALLY_ALERT_RADIUS_WC3 := TeamRegistry.ALLY_ALERT_RADIUS_WC3


func notify_camp_ally_engaged(attacker: Node3D) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	var body := _body()
	if body == null:
		return
	var reg := TeamRegistry.get_for(self)
	if reg == null:
		try_engage(attacker)
		return
	reg.notify_ally_engaged(body, attacker, ALLY_ALERT_RADIUS_WC3)


func _alert_nearby_allies(attacker: Node3D) -> void:
	# 旧 owner 全图遍历实现已被 TeamRegistry 取代；保留 stub 防外部旧调用。
	notify_camp_ally_engaged(attacker)


## 当前攻击目标死亡/离场（DeathService 广播）。脱战并归巢（leash）。
func notify_combat_target_lost(_dead: Node3D) -> void:
	if not _owns_engagement and _state != State.ENGAGED:
		return
	var ac := _attack_controller()
	if ac != null and _ac_is_active(ac):
		return
	_on_combat_ended()


## 玩家（或其它非 AI）命令占用单位：清 AI 意图。Router abort Attack 仍由命令层负责。
func yield_to_player() -> void:
	_owns_engagement = false
	_acquire_cd = 0.0
	if _state == State.SLEEPING:
		_refresh_process()
		return
	_set_state(State.IDLE)
	_refresh_process()


## 对目标发起 AI 进攻（U1/U2 共用入口）。归巢途中不接新仇恨。
func try_engage(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if _state == State.RETURNING:
		return false
	if _player_occupied():
		return false
	# 切目标冷却未到：仅当「当前锁定目标已死/失效」或「目标就是攻击者」才允许。
	# 受击反击已在外层清 swap_cd。
	if _swap_cd > 0.0 and target != _locked_target:
		var cur := _locked_target
		if cur != null and is_instance_valid(cur) and CombatQuery.is_auto_acquire_target(_body(), cur):
			return false
	var ok := _issue_ai_attack(target)
	if ok:
		# 锁定目标 + 切目标冷却：减少「acquire 来回横跳」
		_locked_target = target
		_locked_at_msec = Time.get_ticks_msec()
		_swap_cd = TARGET_SWAP_COOLDOWN_SEC
		# 基础仇恨写入（避免未被攻击的目标仇恨=0、下一拍 decay 后被踢出表）
		if not _threat.has(target.get_instance_id()):
			_threat[target.get_instance_id()] = THREAT_BASE_ACQUIRE
	return ok


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
	# 归巢途中不重新开打（WC3 脱战回营手感）
	if _state == State.RETURNING:
		return
	if not _profile_retaliates():
		return
	if _player_occupied():
		return
	var attacker: Node3D = result.get("attacker") as Node3D
	if attacker == null or not is_instance_valid(attacker):
		return
	if not CombatQuery.is_auto_acquire_target(body, attacker):
		return
	# 受击 → 加仇恨（受击伤害是仇恨的主要来源）
	var dmg := float(result.get("amount", 0.0))
	if dmg > 0.0:
		add_threat(attacker, dmg * THREAT_PER_DAMAGE)
	# 受击强制让仇恨表「拿主意」：清切目标冷却，立即可切回攻击者
	_swap_cd = 0.0
	try_engage(attacker)
	_alert_nearby_allies(attacker)


func _ready() -> void:
	_refresh_process()


func _process(delta: float) -> void:
	if _swap_cd > 0.0:
		_swap_cd -= delta
	if THREAT_DECAY_PER_SEC > 0.0:
		_decay_threat(delta)
	if _state == State.RETURNING:
		_tick_returning()
		return
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
	# 切目标冷却未到 → 跳过（防 acquire 抖动）
	if _swap_cd > 0.0:
		return
	var target := _pick_target(host)
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
	if is_beyond_leash():
		_begin_return()
		return
	var ac := _attack_controller()
	if ac == null or not _ac_is_active(ac):
		_on_combat_ended()
		return


func _on_combat_ended() -> void:
	_owns_engagement = false
	_clear_ai_order_if_ours()
	var nav := _navigator()
	if nav != null:
		_nav_stop(nav)
	var body := _body()
	if body != null and (wants_idle_acquire() or _profile_retaliates()):
		var host := body.get_parent()
		var acq := _pick_target(host)
		if acq != null and try_engage(acq):
			return
	if uses_leash() and not _is_at_home():
		_begin_return()
		return
	if _state != State.SLEEPING:
		_set_state(State.IDLE)
	_refresh_process()


func _tick_returning() -> void:
	if _player_occupied():
		_owns_engagement = false
		_set_state(State.IDLE)
		_refresh_process()
		return
	if _is_at_home():
		_finish_return()
		return
	var nav := _resolve_navigator()
	if nav == null:
		_finish_return()
		return
	if not _nav_is_moving(nav):
		_nav_go_home(nav)


func _begin_return() -> void:
	_owns_engagement = false
	var ac := _attack_controller()
	if ac != null:
		_ac_cancel(ac)
	_clear_ai_order_if_ours()
	if not uses_leash():
		if _state != State.SLEEPING:
			_set_state(State.IDLE)
		_refresh_process()
		return
	_write_ai_move_order(home_wc3)
	var nav := _resolve_navigator()
	_nav_go_home(nav)
	_set_state(State.RETURNING)
	_refresh_process()


func _finish_return() -> void:
	_owns_engagement = false
	_clear_ai_order_if_ours()
	var nav := _navigator()
	if nav != null:
		_nav_stop(nav)
	_acquire_cd = ACQUIRE_INTERVAL_SEC
	_set_state(State.IDLE)
	_refresh_process()


func _is_at_home() -> bool:
	if not uses_leash():
		return true
	return _dist_from_home_wc3() <= HOME_ARRIVE_WC3


func _dist_from_home_wc3() -> float:
	var body := _body()
	if body == null or home_wc3 == Vector2.INF:
		return 0.0
	return Wc3Coords.godot_to_wc3_xy(body.global_position).distance_to(home_wc3)


# ---------------------------------------------------------------------------
# 仇恨表（ThreatTable，U5）。
# 设计：
# - key = attacker Node3D instance_id；value = float 仇恨值。
# - 写入：受击伤害 (`add_threat`) + idle acquire 候选（THREAT_BASE_ACQUIRE）。
# - 衰减：每帧 -THREAT_DECAY_PER_SEC；≤0 移除（避免内存泄漏）。
# - 读取 (`top_threat`)：按仇恨排序，过滤掉已死 / 已脱敌对 / 已脱离 acquire 半径的。
# - 选目标 (`_pick_target`)：1) 当前锁定目标存活+敌对+半径内 → sticky 保留；
#   2) 否则取仇恨表 top；3) 仇恨表空 → 退到 `find_acquire_target`（最近）兜底。
# ---------------------------------------------------------------------------

func add_threat(attacker: Node3D, amount: float) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if amount <= 0.0:
		return
	var id := attacker.get_instance_id()
	_threat[id] = float(_threat.get(id, 0.0)) + amount


func clear_threat_for(target: Node3D) -> void:
	if target == null:
		return
	_threat.erase(target.get_instance_id())


## 取仇恨表里仇恨最高的「存活 + 敌对 + 在 acquire 半径内」的目标。无则 null。
## `host` 可为 null（仅做敌对 / 存活过滤，不做距离）。
func top_threat(host: Node = null) -> Node3D:
	var body := _body()
	if body == null or _threat.is_empty():
		return null
	var best: Node3D = null
	var best_v := -INF
	for id in _threat.keys():
		var n := instance_from_id(int(id)) as Node3D
		if n == null or not is_instance_valid(n):
			_threat.erase(id)
			continue
		if not CombatQuery.is_valid_attack_target(body, n):
			_threat.erase(id)
			continue
		var v := float(_threat[id])
		if v > best_v:
			best_v = v
			best = n
	return best


func _decay_threat(delta: float) -> void:
	if _threat.is_empty():
		return
	var step := THREAT_DECAY_PER_SEC * delta
	for id in _threat.keys():
		var v := float(_threat[id]) - step
		if v <= 0.0:
			_threat.erase(id)
		else:
			_threat[id] = v


## 选目标：sticky 锁定 → 仇恨表 top → find_acquire_target 最近（兜底）。
## `host` 用于 acquire 半径判断；为 null 时取 body.get_parent()。
func _pick_target(host: Node = null) -> Node3D:
	var body := _body()
	if body == null:
		return null
	if host == null:
		host = body.get_parent()
	if host == null:
		return null
	var now_msec := Time.get_ticks_msec()
	# 1) Sticky 锁定：当前 _locked_target 还活着 + 仍敌对 + 在 acquire 半径内 → 保留
	var cur := _locked_target
	if cur != null and is_instance_valid(cur):
		var stuck_ms := now_msec - _locked_at_msec
		if stuck_ms < int(TARGET_HOLD_SEC * 1000.0):
			if (
				CombatQuery.is_valid_attack_target(body, cur)
				and CombatQuery.distance_wc3(body, cur) <= effective_acquire_range_wc3()
			):
				return cur
			# 死亡 / 失效 / 跑出 → 清锁定
			_locked_target = null
			_threat.erase(cur.get_instance_id())
		else:
			# 锁定超时 → 清掉，让仇恨表重新选
			_locked_target = null
	# 2) 仇恨表 top
	var top := top_threat(host)
	if top != null:
		return top
	# 3) 兜底：按距离最近
	return CombatQuery.find_acquire_target(body, host, effective_acquire_range_wc3())


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
	var q := _order_queue(body)
	q.set_current(UnitOrder.attack(target, UnitOrder.Source.UNIT_AI))


func _write_ai_move_order(goal: Vector2) -> void:
	var body := _body()
	if body == null or goal == Vector2.INF:
		return
	var q := _order_queue(body)
	q.set_current(UnitOrder.move(goal, UnitOrder.Source.UNIT_AI))


func _order_queue(body: Node3D) -> OrderQueue:
	var q: OrderQueue
	if body.has_meta(META_ORDER_QUEUE):
		var raw: Variant = body.get_meta(META_ORDER_QUEUE)
		q = raw as OrderQueue
	if q == null:
		q = OrderQueue.new()
		body.set_meta(META_ORDER_QUEUE, q)
	return q


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


func _ac_cancel(ac: Node) -> void:
	if ac != null and ac.has_method("cancel"):
		ac.call("cancel")


func _resolve_navigator() -> Node:
	var existing := _navigator()
	if existing != null:
		return existing
	if not _ensure_navigator.is_valid():
		return null
	var body := _body()
	if body == null:
		return null
	return _ensure_navigator.call(body) as Node


func _navigator() -> Node:
	var body := _body()
	if body == null:
		return null
	return body.get_node_or_null("UnitNavigator")


func _nav_go_home(nav: Node) -> void:
	if nav == null or home_wc3 == Vector2.INF:
		return
	if nav.has_method("go_to_wc3"):
		nav.call("go_to_wc3", home_wc3)


func _nav_is_moving(nav: Node) -> bool:
	if nav != null and nav.has_method("is_moving"):
		return bool(nav.call("is_moving"))
	return false


func _nav_stop(nav: Node) -> void:
	if nav != null and nav.has_method("stop"):
		nav.call("stop")


func _refresh_process() -> void:
	set_process(wants_idle_acquire() or _owns_engagement or _state == State.RETURNING)


func _profile_retaliates() -> bool:
	return (
		_profile == Profile.CAMP_CREEP
		or _profile == Profile.TEAM_PLAYER
		or _profile == Profile.REACTIVE
	)


func _profile_idle_acquires() -> bool:
	return _profile == Profile.CAMP_CREEP or _profile == Profile.TEAM_PLAYER


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
