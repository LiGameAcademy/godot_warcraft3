extends SceneTree

var _failures: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var bridge: Node = Node.new()
	bridge.set_script(load("res://adapters/godot/RtsKernelBridge.cs"))
	root.add_child(bridge)
	await process_frame
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
	_check(bool(bridge.call("ResetContentMatch", pathing, terrain, data, balance, starts, flags, 30, 7)), "content ready")
	_check(bool((bridge.call("SpawnPreset", "hfoo", 24, 0) as Dictionary).accepted), "24 members spawn")
	var frame: Dictionary = bridge.call("ReadMovementFrame")
	var ids: PackedInt64Array = frame.ids
	bridge.call("SubmitGroupMove", 2, 0, 25, ids, Vector2(2700, 2000), 0, false)
	bridge.call("Step", 1)
	var before: String = str(bridge.call("GetStateHash"))
	var routes: Array[Dictionary] = bridge.call("ReadMovementRoutes", ids)
	_check(routes.size() == 24, "all selected current routes are exposed")
	_check(str(bridge.call("GetStateHash")) == before, "debug routes leave simulation unchanged")
	var packed: PackedScene = load("res://scenes/kernel_movement/movement_route_view.tscn") as PackedScene
	var first: MovementRouteView = packed.instantiate() as MovementRouteView
	var second: MovementRouteView = packed.instantiate() as MovementRouteView
	root.add_child(first)
	root.add_child(second)
	await process_frame
	_check(not first.visible and not second.visible, "route drawing defaults to hidden")
	first.visible = true
	second.visible = true
	first.show_routes(routes)
	second.show_routes(routes)
	_check(first.mesh.get_surface_count() == 1, "routes and goal markers produce line geometry")
	first.clear_routes()
	_check(first.mesh.get_surface_count() == 0 and second.mesh.get_surface_count() == 1, "drawing resources are instance owned")
	bridge.call("SubmitStop", 3, 0, 26, ids[0])
	bridge.call("Step", 1)
	var stopped: Array[Dictionary] = bridge.call("ReadMovementRoutes", PackedInt64Array([ids[0]]))
	_check(stopped.is_empty(), "stopped member no longer displays a stale route")
	first.queue_free()
	second.queue_free()
	bridge.queue_free()
	await process_frame
	print("selftest_movement_routes: %s" % ["PASS" if _failures == 0 else "FAIL"])
	quit(0 if _failures == 0 else 1)


func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures += 1
		push_error("movement routes: " + message)
