class_name AttackController
extends Node

## 攻击订单状态机（Logic）。Present 只订阅 strike_begun / 弹道壳；扣血走 DamagePipeline。
## 时序：进入射程 → WINDUP（播 Attack，等 dmgpt）→ instant 结算或 missile 出弹 → COOLDOWN。

signal state_changed(state: int)							## 状态改变信号
signal strike_begun(attacker: Node3D, target: Node3D)		## 攻击开始信号（windup 起点）
signal damage_applied(result: Dictionary)					## 伤害应用信号（瞬时伤或弹道命中）

## 状态
enum State {
	IDLE = 0,				## 空闲
	CHASE = 1,				## 追逐
	WINDUP = 2,				## 前摇（动画 + 等待伤害点）
	COOLDOWN = 3,			## 冷却（伤害点之后到下一击）
	MOVE_TO_GOAL = 4,		## 移动到目标
}

## 模式
enum Mode {
	NONE = 0,				## 无
	ATTACK = 1,				## 攻击
	ATTACK_MOVE = 2,		## 攻击移动
	HOLD = 3,				## 待命
}

var _state: int = State.IDLE								## 状态
var _mode: int = Mode.NONE									## 模式
var _target: Node3D = null									## 目标
var _goal_wc3: Vector2 = Vector2.INF						## 目标位置
var _cooldown_left: float = 0.0								## 距可再开一击的剩余时间
var _dmgpt_left: float = 0.0								## windup 内距伤害点剩余
var _repath_cd: float = 0.0									## 重新路径时间
var _ensure_navigator: Callable = Callable()				## 确保导航器
var _unit_host: Callable = Callable()						## 单位主机
var _pipeline: DamagePipeline = null						## 伤害管道
var _projectiles: ProjectileService = null					## 弹道服务（会话共享）
var _active: bool = false									## 是否活跃

## 配置
func configure(
	ensure_navigator: Callable,
	unit_host: Callable,
	pipeline: DamagePipeline,
	projectiles: ProjectileService = null
) -> void:
	_ensure_navigator = ensure_navigator
	_unit_host = unit_host
	_pipeline = pipeline
	_projectiles = projectiles

## 获取状态
func get_state() -> int:
	return _state


## 当前模式（ATTACK / ATTACK_MOVE / HOLD / NONE）。
func get_mode() -> int:
	return _mode


## 当前攻击目标（无则 null）。
func get_target() -> Node3D:
	return _target


## 是否活跃
func is_active() -> bool:
	return _active and _state != State.IDLE

## 取消
func cancel() -> void:
	var body := _body()
	if _projectiles != null and body != null:
		_projectiles.cancel_attacker(body)
	_active = false
	_mode = Mode.NONE
	_target = null
	_goal_wc3 = Vector2.INF
	_cooldown_left = 0.0
	_dmgpt_left = 0.0
	_set_state(State.IDLE)
	_set_attack_anim(false)
	var nav := _nav()
	if nav != null:
		nav.stop()

## 弹道命中后的结算转发（由会话层接 ProjectileService.projectile_resolved）。
func notify_strike_result(result: Dictionary) -> void:
	if result.is_empty() or bool(result.get("visual_only", false)):
		return
	damage_applied.emit(result)
	if not bool(result.get("killed", false)):
		return
	var killed: Node3D = result.get("target") as Node3D
	if killed != null and _target == killed:
		_target = null
		_set_attack_anim(false)
		if _mode == Mode.ATTACK:
			cancel()
		elif _mode == Mode.ATTACK_MOVE:
			_set_state(State.MOVE_TO_GOAL)
			_path_to_goal()
		elif _mode == Mode.HOLD:
			_set_state(State.IDLE)

## 通知目标死亡
func notify_target_died(dead: Node3D) -> void:
	if dead != null and _target == dead:
		_target = null
		_dmgpt_left = 0.0
		if _mode == Mode.ATTACK_MOVE or _mode == Mode.HOLD:
			_set_attack_anim(false)
			_set_state(State.MOVE_TO_GOAL if _mode == Mode.ATTACK_MOVE else State.IDLE)
		elif _mode == Mode.ATTACK:
			cancel()

## 开始攻击
func start_attack(target: Node3D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var body := _body()
	if body == null or not CombatQuery.has_weapon(body):
		return false
	if not CombatQuery.is_valid_attack_target(body, target):
		return false
	_active = true
	_mode = Mode.ATTACK
	_target = target
	_goal_wc3 = Vector2.INF
	# 切目标时保留原 cooldown 余量，避免「卡刀刷伤」（同一帧在 A/B 之间来回切）
	_cooldown_left = maxf(_cooldown_left, _MIN_SWAP_COOLDOWN)
	_dmgpt_left = 0.0
	_set_state(State.CHASE)
	_chase_or_strike(0.0)
	return true


## 切目标的最小冷却（秒）：被新 target 覆盖时给一拍冷却窗，避免连挥刷伤。
const _MIN_SWAP_COOLDOWN := 0.05

## 开始攻击移动
func start_attack_move(goal_wc3: Vector2) -> bool:
	var body := _body()
	if body == null or not CombatQuery.has_weapon(body):
		return false
	if goal_wc3 == Vector2.INF:
		return false
	_active = true
	_mode = Mode.ATTACK_MOVE
	_target = null
	_goal_wc3 = goal_wc3
	_cooldown_left = 0.0
	_dmgpt_left = 0.0
	_set_state(State.MOVE_TO_GOAL)
	_path_to_goal()
	return true

## 开始待命
func start_hold() -> bool:
	var body := _body()
	if body == null:
		return false
	_active = true
	_mode = Mode.HOLD
	_target = null
	_goal_wc3 = Vector2.INF
	_cooldown_left = 0.0
	_dmgpt_left = 0.0
	_set_state(State.IDLE)
	_set_attack_anim(false)
	var nav := _nav()
	if nav != null:
		nav.stop()
	return true

## 处理
func _process(delta: float) -> void:
	if not _active:
		return
	var body := _body()
	if body != null and UnitStatusEffects.is_stunned(body):
		_set_attack_anim(false)
		return
	if _repath_cd > 0.0:
		_repath_cd -= delta
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	match _state:
		State.CHASE:
			_chase_or_strike(delta)
		State.WINDUP:
			_tick_windup(delta)
		State.COOLDOWN:
			_tick_cooldown(delta)
		State.MOVE_TO_GOAL:
			_tick_attack_move(delta)
		_:
			if _mode == Mode.HOLD:
				_tick_hold(delta)

## 追逐或开挥
func _chase_or_strike(_delta: float) -> void:
	var body := _body()
	if body == null:
		cancel()
		return
	if _target == null or not is_instance_valid(_target) or not CombatQuery.is_valid_attack_target(body, _target):
		if _mode == Mode.ATTACK_MOVE:
			_target = null
			_set_attack_anim(false)
			_set_state(State.MOVE_TO_GOAL)
			_path_to_goal()
			return
		if _mode == Mode.HOLD:
			_target = null
			_set_state(State.IDLE)
			_set_attack_anim(false)
			return
		cancel()
		return
	_face_target()
	if CombatQuery.in_attack_range(body, _target):
		var nav := _nav()
		if nav != null and nav.is_moving():
			nav.stop()
		if _cooldown_left <= 0.0:
			_begin_windup()
		else:
			_set_attack_anim(false)
			_set_state(State.COOLDOWN)
	else:
		_set_attack_anim(false)
		_set_state(State.CHASE)
		if _repath_cd <= 0.0:
			_path_to_target()
			_repath_cd = 0.35

## 开一击前摇：播 Attack，等 dmgpt 再结算；整段 cool1 从此时起算。
func _begin_windup() -> void:
	var body := _body()
	if body == null or _target == null:
		return
	var cool := CombatQuery.cooldown_sec(body)
	var atk_spd := UnitStatusEffects.attack_speed_mul(body)
	if atk_spd > 0.0 and atk_spd < 1.0:
		cool /= atk_spd
	var dmgpt := CombatQuery.damage_point_sec(body)
	_cooldown_left = cool
	_dmgpt_left = dmgpt
	_set_attack_anim(true)
	strike_begun.emit(body, _target)
	_set_state(State.WINDUP)
	if dmgpt <= 0.0:
		_resolve_strike()

## 前摇
func _tick_windup(delta: float) -> void:
	var body := _body()
	if body == null:
		cancel()
		return
	if _target == null or not is_instance_valid(_target) or not CombatQuery.is_valid_attack_target(body, _target):
		_dmgpt_left = 0.0
		_set_attack_anim(false)
		_chase_or_strike(0.0)
		return
	_face_target()
	# 前摇中目标跑出交战圈：取消本击动画，改追（冷却已占用，避免连挥刷伤）
	if not CombatQuery.in_engage_range(body, _target, 16.0):
		_dmgpt_left = 0.0
		_set_attack_anim(false)
		_set_state(State.CHASE)
		return
	_dmgpt_left -= delta
	if _dmgpt_left <= 0.0:
		_resolve_strike()

## 伤害点结算：instant/normal 当场 Pipeline；missile 交 ProjectileService 飞行后再结算。
func _resolve_strike() -> void:
	var body := _body()
	_dmgpt_left = 0.0
	if body == null or _target == null or _pipeline == null:
		_set_attack_anim(false)
		_set_state(State.COOLDOWN)
		return
	# 出手瞬间仍须在射程内（允许少量容差）；否则空挥
	if (
		CombatQuery.is_valid_attack_target(body, _target)
		and CombatQuery.in_attack_range(body, _target, 24.0)
	):
		if CombatQuery.uses_projectile_travel(body) and _projectiles != null:
			_projectiles.fire(body, _target, false)
			# 命中结果由会话层 projectile_resolved → 可选转发；此处不立刻 kill 切态
		else:
			var result := _pipeline.apply({"attacker": body, "target": _target, "source_kind": "weapon"})
			damage_applied.emit(result)
			# hrif 等 instant 远程：Present 弹道壳，Logic 已扣血
			if CombatQuery.wants_projectile_visual(body) and _projectiles != null:
				_projectiles.fire(body, _target, true)
			if bool(result.get("killed", false)):
				_target = null
				_set_attack_anim(false)
				if _mode == Mode.ATTACK:
					cancel()
					return
				if _mode == Mode.ATTACK_MOVE:
					_set_state(State.MOVE_TO_GOAL)
					_path_to_goal()
					return
				if _mode == Mode.HOLD:
					_set_state(State.IDLE)
					return
	_set_attack_anim(false)
	_set_state(State.COOLDOWN)

## 冷却（站桩等下一击）
func _tick_cooldown(_delta: float) -> void:
	var body := _body()
	if body == null or _target == null or not CombatQuery.is_valid_attack_target(body, _target):
		_chase_or_strike(0.0)
		return
	_face_target()
	if not CombatQuery.in_attack_range(body, _target, 16.0):
		_set_state(State.CHASE)
		_set_attack_anim(false)
		return
	if _cooldown_left <= 0.0:
		_begin_windup()

## 攻击移动
func _tick_attack_move(delta: float) -> void:
	var body := _body()
	if body == null:
		cancel()
		return
	var host: Node = _unit_host.call() if _unit_host.is_valid() else null
	var acq := CombatQuery.find_acquire_target(body, host)
	if acq != null:
		_target = acq
		_set_state(State.CHASE)
		_chase_or_strike(delta)
		return
	# 已到终点附近
	var here := Wc3Coords.godot_to_wc3_xy(body.global_position)
	if here.distance_to(_goal_wc3) <= 48.0:
		cancel()
		return
	if _repath_cd <= 0.0:
		_path_to_goal()
		_repath_cd = 0.5

## 待命：只打出手射程内，不追击
func _tick_hold(delta: float) -> void:
	var body := _body()
	if body == null or not CombatQuery.has_weapon(body):
		return
	if _target != null and CombatQuery.is_valid_attack_target(body, _target) and CombatQuery.in_attack_range(body, _target):
		_set_state(State.CHASE)
		_chase_or_strike(delta)
		return
	var host: Node = _unit_host.call() if _unit_host.is_valid() else null
	var acq := CombatQuery.find_acquire_target(body, host, CombatQuery.attack_range_wc3(body))
	if acq != null:
		_target = acq
		_set_state(State.CHASE)
		_chase_or_strike(delta)

## 移动到目标
func _path_to_target() -> void:
	if _target == null or not _ensure_navigator.is_valid():
		return
	var body := _body()
	var nav := _ensure_navigator.call(body) as UnitNavigator
	if nav == null:
		return
	var goal := Wc3Coords.godot_to_wc3_xy(_target.global_position)
	nav.go_to_wc3(goal)

## 移动到目标位置
func _path_to_goal() -> void:
	if _goal_wc3 == Vector2.INF or not _ensure_navigator.is_valid():
		return
	var nav := _ensure_navigator.call(_body()) as UnitNavigator
	if nav != null:
		nav.go_to_wc3(_goal_wc3)

## 面向目标
func _face_target() -> void:
	var body := _body()
	if body == null or _target == null:
		return
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
	var to := Wc3Coords.godot_to_wc3_xy(_target.global_position)
	var dir := to - from
	if dir.length_squared() < 1.0:
		return
	# 与 UnitNavigator 一致：前进轴 +X，yaw = atan2(dy, dx)
	body.rotation.y = atan2(dir.y, dir.x)

## 设置攻击动画
func _set_attack_anim(on: bool) -> void:
	var body := _body()
	if body == null:
		return
	var vis := Unit.of(body)
	if vis != null:
		vis.set_combat_attack(on)

## 设置状态
func _set_state(s: int) -> void:
	if _state == s:
		return
	_state = s
	state_changed.emit(s)

## 获取导航器
func _nav() -> UnitNavigator:
	var body := _body()
	if body == null:
		return null
	if _ensure_navigator.is_valid():
		return _ensure_navigator.call(body) as UnitNavigator
	return body.get_node_or_null("UnitNavigator") as UnitNavigator

## 获取单位主体
func _body() -> Node3D:
	return get_parent() as Node3D
