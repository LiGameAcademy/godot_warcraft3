extends SceneTree

var _checks: int = 0
var _failures: int = 0


func _initialize() -> void:
	var bridge: Node = Node.new()
	bridge.set_script(load("res://adapters/godot/RtsKernelBridge.cs"))
	root.add_child(bridge)
	await process_frame
	var flags: PackedByteArray = PackedByteArray()
	flags.resize(96 * 96)
	flags[48 * 96 + 48] = 2
	var heights: Array[float] = []
	heights.resize(625)
	heights.fill(100.0)
	var pathing: String
	var static_cells: PackedByteArray = PackedByteArray()
	static_cells.resize(96 * 96)
	pathing = JSON.stringify({"width":96, "height":96, "cellsBase64":Marshalls.raw_to_base64(static_cells)})
	var terrain: String = JSON.stringify({"tilepointWidth":25, "tilepointHeight":25, "tileSize":128, "heights":heights})
	var data: String = '{"records":[{"unitID":"hfoo","movetp":"foot","turnRate":0.6}]}'
	var balance: String = '{"records":[{"unitBalanceID":"hfoo","spd":270,"collision":31}]}'
	var starts: String = '{"units":[{"typeId":"sloc","owner":0,"position":{"x":1536,"y":1536}}]}'
	_check(bool(bridge.call("ResetContentMatch", pathing, terrain, data, balance, starts, flags, 30, 14)), "content initializes with runtime footprints")
	var spawned: Dictionary = bridge.call("SpawnPreset", "hfoo", 65, 0)
	_check(bool(spawned.accepted), "65 actual-sized bodies spawn atomically")
	var view: Dictionary = bridge.call("ReadMovementFrame")
	var ids: PackedInt64Array = view.ids
	var positions: PackedVector3Array = view.positions
	_check(ids.size() == 65 and positions.size() == 65 and view.definitions[0] == 0x68666f6f, "packed view retains entity and content identity")
	_check(is_equal_approx(float(view.radii[0]), 31.0) and is_equal_approx(positions[0].z, 100.0), "packed view consumes real radius and terrain height")
	var overlay_clear: bool = true
	for point: Vector3 in positions:
		if Vector2i(int(floor(point.x / 32.0)), int(floor(point.y / 32.0))) == Vector2i(48, 48):
			overlay_clear = false
	_check(overlay_clear, "runtime no-walk footprint is respected during spawn")
	var first: Dictionary = bridge.call("SubmitGroupMove", 2, 0, 1000, ids, Vector2(2048, 1536), 1, false)
	_check(bool(first.accepted), "group command uses definitions instead of host speed and slots")
	bridge.call("Step", 1)
	var snapshot: String = str(bridge.call("CaptureSnapshotJson"))
	var saved: String = str(bridge.call("GetStateHash"))
	bridge.call("Step", 10)
	var expected: String = str(bridge.call("GetStateHash"))
	_check(bool(bridge.call("RestoreSnapshotJson", snapshot)), "content and unfinished planning snapshot restore")
	_check(str(bridge.call("GetStateHash")) == saved, "opaque raw snapshot preserves exact state")
	bridge.call("Step", 10)
	_check(str(bridge.call("GetStateHash")) == expected, "restored group planning and movement continue identically")
	var frame: int = int(bridge.call("GetFrame"))
	bridge.call("SubmitStop", frame + 1, 0, 1001, ids[0])
	bridge.call("Step", 1)
	view = bridge.call("ReadMovementFrame")
	_check(int(view.moving[0]) == 0 and int(view.queued[0]) == 0, "stop cancels member movement and queue")
	var before: String = str(bridge.call("GetStateHash"))
	bridge.call("ReadMovementFrame")
	_check(str(bridge.call("GetStateHash")) == before, "presentation read leaves authority unchanged")
	_check(not bool(bridge.call("ResetContentMatch", pathing, "{}", data, balance, starts, flags, 30, 1)), "invalid content reset reports failure")
	_check(str(bridge.call("GetStateHash")) == before, "failed content loading preserves live match")
	var tiny: String = '{"tilepointWidth":2,"tilepointHeight":2,"heights":[0,0,0,0]}'
	_check(not bool(bridge.call("ResetContentMatch", pathing, tiny, data, balance, starts, flags, 30, 1)), "incomplete terrain coverage is rejected")
	_check(bool(bridge.call("ResetContentMatch", pathing, terrain, data, balance, starts, static_cells, 30, 14)), "different static occupancy can initialize separately")
	before = str(bridge.call("GetStateHash"))
	_check(not bool(bridge.call("RestoreSnapshotJson", snapshot)), "snapshot rejects a different footprint content identity")
	_check(str(bridge.call("GetStateHash")) == before, "failed cross-content restore preserves fresh match")
	bridge.queue_free()
	await process_frame
	print("selftest_rts_kernel_content: %s (%d checks)" % ["PASS" if _failures == 0 else "FAIL", _checks])
	quit(0 if _failures == 0 else 1)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[kernel_content] " + message)
