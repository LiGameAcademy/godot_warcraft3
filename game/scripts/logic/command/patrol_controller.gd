class_name PatrolController
extends Node

## 巡逻订单执行（Logic）：在 A↔B 两点间往返。攻击接敌由日后 AttackController / acquire 接管。
## Present 只消费 Navigator 移动；本类不播动画。

signal patrol_leg_changed(to_b: bool)

const META_ACTIVE := "patrol_active"

var _point_a_wc3: Vector2 = Vector2.INF
var _point_b_wc3: Vector2 = Vector2.INF
var _going_to_b: bool = true
var _ensure_navigator: Callable = Callable()
var _wired_nav: UnitNavigator = null


func configure(ensure_navigator: Callable) -> void:
	_ensure_navigator = ensure_navigator


func is_active() -> bool:
	return _point_a_wc3 != Vector2.INF and _point_b_wc3 != Vector2.INF


func cancel() -> void:
	_point_a_wc3 = Vector2.INF
	_point_b_wc3 = Vector2.INF
	_going_to_b = true
	_unwire_nav()
	var body := get_parent() as Node3D
	if body != null and body.has_meta(META_ACTIVE):
		body.remove_meta(META_ACTIVE)


## 从当前位置到 goal 开始巡逻。
func begin(goal_wc3: Vector2) -> bool:
	var body := get_parent() as Node3D
	if body == null or goal_wc3 == Vector2.INF:
		return false
	var here := Wc3Coords.godot_to_wc3_xy(body.global_position)
	if here.distance_to(goal_wc3) < 8.0:
		return false
	_point_a_wc3 = here
	_point_b_wc3 = goal_wc3
	_going_to_b = true
	body.set_meta(META_ACTIVE, true)
	return _path_to_current_goal()


func _path_to_current_goal() -> bool:
	var body := get_parent() as Node3D
	if body == null or not _ensure_navigator.is_valid():
		return false
	var nav := _ensure_navigator.call(body) as UnitNavigator
	if nav == null:
		return false
	_wire_nav(nav)
	var goal := _point_b_wc3 if _going_to_b else _point_a_wc3
	return nav.go_to_wc3(goal)


func _wire_nav(nav: UnitNavigator) -> void:
	if _wired_nav == nav:
		return
	_unwire_nav()
	_wired_nav = nav
	if not nav.arrived.is_connected(_on_nav_arrived):
		nav.arrived.connect(_on_nav_arrived)


func _unwire_nav() -> void:
	if _wired_nav != null and is_instance_valid(_wired_nav):
		if _wired_nav.arrived.is_connected(_on_nav_arrived):
			_wired_nav.arrived.disconnect(_on_nav_arrived)
	_wired_nav = null


func _on_nav_arrived() -> void:
	if not is_active():
		return
	_going_to_b = not _going_to_b
	patrol_leg_changed.emit(_going_to_b)
	_path_to_current_goal()
