extends Node

var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var map: Wc3PathingMap = Wc3PathingMap.new()
	map.width = 64
	map.height = 40
	map.cells.resize(2560)
	map.clear_dynamic()
	var query: PathQuery = PathQuery.new()
	query.bind_pathing(map)
	query.prepare_navigation()
	var original: AStarGrid2D = query._native_grids[1]
	var layer: MapPathingLayer = MapPathingLayer.new()
	add_child(layer)
	layer.enabled = true
	layer.rebuild(map)
	var texture: ImageTexture = layer._tex
	var reference_pixel: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	for step in range(12):
		# Addition, overlap, removal, border changes and non-walk flags.
		map.clear_dynamic()
		for offset in range(8):
			map.cells_dynamic[(step * 37 + offset) % 2560] = 10 if step % 2 == 0 else 8
		query.prepare_navigation()
		for clearance in [0, 1]:
			var grid: AStarGrid2D = query._native_grids[clearance]
			for y in range(map.height):
				for x in range(map.width):
					var blocked: bool = false
					for dy in range(-clearance, clearance + 1):
						for dx in range(-clearance, clearance + 1):
							blocked = blocked or not map.can_walk_cell(x + dx, y + dy)
					check(grid.is_point_solid(Vector2i(x, y)) == blocked, "Grid clearance mismatch")
		layer.rebuild(map)
		check(layer._tex == texture, "Overlay texture identity preserved")
		var expected_count: int = 0
		for y in range(map.height):
			for x in range(map.width):
				var flags: int = map.flag_at(x, y) & 10
				var color: Color = Color(0, 0, 0, 0)
				if flags == 10:
					color = MapPathingLayer.COLOR_BOTH
				elif flags == 8:
					color = MapPathingLayer.COLOR_NO_BUILD
				elif flags == 2:
					color = MapPathingLayer.COLOR_NO_WALK
				if flags != 0:
					expected_count += 1
				reference_pixel.set_pixel(0, 0, color)
				check(layer._image.get_pixel(x, map.height - 1 - y) == reference_pixel.get_pixel(0, 0), "Overlay color mismatch")
		check(layer.last_cell_count == expected_count, "Overlay blocked count")
	check(query._native_grids[1] == original, "Small dynamic changes reuse grids")
	map.cells[100] = 2
	query.prepare_navigation()
	check(query._native_grids[1] != original, "Direct static changes invalidate grids")
	layer.clear()
	layer.rebuild(map)
	check(layer.last_cell_count > 0, "Overlay clear/re-enable restores flags")
	layer.free()
	var loader: MapLoader = MapLoader.new()
	check(not loader.unit_has_pathing_footprint("hpea"), "Mobile worker has no map footprint")
	check(loader.unit_has_pathing_footprint("hhou"), "Building retains map footprint")
	check(not loader.unit_has_pathing_footprint("sloc"), "Start marker does not block")
	loader.free()

	var module: ProductionModule = ProductionModule.new()
	add_child(module)
	var building: Node3D = Node3D.new()
	add_child(building)
	var queue: TrainQueue = TrainQueue.new()
	building.add_child(queue)
	module.watch(queue)
	var notifications: Array[int] = [0]
	module.queue_changed.connect(func(_queue: TrainQueue): notifications[0] += 1)
	queue.enqueue("hfoo", 10, 100, 0, 2, Vector2.ZERO, 0)
	check(notifications[0] == 1, "Enqueue emits one module notification")
	var panel: ProductionPanel = ProductionPanel.new()
	add_child(panel)
	var refreshes: Array[int] = [0]
	panel.selection_refresh_requested.connect(func(): refreshes[0] += 1)
	panel.on_queue_changed(queue)
	panel.on_queue_changed(queue)
	queue.free() # Pending UI must tolerate removal before the deferred flush.
	await get_tree().process_frame
	await get_tree().process_frame
	check(refreshes[0] == 1, "UI coalesces notifications and tolerates freed queue")
	panel.free()
	building.free()
	module.free()
	print("selftest_interaction_hotpaths: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
