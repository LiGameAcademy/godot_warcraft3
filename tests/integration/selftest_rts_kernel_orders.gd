extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _details: Array[String] = []


func _initialize() -> void:
	var bridge_script: Script = load("res://adapters/godot/RtsKernelBridge.cs")
	var bridge: Node = Node.new()
	bridge.set_script(bridge_script)
	root.add_child(bridge)
	bridge.connect("MatchEventRaised", _on_event)
	await process_frame
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(32)
	_check(bool(bridge.call("ResetNavigationMatch", 8, 4, 10.0, Vector2.ZERO, flags, 30, 7)), "queue match reset")
	bridge.call("SubmitSpawn", 1, 0, 0, Vector2(5, 5))
	bridge.call("Step", 1)
	var initial: Dictionary = bridge.call("SubmitMotionMoveOrder", 2, 0, 1, 1, Vector2(65, 5), 30.0, 0, 0.5, false, false, 0)
	var append: Dictionary = bridge.call("SubmitMotionMoveOrder", 2, 0, 2, 1, Vector2(25, 5), 30.0, 0, 0.5, false, true, 0)
	_check(bool(initial["accepted"]) and bool(append["accepted"]), "move and append accepted through GDScript")
	bridge.call("Step", 25)
	var expected: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-cli-hash="):
			expected = argument.trim_prefix("--expected-cli-hash=")
	_check(expected.length() == 64 and str(bridge.call("GetStateHash")) == expected, "native queued motion and Godot hash match")
	var view: Dictionary = _read_view(bridge)
	_check(int(view["pending_orders"]) == 1 and int(view["order_kind"]) == 1 and int(view["order_source"]) == 0,
		"read-only view reports current and pending player orders")
	var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
	var other: Node = Node.new()
	other.set_script(bridge_script)
	root.add_child(other)
	await process_frame
	other.call("ResetNavigationMatch", 8, 4, 10.0, Vector2.ZERO, flags, 30, 7)
	_check(bool(other.call("RestoreSnapshotJson", snapshot)), "new host restores active path and FIFO queue")
	bridge.call("Step", 200)
	other.call("Step", 80)
	other.call("Step", 120)
	_check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "queued motion converges across host cadence")
	view = _read_view(bridge)
	_check((view["position"] as Vector2).is_equal_approx(Vector2(25, 5)) and not bool(view["moving"])
		and int(view["pending_orders"]) == 0 and int(view["order_kind"]) == 0, "FIFO reaches final goal and clears finished orders")
	var frame: int = int(bridge.call("GetFrame")) + 1
	bridge.call("SubmitOrderStop", frame, 0, 3, 1, 0)
	bridge.call("SubmitMoveOrder", frame, 0, 4, 1, Vector2(65, 5), 30.0, 0, false, 2)
	bridge.call("Step", 1)
	view = _read_view(bridge)
	_check(int(view["order_kind"]) == 2 and not bool(view["moving"]) and _details.has("player_order_active"),
		"persistent Stop blocks same-frame unit AI move")
	var stop_snapshot: String = str(bridge.call("CaptureSnapshotJson"))
	_check(bool(other.call("RestoreSnapshotJson", stop_snapshot)), "persistent Stop restores into other host")
	other.call("SubmitMoveOrder", int(other.call("GetFrame")) + 1, 0, 5, 1, Vector2(65, 5), 30.0, 0, false, 2)
	other.call("Step", 1)
	_check(int(_read_view(other)["order_kind"]) == 2 and not bool(_read_view(other)["moving"]), "restored Stop blocks later unit AI")
	var live_hash: String = str(other.call("GetStateHash"))
	var invalid: Dictionary = other.call("SubmitMoveOrder", int(other.call("GetFrame")) + 1, 0, 6, 1, Vector2(65, 5), 30.0, 0, false, 99)
	_check(not bool(invalid["accepted"]) and str(other.call("GetStateHash")) == live_hash, "invalid source rejected without enqueuing")
	var old_format: Dictionary = JSON.parse_string(stop_snapshot) as Dictionary
	old_format["formatVersion"] = 4
	_check(not bool(other.call("RestoreSnapshotJson", JSON.stringify(old_format)))
		and str(other.call("GetStateHash")) == live_hash, "v4 recovery rejected atomically")
	other.call("SubmitMotionMoveOrder", int(other.call("GetFrame")) + 1, 0, 7, 1, Vector2(65, 5), 30.0, 0, 0.5, false, true, 0)
	other.call("Step", 1)
	_check(bool(_read_view(other)["moving"]) and int(_read_view(other)["pending_orders"]) == 0, "player append replaces persistent Stop")
	bridge.queue_free()
	other.queue_free()
	await process_frame

	var scene: PackedScene = load("res://scenes/rts_kernel_navigation_probe.tscn")
	_check(scene != null, "queue probe scene loads")
	if scene != null:
		var probe: Node = scene.instantiate()
		root.add_child(probe)
		await process_frame
		probe.set_process(false)
		var probe_bridge: Node = probe.get_node("RtsKernelBridge")
		var click: InputEventMouseButton = InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = true
		click.position = Vector2(144, 80)
		probe.call("_unhandled_input", click)
		click.shift_pressed = true
		click.position = Vector2(208, 80)
		probe.call("_unhandled_input", click)
		probe_bridge.call("Step", 1)
		probe.call("_sync_view")
		_check(int(_read_view(probe_bridge)["pending_orders"]) == 1, "scene Shift+click appends without replacing current movement")
		var status: Label = probe.get_node("Status") as Label
		_check(status.text.contains("queued=1"), "scene shows authoritative pending count")
		var key: InputEventKey = InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_S
		probe.call("_unhandled_input", key)
		var queue_hash: String = str(probe_bridge.call("GetStateHash"))
		key.keycode = KEY_SPACE
		probe.call("_unhandled_input", key)
		probe_bridge.call("Step", 1)
		_check(int(_read_view(probe_bridge)["pending_orders"]) == 0 and int(_read_view(probe_bridge)["order_kind"]) == 2,
			"scene stop clears queue and retains Stop order")
		key.keycode = KEY_R
		probe.call("_unhandled_input", key)
		_check(str(probe_bridge.call("GetStateHash")) == queue_hash and int(_read_view(probe_bridge)["pending_orders"]) == 1,
			"scene save/restore preserves queued movement")
		click.shift_pressed = false
		click.position = Vector2(272, 80)
		probe.call("_unhandled_input", click)
		probe_bridge.call("Step", 1)
		_check(int(_read_view(probe_bridge)["pending_orders"]) == 0 and bool(_read_view(probe_bridge)["moving"]),
			"ordinary scene click replaces current movement and clears queue")
		probe.queue_free()
		await process_frame
	print("selftest_rts_kernel_orders: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)


func _read_view(bridge: Node) -> Dictionary:
	var views: Array[Dictionary] = bridge.call("ReadEntityViews")
	return views[0]


func _on_event(_frame: int, _sequence: int, _kind: int, _entity_id: int, detail: String) -> void:
	_details.append(detail)


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if condition:
		print("[rts_kernel_orders] PASS: %s" % label)
	else:
		_failures += 1
		push_error("[rts_kernel_orders] FAIL: %s" % label)
