extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _completed: int = 0
var _movement_failures: int = 0
var _review_replays: int = 0
var _bridge: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_bridge = Node.new()
	_bridge.set_script(load("res://adapters/godot/RtsKernelBridge.cs"))
	root.add_child(_bridge)
	_bridge.connect("MatchEventRaised", _on_match_event)
	await process_frame
	_run_case(31, [Vector2(1443, 1425), Vector2(2399, 2335), Vector2(2470, 1415), Vector2(2119, 2823), Vector2(1380, 2995)])
	_run_case(10, [Vector2(2337, 2186), Vector2(2711, 1201), Vector2(2935, 2829), Vector2(2653, 2878), Vector2(2066, 2735)])
	_run_case(80, [Vector2(2586, 2986), Vector2(2242, 2699), Vector2(1250, 2186), Vector2(1919, 2526), Vector2(2573, 1871)])
	_run_case(62, [Vector2(1799, 1480), Vector2(1673, 1354), Vector2(2079, 2420), Vector2(2028, 1542), Vector2(1267, 2812)])
	_run_case(46, [Vector2(2522, 2353), Vector2(2036, 2745), Vector2(2275, 1918), Vector2(2974, 1282), Vector2(2224, 2903)])
	_run_case(65, [Vector2(2694, 1756), Vector2(1346, 2738), Vector2(2438, 1719), Vector2(2168, 2786), Vector2(1200, 2613)])
	_check(_review_replays > 0, "runtime replay contains active authoritative route-review state")
	_check_stop()
	_bridge.queue_free()
	await process_frame
	print("selftest_rts_kernel_route_review: %s (%d checks; %d review replays)" % ["PASS" if _failures == 0 else "FAIL", _checks, _review_replays])
	quit(0 if _failures == 0 else 1)


func _reset() -> PackedInt64Array:
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(128 * 128)
	var heights: Array[float] = []
	heights.resize(33 * 33)
	heights.fill(0.0)
	var pathing: String = JSON.stringify({"width": 128, "height": 128, "cellsBase64": Marshalls.raw_to_base64(flags)})
	var terrain: String = JSON.stringify({"tilepointWidth": 33, "tilepointHeight": 33, "tileSize": 128, "heights": heights})
	var data: String = '{"records":[{"unitID":"hfoo","movetp":"foot","turnRate":0.6}]}'
	var balance: String = '{"records":[{"unitBalanceID":"hfoo","spd":270,"collision":31}]}'
	var starts: String = '{"units":[{"typeId":"sloc","owner":0,"position":{"x":2048,"y":2048}}]}'
	_check(bool(_bridge.call("ResetContentMatch", pathing, terrain, data, balance, starts, flags, 30, 7)), "content initializes")
	var spawned: Dictionary = _bridge.call("SpawnPreset", "hfoo", 24, 0)
	_check(bool(spawned.accepted), "24 actual-sized units spawn")
	var frame: Dictionary = _bridge.call("ReadMovementFrame")
	return frame.ids as PackedInt64Array


func _run_case(interval: int, goals: Array[Vector2]) -> void:
	var ids: PackedInt64Array = _reset()
	var last: int = interval * (goals.size() - 1)
	var last_command_frame: int = 0
	_completed = 0
	_movement_failures = 0
	for elapsed: int in range(last + 600):
		if elapsed % interval == 0 and elapsed / interval < goals.size():
			var index: int = elapsed / interval
			last_command_frame = int(_bridge.call("GetFrame")) + 1
			_bridge.call("SubmitGroupMove", last_command_frame, 0, 1000 + index, ids, goals[index], 0, false)
			_completed = 0
			_movement_failures = 0
		_bridge.call("Step", 1)
		if elapsed == last + 40:
			_check_replay()
		if elapsed >= last and _completed == 24:
			break
	var duration: int = int(_bridge.call("GetFrame")) - last_command_frame + 1
	print("godot_route_review interval=%d complete=%d failed=%d frames_after_last=%d" % [interval, _completed, _movement_failures, duration])
	_check(_completed == 24 and _movement_failures == 0 and duration <= 450, "all24 finish repeated replacements without a failure substitute")
	var before: Dictionary = _bridge.call("ReadMovementFrame")
	var positions: PackedVector3Array = before.positions
	_bridge.call("Step", 90)
	var after: Dictionary = _bridge.call("ReadMovementFrame")
	_check(positions == after.positions and _completed == 24, "party remains still with exactly-once completion")


func _check_replay() -> void:
	var saved: String = str(_bridge.call("CaptureSnapshotJson"))
	var completed: int = _completed
	var failures: int = _movement_failures
	_bridge.call("Step", 20)
	var expected: String = str(_bridge.call("GetStateHash"))
	_check(bool(_bridge.call("RestoreSnapshotJson", saved)), "opaque v14 snapshot restores")
	_completed = completed
	_movement_failures = failures
	_bridge.call("Step", 20)
	_check(str(_bridge.call("GetStateHash")) == expected, "route progress and movement resume identically")
	if saved.contains('"review":{'):
		_review_replays += 1


func _check_stop() -> void:
	var frame: Dictionary = _bridge.call("ReadMovementFrame")
	var ids: PackedInt64Array = frame.ids
	_bridge.call("SubmitGroupMove", int(_bridge.call("GetFrame")) + 1, 0, 2000, ids, Vector2(2400, 2400), 0, false)
	_bridge.call("Step", 20)
	_bridge.call("SubmitStop", int(_bridge.call("GetFrame")) + 1, 0, 2001, ids[0])
	_bridge.call("Step", 1)
	frame = _bridge.call("ReadMovementFrame")
	var position: Vector3 = (frame.positions as PackedVector3Array)[0]
	_bridge.call("Step", 90)
	frame = _bridge.call("ReadMovementFrame")
	var routes: Array[Dictionary] = _bridge.call("ReadMovementRoutes", PackedInt64Array([ids[0]]))
	_check((frame.positions as PackedVector3Array)[0] == position and routes.is_empty(), "review cannot reactivate a stopped unit")


func _on_match_event(_frame: int, _sequence: int, kind: int, _entity: int, _detail: String) -> void:
	if kind == 3:
		_completed += 1
	elif kind == 2 or kind == 4:
		_movement_failures += 1


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[kernel_route_review] " + message)
