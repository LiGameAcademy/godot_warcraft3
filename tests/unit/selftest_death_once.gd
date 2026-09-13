extends Node

var calls := 0
var events := 0
var failures := 0

func _ready() -> void:
	var victim := Node3D.new()
	victim.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	add_child(victim)
	var service := DeathService.new()
	service.on_before_exit = func(_unit: Node3D) -> void: calls += 1
	service.unit_died.connect(func(_unit: Node3D, _killer: Node3D) -> void: events += 1)
	# 伤害入口先扣至零，再调用死亡编排，不能仅用 HP=0 拒绝第一次死亡。
	UnitLife.set_life(victim, 0)
	service.kill(victim)
	if calls != 1 or events != 1:
		failures += 1
		push_error("DEATH ONCE: 首次零生命死亡必须结算")
	service.kill(victim)
	var other := DeathService.new()
	other.on_before_exit = func(_unit: Node3D) -> void: calls += 1
	other.unit_died.connect(func(_unit: Node3D, _killer: Node3D) -> void: events += 1)
	other.kill(victim)
	if calls != 1 or events != 1:
		failures += 1
		push_error("DEATH ONCE: 重复死亡不能重复广播或清理")
	if WorldMembership.is_in_world(victim):
		failures += 1
		push_error("DEATH ONCE: 死亡单位必须离场")
	var reentrant := Node3D.new()
	add_child(reentrant)
	var nested := DeathService.new()
	var entered := [0]
	nested.on_before_exit = func(unit: Node3D) -> void:
		entered[0] += 1
		if entered[0] == 1:
			nested.kill(unit)
	nested.kill(reentrant)
	if entered[0] != 1:
		failures += 1
		push_error("DEATH ONCE: 回调重入必须拒绝")
	# 解除测试闭包捕获的 RefCounted 自引用。
	nested.on_before_exit = Callable()
	var removed := Node3D.new()
	add_child(removed)
	var cleanup := DeathService.new()
	cleanup.on_before_exit = func(unit: Node3D) -> void: unit.free()
	cleanup.kill(removed)
	if is_instance_valid(removed):
		failures += 1
		push_error("DEATH ONCE: 回调已释放节点时安全退出")
	print("selftest_death_once: %s (5 checks)" % ["PASS" if failures == 0 else "FAIL"])
	get_tree().quit(0 if failures == 0 else 1)
