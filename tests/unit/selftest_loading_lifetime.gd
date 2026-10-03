extends Node

var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("LOADING LIFETIME: " + label)

func tween_refs(excluded: Array[WeakRef] = []) -> Array[WeakRef]:
	var refs: Array[WeakRef] = []
	for tween: Tween in get_tree().get_processed_tweens():
		var existing: bool = false
		for previous: WeakRef in excluded:
			existing = existing or previous.get_ref() == tween
		if not existing:
			refs.append(weakref(tween))
	return refs

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/game_loading_screen.tscn")
	var screen: GameLoadingScreen = packed.instantiate()
	screen.min_visible_sec = 0.0
	screen.fade_out_sec = 10.0
	add_child(screen)
	# 只跟踪本加载屏产生的补间；控制台等 Autoload 也可能有动画。
	var baseline: Array[WeakRef] = tween_refs()
	screen.finish()
	var refs: Array[WeakRef] = tween_refs(baseline)
	await get_tree().process_frame
	check(refs.size() == 1, "长淡出产生一个补间动画")
	screen.process_mode = Node.PROCESS_MODE_DISABLED
	screen.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var released: bool = true
	for ref: WeakRef in refs:
		released = released and ref.get_ref() == null
	check(released, "冻结中卸载加载层释放未结束补间")
	var normal: GameLoadingScreen = packed.instantiate()
	normal.min_visible_sec = 0.0
	normal.fade_out_sec = 0.02
	add_child(normal)
	normal.finish()
	await get_tree().create_timer(0.15).timeout
	check(not is_instance_valid(normal), "正常淡出结束自动移除加载层")
	var waiting: GameLoadingScreen = packed.instantiate()
	waiting.min_visible_sec = 10.0
	add_child(waiting)
	waiting.finish()
	var pending: WeakRef = null
	for child: Node in waiting.get_children():
		if child is Timer:
			pending = weakref(child)
	check(pending != null, "最短显示时间等待由子计时器持有")
	waiting.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(pending != null and pending.get_ref() == null, "淡出前卸载也释放等待计时器")
	print("selftest_loading_lifetime: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
