extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var bridge_script: Script = load("res://adapters/godot/RtsKernelBridge.cs")
	var bridge: Node = Node.new()
	bridge.set_script(bridge_script)
	root.add_child(bridge)
	await process_frame
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(48)
	for y: int in range(4):
		flags[y * 8 + 3] = 2
	_check(bool(bridge.call("ResetNavigationMatch", 8, 6, 10.0, Vector2.ZERO, flags, 30, 7)), "navigation match reset")
	bridge.call("SubmitSpawn", 1, 0, 0, Vector2(15, 15))
	bridge.call("Step", 1)
	var result: Dictionary = bridge.call("SubmitMoveTo", 2, 0, 1, 1, Vector2(65, 15), 45.0, 0)
	_check(bool(result["accepted"]), "move command accepted")
	bridge.call("Step", 25)
	var expected: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-cli-hash="):
			expected = argument.trim_prefix("--expected-cli-hash=")
	_check(expected.length() == 64 and str(bridge.call("GetStateHash")) == expected, "native navigation and Godot state match")
	var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
	var hash_before: String = str(bridge.call("GetStateHash"))
	bridge.call("Step", 4)
	_check(bool(bridge.call("RestoreSnapshotJson", snapshot)), "midmovement snapshot restored")
	_check(str(bridge.call("GetStateHash")) == hash_before, "restored movement hash matches")
	var other: Node = Node.new()
	other.set_script(bridge_script)
	root.add_child(other)
	await process_frame
	other.call("ResetNavigationMatch", 8, 6, 10.0, Vector2.ZERO, flags, 30, 7)
	_check(bool(other.call("RestoreSnapshotJson", snapshot)), "new bridge restores navigation with map")
	bridge.call("Step", 80)
	other.call("Step", 30)
	other.call("Step", 50)
	_check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "different host cadence converges while moving")
	var view: Dictionary = (bridge.call("ReadEntityViews") as Array)[0]
	_check((view["position"] as Vector2).is_equal_approx(Vector2(65, 15)) and not bool(view["moving"]), "arrives without overshoot")
	var saved_live_hash: String = str(other.call("GetStateHash"))
	_check(not bool(other.call("RestoreSnapshotJson", "{}")), "bad navigation snapshot rejected")
	_check(str(other.call("GetStateHash")) == saved_live_hash, "failed restore preserves live bridge")
	bridge.queue_free()
	other.queue_free()
	await process_frame
	var scene: PackedScene = load("res://scenes/rts_kernel_navigation_probe.tscn")
	_check(scene != null, "playable navigation scene loads")
	if scene != null:
		var probe: Node = scene.instantiate()
		root.add_child(probe)
		await process_frame
		var probe_bridge: Node = probe.get_node("RtsKernelBridge")
		_check((probe_bridge.call("ReadEntityViews") as Array).size() == 1, "playable scene spawns kernel entity")
		probe.set_process(false)
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(700, 80)
		probe.call("_unhandled_input", click)
		probe_bridge.call("Step", 1)
		var clicked_view: Dictionary = (probe_bridge.call("ReadEntityViews") as Array)[0]
		_check(bool(clicked_view["moving"]), "scene click starts kernel movement")
		var key: InputEventKey = InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_S
		probe.call("_unhandled_input", key)
		var probe_hash: String = str(probe_bridge.call("GetStateHash"))
		probe_bridge.call("Step", 5)
		key.keycode = KEY_R
		probe.call("_unhandled_input", key)
		_check(str(probe_bridge.call("GetStateHash")) == probe_hash, "scene keys restore moving snapshot")
		key.keycode = KEY_SPACE
		probe.call("_unhandled_input", key)
		probe_bridge.call("Step", 1)
		var stopped_view: Dictionary = (probe_bridge.call("ReadEntityViews") as Array)[0]
		_check(not bool(stopped_view["moving"]), "scene space stops kernel movement")
		probe.queue_free()
		await process_frame
	print("selftest_rts_kernel_navigation: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[rts_kernel_navigation] PASS: %s" % label)
	else:
		_failures += 1
		push_error("[rts_kernel_navigation] FAIL: %s" % label)
