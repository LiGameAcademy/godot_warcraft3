extends Node

## 初版经营决策：补充工人并为己方空闲工人分配采集；实际生产与采集走公共命令。
var router: CommandRouter
var unit_host: Node
var trees: TreeRegistry
var player_owner_id: int = -1
var interval := 1.0
var gold_workers := 3
var desired_workers := 8
var develop_army := true
var desired_footmen := 6
var supply_buffer := 2
var stock: PlayerStock
var pathing: Wc3PathingMap
var path_query: PathQuery
var _elapsed := 0.0
var last_status := "等待初始化"

func configure(commands: CommandRouter, host: Node, tree_registry: TreeRegistry, player_owner: int) -> void:
	router = commands
	unit_host = host
	trees = tree_registry
	player_owner_id = player_owner

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < interval:
		return
	_elapsed = 0.0
	decide()

func decide() -> void:
	if router == null or not is_instance_valid(unit_host):
		return
	var workers: Array[Node3D] = []
	var mining := 0
	# 矿内工人暂时退出 WorldMembership，但仍存活且占用人口，不能当成缺员。
	for unit in unit_host.get_children():
		if not unit is Node3D or not CombatQuery.is_controllable(unit, player_owner_id):
			continue
		if not HarvestController.is_peasant(unit) or UnitLife.get_life(unit) <= 0.0:
			continue
		workers.append(unit)
		var harvest := unit.get_node_or_null("HarvestController") as HarvestController
		if harvest != null and harvest.is_active():
			var order := router.queue_for(unit).current
			if order != null and order.kind == UnitOrder.Kind.HARVEST_GOLD:
				mining += 1
	var assigned := 0
	_replenish_workers(workers.size())
	_ensure_supply(workers)
	if develop_army:
		_develop_army(workers)
	for worker in workers:
		if not CombatQuery.is_alive_in_world(worker):
			continue
		var harvest := worker.get_node_or_null("HarvestController") as HarvestController
		if harvest != null and harvest.is_active():
			continue
		var build := worker.get_node_or_null("BuildController") as BuildController
		if build != null and build.is_active():
			continue
		var queue := router.queue_for(worker)
		if not queue.is_idle() and queue.current.kind not in [UnitOrder.Kind.HARVEST_GOLD, UnitOrder.Kind.HARVEST_LUMBER, UnitOrder.Kind.RETURN_GOODS]:
			continue
		if harvest != null and harvest.is_carrying():
			assigned += router.issue_return_goods([worker], UnitOrder.Source.PLAYER_AI)
			continue
		var mine := _nearest_mine(worker)
		if mining < gold_workers and mine != null:
			var issued := router.issue_harvest_gold([worker], mine, UnitOrder.Source.PLAYER_AI)
			mining += issued
			assigned += issued
		elif is_instance_valid(trees):
			var cn := trees.nearest_cn(Wc3Coords.godot_to_wc3_xy(worker.global_position), 4096.0)
			if cn >= 0:
				assigned += router.issue_harvest_lumber([worker], cn, UnitOrder.Source.PLAYER_AI)
	last_status = "工人 %d，采金 %d，本轮分配 %d" % [workers.size(), mining, assigned]

func _replenish_workers(alive_count: int) -> void:
	var queued := 0
	var halls: Array[Node3D] = []
	for unit in router.filter_controllable(unit_host.get_children()):
		var queue := unit.get_node_or_null("TrainQueue") as TrainQueue
		if queue != null:
			for entry in queue.snapshot():
				if entry.get("unit_id", "") == "hpea":
					queued += 1
		var type_id := str(unit.get_meta("unit_data", {}).get("typeId", ""))
		if type_id in ["htow", "hkee", "hcas"] and not UnitLife.is_under_construction(unit):
			halls.append(unit)
	if alive_count + queued >= desired_workers:
		return
	for hall in halls:
		if router.issue_train(hall, "hpea"):
			return

func _ensure_supply(workers: Array[Node3D]) -> void:
	if stock == null:
		return
	var required := supply_buffer
	# 首英雄需五人口；只按两人口余量规划会卡在八工人/十二上限。
	# 队列中的英雄已经预占人口，不能再为同一英雄重复预留。
	if develop_army and _needs_first_hero():
		required = maxi(required, BuildingCatalog.get_food_used("Hamg"))
	if stock.food_cap - stock.food_used >= required:
		return
	_build_one(workers, "hhou")

func _needs_first_hero() -> bool:
	if HeroDeathRegistry.dead_count(player_owner_id) > 0:
		return false
	for unit in router.filter_controllable(unit_host.get_children()):
		if CombatQuery.type_id_of(unit) == "Hamg":
			return false
		var queue := unit.get_node_or_null("TrainQueue") as TrainQueue
		if queue != null:
			for entry in queue.snapshot():
				if entry.get("unit_id", "") == "Hamg":
					return false
	return true

func _build_one(workers: Array[Node3D], building_id: String) -> void:
	if stock == null or pathing == null or path_query == null:
		return
	if stock.gold < BuildingCatalog.get_gold_cost(building_id) or stock.lumber < BuildingCatalog.get_lumber_cost(building_id):
		return
	for worker in workers:
		var build := worker.get_node_or_null("BuildController") as BuildController
		if build != null and build.is_active():
			return
	var hall: Node3D = null
	for unit in router.filter_controllable(unit_host.get_children()):
		var id := str(unit.get_meta("unit_data", {}).get("typeId", ""))
		if id == building_id and UnitLife.is_under_construction(unit):
			return
		if id in ["htow", "hkee", "hcas"] and not UnitLife.is_under_construction(unit):
			hall = unit
	if hall == null:
		return
	var builder: Node3D = null
	for worker in workers:
		if not CombatQuery.is_alive_in_world(worker):
			continue
		var build := worker.get_node_or_null("BuildController") as BuildController
		if build != null and build.is_active():
			continue
		var harvest := worker.get_node_or_null("HarvestController") as HarvestController
		if harvest != null and harvest.is_carrying():
			continue
		builder = worker
		break
	if builder == null:
		return
	var center := Wc3Coords.godot_to_wc3_xy(hall.global_position)
	var from := Wc3Coords.godot_to_wc3_xy(builder.global_position)
	for radius in [512.0, 768.0, 1024.0]:
		for step in range(16):
			var raw: Vector2 = center + Vector2.from_angle(TAU * step / 16.0) * float(radius)
			var site := PlacementRules.snap_site_wc3(building_id, raw, pathing)
			if not PlacementRules.can_build_at(building_id, site, pathing):
				continue
			var route := path_query.find_path(from, site)
			if not bool(route.get("ok", false)):
				continue
			if router.issue_build([builder], building_id, site, UnitOrder.Source.PLAYER_AI) > 0:
				return

func _develop_army(workers: Array[Node3D]) -> void:
	var barracks: Node3D = null
	var altar: Node3D = null
	var blacksmith: Node3D = null
	var counts := {"hfoo": 0, "Hamg": 0}
	for unit in router.filter_controllable(unit_host.get_children()):
		var id := str(unit.get_meta("unit_data", {}).get("typeId", ""))
		if id == "hbar":
			barracks = unit
		elif id == "halt":
			altar = unit
		elif id == "hbla":
			blacksmith = unit
		if counts.has(id):
			counts[id] += 1
		var queue := unit.get_node_or_null("TrainQueue") as TrainQueue
		if queue != null:
			for entry in queue.snapshot():
				var queued_id := str(entry.get("unit_id", ""))
				if counts.has(queued_id):
					counts[queued_id] += 1
	if barracks == null:
		_build_one(workers, "hbar")
		return
	if altar == null:
		_build_one(workers, "halt")
		return
	if blacksmith == null:
		_build_one(workers, "hbla")
		return
	if (
		UnitLife.is_under_construction(barracks)
		or UnitLife.is_under_construction(altar)
		or UnitLife.is_under_construction(blacksmith)
	):
		return
	if counts.Hamg == 0 and HeroDeathRegistry.dead_count(player_owner_id) == 0:
		router.issue_train(altar, "Hamg")
		return
	# 科技：兵营顶盾 → 铁匠近战攻/甲（各升一级即可）
	if _try_research(barracks, "Rhde"):
		return
	if _try_research(blacksmith, "Rhme"):
		return
	if _try_research(blacksmith, "Rhar"):
		return
	if counts.hfoo < desired_footmen:
		router.issue_train(barracks, "hfoo")


func _try_research(building: Node3D, upgrade_id: String) -> bool:
	if building == null or stock == null or router == null:
		return false
	var uid := upgrade_id.strip_edges()
	if uid.is_empty():
		return false
	var cur := stock.upgrade_level(uid)
	var next_lv := TechPresence.upgrade_next_level(uid, cur)
	if next_lv <= 0:
		return false
	if TechPresence.is_upgrade_queued(unit_host, player_owner_id, uid):
		return false
	var owned := TechPresence.collect_owned_buildings(unit_host, player_owner_id)
	var missing := TechPresence.missing_requires(
		owned, TechPresence.upgrade_requires_for_level(uid, next_lv), stock.upgrade_map()
	)
	if not missing.is_empty():
		return false
	var gold := TechPresence.upgrade_gold_at_level(uid, next_lv)
	var lumber := TechPresence.upgrade_lumber_at_level(uid, next_lv)
	if stock.gold < gold or stock.lumber < lumber:
		return false
	return router.issue_research(building, uid)

func _nearest_mine(worker: Node3D) -> Node3D:
	var best: Node3D = null
	var distance := INF
	for child in unit_host.get_children():
		if not child is Node3D or not CombatQuery.is_alive_in_world(child):
			continue
		if child.get_meta("unit_data", {}).get("typeId", "") != "ngol":
			continue
		var runtime := GoldMineRuntime.ensure(child)
		if runtime == null or runtime.is_depleted():
			continue
		var d := worker.global_position.distance_squared_to(child.global_position)
		if d < distance:
			distance = d
			best = child
	return best
