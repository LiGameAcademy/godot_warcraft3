extends SceneTree

var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var map := Wc3PathingMap.new()
	map.width = 256
	map.height = 256
	map.cells.resize(map.width * map.height)
	# Long wall: both reachable detour and completely disconnected destination.
	for y in range(220):
		map.cells[y * map.width + 128] = Wc3PathingMap.FLAG_NO_WALK
	var query := PathQuery.new()
	query.bind_pathing(map)
	MatchHotpathMetrics.enabled = true
	for clearance in [0, 1]:
		for attempt in range(3):
			var started := Time.get_ticks_usec()
			var result := query.find_path(map.cell_center_wc3(100, 40), map.cell_center_wc3(150, 40), clearance)
			print("CLICK_BENCH detour clearance=%d run=%d ms=%.3f ok=%s" % [clearance, attempt, (Time.get_ticks_usec() - started) / 1000.0, result.ok])
			if not result.ok:
				failed += 1
	for y in range(220, 256):
		map.cells[y * map.width + 128] = Wc3PathingMap.FLAG_NO_WALK
	var started := Time.get_ticks_usec()
	var result := query.find_path(map.cell_center_wc3(100, 40), map.cell_center_wc3(150, 40), 1)
	print("CLICK_BENCH unreachable ms=%.3f ok=%s" % [(Time.get_ticks_usec() - started) / 1000.0, result.ok])
	if result.ok:
		failed += 1
	print("CLICK_METRICS ", JSON.stringify(MatchHotpathMetrics.drain()))
	MatchHotpathMetrics.enabled = false
	_test_native_equivalence()
	_test_no_duplicate_retry()
	_test_pull_probe_count()
	print("selftest_path_click_latency: ", "PASS" if failed == 0 else "FAIL")
	quit(0 if failed == 0 else 1)

func check(ok: bool, message: String) -> void:
	if not ok:
		failed += 1
		push_error(message)

func _cost(path: Array[Vector2i]) -> float:
	var result := 0.0
	for i in range(1, path.size()):
		result += Vector2(path[i] - path[i - 1]).length()
	return result

func _test_native_equivalence() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 928341
	var map := Wc3PathingMap.new()
	map.width = 24
	map.height = 24
	map.cells.resize(576)
	map.cells_dynamic.resize(576)
	var query := PathQuery.new()
	query.bind_pathing(map)
	var reservations := PathCellReservation.new()
	query.bind_reservation(reservations)
	for iteration in range(80):
		# Mutate arrays in place, including dynamic building placement/removal.
		map.cells.fill(0)
		map.cells_dynamic.fill(0)
		for i in range(576):
			if rng.randf() < 0.08:
				map.cells[i] = Wc3PathingMap.FLAG_NO_WALK
		for i in range(12):
			map.cells_dynamic[rng.randi_range(0, 575)] = Wc3PathingMap.FLAG_NO_WALK
		reservations.clear()
		reservations.set_owner_cells(10, [Vector2i(10, 10), Vector2i(11, 10)])
		reservations.set_owner_cells(20, [Vector2i(14, 14)])
		query._agent_id = 10 if iteration % 2 == 0 else 20
		query._clearance = iteration % 2
		var grid := query._native_grid()
		for y in range(24):
			for x in range(24):
				var saved := query.reservation
				query.reservation = null
				check(grid.is_point_solid(Vector2i(x, y)) != query.can_walk_cell_clear(x, y), "native clearance mismatch")
				query.reservation = saved
		var start := query.snap_to_walkable(80, 80, 12)
		var goal := query.snap_to_walkable(650, 650, 12)
		if not start.ok or not goal.ok:
			continue
		var reference := query._astar(start.cell, goal.cell)
		var actual := query._native_astar(start.cell, goal.cell)
		check(reference.is_empty() == actual.is_empty(), "native reachability differs")
		check(absf(_cost(reference) - _cost(actual)) < 0.001, "native shortest path cost differs")
		for point in actual:
			check(query.can_walk_cell_clear(point.x, point.y), "native path crosses blocked cell")
		for i in range(1, actual.size()):
			var a := actual[i - 1]
			var b := actual[i]
			var direction := (b - a).sign()
			# Jump search returns sparse axis/diagonal segments; verify every
			# traversed cell and corner, not the rectangle across the whole jump.
			check(a.x == b.x or a.y == b.y or absi(b.x - a.x) == absi(b.y - a.y), "non-grid jump")
			for step in range(maxi(absi(b.x - a.x), absi(b.y - a.y))):
				var next := a + direction
				check(query.can_walk_cell_clear(next.x, next.y), "jump crosses blocked cell")
				if direction.x != 0 and direction.y != 0:
					check(query.can_walk_cell_clear(a.x, next.y) and query.can_walk_cell_clear(next.x, a.y), "native path cuts blocked corner")
				a = next
		# Temporary per-owner reservations must never contaminate the cached base grid.
		check(not grid.is_point_solid(Vector2i(10, 10)) or not map.can_walk_cell(10, 10) or query._clearance > 0, "reservation leaked into base grid")
		var raw: Array[Vector2] = []
		for point in actual:
			raw.append(map.cell_center_wc3(point.x, point.y))
		if not raw.is_empty():
			var anchor: Vector2 = raw[0]
			for point in query._string_pull(anchor, raw):
				check(query.is_straight_walkable(anchor, point), "pulled path crosses obstacle")
				anchor = point
	print("NATIVE_DIFFERENTIAL 80 maps: static/dynamic/clearance/owners/corners/cost/smoothing checked")

func _test_no_duplicate_retry() -> void:
	var body := Node3D.new()
	root.add_child(body)
	var nav := UnitNavigator.new()
	body.add_child(nav)
	var query := FailedQuery.new()
	nav.configure(query, null)
	check(not nav.go_to_wc3(Vector2(100, 100)), "unreachable navigation should fail")
	check(query.calls == 1, "unchanged origin must not repeat failed search")
	body.free()

class FailedQuery extends PathQuery:
	var calls := 0
	func find_path(_from: Vector2, _to: Vector2, _clearance_cells: int = 0, _id: int = 0, _ignore: bool = false) -> Dictionary:
		calls += 1
		return {"ok": false, "waypoints": [], "reason": "unreachable"}
	func snap_to_open_walkable(x: float, y: float, _radius: int = 10, _open: int = 4) -> Dictionary:
		return {"ok": true, "moved": false, "wc3": Vector2(x, y)}

func _test_pull_probe_count() -> void:
	var query := CountLineQuery.new()
	var points: Array[Vector2] = []
	for i in range(1, 1025):
		points.append(Vector2(i * 32, 16))
	var result := query._string_pull(Vector2(16, 16), points)
	check(result.size() == 1 and result[0] == points[-1], "open path should pull to destination")
	check(query.calls < 20, "long visible prefix must not require linear ray count")

class CountLineQuery extends PathQuery:
	var calls := 0
	func is_straight_walkable(_from: Vector2, _to: Vector2) -> bool:
		calls += 1
		return true
