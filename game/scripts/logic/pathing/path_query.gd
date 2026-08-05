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


func bind_pathing(map: Wc3PathingMap) -> void:
	pathing = map


func is_ready() -> bool:
	return pathing != null and pathing.is_valid()


func can_walk_wc3(wc3_x: float, wc3_y: float) -> bool:
	if not is_ready():
		return false
	return pathing.can_walk_at(wc3_x, wc3_y)


## 将任意点吸到附近可走格中心。失败返回原格（调用方应看 ok）。
## 为何需要：玩家右键常点在装饰/脚印边缘，原作也会把终点「弹」到可走处。
func snap_to_walkable(wc3_x: float, wc3_y: float, max_radius_cells: int = 12) -> Dictionary:
	var empty := {"ok": false, "wc3": Vector2(wc3_x, wc3_y), "cell": Vector2i.ZERO}
	if not is_ready():
		return empty
	var c0 := pathing.world_to_cell(wc3_x, wc3_y)
	if pathing.can_walk_cell(c0.x, c0.y):
		return {"ok": true, "wc3": pathing.cell_center_wc3(c0.x, c0.y), "cell": c0}
	for r in range(1, max_radius_cells + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var cx := c0.x + dx
				var cy := c0.y + dy
				if pathing.can_walk_cell(cx, cy):
					return {
						"ok": true,
						"wc3": pathing.cell_center_wc3(cx, cy),
						"cell": Vector2i(cx, cy),
					}
	return empty


## 直线是否全程可走（D0 快捷路径）。为何先做直线：
## 多数短距离移动无遮挡，可跳过 A*，手感更「点哪走哪」。
func is_straight_walkable(from_wc3: Vector2, to_wc3: Vector2) -> bool:
	if not is_ready():
		return false
	if not pathing.can_walk_at(from_wc3.x, from_wc3.y):
		return false
	if not pathing.can_walk_at(to_wc3.x, to_wc3.y):
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
		if not pathing.can_walk_at(p.x, p.y):
			return false
	return true


## 主入口：返回 { ok, waypoints: Array[Vector2](WC3 XY), reason }。
## waypoints 含起点附近第一跳到终点；跟随器从当前世界位置接到第一条即可。
func find_path(from_wc3: Vector2, to_wc3: Vector2) -> Dictionary:
	if not is_ready():
		return {"ok": false, "waypoints": [], "reason": "no_pathing"}
	var start_snap := snap_to_walkable(from_wc3.x, from_wc3.y, 6)
	var goal_snap := snap_to_walkable(to_wc3.x, to_wc3.y, 12)
	if not start_snap.get("ok", false):
		return {"ok": false, "waypoints": [], "reason": "start_blocked"}
	if not goal_snap.get("ok", false):
		return {"ok": false, "waypoints": [], "reason": "goal_blocked"}
	var start_c: Vector2i = start_snap["cell"]
	var goal_c: Vector2i = goal_snap["cell"]
	var start_p: Vector2 = start_snap["wc3"]
	var goal_p: Vector2 = goal_snap["wc3"]
	if start_c == goal_c:
		return {"ok": true, "waypoints": [goal_p], "reason": "same_cell"}
	if is_straight_walkable(start_p, goal_p):
		return {"ok": true, "waypoints": [goal_p], "reason": "straight"}
	var cells := _astar(start_c, goal_c)
	if cells.is_empty():
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
		var cy: int = cur_i / w
		for n in _neighbors(cx, cy):
			var ni := _idx(n, w)
			if ni < 0 or closed[ni] != 0:
				continue
			if not pathing.can_walk_cell(n.x, n.y):
				continue
			# 禁止斜穿「墙角」：否则单位视觉上会卡进建筑直角。
			if n.x != cx and n.y != cy:
				if not pathing.can_walk_cell(cx, n.y) or not pathing.can_walk_cell(n.x, cy):
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
