class_name MeleeBootstrap
extends RefCounted
## 在起始点刷主城 + 初始工人（竖切）。
## 工人落点对齐 Blizzard.j MeleeStartingUnits*：朝最近金矿投影后再按 unitSpacing 排阵。

## bj_MELEE_MINE_SEARCH_RADIUS
const MINE_SEARCH_RADIUS_WC3 := 2560.0
## MeleeStartingUnitsHuman：投影距离
const WORKER_PROJECT_DIST_WC3 := 320.0
## unitSpacing
const UNIT_SPACING_WC3 := 64.0
## bj_UNIT_FACING
const UNIT_FACING_RAD := deg_to_rad(270.0)
const GOLD_MINE_TYPE := "ngol"

## 相对「金矿方向投影点」的偏移（× unitSpacing），来自 MeleeStartingUnitsHuman。
const WORKER_SPACING_MULTS: Array[Vector2] = [
	Vector2(0.00, 1.00),
	Vector2(1.00, 0.15),
	Vector2(-1.00, 0.15),
	Vector2(0.60, -1.00),
	Vector2(-0.60, -1.00),
]


## 在 sloc 刷开局单位。返回主城世界坐标（Godot）与摘要。
static func spawn_at_sloc(
	map_loader: MapLoader,
	sloc: Dictionary,
	race: int,
	player_owner: int = 0,
	hf_dict: Dictionary = {}
) -> Dictionary:
	var empty := {"ok": false, "hall_world": Vector3.ZERO, "spawned": 0}
	if map_loader == null:
		return empty
	var pos: Dictionary = sloc.get("position", {})
	var hx := float(pos.get("x", 0.0))
	var hy := float(pos.get("y", 0.0))
	var hz := float(pos.get("z", 0.0))
	var hall_id := MeleeRacePreview.town_hall_id(race)
	var worker_id := MeleeRacePreview.worker_id(race)
	var worker_n: int = mini(MeleeRacePreview.default_worker_count(race), WORKER_SPACING_MULTS.size())
	var angle := float(sloc.get("angle", UNIT_FACING_RAD))
	var cn_base := 90000 + player_owner * 100
	var map_dir := str(map_loader.map_dir)

	var hall_entry := _make_entry(hall_id, hx, hy, hz, angle, player_owner, cn_base)
	if not map_loader.add_unit_instance(hall_entry, hf_dict):
		push_warning("MeleeBootstrap: 主城放置失败 %s" % hall_id)
		return empty

	var start_xy := Vector2(hx, hy)
	var mine_xy := find_nearest_gold_mine_xy(map_dir, start_xy, MINE_SEARCH_RADIUS_WC3)
	var cluster_xy := _worker_cluster_origin(start_xy, mine_xy)

	var spawned := 1
	for i in range(worker_n):
		var mult: Vector2 = WORKER_SPACING_MULTS[i]
		var wx := cluster_xy.x + mult.x * UNIT_SPACING_WC3
		var wy := cluster_xy.y + mult.y * UNIT_SPACING_WC3
		var we := _make_entry(worker_id, wx, wy, hz, UNIT_FACING_RAD, player_owner, cn_base + 1 + i)
		if map_loader.add_unit_instance(we, hf_dict):
			spawned += 1

	var hall_world := Wc3Coords.wc3_xy_to_godot(hx, hy, hz)
	return {
		"ok": true,
		"hall_world": hall_world,
		"hall_wc3": Vector2(hx, hy),
		"worker_cluster_wc3": cluster_xy,
		"mine_wc3": mine_xy,
		"spawned": spawned,
		"race": MeleeRacePreview.race_id(race),
		"town_hall": hall_id,
		"worker": worker_id,
	}


## MeleeGetProjectedLoc(mine, start, dist, 0)：从 start 朝 mine 走 dist。
static func _worker_cluster_origin(start_xy: Vector2, mine_xy: Vector2) -> Vector2:
	if mine_xy == Vector2.INF:
		# 无金矿：落在出生点南侧（对齐旧版 Blizzard 兜底观感）
		return start_xy + Vector2(0.0, -WORKER_PROJECT_DIST_WC3)
	var delta := mine_xy - start_xy
	var len_sq := delta.length_squared()
	if len_sq < 1.0:
		return start_xy + Vector2(0.0, -WORKER_PROJECT_DIST_WC3)
	return start_xy + delta.normalized() * WORKER_PROJECT_DIST_WC3


static func find_nearest_gold_mine_xy(
	map_dir: String,
	from_xy: Vector2,
	max_radius: float = MINE_SEARCH_RADIUS_WC3
) -> Vector2:
	var best := Vector2.INF
	var best_d2 := max_radius * max_radius
	var path := map_dir.path_join("units.json")
	if not FileAccess.file_exists(path):
		return best
	var list := Wc3UnitList.load_json_path(path)
	if list == null:
		return best
	for e in list.to_entries_array():
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if str(d.get("typeId", "")) != GOLD_MINE_TYPE:
			continue
		var p: Dictionary = d.get("position", {})
		var mx := float(p.get("x", 0.0))
		var my := float(p.get("y", 0.0))
		var d2 := from_xy.distance_squared_to(Vector2(mx, my))
		if d2 <= best_d2:
			best_d2 = d2
			best = Vector2(mx, my)
	return best


static func _make_entry(
	type_id: String,
	x: float,
	y: float,
	z: float,
	angle: float,
	owner_id: int,
	creation_number: int
) -> Dictionary:
	return {
		"typeId": type_id,
		"variation": 0,
		"position": {"x": x, "y": y, "z": z},
		"angle": angle,
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner_id,
		"flags": 2,
		"creationNumber": creation_number,
	}


## 从 units.json 收集 sloc。
static func collect_slocs(map_dir: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var path := map_dir.path_join("units.json")
	if not FileAccess.file_exists(path):
		return out
	var list := Wc3UnitList.load_json_path(path)
	if list == null:
		return out
	for e in list.to_entries_array():
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = e
		if str(d.get("typeId", "")) == "sloc":
			out.append(d)
	return out


static func pick_random_sloc(slocs: Array[Dictionary], rng: RandomNumberGenerator = null) -> Dictionary:
	if slocs.is_empty():
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return slocs[rng.randi_range(0, slocs.size() - 1)]
