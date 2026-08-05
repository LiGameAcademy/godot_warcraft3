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

## WC3 单位/秒。270 ≈ 人族步兵量级；精确值日后读 UnitUI.walk。
@export var speed_wc3: float = 270.0
## 到达路点阈值（WC3 单位）。过小会抖动绕圈，过大会「切角穿模」。
@export var arrive_eps_wc3: float = 12.0
@export var face_move_dir: bool = true

var _query: RefCounted = null ## PathQuery
var _heightfield: Wc3Heightfield = null
var _waypoints: Array[Vector2] = [] ## WC3 XY
var _wp_i: int = 0
var _moving: bool = false


func configure(query: RefCounted, heightfield: Wc3Heightfield) -> void:
	_query = query
	_heightfield = heightfield


func is_moving() -> bool:
	return _moving


func stop() -> void:
	_moving = false
	_waypoints.clear()
	_wp_i = 0
	set_physics_process(false)


## 对目标点求路并开始跟随。返回是否成功发出路径。
func go_to_wc3(goal_wc3: Vector2) -> bool:
	var body := _body()
	if body == null or _query == null or not _query.has_method("find_path"):
		path_failed.emit("not_configured")
		return false
	var from := Wc3Coords.godot_to_wc3_xy(body.global_position)
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
		stop()
		arrived.emit()
		return true
	_moving = true
	set_physics_process(true)
	return true


func _ready() -> void:
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _moving or _waypoints.is_empty():
		set_physics_process(false)
		return
	var body := _body()
	if body == null:
		stop()
		return
	if _wp_i >= _waypoints.size():
		_finish()
		return
	var target_wc3: Vector2 = _waypoints[_wp_i]
	var cur_wc3 := Wc3Coords.godot_to_wc3_xy(body.global_position)
	var to := target_wc3 - cur_wc3
	var dist := to.length()
	if dist <= arrive_eps_wc3:
		_wp_i += 1
		if _wp_i >= _waypoints.size():
			_stick_height(body, target_wc3)
			_finish()
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
		# WC3 朝向角：atan2(dy, dx)；再映射到 Godot Yaw。
		var ang := atan2(to.y, to.x)
		body.rotation.y = Wc3Coords.yaw_wc3_to_godot(ang)


func _apply_wc3_pos(body: Node3D, wc3_xy: Vector2) -> void:
	var z := 0.0
	if _heightfield != null and _heightfield.is_valid():
		z = _heightfield.interpolated_height(wc3_xy.x, wc3_xy.y)
	body.global_position = Wc3Coords.wc3_xy_to_godot(wc3_xy.x, wc3_xy.y, z)


func _stick_height(body: Node3D, wc3_xy: Vector2) -> void:
	_apply_wc3_pos(body, wc3_xy)


func _finish() -> void:
	_moving = false
	_waypoints.clear()
	_wp_i = 0
	set_physics_process(false)
	arrived.emit()


func _body() -> Node3D:
	var p := get_parent()
	return p as Node3D
