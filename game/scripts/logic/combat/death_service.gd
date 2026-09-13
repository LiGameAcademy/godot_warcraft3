class_name DeathService
extends RefCounted

## 单位死亡编排（Logic）：清选中、离场、广播。不播 Mesh。

signal unit_died(unit: Node3D, killer: Node3D)		## 单位死亡信号

const META_DEATH_PROCESSED := "death_processed"

## Callable(unit: Node3D) -> void；可选清选中
var on_before_exit: Callable = Callable()

## 杀死单位
func kill(unit: Node3D, killer: Node3D = null) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if bool(unit.get_meta(META_DEATH_PROCESSED, false)):
		return
	# 在回调前锁存，阻止重入或另一服务实例重复发奖/登记/清理。
	# 当前英雄复活使用新节点；以后原节点复生需显式开启新的生命期。
	unit.set_meta(META_DEATH_PROCESSED, true)
	UnitLife.set_life(unit, 0.0)
	if on_before_exit.is_valid():
		on_before_exit.call(unit)
	if not is_instance_valid(unit):
		return
	# 清以其为目标的攻击订单（同宿主下其它单位）
	_clear_attackers_of(unit)
	# 从队伍 / 营地注册表中剔除并重算 home（营地成员死亡后中心点会变化）
	var _tree := Engine.get_main_loop() as SceneTree
	var reg := TeamRegistry.get_for(_tree.root if _tree != null else null)
	if reg != null and reg.has_member(unit):
		reg.on_unit_gone(unit)
	WorldMembership.exit(unit)
	# 在场性已关（不可选、不占寻路）；尸体仍要看见 Death / Decay geoset
	if is_instance_valid(unit):
		unit.visible = true
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
		var ai := UnitAI.of(c as Node3D)
		if ai != null:
			ai.notify_combat_target_lost(dead)
