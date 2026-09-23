class_name ItemPickupController
extends Node

## 拾取订单与 OrderQueue 同步；别的命令替换后立即让步，绝不延迟偷捡。
signal finished(reason: String)
var target: GroundItem
var order: UnitOrder
var navigator: UnitNavigator
var elapsed: float = 0.0
const PICKUP_RANGE := 128.0

func _ready() -> void:
	set_process(false)

func begin(ground: GroundItem, nav: UnitNavigator, queue_order: UnitOrder) -> bool:
	target = ground
	navigator = nav
	order = queue_order
	elapsed = 0.0
	if not is_instance_valid(target) or target.claimed or nav == null:
		return false
	nav.stop()
	var xy := Wc3Coords.godot_to_wc3_xy((get_parent() as Node3D).global_position)
	var goal := Wc3Coords.godot_to_wc3_xy(target.global_position)
	# 已在拾取范围内时不寻路；寻路脱困会把贴建筑站立的英雄推离道具。
	if xy.distance_to(goal) > PICKUP_RANGE:
		nav.go_to_wc3(goal)
	set_process(true)
	return true

func _process(delta: float) -> void:
	var unit := get_parent() as Node3D
	var q := unit.get_meta("order_queue", null) as OrderQueue
	if not CombatQuery.is_alive_in_world(unit) or q == null or q.current != order:
		set_process(false)
		target = null
		return
	if not is_instance_valid(target) or target.claimed:
		_finish("道具已被拾取")
		return
	elapsed += delta
	var dist := Wc3Coords.godot_to_wc3_xy(unit.global_position).distance_to(Wc3Coords.godot_to_wc3_xy(target.global_position))
	if dist <= PICKUP_RANGE:
		var inv := Inventory.of(unit)
		if inv == null or inv.is_full():
			_finish("背包已满，未拾取")
			return
		if inv.insert(target.item):
			target.claimed = true
			target.visible = false
			target.queue_free()
			_finish("已拾取道具")
		else:
			_finish("道具已被领取")
	elif (elapsed > 1.0 and not navigator.is_moving()) or elapsed > 30.0:
		_finish("无法到达道具，请靠近后重试")

func _finish(reason: String) -> void:
	set_process(false)
	var unit := get_parent()
	var q := unit.get_meta("order_queue", null) as OrderQueue
	if q != null and q.current == order:
		q.clear()
		if is_instance_valid(navigator):
			navigator.stop()
	target = null
	finished.emit(reason)
