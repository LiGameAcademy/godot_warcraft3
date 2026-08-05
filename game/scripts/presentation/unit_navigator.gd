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

## WC3 单位/秒。默认 270 ≈ 步兵；开局后由 UnitUI.walk 覆盖。
@export var speed_wc3: float = 270.0
## 到达路点阈值（WC3 单位）。过小会抖动绕圈，过大会提前切点。
@export var arrive_eps_wc3: float = 8.0
@export var face_move_dir: bool = true
## WC3 UnitData.turnRate：圈/秒。0.6 ≈ 农民；角速度 = turn_rate * TAU。
@export var turn_rate: float = 0.5

var _query: RefCounted = null ## PathQuery
var _heightfield: Wc3Heightfield = null
## UnitVisual 实例；用 Node 避免 class_name 全局注册时序导致 Parser Error
var _visual: Node = null
var _waypoints: Array[Vector2] = [] ## WC3 XY
var _wp_i: int = 0
var _moving: bool = false


func configure(query: RefCounted, heightfield: Wc3Heightfield) -> void:
	_query = query
	_heightfield = heightfield


func set_visual(visual: Node) -> void:
	_visual = visual


## 从 SLK 写入速度/转向；≤0 的项保留现有值。
func apply_unit_stats(walk_speed_wc3: float, turn_rate_rps: float) -> void:
	if walk_speed_wc3 > 0.0:
		speed_wc3 = walk_speed_wc3
	if turn_rate_rps > 0.0:
		turn_rate = turn_rate_rps


func is_moving() -> bool:
	return _moving


func stop() -> void:
	var was := _moving
	_moving = false
	_waypoints.clear()
	_wp_i = 0
	set_process(false)
	if was:
		_set_locomotion(false)


## 对目标点求路并开始跟随。返回是否成功发出路径。
func go_to_wc3(goal_wc3: Vector2) -> bool:
	var body := _body()
	if body == null or _query == null or not _query.has_method("find_path"):
		path_failed.emit("not_configured")
		return false
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var from := Vector2(body.global_position.x * inv, -body.global_position.z * inv)
	var result: Dictionary = _query.call("find_path", from, goal_wc3)
	if not result.get("ok", false):
		stop()
		path_failed.emit(str(result.get("reason", "fail")))
		return false
	var wps: Array = result.get("waypoints", [])
	_waypoints.clear()
	for p in wps:
		if p is Vector2:
			_waypoints.append(p)
	_wp_i = 0
	if _waypoints.is_empty():
		_moving = false
		set_process(false)
		_set_locomotion(false)
		arrived.emit()
		return true
	_moving = true
	_set_locomotion(true)
	# 用 _process 而非 _physics_process：本项目移动不依赖物理步进；
	# 且避免「add_child 后本帧 go_to 开物理，下一帧 _ready 又关掉」的竞态（见 _ready 注释）。
	set_process(true)
	return true


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
	if dist <= arrive_eps_wc3:
		# 中间点可跳过；最后一点要落到精确目标，否则「点哪走哪」会差半个格。
		if _wp_i >= _waypoints.size() - 1:
			_apply_wc3_pos(body, target_wc3)
			_finish()
			return
		_wp_i += 1
		return
	var step := speed_wc3 * delta
	if step >= dist:
		_apply_wc3_pos(body, target_wc3)
		_wp_i += 1
		if _wp_i >= _waypoints.size():
			_finish()
		return
	var next := cur_wc3 + to * (step / dist)
	_apply_wc3_pos(body, next)
	if face_move_dir and dist > 0.01:
		_face_dir(body, to, delta)


func _face_dir(body: Node3D, dir_wc3: Vector2, delta: float) -> void:
	# WC3 MDX→GLB 单位前进轴是本地 +X（不是 Godot look_at 的 -Z）。
	# 位移 Godot(dx,0,-dy) 要对齐 +X：yaw = atan2(dy, dx)（= WC3 facing，不必再 -a+PI）。
	# -Z 对准会偏 90°；yaw_wc3_to_godot 会偏 180°（反着走）。
	var target_yaw := atan2(dir_wc3.y, dir_wc3.x)
	var rate := maxf(turn_rate, 0.05) * TAU
	body.rotation.y = rotate_toward(body.rotation.y, target_yaw, rate * delta)


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
	set_process(false)
	_set_locomotion(false)
	arrived.emit()


func _set_locomotion(moving: bool) -> void:
	if _visual != null and _visual.has_method("set_locomotion"):
		_visual.call("set_locomotion", moving)
	locomotion_changed.emit(moving)


func _body() -> Node3D:
	var p := get_parent()
	return p as Node3D
