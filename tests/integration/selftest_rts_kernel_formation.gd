extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _goals: Dictionary[int, Vector2] = {}
var _reported_failures: int = 0


func _initialize() -> void:
    var script: Script = load("res://adapters/godot/RtsKernelBridge.cs")
    var bridge: Node = Node.new()
    bridge.set_script(script)
    root.add_child(bridge)
    bridge.connect("GroupMoveResultRaised", _on_group_result)
    await process_frame
    var flags: PackedByteArray = PackedByteArray()
    flags.resize(1024)
    var definitions: String = '[{"id":1,"speed":30,"radius":4},{"id":2,"speed":20,"radius":6}]'
    _check(bool(bridge.call("ResetConfiguredNavigationMatch", 32, 32, 10.0, Vector2.ZERO, flags, definitions, 30, 7)),
        "configured match loads frozen movement definitions")
    for i: int in range(6):
        bridge.call("SubmitConfiguredSpawn", 1, 0, i, Vector2(35 + i * 20, 35), 1 if i % 2 == 0 else 2)
    bridge.call("Step", 1)
    var ids: PackedInt64Array = PackedInt64Array([6, 5, 4, 3, 2, 1])
    var result: Dictionary = bridge.call("SubmitGroupMove", 2, 0, 6, ids, Vector2(225, 225), 1, 0, 0.0, true, false, 0)
    _check(bool(result["accepted"]), "GDScript submits group without member speed/radius parameters")
    bridge.call("Step", 25)
    var expected: String = ""
    for argument: String in OS.get_cmdline_user_args():
        if argument.begins_with("--expected-cli-hash="):
            expected = argument.trim_prefix("--expected-cli-hash=")
    _check(expected.length() == 64 and str(bridge.call("GetStateHash")) == expected, "group CLI and Godot hashes match")
    _check(_goals.size() == 6 and _reported_failures == 0, "typed result signal reports all actual destinations")
    var views: Array[Dictionary] = bridge.call("ReadEntityViews")
    _check(views.size() == 6 and float(views[1]["radius"]) == 6.0 and int(views[1]["movement_definition_id"]) == 2,
        "view consumes per-unit frozen sizes")
    var orders: Array[Dictionary] = bridge.call("ReadOrderViews")
    _check(orders.size() == 6 and int(orders[0]["group_id"]) > 0 and int(orders[0]["slot"]) >= 0,
        "read-only order views include persisted group and slots")
    var hash: String = str(bridge.call("GetStateHash"))
    orders[0]["goal"] = Vector2(-999, -999)
    _check(str(bridge.call("GetStateHash")) == hash, "presentation cannot overwrite assigned goals")
    var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
    var other: Node = Node.new()
    other.set_script(script)
    root.add_child(other)
    await process_frame
    other.call("ResetConfiguredNavigationMatch", 32, 32, 10.0, Vector2.ZERO, flags, definitions, 30, 7)
    _check(bool(other.call("RestoreSnapshotJson", snapshot)), "new host restores active group and definitions")
    bridge.call("Step", 500)
    other.call("Step", 123)
    other.call("Step", 377)
    _check(str(bridge.call("GetStateHash")) == str(other.call("GetStateHash")), "restored soft formation agrees across host cadence")
    views = bridge.call("ReadEntityViews")
    var arrived: bool = true
    for view: Dictionary in views:
        arrived = arrived and not bool(view["moving"]) and (view["position"] as Vector2).is_equal_approx(_goals[int(view["id"])])
    _check(arrived, "members arrive at actual separated formation destinations")
    var altered: String = definitions.replace('"speed":30', '"speed":31')
    other.call("ResetConfiguredNavigationMatch", 32, 32, 10.0, Vector2.ZERO, flags, altered, 30, 7)
    hash = str(other.call("GetStateHash"))
    _check(not bool(other.call("RestoreSnapshotJson", snapshot)) and str(other.call("GetStateHash")) == hash,
        "definition mismatch rejects recovery atomically")
    _check(not bool(other.call("ResetConfiguredNavigationMatch", 32, 32, 10.0, Vector2.ZERO, flags, '[{"id":1,"speed":0,"radius":4}]', 30, 7))
        and str(other.call("GetStateHash")) == hash, "bad startup content retains current match")
    var invalid: Dictionary = bridge.call("SubmitGroupMove", int(bridge.call("GetFrame")) + 1, 0, 7,
        PackedInt64Array([1, 1]), Vector2(200, 200), 1, 0, 0.0, true, false, 0)
    _check(not bool(invalid["accepted"]), "duplicate group member input rejected")
    var old: Dictionary = JSON.parse_string(snapshot) as Dictionary
    old["formatVersion"] = 5
    _check(not bool(bridge.call("RestoreSnapshotJson", JSON.stringify(old))), "v5 snapshot rejected after group format change")
    bridge.queue_free()
    other.queue_free()
    await process_frame

    var scene: PackedScene = load("res://scenes/rts_kernel_formation_probe.tscn")
    _check(scene != null, "configured formation probe scene loads")
    if scene != null:
        var probe: Node = scene.instantiate()
        root.add_child(probe)
        probe.set_process(false)
        await process_frame
        var probe_bridge: Node = probe.get_node("RtsKernelBridge")
        var click: InputEventMouseButton = InputEventMouseButton.new()
        click.button_index = MOUSE_BUTTON_RIGHT
        click.pressed = true
        click.shift_pressed = true
        click.position = Vector2(225, 225)
        probe.call("_unhandled_input", click)
        probe_bridge.call("Step", 1)
        orders = probe_bridge.call("ReadOrderViews")
        _check(orders.size() == 6 and int(orders[0]["formation"]) == 1, "scene Shift+RMB submits rectangle through kernel")
        click.ctrl_pressed = true
        click.position = Vector2(175, 175)
        probe.call("_unhandled_input", click)
        probe_bridge.call("Step", 1)
        orders = probe_bridge.call("ReadOrderViews")
        _check(orders.size() == 12 and int(orders[6]["group_id"]) > 0, "scene Ctrl appends resolved formation goals")
        var key: InputEventKey = InputEventKey.new()
        key.pressed = true
        key.keycode = KEY_S
        probe.call("_unhandled_input", key)
        hash = str(probe_bridge.call("GetStateHash"))
        key.keycode = KEY_SPACE
        probe.call("_unhandled_input", key)
        probe_bridge.call("Step", 1)
        views = probe_bridge.call("ReadEntityViews")
        var stopped: bool = true
        for view: Dictionary in views:
            stopped = stopped and int(view["order_kind"]) == 2 and int(view["pending_orders"]) == 0
        _check(stopped, "scene Stop clears formation queues and retains player Stop")
        key.keycode = KEY_R
        probe.call("_unhandled_input", key)
        _check(str(probe_bridge.call("GetStateHash")) == hash, "scene saves/restores current and queued group assignments")
        var status: Label = probe.get_node("Status") as Label
        _check(status.text.contains("selected=6"), "scene shows selection and kernel result feedback")
        probe.queue_free()
        await process_frame
    print("selftest_rts_kernel_formation: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
    quit(0 if _failures == 0 else 1)


func _on_group_result(_frame: int, _group_id: int, entity_id: int, _slot: int, goal: Vector2,
    assigned: bool, _adjusted: bool, _reason: String) -> void:
    if assigned:
        _goals[entity_id] = goal
    else:
        _reported_failures += 1


func _check(condition: bool, label: String) -> void:
    _checks += 1
    if condition:
        print("[rts_kernel_formation] PASS: %s" % label)
    else:
        _failures += 1
        push_error("[rts_kernel_formation] FAIL: %s" % label)
