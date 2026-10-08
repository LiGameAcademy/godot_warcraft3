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
	var heights: PackedFloat64Array = PackedFloat64Array()
	heights.resize(63)
	for index: int in range(heights.size()):
		heights[index] = float(index % 9) * 10.0
	_check(bool(bridge.call("ResetTerrainMatch", 8, 6, 10.0, Vector2.ZERO, flags,
		9, 7, 10.0, Vector2.ZERO, heights, 30, 7)), "terrain match reset")
	bridge.call("SubmitSpawn", 1, 0, 0, Vector2(15, 15))
	bridge.call("Step", 1)
	var result: Dictionary = bridge.call("SubmitMotionMoveTo", 2, 0, 1, 1, Vector2(65, 15), 45.0, 0, 0.5, true)
	_check(bool(result["accepted"]), "motion command accepted")
	bridge.call("Step", 25)
	var expected: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-cli-hash="):
			expected = argument.trim_prefix("--expected-cli-hash=")
	_check(expected.length() == 64 and str(bridge.call("GetStateHash")) == expected, "native motion and Godot hash match")
	var views: Array[Dictionary] = bridge.call("ReadEntityViews")
	var view: Dictionary = views[0]
	_check(bool(view["moving"]) and absf(float(view["facing"])) > 0.01, "view exposes in-flight authoritative facing")
	var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
	var saved_hash: String = str(bridge.call("GetStateHash"))
	bridge.call("Step", 4)
	_check(bool(bridge.call("RestoreSnapshotJson", snapshot)), "moving slope snapshot restored")
	_check(str(bridge.call("GetStateHash")) == saved_hash, "facing and path recovery preserve hash")
	var other: Node = Node.new()
	other.set_script(bridge_script)
	root.add_child(other)
	await process_frame
	other.call("ResetTerrainMatch", 8, 6, 10.0, Vector2.ZERO, flags, 9, 7, 10.0, Vector2.ZERO, heights, 30, 7)
	_check(bool(other.call("RestoreSnapshotJson", snapshot)), "new host restores identical height content")
	bridge.call("Step", 80)
	other.call("Step", 30)
	other.call("Step", 50)
	_check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "motion agrees across different host cadence")
	heights[0] += 1.0
	other.call("ResetTerrainMatch", 8, 6, 10.0, Vector2.ZERO, flags, 9, 7, 10.0, Vector2.ZERO, heights, 30, 7)
	var live_hash: String = str(other.call("GetStateHash"))
	_check(not bool(other.call("RestoreSnapshotJson", snapshot)), "different height content rejects recovery")
	_check(str(other.call("GetStateHash")) == live_hash, "failed height recovery preserves running host")
	_check(not bool(other.call("ResetTerrainMatch", 8, 6, 10.0, Vector2.ZERO, flags,
		2, 2, 10.0, Vector2.ZERO, PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), 30, 7)), "incomplete height field rejected")
	_check(str(other.call("GetStateHash")) == live_hash, "failed terrain reset is atomic")
	bridge.queue_free()
	other.queue_free()
	await process_frame
	var scene: PackedScene = load("res://scenes/rts_kernel_navigation_probe.tscn")
	_check(scene != null, "motion probe scene loads")
	if scene != null:
		var probe: Node = scene.instantiate()
		root.add_child(probe)
		await process_frame
		probe.set_process(false)
		var probe_bridge: Node = probe.get_node("RtsKernelBridge")
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(16, 80)
		probe.call("_unhandled_input", click)
		probe_bridge.call("Step", 1)
		probe.call("_sync_view")
		var motion_views: Array[Dictionary] = probe_bridge.call("ReadEntityViews")
		var motion_view: Dictionary = motion_views[0]
		var visual: Polygon2D = probe.get_node("EntityVisual") as Polygon2D
		_check(float(motion_view["facing"]) < 0 and is_equal_approx(visual.rotation, float(motion_view["facing"])),
			"scene rotation consumes kernel facing")
		var visual_hash: String = str(probe_bridge.call("GetStateHash"))
		visual.position = Vector2.ZERO
		visual.rotation = 0.0
		_check(str(probe_bridge.call("GetStateHash")) == visual_hash, "visual edits cannot change authoritative state")
		probe.call("_sync_view")
		_check(visual.position.is_equal_approx(motion_view["position"] as Vector2), "view restores presentation position")
		probe.queue_free()
		await process_frame
	print("selftest_rts_kernel_motion: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[rts_kernel_motion] PASS: %s" % label)
	else:
		_failures += 1
		push_error("[rts_kernel_motion] FAIL: %s" % label)
