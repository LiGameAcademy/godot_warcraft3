class_name SelectionPicker
extends Node

## 点选 / 框选命中裁决（模型表面优先，脚底容错）。
## 不持有选中集合；[UnitSelector] 负责 [method UnitSelector._set_selection]。
##
## 热路径不调用 [InteractionSetup.attach]，避免首次点击给全图实例化选中环。

## 建筑略大半径惩罚：同点多圆重叠时优先小单位 / 近圆心。
const BUILDING_RADIUS_SCORE_MUL := 0.35
## 小幅脚底容错，不能让离鼠标几十像素的单位抢走建筑命中。
const FOOT_FALLBACK_UNIT_PX := 10.0
const FOOT_FALLBACK_BUILDING_PX := 8.0

## ≥0 时只可选该 owner；-1 不限。
var owner_filter: int = -1
## 框选仅保留该玩家；-1 不限。
var marquee_owner: int = -1
var allow_buildings: bool = true
var allow_units: bool = true

var camera: Camera3D
var unit_host: Node


## 绑定相机与单位层；可重复调用。
func bind(p_camera: Camera3D, p_unit_host: Node) -> void:
	camera = p_camera
	unit_host = p_unit_host


## 同步过滤条件（由 [UnitSelector] 在 setup / 拾取前写入）。
func set_filters(p_owner_filter: int, p_marquee_owner: int, p_allow_buildings: bool, p_allow_units: bool) -> void:
	owner_filter = p_owner_filter
	marquee_owner = p_marquee_owner
	allow_buildings = p_allow_buildings
	allow_units = p_allow_units


## 预热单位模型包围盒，避免首次点击尖峰。
func warm_bounds() -> void:
	if unit_host == null:
		return
	for child in unit_host.get_children():
		var model := child.get_node_or_null("Model") as Node3D
		if model != null:
			UnitPickVolume.model_bounds(model)


## 屏幕点选单位（含金矿建筑）。不含树木（树走 TreeRegistry）。
func pick_at(screen_pos: Vector2) -> Node3D:
	if camera == null or unit_host == null:
		return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-10:
		return null
	dir = dir.normalized()

	var best_unit: Node3D = null
	var best_unit_score := INF
	var best_bldg: Node3D = null
	var best_bldg_score := INF
	var best_body: Node3D = null
	var best_body_distance := INF

	for n in iter_unit_nodes():
		var body_distance := UnitPickVolume.ray_distance(n, origin, dir)
		if body_distance < best_body_distance:
			best_body_distance = body_distance
			best_body = n
		var is_bldg := _node_is_building(n)
		var radius := _pick_radius_of(n)
		var hit := _ray_foot_plane_hit(origin, dir, n.global_position)
		var score := INF
		var hit_ok := false
		if hit.t >= 0.0:
			var dist_xz := Vector2(hit.pos.x, hit.pos.z).distance_to(
				Vector2(n.global_position.x, n.global_position.z)
			)
			if dist_xz <= radius:
				hit_ok = true
				score = dist_xz + radius * (BUILDING_RADIUS_SCORE_MUL if is_bldg else 0.05)
				score += hit.t * 0.02
		if not hit_ok:
			if camera.is_position_behind(n.global_position):
				continue
			var sp := camera.unproject_position(n.global_position)
			var d2 := sp.distance_squared_to(screen_pos)
			var foot_px := FOOT_FALLBACK_BUILDING_PX if is_bldg else FOOT_FALLBACK_UNIT_PX
			if d2 > foot_px * foot_px:
				continue
			hit_ok = true
			score = 40.0 + sqrt(d2) * 0.02 + radius * (BUILDING_RADIUS_SCORE_MUL if is_bldg else 0.05)
		if not hit_ok:
			continue
		if is_bldg:
			if score < best_bldg_score:
				best_bldg_score = score
				best_bldg = n
		elif score < best_unit_score:
			best_unit_score = score
			best_unit = n

	if best_body != null:
		return best_body
	if best_unit != null:
		return best_unit
	return best_bldg


## 框选命中列表（已应用 marquee_owner 与单位优先规则）。
func pick_in_rect(rect: Rect2) -> Array[Node3D]:
	var hits: Array[Node3D] = []
	for n in iter_unit_nodes():
		if not _allows_marquee(n):
			continue
		var radius := _pick_radius_of(n)
		if _footprint_in_marquee(n, radius, rect):
			hits.append(n)
	if marquee_owner >= 0:
		var owned: Array[Node3D] = []
		for n in hits:
			if _owner_of(n) == marquee_owner:
				owned.append(n)
		hits = owned
	return _prefer_units_over_buildings(hits)


## 脚底到屏幕点的像素距离；不可见 / 无相机返回 INF。
func screen_foot_distance(node: Node3D, screen_pos: Vector2) -> float:
	if camera == null or node == null or not is_instance_valid(node):
		return INF
	if camera.is_position_behind(node.global_position):
		return INF
	return camera.unproject_position(node.global_position).distance_to(screen_pos)


## 当前可点选 / 框选的候选单位。
func iter_unit_nodes() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if unit_host == null:
		return out
	for c in unit_host.get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if not WorldMembership.is_in_world(n) or not n.is_visible_in_tree() or n.is_queued_for_deletion():
			continue
		if not n.has_meta("unit_data"):
			continue
		var d: Dictionary = n.get_meta("unit_data", {})
		var tid := str(d.get("typeId", ""))
		if tid == "sloc":
			continue
		if owner_filter >= 0 and int(d.get("owner", -1)) != owner_filter:
			continue
		var is_bldg := _node_is_building(n, tid)
		if is_bldg and not allow_buildings:
			continue
		if not is_bldg and not allow_units:
			continue
		out.append(n)
	return out


func _ray_foot_plane_hit(origin: Vector3, dir: Vector3, foot: Vector3) -> Dictionary:
	if absf(dir.y) < 1e-8:
		return {"t": -1.0, "pos": Vector3.ZERO}
	var t := (foot.y - origin.y) / dir.y
	if t < 0.0:
		return {"t": -1.0, "pos": Vector3.ZERO}
	return {"t": t, "pos": origin + dir * t}


func _footprint_in_marquee(node: Node3D, radius: float, rect: Rect2) -> bool:
	if camera == null or node == null:
		return false
	if MarqueeSelection.world_in_rect(camera, node.global_position, rect):
		return true
	if camera.is_position_behind(node.global_position):
		return false
	var foot_sp := camera.unproject_position(node.global_position)
	var edge := node.global_position + Vector3(maxf(radius, 0.12), 0.0, 0.0)
	if camera.is_position_behind(edge):
		return false
	var r_px := foot_sp.distance_to(camera.unproject_position(edge))
	r_px = clampf(r_px, 4.0, 120.0)
	return _distance_point_to_rect(foot_sp, rect) <= r_px


func _distance_point_to_rect(p: Vector2, rect: Rect2) -> float:
	var x := clampf(p.x, rect.position.x, rect.position.x + rect.size.x)
	var y := clampf(p.y, rect.position.y, rect.position.y + rect.size.y)
	return p.distance_to(Vector2(x, y))


func _prefer_units_over_buildings(nodes: Array[Node3D]) -> Array[Node3D]:
	var units: Array[Node3D] = []
	var buildings: Array[Node3D] = []
	for n in nodes:
		if _node_is_building(n):
			buildings.append(n)
		else:
			units.append(n)
	if not units.is_empty():
		return units
	return buildings


func _pick_radius_of(n: Node3D) -> float:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.pick_radius_world()
	# 热路径不 attach：用 Selectable 共享的轻量估计。
	return SelectableComponent.estimate_pick_radius_world(n)


func _node_is_building(n: Node3D, tid: String = "") -> bool:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.is_building()
	if tid.is_empty():
		tid = _type_id_of(n)
	return BuildingVisual.is_building(tid)


func _type_id_of(n: Node3D) -> String:
	if n == null:
		return ""
	var d: Dictionary = n.get_meta("unit_data", {})
	return str(d.get("typeId", "")).strip_edges()


func _owner_of(n: Node3D) -> int:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.owner_id()
	if n == null:
		return -1
	return int(n.get_meta("unit_data", {}).get("owner", -1))


func _allows_marquee(n: Node3D) -> bool:
	var sel := InteractionSetup.get_selectable(n)
	if sel != null:
		return sel.allow_marquee
	var oid := _owner_of(n)
	if oid >= 12 or _type_id_of(n) == "ngol":
		return false
	return true
