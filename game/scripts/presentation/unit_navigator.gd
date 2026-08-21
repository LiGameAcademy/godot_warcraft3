class_name UnitNavigator
extends Node

## 单位移动执行器：作为单位 Node3D 的子节点挂载。
##
## 为何是子节点而不是把 A* 写进单位脚本：
## - 表现层单位只负责「沿路点走」；换皮/换动画时不应牵动寻路算法。
## - 建筑、静止物可以不挂本节点；需要移动时再 ensure，避免无谓 _process。
## - PathQuery 由 Director/Session 注入（共享一张 WPM），这里绝不持有 pathing 副本。

signal arrived
signal path_failed(reason: String)
signal locomotion_changed(moving: bool)

const SeparationScr = preload("res://game/scripts/logic/pathing/unit_separation.gd")
const AgentProfileScr = preload("res://game/scripts/logic/pathing/path_agent_profile.gd")
const SlopeSpeedScr = preload("res://game/scripts/logic/pathing/slope_speed.gd")
const FormationFollowScr = preload("res://game/scripts/logic/pathing/formation_follow.gd")
const SteeringScr = preload("res://game/scripts/logic/pathing/steering_behaviors.gd")
const PathArcScr = preload("res://game/scripts/logic/pathing/path_arc.gd")
## WC3 单位/秒。默认 270 ≈ 步兵；开局后由 UnitBalance.spd 覆盖。
@export var speed_wc3: float = 270.0
## 外部倍率（顶盾等）；1=全速。不改 speed_wc3 权威值。
@export var speed_mul: float = 1.0
## 到达路点阈值（WC3 单位）。过小会抖动绕圈，过大会提前切点。
@export var arrive_eps_wc3: float = 10.0
## 最终路点（常在不可走边缘）放宽阈值，避免贴墙永远差几单位到不了。
@export var arrive_eps_last_wc3: float = 22.0
@export var face_move_dir: bool = true
## WC3 UnitData.turnRate：圈/秒。0.6 ≈ 农民；角速度 = turn_rate * TAU。
@export var turn_rate: float = 0.5
## 转向夹角越大走得越慢，避免蟹行满速横挪。
@export var enable_turn_speed_scale: bool = true
## 夹角 ≤ 此角度（度）仍全速。
@export var turn_speed_full_deg: float = 25.0
## 夹角 ≥ 此角度（度）用到 turn_speed_min。
@export var turn_speed_min_deg: float = 140.0
## 大转弯时的速度倍率（0=原地转向，约 0.1~0.2 较自然）。
@export_range(0.0, 1.0, 0.01) var turn_speed_min: float = 0.12
## UnitBalance.collision（WC3）；用于 soft 分离。农民约 16。
@export var collision_radius_wc3: float = 16.0
## A* 净空格数（由 collision 推导）；0 = 单格通道即可。
@export var clearance_cells: int = 0
@export var enable_separation: bool = true
## F3-3: 上下坡速度衰减（WC3 真实斜坡观感，必须开）。
@export var enable_slope_speed: bool = true
## F3-3: 上坡/下坡最大坡度（度）；超此值钳到。
@export var slope_max_deg: float = 30.0
## 位移几乎为 0 超过该秒数 → 强制到达（点不可走区卡边缘时停 Walk）。
@export var stall_abort_sec: float = 0.4
## F-PATH-7: 是否允许外部 steering override（F4 战斗 pursue/evade 用；false = 走 waypoint 默认）。
@export var enable_steering_override: bool = true
## F-PATH-8: waypoint 转角弧线平滑（骑士 / 英雄 / 高速观感；false = 走直线切角）。
@export var enable_path_arc: bool = true
## F-PATH-8: 弧线每段采样数（值越大越平滑；调高耗 1 个 O(n_samples) per 转角）。
@export var path_arc_samples: int = 8
## 采矿幽灵模式：不占格、寻路忽略他人预约 → 固定走廊互不挡。
## keep_separation=true：仍 soft 分离（伐木用；采金走廊通常关分离）。
var harvest_ghost: bool = false
## soft 分离半径倍率（农民略放大，减轻叠人）。
@export var separation_radius_mul: float = 1.0
## F-PATH-7: 外部 steering override Callable（F4 战斗 pursue/evade 用）。
## 签名: (self_pos: Vector2, delta: float) -> Vector2（期望速度 WC3 单位/秒）。
## 有效时，_process 末尾用其返回替换默认 waypoint 跟随。
var _steering_override: Callable = Callable()

var _query: PathQuery = null
var _heightfield: Wc3Heightfield = null
var _crowd: UnitCrowdQuery = null
var _reservation: PathCellReservation = null
var _visual: Unit = null
var _waypoints: Array[Vector2] = [] ## WC3 XY
var _wp_i: int = 0
var _moving: bool = false
var _goal_wc3: Vector2 = Vector2.INF
var _stall_time: float = 0.0
## F3-3: 上一帧位置（SlopeSpeed 调速用）
var _prev_wc3: Vector2 = Vector2.INF
## F3-3: formation 标记（-1 = leader / non-follower；>=0 = slot index）
var _formation_slot: int = -1
var _formation_name: String = ""
var _formation_spacing: float = 64.0
## harvest_ghost 切换前暂存原分离设置，便于 off 时恢复。
var _saved_separation: bool = true


func set_harvest_ghost(on: bool, keep_separation: bool = false) -> void:
	if on == harvest_ghost:
		if on:
			_release_reservation()
			if keep_separation:
				enable_separation = true
		return
	if on:
		_saved_separation = enable_separation
		enable_separation = keep_separation
		harvest_ghost = true
		_release_reservation()
	else:
		harvest_ghost = false
		enable_separation = _saved_separation
		_release_reservation()


func configure(
	query: PathQuery,
	heightfield: Wc3Heightfield,
	crowd: UnitCrowdQuery = null,
	reservation: PathCellReservation = null
) -> void:
	_query = query
	_heightfield = heightfield
	_crowd = crowd
	_reservation = reservation


func set_visual(visual: Unit) -> void:
	_visual = visual


func get_waypoints_wc3() -> Array[Vector2]:
	return _waypoints.duplicate()


func get_remaining_waypoints_wc3() -> Array[Vector2]:
	var out: Array[Vector2] = []
	if not _moving:
		return out
	for i in range(_wp_i, _waypoints.size()):
		out.append(_waypoints[i])
	return out


## 从 SLK 写入速度/转向/碰撞；≤0 的项保留现有值。
## move_speed_wc3 ← UnitBalance.spd（玩法）；非 UnitUI.walk（动画）。
func apply_unit_stats(
	move_speed_wc3: float,
	turn_rate_rps: float,
	radius_wc3: float = -1.0
) -> void:
	if move_speed_wc3 > 0.0:
		speed_wc3 = move_speed_wc3
	if turn_rate_rps > 0.0:
		turn_rate = turn_rate_rps
	if radius_wc3 > 0.0:
		collision_radius_wc3 = radius_wc3
		clearance_cells = PathAgentProfile.clearance_from_radius(radius_wc3)


## F-PATH-7: 应用外部 steering override（F4 战斗 pursue/evade 用）。
## fn 签名：(self_pos: Vector2, delta: float) -> Vector2（期望速度 WC3 单位/秒）。
## 有效时，_process 末尾用其返回替换默认 waypoint 跟随。
## 切 waypoint 时不重置 — override 持续到 clear_steering_override。
func apply_steering_override(fn: Callable) -> void:
	_steering_override = fn


## F-PATH-7: 清掉 override（恢复 waypoint 跟随）。
## 战斗结束/被命令移动时调用。
func clear_steering_override() -> void:
	_steering_override = Callable()


## F-PATH-7: 是否有 override。
func has_steering_override() -> bool:
	return _steering_override.is_valid()


func is_moving() -> bool:
	return _moving


func stop() -> void:
	var was := _moving
	_moving = false
	_waypoints.clear()
	_wp_i = 0
	_goal_wc3 = Vector2.INF
	_stall_time = 0.0
	_prev_wc3 = Vector2.INF
	set_process(false)
	_release_reservation()
	if was:
		_set_locomotion(false)


## F3-3: 标记 follower 在 formation 中的 slot（调试/可视化用；不影响寻路）。
## slot = -1 → leader（或非编队）；slot >= 0 → follower slot index。
func set_formation_slot(slot: int, formation: String = "", spacing: float = 64.0) -> void:
	_formation_slot = slot
	_formation_name = formation
	_formation_spacing = spacing


func get_formation_slot() -> int:
	return _formation_slot


func get_formation_name() -> String:
	return _formation_name


## 对目标点求路并开始跟随。返回是否成功发出路径。
func go_to_wc3(goal_wc3: Vector2) -> bool:
	var body := _body()
	if body == null or _query == null or not _query.has_method("find_path"):
		path_failed.emit("not_configured")
		return false
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var from := Vector2(body.global_position.x * inv, -body.global_position.z * inv)
	var agent_id := 0 if harvest_ghost else body.get_instance_id()
	# 凹角口袋（建筑 pathTex 直角）先弹到开阔格，否则 A* 能走也会在墙缝里蹭。
	# 采矿幽灵模式：不弹位，避免每趟落脚点漂移破坏固定走廊。
	if not harvest_ghost:
		from = _unstuck_if_pocket(body, from)
	var result: Dictionary = _query.call(
		"find_path", from, goal_wc3, clearance_cells, agent_id, harvest_ghost
	)
	if not result.get("ok", false) and not harvest_ghost:
		# 再试一次：强制弹开后再寻路
		from = _unstuck_if_pocket(body, from, true)
		result = _query.call(
			"find_path", from, goal_wc3, clearance_cells, agent_id, false
		)
	if not result.get("ok", false):
		stop()
		path_failed.emit(str(result.get("reason", "fail")))
		return false
	return _begin_waypoints(result.get("waypoints", []), goal_wc3)


## 跟随已算好的固定路点（采矿走廊：全员同一条，不再每趟 A*）。
func go_waypoints_wc3(waypoints: Array, goal_hint_wc3: Vector2 = Vector2.INF) -> bool:
	if waypoints.is_empty():
		path_failed.emit("empty_waypoints")
		return false
	return _begin_waypoints(waypoints, goal_hint_wc3)


func _begin_waypoints(waypoints: Array, goal_hint_wc3: Vector2 = Vector2.INF) -> bool:
	var body := _body()
	# F-PATH-8: waypoint 转角弧线平滑（>30° 转弯画弧；<=30° 走直线切角）
	# 走直线时返回原 waypoints 不变；>30° 时插入 n_samples 个中间点（O(n_samples) per 转角）
	if enable_path_arc and waypoints.size() >= 2:
		waypoints = PathArcScr.smooth_path(waypoints, path_arc_samples)
	_waypoints.clear()
	for p in waypoints:
		if p is Vector2:
			_waypoints.append(p)
	_wp_i = 0
	_stall_time = 0.0
	if not _waypoints.is_empty():
		_goal_wc3 = _waypoints[_waypoints.size() - 1]
	elif goal_hint_wc3 != Vector2.INF:
		_goal_wc3 = goal_hint_wc3
	else:
		_goal_wc3 = Vector2.INF
	if _waypoints.is_empty():
		_moving = false
		set_process(false)
		_set_locomotion(false)
		_release_reservation()
		arrived.emit()
		return true
	_moving = true
	_set_locomotion(true)
	if not harvest_ghost:
		_refresh_reservation(body)
	else:
		_release_reservation()
	set_process(true)
	return true


## 若当前格过于「夹」（可走邻居少），弹到附近开阔可走格。
func _unstuck_if_pocket(body: Node3D, from_wc3: Vector2, force: bool = false) -> Vector2:
	if _query == null or not _query.has_method("snap_to_open_walkable"):
		return from_wc3
	var min_open := 3 if force else 4
	var snap: Dictionary = _query.call("snap_to_open_walkable", from_wc3.x, from_wc3.y, 12, min_open)
	if not bool(snap.get("ok", false)):
		return from_wc3
	if not force and not bool(snap.get("moved", false)):
		return from_wc3
	var freed: Vector2 = snap.get("wc3", from_wc3)
	if freed.distance_squared_to(from_wc3) > 0.25:
		_apply_wc3_pos(body, freed)
	return freed


func _ready() -> void:
	# Godot：对已在树内的父节点 add_child 时，子节点 _ready 会延后到帧末。
	# 若这里无条件 set_process(false)，会把同一帧里 go_to_wc3 刚打开的跟随关掉 → 单位原地不动。
	if not _moving:
		set_process(false)


func _process(delta: float) -> void:
	if not _moving or _waypoints.is_empty():
		set_process(false)
		return
	var body := _body()
	if body == null:
		stop()
		return
	if _wp_i >= _waypoints.size():
		_finish()
		return
	var target_wc3: Vector2 = _waypoints[_wp_i]
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var cur_wc3 := Vector2(body.global_position.x * inv, -body.global_position.z * inv)
	var to := target_wc3 - cur_wc3
	var dist := to.length()
	var is_last := _wp_i >= _waypoints.size() - 1
	var arrive_eps := arrive_eps_last_wc3 if is_last else arrive_eps_wc3
	if dist <= arrive_eps:
		if is_last:
			# 末点：不再叠加离墙推，避免刚踩进阈值又被推出去
			_apply_wc3_pos(body, cur_wc3)
			_finish()
			return
		_wp_i += 1
		_stall_time = 0.0
		return
	var base_speed := speed_wc3 * clampf(speed_mul, 0.05, 4.0)
	var speed := base_speed
	# F3-3: 上下坡速度衰减（WC3 真实斜坡观感）
	if enable_slope_speed and _prev_wc3 != Vector2.INF:
		speed = SlopeSpeedScr.apply(cur_wc3, _prev_wc3, base_speed, slope_max_deg)
	# 朝向与前进方向夹角越大越慢（先转向再迈步，减轻蟹行）
	speed *= _turn_speed_mul(body, to)
	var step := speed * delta
	var desired: Vector2
	if step >= dist:
		desired = target_wc3
	else:
		desired = cur_wc3 + to * (step / dist)
	# F-PATH-7: 外部 override 替换默认 waypoint 跟随（F4 战斗 pursue/evade 用）
	if enable_steering_override and _steering_override.is_valid():
		var override_vel: Vector2 = _steering_override.call(cur_wc3, delta)
		# override 也吃转向降速，避免追击时满速侧移
		override_vel *= _turn_speed_mul(body, override_vel)
		desired = cur_wc3 + override_vel * delta
	var next := _with_separation(body, cur_wc3, desired, delta, is_last, dist)
	var moved := next.distance_to(cur_wc3)
	_apply_wc3_pos(body, next)
	_refresh_reservation(body)
	_prev_wc3 = next  # F3-3: 记下上一帧位置
	# 面向期望前进方向（路点/override），大转弯时会先转身再加速
	var face_dir := to
	if enable_steering_override and _steering_override.is_valid():
		var face_move := next - cur_wc3
		if face_move.length_squared() > 0.01:
			face_dir = face_move
	if face_move_dir and face_dir.length_squared() > 0.01:
		_face_dir(body, face_dir, delta)
	# 贴不可走边缘：离墙推与目标对冲 → 位移≈0 却永远到不了 → 停 Walk
	if moved < 0.75:
		_stall_time += delta
		if _stall_time >= stall_abort_sec:
			_finish()
			return
	else:
		_stall_time = 0.0
	if step >= dist and next.distance_to(target_wc3) <= arrive_eps:
		_wp_i += 1
		_stall_time = 0.0
		if _wp_i >= _waypoints.size():
			_finish()


## 路点步进 + soft 分离 + 离墙推开；不可走则回退。
## 接近最终路点时关闭离墙推：终点常在 NO_WALK 旁，推开会导致永不 arrive。
func _with_separation(
	body: Node3D,
	cur_wc3: Vector2,
	desired_wc3: Vector2,
	delta: float,
	is_last: bool = false,
	dist_to_target: float = INF
) -> Vector2:
	var next := desired_wc3
	# 接近末点：关墙推并减弱 soft 分离，减轻「推开↔追目标」微抖
	var near_last := is_last and dist_to_target <= arrive_eps_last_wc3 * 4.0
	var sep_scale := 0.35 if near_last else 1.0
	if not near_last and _query != null and _query.has_method("compute_wall_push_velocity"):
		var wall_vel: Vector2 = _query.call("compute_wall_push_velocity", cur_wc3, 2)
		next += wall_vel * delta
	if enable_separation and _crowd != null and _crowd.has_method("neighbors_of"):
		var query_r := maxf(collision_radius_wc3 * 5.0, 128.0)
		var neighbors: Array = _crowd.call("neighbors_of", body, cur_wc3, query_r, false)
		if not neighbors.is_empty():
			var sep_r := collision_radius_wc3 * maxf(separation_radius_mul, 1.0)
			var push_vel: Vector2 = UnitSeparation.compute_push_velocity(
				cur_wc3,
				sep_r,
				neighbors,
				body.get_instance_id()
			)
			next += push_vel * delta * sep_scale
	return _clamp_walkable(next, desired_wc3, cur_wc3)


## 优先 next；不可走则试 fallback；再不可走则 keep。
func _clamp_walkable(
	next: Vector2,
	fallback: Vector2 = Vector2.INF,
	keep: Vector2 = Vector2.INF
) -> Vector2:
	if _query != null and _query.has_method("can_walk_wc3"):
		if bool(_query.call("can_walk_wc3", next.x, next.y)):
			return next
		if fallback != Vector2.INF and bool(_query.call("can_walk_wc3", fallback.x, fallback.y)):
			return fallback
		if keep != Vector2.INF:
			return keep
	return next


func _face_dir(body: Node3D, dir_wc3: Vector2, delta: float) -> void:
	# WC3 MDX→GLB 单位前进轴是本地 +X（不是 Godot look_at 的 -Z）。
	# 位移 Godot(dx,0,-dy) 要对齐 +X：yaw = atan2(dy, dx)（= WC3 facing，不必再 -a+PI）。
	var target_yaw := atan2(dir_wc3.y, dir_wc3.x)
	var rate := maxf(turn_rate, 0.05) * TAU
	body.rotation.y = rotate_toward(body.rotation.y, target_yaw, rate * delta)


## 当前朝向与期望前进方向夹角 → 速度倍率（1=全速，大转弯→turn_speed_min）。
func _turn_speed_mul(body: Node3D, dir_wc3: Vector2) -> float:
	if not enable_turn_speed_scale or body == null:
		return 1.0
	if dir_wc3.length_squared() < 0.0001:
		return 1.0
	var move_yaw := atan2(dir_wc3.y, dir_wc3.x)
	var ang := absf(angle_difference(body.rotation.y, move_yaw))
	var a0 := deg_to_rad(turn_speed_full_deg)
	var a1 := deg_to_rad(maxf(turn_speed_min_deg, turn_speed_full_deg + 1.0))
	if ang <= a0:
		return 1.0
	var min_mul := clampf(turn_speed_min, 0.0, 1.0)
	if ang >= a1:
		return min_mul
	var t := (ang - a0) / (a1 - a0)
	# smoothstep：中间段更顺，少「突然刹住」感
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(1.0, min_mul, t)


func _apply_wc3_pos(body: Node3D, wc3_xy: Vector2) -> void:
	var z := 0.0
	if _heightfield != null and _heightfield.is_valid():
		z = _heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	# 单位挂在 MapUnitLayer 下时用 local position，避免父节点变换时 global 来回拧。
	var parent_n := body.get_parent() as Node3D
	var gpos := Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z)
	if parent_n != null:
		body.position = parent_n.to_local(gpos)
	else:
		body.global_position = gpos


func _finish() -> void:
	_moving = false
	_waypoints.clear()
	_wp_i = 0
	_goal_wc3 = Vector2.INF
	_stall_time = 0.0
	_prev_wc3 = Vector2.INF
	set_process(false)
	_release_reservation()
	_set_locomotion(false)
	arrived.emit()


func _refresh_reservation(body: Node3D) -> void:
	if harvest_ghost:
		return
	if _reservation == null or not _reservation.has_method("set_owner_cells"):
		return
	if _query == null or body == null or not _query.has_method("world_to_cell"):
		return
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var cur := Vector2(body.global_position.x * inv, -body.global_position.z * inv)
	var cells: Array = []
	cells.append(_query.call("world_to_cell", cur.x, cur.y))
	if _goal_wc3 != Vector2.INF:
		cells.append(_query.call("world_to_cell", _goal_wc3.x, _goal_wc3.y))
	if _wp_i < _waypoints.size():
		var nxt: Vector2 = _waypoints[_wp_i]
		cells.append(_query.call("world_to_cell", nxt.x, nxt.y))
	_reservation.call("set_owner_cells", body.get_instance_id(), cells)


func _release_reservation() -> void:
	var body := _body()
	if body == null or _reservation == null:
		return
	if _reservation.has_method("clear_owner"):
		_reservation.call("clear_owner", body.get_instance_id())


func _set_locomotion(moving: bool) -> void:
	if _visual != null:
		_visual.set_locomotion(moving)
	locomotion_changed.emit(moving)


func _body() -> Node3D:
	var p := get_parent()
	return p as Node3D
