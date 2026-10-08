extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _timeouts: int = 0


func _initialize() -> void:
    var script: Script = load("res://adapters/godot/RtsKernelBridge.cs")
    var bridge: Node = Node.new()
    bridge.set_script(script)
    root.add_child(bridge)
    bridge.connect("MatchEventRaised", _on_event)
    await process_frame
    var flags: PackedByteArray = PackedByteArray()
    flags.resize(1024)
    var definitions: String = '[{"id":1,"speed":60,"radius":4}]'
    _check(bool(bridge.call("ResetConfiguredNavigationMatch", 32, 32, 10.0, Vector2.ZERO, flags, definitions, 30, 7)), "crowd definitions initialize")
    bridge.call("SubmitConfiguredSpawn", 1, 0, 0, Vector2(35, 155), 1)
    bridge.call("SubmitConfiguredSpawn", 1, 0, 1, Vector2(155, 155), 1)
    bridge.call("Step", 1)
    bridge.call("SubmitStop", 2, 0, 2, 2)
    bridge.call("SubmitMoveTo", 2, 0, 3, 1, Vector2(275, 155), 60.0, 0)
    bridge.call("Step", 65)
    var expected: String = ""
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--expected-cli-hash="):
            expected = argument.trim_prefix("--expected-cli-hash=")
    _check(expected.length() == 64 and str(bridge.call("GetStateHash")) == expected, "crowd CLI/Godot state agrees")
    var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
    var other: Node = Node.new()
    other.set_script(script)
    root.add_child(other)
    await process_frame
    other.call("ResetConfiguredNavigationMatch", 32, 32, 10.0, Vector2.ZERO, flags, definitions, 30, 7)
    _check(bool(other.call("RestoreSnapshotJson", snapshot)), "detour and retry state restores")
    bridge.call("Step", 120)
    other.call("Step", 30)
    other.call("Step", 90)
    _check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "detour recovery agrees across host cadence")
    var views: Array[Dictionary] = bridge.call("ReadEntityViews")
    _check((views[0]["position"] as Vector2).is_equal_approx(Vector2(275, 155)), "actor arrives around stationary body")
    _check((views[1]["position"] as Vector2).is_equal_approx(Vector2(155, 155)) and int(views[1]["order_kind"]) == 2, "Stop body remains fixed")

    flags.resize(96)
    flags.fill(2)
    for x: int in range(32):
        flags[32 + x] = 0
    bridge.call("ResetConfiguredNavigationMatch", 32, 3, 10.0, Vector2.ZERO, flags, definitions, 30, 7)
    bridge.call("SubmitConfiguredSpawn", 1, 0, 0, Vector2(35, 15), 1)
    bridge.call("SubmitConfiguredSpawn", 1, 0, 1, Vector2(155, 15), 1)
    bridge.call("Step", 1)
    bridge.call("SubmitMoveTo", 2, 0, 2, 1, Vector2(275, 15), 60.0, 0)
    bridge.call("SubmitMoveOrder", 2, 0, 3, 1, Vector2(25, 15), 60.0, 0, true, 0)
    bridge.call("Step", 80)
    var motion: Array[Dictionary] = bridge.call("ReadMovementViews")
    _check(motion.size() == 1 and int(motion[0]["wait_frames"]) > 0, "read-only bridge reports physical waiting")
    var hash: String = str(bridge.call("GetStateHash"))
    motion[0]["wait_frames"] = 999
    _check(str(bridge.call("GetStateHash")) == hash, "view cannot change blockage clock")
    snapshot = str(bridge.call("CaptureSnapshotJson"))
    other.call("ResetConfiguredNavigationMatch", 32, 3, 10.0, Vector2.ZERO, flags, definitions, 30, 7)
    _check(bool(other.call("RestoreSnapshotJson", snapshot)), "corridor blocked snapshot restores")
    bridge.call("Step", 160)
    other.call("Step", 160)
    views = bridge.call("ReadEntityViews")
    _check(_timeouts == 1 and (views[0]["position"] as Vector2).is_equal_approx(Vector2(25, 15)), "timeout reports once and continues queued goal")
    _check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "timeout/queue continuation agrees after restore")

    flags.resize(4096)
    flags.fill(0)
    bridge.call("ResetConfiguredNavigationMatch", 64, 64, 10.0, Vector2.ZERO, flags, definitions, 30, 7)
    var ids: PackedInt64Array = PackedInt64Array()
    for i: int in range(65):
        bridge.call("SubmitConfiguredSpawn", 1, 0, i, Vector2(35 + i % 10 * 20, 35 + i / 10 * 20), 1)
        ids.append(i + 1)
    bridge.call("Step", 1)
    bridge.call("SubmitGroupMove", 2, 0, 65, ids, Vector2(425, 425), 1, 0, 0.0, true, false, 0)
    bridge.call("Step", 1)
    var plans: Array[Dictionary] = bridge.call("ReadGroupPlanViews")
    _check(plans.size() == 1 and int(plans[0]["members"]) == 65, "large group exposes fixed-work pending plan")
    snapshot = str(bridge.call("CaptureSnapshotJson"))
    other.call("ResetConfiguredNavigationMatch", 64, 64, 10.0, Vector2.ZERO, flags, definitions, 30, 7)
    _check(bool(other.call("RestoreSnapshotJson", snapshot)), "host restores pending assignment work")
    bridge.call("Step", 20)
    other.call("Step", 20)
    _check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "pending plan commits consistently after host restore")
    bridge.queue_free()
    other.queue_free()
    await process_frame

    var scene: PackedScene = load("res://scenes/rts_kernel_crowd_probe.tscn")
    _check(scene != null, "crowd acceptance scene loads")
    if scene != null:
        var probe: Node = scene.instantiate()
        root.add_child(probe)
        probe.set_process(false)
        await process_frame
        var child: Node = probe.get_node("RtsKernelBridge")
        views = child.call("ReadEntityViews")
        _check(views.size() == 13 and int(views[12]["order_kind"]) == 2, "scene has twelve actors and independent stopped blocker")
        var status: Label = probe.get_node("Status") as Label
        _check(status.text.contains("selected=12") and status.text.contains("planning=0"), "scene displays kernel diagnostics")
        var click: InputEventMouseButton = InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_RIGHT
        click.pressed = true
        click.shift_pressed = true
        click.position = Vector2(245, 245)
        probe.call("_unhandled_input", click)
        child.call("Step", 1)
        var orders: Array[Dictionary] = child.call("ReadOrderViews")
        _check(orders.size() == 13 and int(orders[0]["group_id"]) > 0, "scene routes selected formation through kernel")
        var key: InputEventKey = InputEventKey.new()
        key.pressed = true
        key.keycode = KEY_S
        probe.call("_unhandled_input", key)
        hash = str(child.call("GetStateHash"))
        child.call("Step", 100)
        key.keycode = KEY_R
        probe.call("_unhandled_input", key)
        _check(str(child.call("GetStateHash")) == hash, "crowd scene restores positions, waits and slots")
        probe.queue_free()
        await process_frame
    print("selftest_rts_kernel_crowd: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
    quit(0 if _failures == 0 else 1)


func _on_event(_frame: int, _sequence: int, _kind: int, _entity_id: int, detail: String) -> void:
    if detail == "crowd_blocked_timeout":
        _timeouts += 1


func _check(condition: bool, label: String) -> void:
    _checks += 1
    if condition:
        print("[rts_kernel_crowd] PASS: %s" % label)
    else:
        _failures += 1
        push_error("[rts_kernel_crowd] FAIL: %s" % label)
