class_name PathQuery
extends RefCounted

## 网格寻路查询（Logic）：只读 Wc3PathingMap，不碰场景树。
##
## 为何独立成 RefCounted 而不是挂在单位上：
## - A* 的「图」是整张地图共享的；每个单位拷一份 pathing / 各自跑全图搜索会浪费且难单测。
## - 单位子节点只应消费路点（见 UnitNavigator），权威可走性仍来自 WPM（PATHFINDING_CHOICE）。

## 脚本后端搜索上限；显式修改 max_nodes 时使用脚本后端保留限额语义。
## 默认原生后端完整搜索可达区域，不把展开 48000 格当作不可达。
const DEFAULT_MAX_NODES := 48000
## 直线采样步长（寻路格比例）：过稀会「穿墙漏检」，过密浪费。
const LINE_SAMPLE_FRAC := 0.35

var pathing: Wc3PathingMap = null
var max_nodes: int = DEFAULT_MAX_NODES
## 当前寻路净空（find_path 时写入；A*/直线/吸附共用）
var _clearance: int = 0
## 可选：运行时格预约（他人占用视为不可走）
var reservation: PathCellReservation = null
var _agent_id: int = 0
## 弦拉直后是否做 Catmull-Rom 细分（不可走采样会丢弃）
var smooth_catmull: bool = true
var catmull_subdiv: int = 3
## A* 工作缓冲：Echo Isles ≈ 19 万格；代际戳避免每次全表 fill。
var _astar_w: int = 0
var _astar_h: int = 0
var _astar_came: PackedInt32Array = PackedInt32Array()
var _astar_g: PackedFloat32Array = PackedFloat32Array()
var _astar_g_gen: PackedInt32Array = PackedInt32Array()
var _astar_closed_gen: PackedInt32Array = PackedInt32Array()
var _astar_gen: int = 1
var _walk_gen: PackedInt32Array = PackedInt32Array()
var _walk_ok: PackedByteArray = PackedByteArray()
var _walk_cache_active := false
## Native search preserves grid costs/clearance; script backend remains a differential oracle.
var use_native_astar := true
var _native_grids: Dictionary = {}
var _native_static := PackedByteArray()
var _native_dynamic := PackedByteArray()
var _native_size := Vector2i.ZERO
var _query_walk_cache: Dictionary = {}
var _query_active := false


func bind_pathing(map: Wc3PathingMap) -> void:
	pathing = map
	_astar_w = 0
	_astar_h = 0
	_native_grids.clear()


func bind_reservation(res: PathCellReservation) -> void:
	reservation = res


## Build common movement grids during map setup, before the first player click.
func prepare_navigation() -> void:
	var started: int = MatchHotpathMetrics.begin()
	_measured_prepare_navigation()
	MatchHotpathMetrics.finish(&"navigation_prepare", started)


func _measured_prepare_navigation() -> void:
	if not use_native_astar or not is_ready():
		return
	var saved := _clearance
	for clearance in [0, 1]:
		_clearance = clearance
		_native_grid()
	_clearance = saved


func is_ready() -> bool:
	return pathing != null and pathing.is_valid()


func can_walk_wc3(wc3_x: float, wc3_y: float) -> bool:
	if not is_ready():
		return false
	return pathing.can_walk_at(wc3_x, wc3_y)


func world_to_cell(wc3_x: float, wc3_y: float) -> Vector2i:
	if not is_ready():
		return Vector2i.ZERO
	return pathing.world_to_cell(wc3_x, wc3_y)


## 格子是否满足智能体净空（Chebyshev 邻域全可走）+ 他人预约。
func can_walk_cell_clear(cx: int, cy: int, clearance: int = -1) -> bool:
	if _query_active and clearance < 0:
		var cell := Vector2i(cx, cy)
		if not _query_walk_cache.has(cell):
			_query_walk_cache[cell] = _can_walk_cell_clear_uncached(cx, cy, clearance)
		return _query_walk_cache[cell]
	if _walk_cache_active and clearance < 0:
		if cx < 0 or cy < 0 or cx >= _astar_w or cy >= _astar_h:
			return false
		var index := cy * _astar_w + cx
		if _walk_gen[index] != _astar_gen:
			_walk_gen[index] = _astar_gen
			_walk_ok[index] = int(_can_walk_cell_clear_uncached(cx, cy, clearance))
		return _walk_ok[index] != 0
	return _can_walk_cell_clear_uncached(cx, cy, clearance)


func _can_walk_cell_clear_uncached(cx: int, cy: int, clearance: int = -1) -> bool:
	if not is_ready():
		return false
	var c := _clearance if clearance < 0 else maxi(clearance, 0)
	if not pathing.can_walk_cell(cx, cy):
		return false
	var res := reservation
	var aid := _agent_id
	if res != null and res.is_blocked_for(cx, cy, aid):
		return false
	if c <= 0:
		return true
	for dy in range(-c, c + 1):
		for dx in range(-c, c + 1):
			if dx == 0 and dy == 0:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if not pathing.can_walk_cell(nx, ny):
				return false
			if res != null and res.is_blocked_for(nx, ny, aid):
				return false
	return true


## 将任意点吸到附近可走位置。失败返回原格（调用方应看 ok）。
## 为何需要：玩家右键常点在装饰/脚印边缘，原作也会把终点「弹」到可走处。
## 已可走时保留点击坐标（不强制格心），否则手感会「永远差半格」。
func snap_to_walkable(
	wc3_x: float,
	wc3_y: float,
	max_radius_cells: int = 12,
	clearance: int = -1
) -> Dictionary:
	var empty := {"ok": false, "wc3": Vector2(wc3_x, wc3_y), "cell": Vector2i.ZERO}
	if not is_ready():
		return empty
	var c0 := pathing.world_to_cell(wc3_x, wc3_y)
	if can_walk_cell_clear(c0.x, c0.y, clearance):
		return {"ok": true, "wc3": Vector2(wc3_x, wc3_y), "cell": c0}
	for r in range(1, max_radius_cells + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := c0.x + dx
				var cy := c0.y + dy
				if can_walk_cell_clear(cx, cy, clearance):
					return {
						"ok": true,
						"wc3": pathing.cell_center_wc3(cx, cy),
						"cell": Vector2i(cx, cy),
					}
	return empty


## 沿射线向外找第一个可走格（建筑脚印外缘交货/出矿门）。
## 比环形 snap 更稳：不会拐到建筑侧面导致左右出生点不对称。
func snap_along_dir_walkable(
	origin_wc3: Vector2,
	dir_wc3: Vector2,
	start_dist_wc3: float,
	max_extra_cells: int = 16
) -> Dictionary:
	var empty := {"ok": false, "wc3": origin_wc3, "cell": Vector2i.ZERO}
	if not is_ready():
		return empty
	var dir := dir_wc3
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, -1.0)
	else:
		dir = dir.normalized()
	var start := maxf(start_dist_wc3, Wc3Coords.PATHING_CELL)
	for i in range(0, maxi(max_extra_cells, 0) + 1):
		var dist := start + float(i) * Wc3Coords.PATHING_CELL
		var p := origin_wc3 + dir * dist
		var c := pathing.world_to_cell(p.x, p.y)
		if can_walk_cell_clear(c.x, c.y, 0):
			return {
				"ok": true,
				"wc3": pathing.cell_center_wc3(c.x, c.y),
				"cell": c,
			}
	var raw := origin_wc3 + dir * start
	return snap_to_walkable(raw.x, raw.y, maxi(max_extra_cells, 8))


## 建筑交货/贴边：在「目标中心 → 朝 from 外侧」取点，再吸附到可走格。
## 避免 go_to(建筑中心) 被 snap 到建筑背面（远点）。
func approach_point_wc3(
	from_wc3: Vector2,
	target_wc3: Vector2,
	target_radius_wc3: float = 176.0,
	margin_wc3: float = 48.0,
	max_radius_cells: int = 16
) -> Dictionary:
	var empty := {"ok": false, "wc3": target_wc3}
	if not is_ready():
		return empty
	var delta := from_wc3 - target_wc3
	if delta.length_squared() < 1.0:
		delta = Vector2(0.0, -1.0)
	var raw := target_wc3 + delta.normalized() * (maxf(target_radius_wc3, 32.0) + margin_wc3)
	var snap := snap_to_walkable(raw.x, raw.y, max_radius_cells)
	if bool(snap.get("ok", false)):
		return {"ok": true, "wc3": snap["wc3"], "cell": snap.get("cell", Vector2i.ZERO)}
	# 回退：目标周围距 from 最近的可走格
	var best := Vector2.INF
	var best_d2 := INF
	var best_c := Vector2i.ZERO
	var c0 := pathing.world_to_cell(target_wc3.x, target_wc3.y)
	var found := false
	for r in range(1, max_radius_cells + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := c0.x + dx
				var cy := c0.y + dy
				if not can_walk_cell_clear(cx, cy, 0):
					continue
				var center := pathing.cell_center_wc3(cx, cy)
				var d2 := from_wc3.distance_squared_to(center)
				if d2 < best_d2:
					best_d2 = d2
					best = center
					best_c = Vector2i(cx, cy)
					found = true
		if found and r >= 3:
			break
	if not found:
		return empty
	return {"ok": true, "wc3": best, "cell": best_c}


## 8 邻可走格数。建筑 pathTex 凹角口袋通常 ≤3，开阔地接近 8。
func walkable_neighbor_count(cx: int, cy: int) -> int:
	if not is_ready():
		return 0
	var n := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if pathing.can_walk_cell(cx + dx, cy + dy):
				n += 1
	return n


## 把卡在凹角/窄缝的单位弹到更开阔的可走格（不改 WPM）。
## 已够开阔则保留原坐标；否则在半径内选 openness 最高、再选距原点近的格心。
func snap_to_open_walkable(
	wc3_x: float,
	wc3_y: float,
	max_radius_cells: int = 10,
	min_openness: int = 4
) -> Dictionary:
	var empty := {"ok": false, "wc3": Vector2(wc3_x, wc3_y), "cell": Vector2i.ZERO, "openness": 0}
	if not is_ready():
		return empty
	var c0 := pathing.world_to_cell(wc3_x, wc3_y)
	var open0 := 0
	if pathing.can_walk_cell(c0.x, c0.y):
		open0 = walkable_neighbor_count(c0.x, c0.y)
		if open0 >= min_openness:
			return {
				"ok": true,
				"wc3": Vector2(wc3_x, wc3_y),
				"cell": c0,
				"openness": open0,
				"moved": false,
			}
	var best_c := Vector2i.ZERO
	var best_open := -1
	var best_d2 := INF
	var found := false
	for r in range(0, max_radius_cells + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := c0.x + dx
				var cy := c0.y + dy
				if not pathing.can_walk_cell(cx, cy):
					continue
				var op := walkable_neighbor_count(cx, cy)
				if op < min_openness and op <= open0:
					continue
				var center := pathing.cell_center_wc3(cx, cy)
				var d2 := Vector2(wc3_x, wc3_y).distance_squared_to(center)
				if op > best_open or (op == best_open and d2 < best_d2):
					best_open = op
					best_d2 = d2
					best_c = Vector2i(cx, cy)
					found = true
	if not found:
		return snap_to_walkable(wc3_x, wc3_y, max_radius_cells)
	return {
		"ok": true,
		"wc3": pathing.cell_center_wc3(best_c.x, best_c.y),
		"cell": best_c,
		"openness": best_open,
		"moved": true,
	}


## 远离邻近 NO_WALK 格（建筑脚印凹角），避免 soft 分离把人推进死角。
## 返回 WC3 XY / 秒的推开速度。
func compute_wall_push_velocity(pos_wc3: Vector2, sample_cells: int = 2) -> Vector2:
	if not is_ready():
		return Vector2.ZERO
	var c0 := pathing.world_to_cell(pos_wc3.x, pos_wc3.y)
	var push := Vector2.ZERO
	var r := maxi(sample_cells, 1)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx == 0 and dy == 0:
				continue
			var cx := c0.x + dx
			var cy := c0.y + dy
			if pathing.can_walk_cell(cx, cy):
				continue
			var center := pathing.cell_center_wc3(cx, cy)
			var delta := pos_wc3 - center
			var dist := delta.length()
			if dist < 0.01:
				delta = Vector2(float(-dx), float(-dy))
				dist = 0.01
			# 越近墙推力越大；对角格权重略低
			var w := 1.0 / float(maxi(absi(dx), absi(dy)))
			push += (delta / dist) * w * pathing.cell_size
	if push == Vector2.ZERO:
		return Vector2.ZERO
	# 与单位分离同量级上限，避免贴墙时抖
	const MAX_WALL_PUSH := 200.0
	var spd := push.length()
	if spd > MAX_WALL_PUSH:
		push *= MAX_WALL_PUSH / spd
	return push


## 直线是否全程可走（D0 快捷路径）。为何先做直线：
## 多数短距离移动无遮挡，可跳过 A*，手感更「点哪走哪」。
func is_straight_walkable(from_wc3: Vector2, to_wc3: Vector2) -> bool:
	if not is_ready():
		return false
	if not _wc3_clear_ok(from_wc3.x, from_wc3.y):
		return false
	if not _wc3_clear_ok(to_wc3.x, to_wc3.y):
		return false
	var delta := to_wc3 - from_wc3
	var dist := delta.length()
	if dist < 1.0:
		return true
	var step := pathing.cell_size * LINE_SAMPLE_FRAC
	var n: int = maxi(1, int(ceil(dist / step)))
	for i in range(1, n):
		var t := float(i) / float(n)
		var p := from_wc3.lerp(to_wc3, t)
		if not _wc3_clear_ok(p.x, p.y):
			return false
	return true


func _wc3_clear_ok(wc3_x: float, wc3_y: float) -> bool:
	var c := pathing.world_to_cell(wc3_x, wc3_y)
	return can_walk_cell_clear(c.x, c.y)


## 主入口：返回 { ok, waypoints: Array[Vector2](WC3 XY), reason }。
## clearance_cells：PathAgentProfile 净空；agent_id：占格预约时排除自己。
## ignore_reservation：采矿走廊等固定路径，不避开其他单位预约格。
func find_path(
	from_wc3: Vector2,
	to_wc3: Vector2,
	clearance_cells: int = 0,
	agent_id: int = 0,
	ignore_reservation: bool = false
) -> Dictionary:
	var started := MatchHotpathMetrics.begin()
	_query_walk_cache.clear()
	_query_active = true
	var result: Dictionary = _measured_find_path(from_wc3, to_wc3, clearance_cells, agent_id, ignore_reservation)
	_query_active = false
	_query_walk_cache.clear()
	MatchHotpathMetrics.finish(&"pathfinding", started)
	return result


func _measured_find_path(
	from_wc3: Vector2,
	to_wc3: Vector2,
	clearance_cells: int = 0,
	agent_id: int = 0,
	ignore_reservation: bool = false
) -> Dictionary:
	if not is_ready():
		return {"ok": false, "waypoints": [], "reason": "no_pathing"}
	_clearance = maxi(clearance_cells, 0)
	_agent_id = agent_id
	var prev_res: PathCellReservation = reservation
	if ignore_reservation:
		reservation = null
	var start_snap := snap_to_walkable(from_wc3.x, from_wc3.y, 6, _clearance)
	var goal_snap := snap_to_walkable(to_wc3.x, to_wc3.y, 12, _clearance)
	if not start_snap.get("ok", false):
		reservation = prev_res
		return {"ok": false, "waypoints": [], "reason": "start_blocked"}
	if not goal_snap.get("ok", false):
		reservation = prev_res
		return {"ok": false, "waypoints": [], "reason": "goal_blocked"}
	var start_c: Vector2i = start_snap["cell"]
	var goal_c: Vector2i = goal_snap["cell"]
	var start_p: Vector2 = start_snap["wc3"]
	var goal_p: Vector2 = goal_snap["wc3"]
	if start_c == goal_c:
		reservation = prev_res
		return {"ok": true, "waypoints": [goal_p], "reason": "same_cell"}
	if is_straight_walkable(start_p, goal_p):
		reservation = prev_res
		return {"ok": true, "waypoints": [goal_p], "reason": "straight"}
	var stage := MatchHotpathMetrics.begin()
	var cells := _native_astar(start_c, goal_c) if use_native_astar and max_nodes == DEFAULT_MAX_NODES else _astar(start_c, goal_c)
	MatchHotpathMetrics.finish(&"path_search", stage)
	if cells.is_empty():
		reservation = prev_res
		return {"ok": false, "waypoints": [], "reason": "unreachable"}
	var wps: Array[Vector2] = []
	# 跳过起点格：单位已在附近，从下一格中心开始可减少「先走到格心再出发」的顿挫。
	for i in range(1, cells.size()):
		var c: Vector2i = cells[i]
		wps.append(pathing.cell_center_wc3(c.x, c.y))
	if wps.is_empty() or wps[wps.size() - 1].distance_to(goal_p) > 1.0:
		wps.append(goal_p)
	# 轻量拉直：为何在 Logic 做而不是 Navigator——减少每帧几何，路径语义仍基于可走采样。
	stage = MatchHotpathMetrics.begin()
	wps = _string_pull(start_p, wps)
	if smooth_catmull:
		wps = _catmull_smooth(wps)
	MatchHotpathMetrics.finish(&"path_smoothing", stage)
	reservation = prev_res
	return {"ok": true, "waypoints": wps, "reason": "astar"}


func _native_grid() -> AStarGrid2D:
	var size := Vector2i(pathing.width, pathing.height)
	# Keep owned snapshots: packed arrays assigned from script fields share storage.
	# Value comparison also catches
	# direct cell edits by editor/tests without relying on a missed dirty notification.
	if size != _native_size or pathing.cells != _native_static:
		_native_grids.clear()
		_native_size = size
		_native_static = pathing.cells.duplicate()
		_native_dynamic = pathing.cells_dynamic.duplicate()
	elif pathing.cells_dynamic != _native_dynamic:
		_update_native_dynamic(size)
	if _native_grids.has(_clearance):
		return _native_grids[_clearance]
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(Vector2i.ZERO, size)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	# Keep jumping disabled: EI unreachable-target measurements regress with JPS.
	grid.update()
	# Dilate blocked row runs by the same Chebyshev clearance as can_walk_cell_clear.
	for y in range(size.y):
		var run := -1
		for x in range(size.x + 1):
			var blocked := false
			if x < size.x:
				var i := y * size.x + x
				var flags := int(_native_static[i])
				if i < _native_dynamic.size():
					flags |= int(_native_dynamic[i])
				blocked = (flags & Wc3PathingMap.FLAG_NO_WALK) != 0
			if blocked and run < 0:
				run = x
			elif not blocked and run >= 0:
				grid.fill_solid_region(Rect2i(run - _clearance, y - _clearance, x - run + 2 * _clearance, 1 + 2 * _clearance).intersection(grid.region))
				run = -1
	if _clearance > 0:
		grid.fill_solid_region(Rect2i(0, 0, size.x, _clearance).intersection(grid.region))
		grid.fill_solid_region(Rect2i(0, size.y - _clearance, size.x, _clearance).intersection(grid.region))
		grid.fill_solid_region(Rect2i(0, 0, _clearance, size.y).intersection(grid.region))
		grid.fill_solid_region(Rect2i(size.x - _clearance, 0, _clearance, size.y).intersection(grid.region))
	_native_grids[_clearance] = grid
	return grid


## Dynamic edits preserve existing grids. Recompute only points whose clearance
## neighborhood intersects a changed walk bit, including overlapping footprints.
func _update_native_dynamic(size: Vector2i) -> void:
	var changed: Rect2i = Rect2i()
	var found: bool = false
	# Packed comparisons run in native code; inspect only changed chunks in script.
	for chunk in range(0, size.x * size.y, 1024):
		var end: int = mini(chunk + 1024, size.x * size.y)
		if _native_dynamic.slice(chunk, end) == pathing.cells_dynamic.slice(chunk, end):
			continue
		for index in range(chunk, end):
			var before: int = int(_native_dynamic[index]) if index < _native_dynamic.size() else 0
			var after: int = int(pathing.cells_dynamic[index]) if index < pathing.cells_dynamic.size() else 0
			if ((before ^ after) & Wc3PathingMap.FLAG_NO_WALK) == 0:
				continue
			var point: Vector2i = Vector2i(index % size.x, int(index / size.x))
			var cell_rect: Rect2i = Rect2i(point, Vector2i.ONE)
			changed = changed.merge(cell_rect) if found else cell_rect
			found = true
	_native_dynamic = pathing.cells_dynamic.duplicate()
	if not found:
		return
	# Large edits use the original full construction algorithm.
	if changed.get_area() > size.x * size.y / 4:
		_native_grids.clear()
		return
	for clearance: int in _native_grids:
		var grid: AStarGrid2D = _native_grids[clearance]
		var area: Rect2i = changed.grow(clearance).intersection(grid.region)
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				var solid: bool = false
				for dy in range(-clearance, clearance + 1):
					for dx in range(-clearance, clearance + 1):
						if not pathing.can_walk_cell(x + dx, y + dy):
							solid = true
							break
					if solid:
						break
				grid.set_point_solid(Vector2i(x, y), solid)


func _native_astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var grid := _native_grid()
	var temporary: Array[Vector2i] = []
	if reservation != null:
		for cell: Vector2i in reservation.blocked_cells_for(_agent_id):
			var area := Rect2i(cell - Vector2i(_clearance, _clearance), Vector2i.ONE * (2 * _clearance + 1)).intersection(grid.region)
			for y in range(area.position.y, area.end.y):
				for x in range(area.position.x, area.end.x):
					var point := Vector2i(x, y)
					if not grid.is_point_solid(point):
						temporary.append(point)
						grid.set_point_solid(point)
	var result := grid.get_id_path(start, goal)
	for point in temporary:
		grid.set_point_solid(point, false)
	return result


func _ensure_astar_buffers(w: int, h: int) -> void:
	var total: int = w * h
	if total <= 0:
		return
	if _astar_w == w and _astar_h == h and _astar_came.size() == total:
		return
	_astar_w = w
	_astar_h = h
	_astar_came.resize(total)
	_astar_g.resize(total)
	_astar_g_gen.resize(total)
	_astar_closed_gen.resize(total)
	_walk_gen.resize(total)
	_walk_ok.resize(total)
	_walk_gen.fill(0)
	_astar_g_gen.fill(0)
	_astar_closed_gen.fill(0)
	_astar_gen = 1


func _begin_astar_search() -> int:
	_astar_gen += 1
	if _astar_gen >= 2147483647:
		_astar_g_gen.fill(0)
		_astar_closed_gen.fill(0)
		_walk_gen.fill(0)
		_astar_gen = 1
	return _astar_gen


func _astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var w: int = pathing.width
	var h: int = pathing.height
	var total: int = w * h
	if total <= 0:
		return []
	_ensure_astar_buffers(w, h)
	var gen := _begin_astar_search()

	var start_i := _idx(start, w, h)
	var goal_i := _idx(goal, w, h)
	if start_i < 0 or goal_i < 0:
		return []
	# 起终点自身不满足净空时仍允许搜（已由 snap 保证）；邻接扩展必须净空。
	_astar_g_gen[start_i] = gen
	_astar_g[start_i] = 0.0
	_astar_came[start_i] = -1

	# 简陋二元组堆：[{f, i}, ...]；GDScript 无现成优先队列时，小顶堆足够竖切。
	var heap: Array = []
	_heap_push(heap, _heuristic(start, goal), start_i)

	var expanded := 0
	_walk_cache_active = true
	while not heap.is_empty() and expanded < max_nodes:
		var cur_i: int = int(_heap_pop(heap))
		if _astar_closed_gen[cur_i] == gen:
			continue
		_astar_closed_gen[cur_i] = gen
		expanded += 1
		if cur_i == goal_i:
			_walk_cache_active = false
			return _reconstruct(_astar_came, cur_i, w)
		var cx: int = cur_i % w
		@warning_ignore("integer_division")
		var cy: int = cur_i / w
		var cur_g: float = _astar_g[cur_i]
		# 内联 8 邻：避免每次扩展分配 Array。
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				var nx := cx + dx
				var ny := cy + dy
				var ni := _idx_xy(nx, ny, w, h)
				if ni < 0 or _astar_closed_gen[ni] == gen:
					continue
				if not can_walk_cell_clear(nx, ny):
					continue
				# 禁止斜穿「墙角」：否则单位视觉上会卡进建筑直角。
				if dx != 0 and dy != 0:
					if not can_walk_cell_clear(cx, ny) or not can_walk_cell_clear(nx, cy):
						continue
				var step: float = 1.0 if (dx == 0 or dy == 0) else 1.4142135
				var tentative: float = cur_g + step
				if _astar_g_gen[ni] == gen and tentative >= _astar_g[ni]:
					continue
				_astar_came[ni] = cur_i
				_astar_g_gen[ni] = gen
				_astar_g[ni] = tentative
				var f: float = tentative + _heuristic_xy(nx, ny, goal.x, goal.y)
				_heap_push(heap, f, ni)
	_walk_cache_active = false
	return []


func _idx(c: Vector2i, w: int, h: int = -1) -> int:
	return _idx_xy(c.x, c.y, w, h if h >= 0 else pathing.height)


func _idx_xy(x: int, y: int, w: int, h: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return y * w + x


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return _heuristic_xy(a.x, a.y, b.x, b.y)


func _heuristic_xy(ax: int, ay: int, bx: int, by: int) -> float:
	# Octile：与 8 邻接代价匹配，避免曼哈顿高估导致次优扩张。
	var dx := absi(ax - bx)
	var dy := absi(ay - by)
	var mn := mini(dx, dy)
	var mx := maxi(dx, dy)
	return float(mx - mn) + 1.4142135 * float(mn)


func _reconstruct(came: PackedInt32Array, goal_i: int, w: int) -> Array[Vector2i]:
	var rev: Array[Vector2i] = []
	var cur := goal_i
	var guard := 0
	while cur >= 0 and guard < came.size():
		@warning_ignore("integer_division")
		rev.append(Vector2i(cur % w, cur / w))
		cur = came[cur]
		guard += 1
	rev.reverse()
	return rev


## 从起点对路点做「弦拉直」：能直线看见的点就丢掉中间拐点。
func _string_pull(start: Vector2, wps: Array[Vector2]) -> Array[Vector2]:
	if wps.size() <= 1:
		return wps
	var out: Array[Vector2] = []
	var anchor := start
	var i := 0
	while i < wps.size():
		var farthest := i
		# Exponential probes avoid re-sampling the same long visible prefix for
		# every grid waypoint (quadratic work on long paths). Only retain a
		# waypoint after its complete segment passed the existing clearance test.
		var stride := 1
		var upper := wps.size() - 1
		while farthest < upper:
			var probe := mini(i + stride, upper)
			if not is_straight_walkable(anchor, wps[probe]):
				upper = probe - 1
				break
			farthest = probe
			stride *= 2
		while farthest < upper:
			var probe := (farthest + upper + 1) >> 1
			if is_straight_walkable(anchor, wps[probe]):
				farthest = probe
			else:
				upper = probe - 1
		out.append(wps[farthest])
		anchor = wps[farthest]
		i = farthest + 1
	return out


## Catmull-Rom 细分；落在不可走采样点丢弃，保证仍可贴 WPM。
func _catmull_smooth(wps: Array[Vector2]) -> Array[Vector2]:
	if wps.size() < 2 or catmull_subdiv <= 1:
		return wps
	var ext: Array[Vector2] = []
	ext.append(wps[0])
	for p in wps:
		ext.append(p)
	ext.append(wps[wps.size() - 1])
	var out: Array[Vector2] = []
	var min_step := pathing.cell_size * 0.35
	for i in range(1, ext.size() - 2):
		var p0: Vector2 = ext[i - 1]
		var p1: Vector2 = ext[i]
		var p2: Vector2 = ext[i + 1]
		var p3: Vector2 = ext[i + 2]
		for s in range(catmull_subdiv):
			var t := float(s) / float(catmull_subdiv)
			var q := _catmull_point(p0, p1, p2, p3, t)
			if not _wc3_clear_ok(q.x, q.y):
				continue
			if out.is_empty() or out[out.size() - 1].distance_to(q) >= min_step:
				out.append(q)
	var last: Vector2 = wps[wps.size() - 1]
	if out.is_empty() or out[out.size() - 1].distance_to(last) > 1.0:
		out.append(last)
	return out if out.size() >= 2 else wps


func _catmull_point(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * (
		(2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
	)


func _heap_push(heap: Array, f: float, node_i: int) -> void:
	heap.append(Vector2(f, float(node_i)))
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if (heap[p] as Vector2).x <= (heap[i] as Vector2).x:
			break
		var tmp: Variant = heap[p]
		heap[p] = heap[i]
		heap[i] = tmp
		i = p


func _heap_pop(heap: Array) -> int:
	var root: Vector2 = heap[0]
	var last: Vector2 = heap[heap.size() - 1]
	heap.pop_back()
	if heap.is_empty():
		return int(root.y)
	heap[0] = last
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var smallest := i
		if l < heap.size() and (heap[l] as Vector2).x < (heap[smallest] as Vector2).x:
			smallest = l
		if r < heap.size() and (heap[r] as Vector2).x < (heap[smallest] as Vector2).x:
			smallest = r
		if smallest == i:
			break
		var tmp: Variant = heap[i]
		heap[i] = heap[smallest]
		heap[smallest] = tmp
		i = smallest
	return int(root.y)
