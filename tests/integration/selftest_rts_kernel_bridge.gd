extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _events: Array[Dictionary] = []


func _initialize() -> void:
	var bridge_script: Script = load("res://adapters/godot/RtsKernelBridge.cs")
	_check(bridge_script != null, "C# bridge script loads")
	if bridge_script == null:
		_finish()
		return

	var bridge: Node = Node.new()
	bridge.set_script(bridge_script)
	root.add_child(bridge)
	await process_frame

	_check(bridge.has_method("ResetMatch"), "bridge methods exposed to GDScript")
	if not bridge.has_method("ResetMatch"):
		bridge.queue_free()
		await process_frame
		_finish()
		return
	_check(bool(bridge.call("ResetMatch", 30, 1234)), "match reset")
	var spawn: Dictionary = bridge.call("SubmitSpawn", 1, 1, 0, Vector2(10, 20))
	_check(bool(spawn.get("accepted", false)), "spawn command accepted")
	_check(bool(bridge.call("Step", 1)), "spawn frame stepped")

	var views: Array = bridge.call("ReadEntityViews")
	_check(views.size() == 1, "one entity view")
	var entity: Dictionary = views[0]
	_check(int(entity["id"]) == 1, "stable entity id")
	var velocity: Dictionary = bridge.call(
		"SubmitVelocity", 2, 1, 1, int(entity["id"]), Vector2(30, -15)
	)
	_check(bool(velocity.get("accepted", false)), "velocity command accepted")
	bridge.call("Step", 1)

	var moved: Dictionary = (bridge.call("ReadEntityViews") as Array)[0]
	_check((moved["position"] as Vector2).is_equal_approx(Vector2(11, 19.5)), "kernel position mirrored")
	var snapshot: String = bridge.call("CaptureSnapshotJson")
	var hash_before: String = bridge.call("GetStateHash")
	bridge.call("Step", 4)
	_check(bool(bridge.call("RestoreSnapshotJson", snapshot)), "snapshot restored")
	_check(str(bridge.call("GetStateHash")) == hash_before, "restored hash matches")

	# ReadEntityViews returns copied dictionaries; presentation edits cannot mutate the kernel.
	moved["position"] = Vector2(999, 999)
	var reread: Dictionary = (bridge.call("ReadEntityViews") as Array)[0]
	_check((reread["position"] as Vector2).is_equal_approx(Vector2(11, 19.5)), "view is read-only copy")

	_check(bridge.has_signal("MatchEventRaised"), "bridge event signal exposed")
	bridge.connect("MatchEventRaised", _on_match_event)
	var rejected_later: Dictionary = bridge.call(
		"SubmitVelocity", int(bridge.call("GetFrame")) + 1, 1, 2, 999, Vector2.ONE
	)
	_check(bool(rejected_later.get("accepted", false)), "future command enters deterministic queue")
	bridge.call("Step", 1)
	_check(
		_events.size() == 1
		and int(_events[0]["kind"]) == 2
		and int(_events[0]["entity_id"]) == 999
		and str(_events[0]["detail"]) == "entity_missing_or_not_owned",
		"execution rejection emitted as copied event"
	)

	_check_input_failures(bridge)

	# 与 CLI 示例使用完全相同的初始状态和命令日志。
	_check(bool(bridge.call("ResetMatch", 30, 0xC0FFEE)), "CLI parity match reset")
	bridge.call("SubmitSpawn", 1, 0, 0, Vector2(128, 256))
	bridge.call("Step", 1)
	bridge.call("SubmitVelocity", 2, 0, 1, 1, Vector2(30, 0))
	bridge.call("Step", 30)
	var cli_hash: String = _expected_cli_hash()
	_check(cli_hash.length() == 64, "current CLI hash supplied by verification runner")
	_check(str(bridge.call("GetStateHash")) == cli_hash, "Godot and CLI state hashes match")

	var other: Node = Node.new()
	other.set_script(bridge_script)
	root.add_child(other)
	await process_frame
	_check(bool(other.call("ResetMatch", 30, 0xC0FFEE)), "second match reset")
	other.call("SubmitSpawn", 1, 0, 0, Vector2(128, 256))
	other.call("Step", 1)
	other.call("SubmitVelocity", 2, 0, 1, 1, Vector2(30, 0))
	other.call("Step", 10)
	other.call("Step", 20)
	_check(str(other.call("GetStateHash")) == cli_hash, "different host cadence converges")

	other.call("Step", 1)
	_check(str(other.call("GetStateHash")) != str(bridge.call("GetStateHash")), "match clocks are isolated")
	bridge.call("Step", 1)
	_check(str(other.call("GetStateHash")) == str(bridge.call("GetStateHash")), "interleaved matches reconverge")

	var recreate_snapshot: String = bridge.call("CaptureSnapshotJson")
	bridge.queue_free()
	await process_frame
	var replacement: Node = Node.new()
	replacement.set_script(bridge_script)
	root.add_child(replacement)
	await process_frame
	_check(bool(replacement.call("RestoreSnapshotJson", recreate_snapshot)), "destroyed host restores into new bridge")
	other.call("Step", 7)
	replacement.call("Step", 3)
	replacement.call("Step", 4)
	_check(str(other.call("GetStateHash")) == str(replacement.call("GetStateHash")), "recreated match has no residual state")

	replacement.queue_free()
	other.queue_free()
	await process_frame
	_finish()


func _check_input_failures(bridge: Node) -> void:
	var original_hash: String = str(bridge.call("GetStateHash"))
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(16)
	var empty_flags: PackedByteArray = PackedByteArray()
	var heights: PackedFloat64Array = PackedFloat64Array()
	_check_input_rejection(bridge, bool(bridge.call("ResetMatch", 0, 42)), "ResetMatch", original_hash)
	_check_input_rejection(bridge, bool(bridge.call(
		"ResetNavigationMatch", 4, 4, 10.0, Vector2.ZERO, empty_flags, 30, 42
	)), "ResetNavigationMatch", original_hash)
	_check_input_rejection(bridge, bool(bridge.call(
		"ResetTerrainMatch", 4, 4, 10.0, Vector2.ZERO, flags,
		1, 1, 10.0, Vector2.ZERO, heights, 30, 42
	)), "ResetTerrainMatch", original_hash)
	_check_input_rejection(bridge, bool(bridge.call(
		"ResetConfiguredNavigationMatch", 4, 4, 10.0, Vector2.ZERO, flags, "{", 30, 42
	)), "ResetConfiguredNavigationMatch", original_hash)
	_check_input_rejection(bridge, bool(bridge.call(
		"ResetConfiguredNavigationMatch", 4, 4, 10.0, Vector2.ZERO, flags,
		'[{"Id":1,"Speed":-1,"Radius":2}]', 30, 42
	)), "ResetConfiguredNavigationMatch", original_hash)
	_check_input_rejection(bridge, bool(bridge.call("RestoreSnapshotJson", "{")),
		"RestoreSnapshotJson", original_hash)
	_check_input_rejection(bridge, bool(bridge.call("RestoreSnapshotJson", "null")),
		"RestoreSnapshotJson", original_hash)
	var invalid_snapshot: String = str(bridge.call("CaptureSnapshotJson")).replace(
		'"formatVersion":9', '"formatVersion":0'
	)
	_check_input_rejection(bridge, bool(bridge.call("RestoreSnapshotJson", invalid_snapshot)),
		"RestoreSnapshotJson", original_hash)


func _check_input_rejection(bridge: Node, accepted: bool, operation: String, expected_hash: String) -> void:
	_check(not accepted, "%s rejects invalid input" % operation)
	var error_text: String = str(bridge.call("GetLastError"))
	_check(error_text.begins_with(operation + ": "), "%s reports operation context" % operation)
	_check(error_text.contains(": ArgumentException:") or error_text.contains(": ArgumentOutOfRangeException:")
		or error_text.contains(": JsonException:") or error_text.contains(": InvalidDataException:"),
		"%s reports expected exception type" % operation)
	_check(str(bridge.call("GetStateHash")) == expected_hash, "%s preserves the old match" % operation)


func _expected_cli_hash() -> String:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-cli-hash="):
			return argument.trim_prefix("--expected-cli-hash=")
	return ""


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[rts_kernel_bridge] PASS: %s" % label)
	else:
		_failures += 1
		push_error("[rts_kernel_bridge] FAIL: %s" % label)


func _on_match_event(frame: int, sequence: int, kind: int, entity_id: int, detail: String) -> void:
	_events.append({
		"frame": frame,
		"sequence": sequence,
		"kind": kind,
		"entity_id": entity_id,
		"detail": detail,
	})


func _finish() -> void:
	print("selftest_rts_kernel_bridge: %s (%d checks)" % [
		"PASS" if _failures == 0 else "FAIL",
		_checks,
	])
	quit(0 if _failures == 0 else 1)
