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
	_check(bool(bridge.call("ResetNavigationMatch", 12, 4, 10.0, Vector2.ZERO, flags, 30, 7)), "queue map resets")
	bridge.call("SubmitSpawn", 1, 0, 0, Vector2(5, 5))
	bridge.call("Step", 1)
	var first: Dictionary = bridge.call("SubmitMoveOrder", 2, 0, 1, 1, Vector2(25, 5), 300.0, 0, false)
	var second: Dictionary = bridge.call("SubmitMoveOrder", 2, 0, 2, 1, Vector2(45, 5), 300.0, 0, true)
	_check(bool(first["accepted"]) and bool(second["accepted"]), "replace and append enter the same frame")
	bridge.call("Step", 1)
	var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
	var saved_hash: String = str(bridge.call("GetStateHash"))
	bridge.call("Step", 10)
	_check(_position(bridge).is_equal_approx(Vector2(45, 5)), "appended goal executes after the first")
	_check(bool(bridge.call("RestoreSnapshotJson", snapshot)), "opaque raw snapshot restores active and queued movement")
	_check(str(bridge.call("GetStateHash")) == saved_hash, "queue restore preserves the exact hash")
	bridge.call("SubmitStop", 3, 0, 3, 1)
	bridge.call("Step", 10)
	_check(_position(bridge).is_equal_approx(Vector2(15, 5)), "stop cancels current and pending goals")
	var before: String = str(bridge.call("GetStateHash"))
	var invalid: Dictionary = bridge.call("SubmitMoveOrder", 13, 0, 4, 1, Vector2(NAN, 0), 300.0, 0, false)
	_check(not bool(invalid["accepted"]), "nonfinite Godot coordinate is rejected at the boundary")
	_check(str(bridge.call("GetStateHash")) == before, "failed conversion never mutates the queue")
	bridge.queue_free()
	await process_frame
	print("selftest_rts_kernel_order_queue: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)


func _position(bridge: Node) -> Vector2:
	var views: Array[Dictionary] = bridge.call("ReadEntityViews")
	return views[0]["position"] as Vector2


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[kernel_order_queue] " + label)
