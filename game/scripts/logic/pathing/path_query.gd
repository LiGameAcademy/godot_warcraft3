class_name PathQuery
extends RefCounted

## 网格寻路查询（Logic）：只读 Wc3PathingMap，不碰场景树。
##
## 为何独立成 RefCounted 而不是挂在单位上：
## - A* 的「图」是整张地图共享的；每个单位拷一份 pathing / 各自跑全图搜索会浪费且难单测。
## - 单位子节点只应消费路点（见 UnitNavigator），权威可走性仍来自 WPM（PATHFINDING_CHOICE）。

## 单次搜索节点上限：防止极端不可达时拖死主线程（Echo Isles 全图格数很大）。
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


func bind_pathing(map: Wc3PathingMap) -> void:
	pathing = map


func bind_reservation(res: PathCellReservation) -> void:
	reservation = res


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
	if not is_ready():
		return false
	var c := _clearance if clearance < 0 else maxi(clearance, 0)
	if not pathing.can_walk_cell(cx, cy):
		return false
	if reservation != null and reservation.has_method("is_blocked_for"):
		if bool(reservation.call("is_blocked_for", cx, cy, _agent_id)):
			return false
	if c <= 0:
		return true
	for dy in range(-c, c + 1):
		for dx in range(-c, c + 1):
			if dx == 0 and dy == 0:
				continue
			if not pathing.can_walk_cell(cx + dx, cy + dy):
				return false
			if reservation != null and reservation.has_method("is_blocked_for"):
				if bool(reservation.call("is_blocked_for", cx + dx, cy + dy, _agent_id)):
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
	var cells := _astar(start_c, goal_c)
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
	wps = _string_pull(start_p, wps)
	if smooth_catmull:
		wps = _catmull_smooth(wps)
	reservation = prev_res
	return {"ok": true, "waypoints": wps, "reason": "astar"}


func _astar(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var w: int = pathing.width
	var h: int = pathing.height
	var total: int = w * h
	if total <= 0:
		return []
	# came_from / g_score 用平行数组：Dictionary 在大开集上分配开销明显更高。
	var came := PackedInt32Array()
	came.resize(total)
	came.fill(-1)
	var g_score := PackedFloat32Array()
	g_score.resize(total)
	g_score.fill(INF)
	var closed := PackedByteArray()
	closed.resize(total)
	closed.fill(0)

	var start_i := _idx(start, w)
	var goal_i := _idx(goal, w)
	if start_i < 0 or goal_i < 0:
		return []
	# 起终点自身不满足净空时仍允许搜（已由 snap 保证）；邻接扩展必须净空。
	g_score[start_i] = 0.0

	# 简陋二元组堆：[{f, i}, ...]；GDScript 无现成优先队列时，小顶堆足够竖切。
	var heap: Array = []
	_heap_push(heap, _heuristic(start, goal), start_i)

	var expanded := 0
	while not heap.is_empty() and expanded < max_nodes:
		var cur_i: int = int(_heap_pop(heap))
		if closed[cur_i] != 0:
			continue
		closed[cur_i] = 1
		expanded += 1
		if cur_i == goal_i:
			return _reconstruct(came, cur_i, w)
		var cx: int = cur_i % w
		@warning_ignore("integer_division")
		var cy: int = cur_i / w
		for n in _neighbors(cx, cy):
			var ni := _idx(n, w)
			if ni < 0 or closed[ni] != 0:
				continue
			if not can_walk_cell_clear(n.x, n.y):
				continue
			# 禁止斜穿「墙角」：否则单位视觉上会卡进建筑直角。
			if n.x != cx and n.y != cy:
				if not can_walk_cell_clear(cx, n.y) or not can_walk_cell_clear(n.x, cy):
					continue
			var step: float = 1.0 if (n.x == cx or n.y == cy) else 1.4142135
			var tentative: float = g_score[cur_i] + step
			if tentative >= g_score[ni]:
				continue
			came[ni] = cur_i
			g_score[ni] = tentative
			var f: float = tentative + _heuristic(n, goal)
			_heap_push(heap, f, ni)
	return []


func _neighbors(cx: int, cy: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			out.append(Vector2i(cx + dx, cy + dy))
	return out


func _idx(c: Vector2i, w: int) -> int:
	if c.x < 0 or c.y < 0 or c.x >= pathing.width or c.y >= pathing.height:
		return -1
	return c.y * w + c.x


func _heuristic(a: Vector2i, b: Vector2i) -> float:
	# Octile：与 8 邻接代价匹配，避免曼哈顿高估导致次优扩张。
	var dx := absi(a.x - b.x)
	var dy := absi(a.y - b.y)
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
		var j := i
		while j < wps.size() and is_straight_walkable(anchor, wps[j]):
			farthest = j
			j += 1
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
