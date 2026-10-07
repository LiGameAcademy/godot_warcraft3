extends Node

const Delay = preload("res://packages/foundation/infra/scene_delay.gd")
var failures := 0
var checks := 0
var calls := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("SCENE DELAY: " + label)

func _ready() -> void:
	var host := Node.new()
	add_child(host)
	var timer := Delay.create_timer(host, 0.05)
	timer.timeout.connect(func() -> void: calls += 1)
	await get_tree().create_timer(0.15).timeout
	check(calls == 1 and not is_instance_valid(timer), "正常延迟执行一次并回收计时器")
	var frozen := Delay.create_timer(host, 0.05)
	frozen.timeout.connect(func() -> void: calls += 1)
	host.process_mode = Node.PROCESS_MODE_DISABLED
	await get_tree().create_timer(0.15).timeout
	check(calls == 1 and is_instance_valid(frozen), "禁用宿主后不触发延迟")
	host.process_mode = Node.PROCESS_MODE_INHERIT
	await get_tree().create_timer(0.15).timeout
	check(calls == 2 and not is_instance_valid(frozen), "恢复宿主后继续计时")
	var cancelled := Delay.create_timer(host, 0.05)
	cancelled.timeout.connect(func() -> void: calls += 1)
	host.queue_free()
	await get_tree().create_timer(0.15).timeout
	check(calls == 2 and not is_instance_valid(cancelled), "卸载宿主会取消回调并销毁计时器")
	var fresh := Node.new()
	add_child(fresh)
	Delay.create_timer(fresh, 0.01).timeout.connect(func() -> void: calls += 1)
	await get_tree().create_timer(0.15).timeout
	check(calls == 3, "新宿主计时不受旧宿主销毁影响")
	print("selftest_scene_delay: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
