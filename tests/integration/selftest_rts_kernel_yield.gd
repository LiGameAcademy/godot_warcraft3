extends SceneTree

var _checks: int = 0
var _failures: int = 0
var _movement_failures: int = 0


func _initialize() -> void:
	var bridge: Node = Node.new()
	bridge.set_script(load("res://adapters/godot/RtsKernelBridge.cs"))
	root.add_child(bridge)
	bridge.connect("MatchEventRaised", _on_match_event)
	await process_frame
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(128 * 128)
	var heights: Array[float] = []
	heights.resize(33 * 33)
	heights.fill(0.0)
	var pathing: String = JSON.stringify({"width":128, "height":128, "cellsBase64":Marshalls.raw_to_base64(flags)})
	var terrain: String = JSON.stringify({"tilepointWidth":33, "tilepointHeight":33, "tileSize":128, "heights":heights})
	var data: String = '{"records":[{"unitID":"hfoo","movetp":"foot","turnRate":0.6}]}'
	var balance: String = '{"records":[{"unitBalanceID":"hfoo","spd":270,"collision":31}]}'
	var starts: String = '{"units":[{"typeId":"sloc","owner":0,"position":{"x":2048,"y":2048}}]}'
	_check(bool(bridge.call("ResetContentMatch", pathing, terrain, data, balance, starts, flags, 30, 7)), "real-sized footman content initializes")
	var spawned: Dictionary = bridge.call("SpawnPreset", "hfoo", 24, 0)
	_check(bool(spawned.accepted), "24 units spawn using the game preset")
	var view: Dictionary = bridge.call("ReadMovementFrame")
	var ids: PackedInt64Array = view.ids
	_check(ids.size() == 24, "all24 views exist")
	bridge.call("SubmitGroupMove", int(bridge.call("GetFrame")) + 1, 0, 1000, ids, Vector2(3056, 2064), 0, false)
	for frame: int in range(600):
		bridge.call("Step", 1)
		view = bridge.call("ReadMovementFrame")
		var moving: PackedByteArray = view.moving
		if moving.count(1) == 0:
			break
	var settled_motion: PackedByteArray = view.moving
	_check(settled_motion.count(1) == 0 and _movement_failures == 0, "party settles before reverse exit")
	var positions: PackedVector3Array = view.positions
	var centre: Vector3 = Vector3.ZERO
	for position: Vector3 in positions:
		centre += position
	centre /= float(positions.size())
	var selected_index: int = 0
	for index: int in range(positions.size()):
		if positions[index].distance_squared_to(centre) < positions[selected_index].distance_squared_to(centre):
			selected_index = index
	var goal: Vector2 = Vector2(positions[selected_index].x - 800.0, positions[selected_index].y)
	bridge.call("SubmitGroupMove", int(bridge.call("GetFrame")) + 1, 0, 1001, PackedInt64Array([ids[selected_index]]), goal, 0, false)
	var helpers: Dictionary[int, bool] = {}
	var restored_during_yield: bool = false
	for frame: int in range(600):
		bridge.call("Step", 1)
		view = bridge.call("ReadMovementFrame")
		var current: PackedVector3Array = view.positions
		for index: int in range(current.size()):
			if index != selected_index and not current[index].is_equal_approx(positions[index]):
				helpers[ids[index]] = true
		if not restored_during_yield and not helpers.is_empty():
			var saved: String = str(bridge.call("CaptureSnapshotJson"))
			bridge.call("Step", 10)
			var expected_hash: String = str(bridge.call("GetStateHash"))
			_check(bool(bridge.call("RestoreSnapshotJson", saved)), "mid-yield opaque snapshot restores")
			bridge.call("Step", 10)
			_check(str(bridge.call("GetStateHash")) == expected_hash, "mid-yield bridge replay is deterministic")
			restored_during_yield = true
			view = bridge.call("ReadMovementFrame")
		var moving: PackedByteArray = view.moving
		if moving.count(1) == 0:
			break
	var final_positions: PackedVector3Array = view.positions
	var endpoint: Vector3 = final_positions[selected_index]
	_check(Vector2(endpoint.x, endpoint.y).distance_to(goal) <= 188.0, "interior single-selection reaches reverse goal envelope")
	_check(helpers.size() >= 2 and restored_during_yield, "multiple former party members actively open the exit")
	_check(_movement_failures == 0, "no movement or command failures")
	bridge.call("Step", 90)
	view = bridge.call("ReadMovementFrame")
	_check(final_positions == view.positions, "helpers do not oscillate or return after exit")
	bridge.queue_free()
	await process_frame
	print("selftest_rts_kernel_yield: %s (%d checks; %d helpers)" % ["PASS" if _failures == 0 else "FAIL", _checks, helpers.size()])
	quit(0 if _failures == 0 else 1)


func _on_match_event(_frame: int, _sequence: int, kind: int, _entity: int, _detail: String) -> void:
	if kind == 2 or kind == 4:
		_movement_failures += 1


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[kernel_yield] " + message)
