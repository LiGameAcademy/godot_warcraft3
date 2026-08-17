class_name DeathService
extends RefCounted

## 单位死亡编排（Logic）：清选中、离场、广播。不播 Mesh。

signal unit_died(unit: Node3D, killer: Node3D)		## 单位死亡信号

## Callable(unit: Node3D) -> void；可选清选中
var on_before_exit: Callable = Callable()

## 杀死单位
func kill(unit: Node3D, killer: Node3D = null) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	UnitLife.set_life(unit, 0.0)
	if on_before_exit.is_valid():
		on_before_exit.call(unit)
	# 清以其为目标的攻击订单（同宿主下其它单位）
	_clear_attackers_of(unit)
	WorldMembership.exit(unit)
	unit_died.emit(unit, killer)

## 清除以其为目标的攻击订单
func _clear_attackers_of(dead: Node3D) -> void:
	if dead == null or dead.get_parent() == null:
		return
	var host := dead.get_parent()
	for c in host.get_children():
		if not (c is Node3D) or c == dead:
			continue
		var ac := (c as Node3D).get_node_or_null("AttackController") as AttackController
		if ac != null:
			ac.notify_target_died(dead)
