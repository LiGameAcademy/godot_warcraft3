class_name TreeRegistry
extends Node

## 可交互树木注册表（Logic）：creationNumber → life / 空间索引。
## Present 只经 MapLoader.ensure_doodad_promoted / remove_doodad_instance。
## 统一入口：apply_damage（伐木 / 未来投石车）。

signal tree_damaged(creation_number: int, life: float, max_life: float)
signal tree_killed(creation_number: int)

const GRID_CELL_WC3 := 256.0
const DEFAULT_TREE_HP := 50.0
## 拾取：屏幕点到树干脚底的最大像素距离（偏严，避免抢地面移动）
const PICK_FOOT_PX := 28.0
## 世界拾取半径（Godot 单位）
const PICK_RADIUS_GODOT := 0.7

var _map_loader: Node = null
var _catalog: Wc3IdCatalog = null
var _camera: Camera3D = null
## cn → entry dict
var _entries: Dictionary = {}
## cn → 当前 life
var _life: Dictionary = {}
## cn → max life
var _max_life: Dictionary = {}
## cn → true 已死（树桩：Present 保留，pathing 已清）
var _dead: Dictionary = {}
## cn → true 已成树桩（Death 定格）
var _stump: Dictionary = {}
## cn → { body_instance_id: slot_wc3 } 砍位预约（防多人抢同一点）
var _chop_claims: Dictionary = {}
## cell_key → PackedInt32Array of cn
var _grid: Dictionary = {}


func configure(map_loader: Node, catalog: Wc3IdCatalog, camera: Camera3D = null) -> void:
	_map_loader = map_loader
	_catalog = catalog
	_camera = camera


func set_camera(camera: Camera3D) -> void:
	_camera = camera


## 从 MapLoader pathing doodad 列表重建可伐索引。
func rebuild_from_map() -> void:
	_entries.clear()
	_life.clear()
	_max_life.clear()
	_dead.clear()
	_stump.clear()
	_chop_claims.clear()
	_grid.clear()
	if _map_loader == null or not _map_loader.has_method("get_pathing_doodad_entries"):
		return
	var arr: Array = _map_loader.call("get_pathing_doodad_entries")
	for e in arr:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		var tid := str(d.get("id", "")).strip_edges()
		if not is_harvestable_type(tid):
			continue
		var cn := int(d.get("creationNumber", -1))
		if cn < 0:
			continue
		_entries[cn] = d
		var hp := _max_hp_for_type(tid)
		_max_life[cn] = hp
		_life[cn] = hp
		_grid_insert(cn, _pos_wc3_of(d))
	AppLog.info(
		AppLog.Layer.LOGIC,
		"TreeRegistry",
		"harvestable trees=%d / doodads=%d" % [_entries.size(), arr.size()]
	)


func is_harvestable_type(type_id: String) -> bool:
	if type_id.is_empty() or _catalog == null:
		return false
	var info: Dictionary = _catalog.lookup(type_id)
	if info.is_empty():
		return false
	if str(info.get("kind", "")) != "destructable":
		return false
	# DestructableData.targType == tree；或 category T（树木）
	Wc3DefStore.ensure_table(DestructableDataDef.TABLE_NAME)
	var row := Wc3DefStore.get_row(DestructableDataDef.TABLE_NAME, type_id) as DestructableDataDef
	if row == null:
		return false
	var targ := row.targ_type.strip_edges().to_lower()
	if targ == "tree":
		return true
	var cat := row.category.strip_edges().to_upper()
	return cat == "T" or cat.begins_with("TREE")


func has_tree(creation_number: int) -> bool:
	return _entries.has(creation_number) and not bool(_dead.get(creation_number, false))


func is_alive(creation_number: int) -> bool:
	return has_tree(creation_number) and float(_life.get(creation_number, 0.0)) > 0.0


func is_stump(creation_number: int) -> bool:
	return bool(_stump.get(creation_number, false)) or bool(_dead.get(creation_number, false))


## 预约砍位。sep_wc3：与其他预约点的最小间距。
func claim_chop_slot(creation_number: int, body_id: int, pos_wc3: Vector2, sep_wc3: float = 64.0) -> bool:
	if body_id == 0 or pos_wc3 == Vector2.INF or not is_alive(creation_number):
		return false
	if not is_chop_slot_free(creation_number, pos_wc3, body_id, sep_wc3):
		return false
	release_chop_claims_for(body_id)
	if not _chop_claims.has(creation_number):
		_chop_claims[creation_number] = {}
	(_chop_claims[creation_number] as Dictionary)[body_id] = pos_wc3
	return true


func release_chop_claims_for(body_id: int) -> void:
	if body_id == 0:
		return
	var empty_keys: Array[int] = []
	for cn_v in _chop_claims.keys():
		var cn := int(cn_v)
		var d: Dictionary = _chop_claims[cn]
		if d.has(body_id):
			d.erase(body_id)
		if d.is_empty():
			empty_keys.append(cn)
	for cn2 in empty_keys:
		_chop_claims.erase(cn2)


func is_chop_slot_free(
	creation_number: int,
	pos_wc3: Vector2,
	body_id: int,
	sep_wc3: float = 64.0
) -> bool:
	if not _chop_claims.has(creation_number):
		return true
	var d: Dictionary = _chop_claims[creation_number]
	var need := maxf(sep_wc3, 32.0)
	for id_v in d.keys():
		if int(id_v) == body_id:
			continue
		var other: Vector2 = d[id_v]
		if pos_wc3.distance_to(other) < need:
			return false
	return true


func get_pos_wc3(creation_number: int) -> Vector2:
	if not _entries.has(creation_number):
		return Vector2.INF
	return _pos_wc3_of(_entries[creation_number])


func get_life(creation_number: int) -> float:
	return float(_life.get(creation_number, 0.0))


func get_max_life(creation_number: int) -> float:
	return float(_max_life.get(creation_number, DEFAULT_TREE_HP))


func get_entry(creation_number: int) -> Dictionary:
	return _entries.get(creation_number, {})


## 需要独立 Present（选中黄环 / 即将扣血 / 死亡动画）。
func ensure_promoted(creation_number: int) -> Node3D:
	if not _entries.has(creation_number):
		return null
	if _map_loader == null or not _map_loader.has_method("ensure_doodad_promoted"):
		return null
	var node := _map_loader.call("ensure_doodad_promoted", creation_number) as Node3D
	if node != null:
		InteractionSetup.attach(node, InteractableComponent.SmartKind.TREE)
	return node


## 统一受伤入口。返回 {ok, killed, life, taken}。
func apply_damage(creation_number: int, amount: float, _source: Object = null) -> Dictionary:
	var out := {"ok": false, "killed": false, "life": 0.0, "taken": 0.0}
	if amount <= 0.0 or not is_alive(creation_number):
		return out
	# 首伤才 promote；失败也不阻断扣血（MM 仍在）
	var node := ensure_promoted(creation_number)
	var life := float(_life.get(creation_number, 0.0))
	var taken := minf(amount, life)
	life = maxf(0.0, life - taken)
	_life[creation_number] = life
	out["ok"] = true
	out["taken"] = taken
	out["life"] = life
	tree_damaged.emit(creation_number, life, get_max_life(creation_number))
	if life <= 0.0:
		_kill(creation_number)
		out["killed"] = true
	else:
		_play_hit_then_stand(node, creation_number)
	return out


## 附近存活树，按距离升序（供伐木 AI 改砍邻树）。
func list_near_cn(from_wc3: Vector2, max_r_wc3: float = 900.0) -> Array[int]:
	var out: Array[int] = []
	if from_wc3 == Vector2.INF:
		return out
	var max_r2 := max_r_wc3 * max_r_wc3 if max_r_wc3 > 0.0 else INF
	var scored: Array = []
	var cells := _nearby_cell_keys(from_wc3, max_r_wc3 if max_r_wc3 > 0.0 else GRID_CELL_WC3 * 2.0)
	var seen: Dictionary = {}
	for key in cells:
		if not _grid.has(key):
			continue
		var arr: PackedInt32Array = _grid[key]
		for cn in arr:
			if seen.has(cn) or not is_alive(cn):
				continue
			seen[cn] = true
			var d2 := from_wc3.distance_squared_to(get_pos_wc3(cn))
			if d2 <= max_r2:
				scored.append({"cn": cn, "d2": d2})
	if scored.is_empty():
		for cn_v in _entries.keys():
			var cn2 := int(cn_v)
			if not is_alive(cn2):
				continue
			var d22 := from_wc3.distance_squared_to(get_pos_wc3(cn2))
			if d22 <= max_r2:
				scored.append({"cn": cn2, "d2": d22})
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d2"]) < float(b["d2"]))
	for item in scored:
		out.append(int(item["cn"]))
	return out


## 附近最近存活树（WC3 XY）。max_r_wc3<=0 不限。
func nearest_cn(from_wc3: Vector2, max_r_wc3: float = 512.0) -> int:
	if from_wc3 == Vector2.INF:
		return -1
	var best_cn := -1
	var best_d2 := INF
	var max_r2 := max_r_wc3 * max_r_wc3 if max_r_wc3 > 0.0 else INF
	var cells := _nearby_cell_keys(from_wc3, max_r_wc3 if max_r_wc3 > 0.0 else GRID_CELL_WC3 * 2.0)
	for key in cells:
		if not _grid.has(key):
			continue
		var arr: PackedInt32Array = _grid[key]
		for cn in arr:
			if not is_alive(cn):
				continue
			var p := get_pos_wc3(cn)
			var d2 := from_wc3.distance_squared_to(p)
			if d2 < best_d2 and d2 <= max_r2:
				best_d2 = d2
				best_cn = cn
	# 网格漏扫兜底
	if best_cn < 0:
		for cn in _entries.keys():
			if not is_alive(int(cn)):
				continue
			var p2 := get_pos_wc3(int(cn))
			var d22 := from_wc3.distance_squared_to(p2)
			if d22 < best_d2 and d22 <= max_r2:
				best_d2 = d22
				best_cn = int(cn)
	return best_cn


## 屏幕点选最近树脚底；命中则 promote 并返回 Node（供选中环）。
func pick_promoted_at_screen(screen_pos: Vector2) -> Node3D:
	var cn := pick_cn_at_screen(screen_pos)
	if cn < 0:
		return null
	return ensure_promoted(cn)


func pick_cn_at_screen(screen_pos: Vector2) -> int:
	if _camera == null or not is_instance_valid(_camera):
		return -1
	var best_cn := -1
	var best_score := INF
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if dir.length_squared() < 1e-10:
		return -1
	dir = dir.normalized()
	for cn_v in _entries.keys():
		var cn := int(cn_v)
		if not is_alive(cn):
			continue
		var entry: Dictionary = _entries[cn]
		var pos: Dictionary = entry.get("position", {})
		var p := Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))
		var z := float(pos.get("z", 0.0))
		var gpos := Wc3Coords.wc3_xy_to_godot(p.x, p.y, z)
		# 2D 脚底圆：射线 ∩ 水平面，再比 XZ 半径（与 UnitSelector 一致）
		var hit_ok := false
		var score := INF
		if absf(dir.y) > 1e-8:
			var t := (gpos.y - origin.y) / dir.y
			if t >= 0.0:
				var hit := origin + dir * t
				var dist_xz := Vector2(hit.x, hit.z).distance_to(Vector2(gpos.x, gpos.z))
				if dist_xz <= PICK_RADIUS_GODOT:
					hit_ok = true
					score = dist_xz + t * 0.02
		if not hit_ok:
			if _camera.is_position_behind(gpos):
				continue
			var sp := _camera.unproject_position(gpos)
			var d2 := sp.distance_squared_to(screen_pos)
			if d2 > PICK_FOOT_PX * PICK_FOOT_PX:
				continue
			score = 1000.0 + d2
			hit_ok = true
		if hit_ok and score < best_score:
			best_score = score
			best_cn = cn
	return best_cn


func _kill(creation_number: int) -> void:
	if bool(_dead.get(creation_number, false)):
		return
	var node := ensure_promoted(creation_number)
	_dead[creation_number] = true
	_life[creation_number] = 0.0
	_chop_claims.erase(creation_number)
	# 立刻清脚印：地面可走；Present 留下成树桩（建造时再 remove_stump）
	_grid_remove(creation_number)
	if _map_loader != null and _map_loader.has_method("clear_doodad_pathing"):
		_map_loader.call("clear_doodad_pathing", creation_number)
	var wait_sec := _play_tree_anim(node, ["Death", "Death - 1", "Death_1"], false)
	if wait_sec < 0.35:
		wait_sec = 1.35
	if is_inside_tree():
		get_tree().create_timer(wait_sec).timeout.connect(
			func() -> void: _freeze_as_stump(creation_number, node),
			CONNECT_ONE_SHOT
		)
	else:
		_freeze_as_stump(creation_number, node)
	tree_killed.emit(creation_number)


## Death 定格为树桩：不删 Present，不影响寻路。
func _freeze_as_stump(creation_number: int, node: Node3D) -> void:
	_stump[creation_number] = true
	if node == null or not is_instance_valid(node):
		return
	node.set_meta("tree_stump", true)
	var ap := _find_anim_player(node)
	if ap == null:
		return
	var cur := str(ap.current_animation)
	if cur.is_empty():
		ap.stop()
		return
	var anim := ap.get_animation(cur)
	var end_t := anim.length if anim != null else ap.current_animation_length
	ap.seek(maxf(end_t - 0.02, 0.0), true)
	ap.pause()


## 建造等需要清树桩时调用（Present + 条目全删）。
func remove_stump(creation_number: int) -> void:
	if creation_number < 0:
		return
	_chop_claims.erase(creation_number)
	_stump.erase(creation_number)
	_dead[creation_number] = true
	_life[creation_number] = 0.0
	_remove_present(creation_number)


func _play_hit_then_stand(node: Node3D, creation_number: int) -> void:
	if node == null or not is_instance_valid(node):
		return
	var wait_sec := _play_tree_anim(node, ["Stand Hit", "Stand_Hit", "Hit"], false)
	if wait_sec <= 0.05:
		return
	if not is_inside_tree():
		return
	var cn := creation_number
	get_tree().create_timer(wait_sec).timeout.connect(
		func() -> void:
			if bool(_dead.get(cn, false)):
				return
			if node == null or not is_instance_valid(node):
				return
			var cache := _model_cache()
			if cache != null:
				cache.autoplay_stand(node, false),
		CONNECT_ONE_SHOT
	)


## 按候选逻辑名解析并播放；返回动画时长（秒），失败 0。
func _play_tree_anim(node: Node3D, logical_names: Array, loop: bool) -> float:
	if node == null or not is_instance_valid(node):
		return 0.0
	var cache := _model_cache()
	if cache == null:
		return 0.0
	var resolved := ""
	for name_v in logical_names:
		var logical := str(name_v)
		resolved = BuildingVisual.resolve_animation(node, logical)
		if resolved.is_empty() and logical.contains(" "):
			resolved = BuildingVisual.resolve_animation(node, logical.replace(" ", "_"))
		if not resolved.is_empty():
			break
	if resolved.is_empty():
		# 叶子名模糊：含 death / hit
		var ap0 := _find_anim_player(node)
		if ap0 != null:
			var want := str(logical_names[0]).to_lower()
			for n in ap0.get_animation_list():
				var leaf := str(n)
				var slash := leaf.rfind("/")
				if slash >= 0:
					leaf = leaf.substr(slash + 1)
				var ll := leaf.to_lower()
				if want.contains("death") and ll.contains("death"):
					resolved = str(n)
					break
				if want.contains("hit") and ll.contains("hit") and not ll.contains("death"):
					resolved = str(n)
					break
	if resolved.is_empty():
		return 0.0
	if not cache.play_animation(node, resolved, loop):
		return 0.0
	var ap := _find_anim_player(node)
	if ap == null:
		return 0.8
	var anim := ap.get_animation(resolved)
	if anim != null:
		anim.loop_mode = Animation.LOOP_NONE if not loop else Animation.LOOP_LINEAR
		return maxf(anim.length, 0.1)
	if str(ap.current_animation).is_empty():
		return 0.8
	return maxf(ap.current_animation_length, 0.1)


func _model_cache() -> MapModelCache:
	if _map_loader != null and _map_loader.has_method("get_model_cache"):
		return _map_loader.call("get_model_cache") as MapModelCache
	return null


func _find_anim_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_anim_player(c)
		if found != null:
			return found
	return null


func _remove_present(creation_number: int) -> void:
	_grid_remove(creation_number)
	if _map_loader != null and _map_loader.has_method("remove_doodad_instance"):
		_map_loader.call("remove_doodad_instance", creation_number)
	_entries.erase(creation_number)


func _max_hp_for_type(type_id: String) -> float:
	Wc3DefStore.ensure_table(DestructableDataDef.TABLE_NAME)
	var row := Wc3DefStore.get_row(DestructableDataDef.TABLE_NAME, type_id) as DestructableDataDef
	if row != null and row.hp > 0:
		return float(row.hp)
	return DEFAULT_TREE_HP


func _pos_wc3_of(d: Dictionary) -> Vector2:
	var pos: Dictionary = d.get("position", {})
	return Vector2(float(pos.get("x", 0.0)), float(pos.get("y", 0.0)))


func _grid_key(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / GRID_CELL_WC3), floori(pos.y / GRID_CELL_WC3))


func _grid_insert(cn: int, pos: Vector2) -> void:
	var key := _grid_key(pos)
	if not _grid.has(key):
		_grid[key] = PackedInt32Array()
	var arr: PackedInt32Array = _grid[key]
	arr.append(cn)
	_grid[key] = arr


func _grid_remove(cn: int) -> void:
	var pos := get_pos_wc3(cn)
	if pos == Vector2.INF:
		return
	var key := _grid_key(pos)
	if not _grid.has(key):
		return
	var arr: PackedInt32Array = _grid[key]
	var out := PackedInt32Array()
	for id in arr:
		if id != cn:
			out.append(id)
	if out.is_empty():
		_grid.erase(key)
	else:
		_grid[key] = out


func _nearby_cell_keys(pos: Vector2, radius_wc3: float) -> Array[Vector2i]:
	var r := maxf(radius_wc3, GRID_CELL_WC3)
	var c0 := _grid_key(pos)
	var n := maxi(1, ceili(r / GRID_CELL_WC3))
	var keys: Array[Vector2i] = []
	for dy in range(-n, n + 1):
		for dx in range(-n, n + 1):
			keys.append(Vector2i(c0.x + dx, c0.y + dy))
	return keys
