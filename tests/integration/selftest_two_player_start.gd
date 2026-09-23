extends Node

var failed := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("TWO PLAYER START: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var a := {"owner": 0, "position": {"x": 0, "y": 0}}
	var duplicate := {"owner": 1, "position": {"x": 0, "y": 0}}
	var b := {"owner": 2, "position": {"x": 1024, "y": 1024}}
	var free := MeleeBootstrap.available_slocs([a, duplicate, b, b], [a])
	check(free.size() == 1 and free[0] == b, "按坐标排除已占和重复出生点")
	check(MeleeBootstrap.available_slocs([a, duplicate], [a]).is_empty(), "无剩余出生点不会重叠分配")
	var game: Node = load("res://scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.spawn_opponent_base = true
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	director.local_player = 0
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "真实游戏完成初始化")
	if director.is_session_ready():
		var session := director.get_session()
		var halls: Dictionary = {}
		var workers := {0: 0, 1: 0}
		for unit in director.map_root.get_unit_layer().get_children():
			var data: Dictionary = unit.get_meta("unit_data", {})
			var owner := int(data.get("owner", -1))
			if owner not in [0, 1]:
				continue
			if data.get("typeId", "") == "htow":
				halls[owner] = unit.global_position
			elif data.get("typeId", "") == "hpea":
				workers[owner] += 1
		check(halls.size() == 2 and halls[0] != halls[1], "两方主城位于不同出生点")
		check(workers[0] == 5 and workers[1] == 5, "双方各生成五名工人")
		check(session.stocks.has(1), "对手库存已注册")
		if session.stocks.has(1):
			var human := session.stocks[0] as PlayerStock
			var opponent := session.stocks[1] as PlayerStock
			check(human != opponent and human.gold == 500 and opponent.gold == 500, "双方初始金币相同但库存独立")
			check(opponent.food_used == 5 and opponent.food_cap == BuildingCatalog.get_food_made("htow"), "对手人口匹配实际开局单位")
			check(not director._spawn_opponent_base(MeleeBootstrap.collect_slocs(director.map_dir), a), "重复开局不再创建对手基地")
			await check_opponent_harvest(director)
			var gold_before := opponent.gold
			var lumber_before := opponent.lumber
			var human_gold := human.gold
			var human_lumber := human.lumber
			director._setup_opponent_economy()
			director.get_node("OpponentEconomy").desired_workers = 5
			director.get_node("OpponentEconomy").develop_army = false
			var economy_deadline := Time.get_ticks_msec() + 90000
			while (opponent.gold <= gold_before or opponent.lumber <= lumber_before) and Time.get_ticks_msec() < economy_deadline:
				await get_tree().process_frame
			check(opponent.gold > gold_before and opponent.lumber > lumber_before, "电脑自行分工完成金木交货")
			check(human.gold == human_gold and human.lumber == human_lumber, "电脑经营不改变本地资源")
			var economy := director.get_node("OpponentEconomy")
			check(not str(economy.last_status).is_empty(), "经营决策提供当前状态")
			await check_worker_production(director, economy)
			var cap_before := opponent.food_cap
			var local_cap := human.food_cap
			economy.supply_buffer = cap_before - opponent.food_used + 1
			var farm_deadline := Time.get_ticks_msec() + 90000
			while opponent.food_cap == cap_before and Time.get_ticks_msec() < farm_deadline:
				await get_tree().process_frame
			check(opponent.food_cap == cap_before + BuildingCatalog.get_food_made("hhou"), "电脑建成农场增加自身人口上限")
			check(human.food_cap == local_cap, "电脑农场不增加本地人口上限")
			var farms := 0
			for unit in director.map_root.get_unit_layer().get_children():
				var data: Dictionary = unit.get_meta("unit_data", {})
				if data.get("typeId", "") == "hhou" and int(data.get("owner", -1)) == 1:
					farms += 1
			check(farms == 1, "施工期间不重复下单造农场")
			economy.develop_army = true
			economy.supply_buffer = 2
			var army_deadline := Time.get_ticks_msec() + 210000
			while (owned_type_count(director, "Hamg") < 1 or owned_type_count(director, "hfoo") < 1) and Time.get_ticks_msec() < army_deadline:
				await get_tree().process_frame
			check(owned_type_count(director, "hbar") == 1 and owned_type_count(director, "halt") == 1, "电脑建成兵营和祭坛且不重复")
			check(owned_type_count(director, "Hamg") == 1, "电脑从祭坛正常训练英雄")
			check(owned_type_count(director, "hfoo") >= 1, "电脑从兵营正常训练步兵")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("selftest_two_player_start: %s (%d checks)" % ["PASS" if failed == 0 else "FAIL", checks])
	get_tree().quit(0 if failed == 0 else 1)

func check_opponent_harvest(director: GameDirector) -> void:
	var host := director.map_root.get_unit_layer()
	var worker: Node3D = null
	for unit in host.get_children():
		var data: Dictionary = unit.get_meta("unit_data", {})
		if data.get("typeId", "") == "hpea" and int(data.get("owner", -1)) == 1:
			worker = unit
			break
	check(worker != null, "找到对手采集工人")
	if worker == null:
		return
	var mine: Node3D = null
	var distance := INF
	for unit in host.get_children():
		if unit.get_meta("unit_data", {}).get("typeId", "") != "ngol":
			continue
		var d := worker.global_position.distance_squared_to(unit.global_position)
		if d < distance:
			distance = d
			mine = unit
	var router := CommandRouter.new()
	router.configure(null, null, director._ensure_navigator, director._ensure_harvest_controller, Callable(), director.get_session(), Callable(), Callable(), Callable(), 1)
	var human := director.get_session().stocks[0] as PlayerStock
	var opponent := director.get_session().stocks[1] as PlayerStock
	var human_before := human.gold
	var opponent_before := opponent.gold
	check(router.issue_harvest_gold([worker], mine) == 1, "对手命令入口下达采金")
	var deadline := Time.get_ticks_msec() + 45000
	while opponent.gold == opponent_before and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(opponent.gold > opponent_before, "实际采金往返增加对手库存")
	check(human.gold == human_before, "对手交金不增加本地金币")
	var controller := worker.get_node_or_null("HarvestController") as HarvestController
	if controller != null:
		controller.abort()

func check_worker_production(director: GameDirector, economy: Node) -> void:
	var session := director.get_session()
	var opponent := session.stocks[1] as PlayerStock
	var human := session.stocks[0] as PlayerStock
	var old_workers := opponent_workers(director)
	var before := opponent.gold
	var human_before := human.gold
	economy.desired_workers = old_workers.size() + 1
	economy.decide()
	economy.decide()
	economy.decide()
	check(opponent.gold == before - BuildingCatalog.get_gold_cost("hpea"), "多次决策仅支付一名缺额工人的费用")
	check(human.gold == human_before, "电脑补工人不扣本地金币")
	var deadline := Time.get_ticks_msec() + 60000
	var joined := false
	while not joined and Time.get_ticks_msec() < deadline:
		for worker in opponent_workers(director):
			if worker not in old_workers:
				var harvest := worker.get_node_or_null("HarvestController") as HarvestController
				if harvest != null and harvest.is_active():
					joined = true
		await get_tree().process_frame
	check(opponent_workers(director).size() == old_workers.size() + 1, "主城真实训练出缺额工人")
	check(joined, "新工人自动加入采集")
	check(opponent.food_used == old_workers.size() + 1, "补工人人口只预占一次，实际 %d" % opponent.food_used)

func opponent_workers(director: GameDirector) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for unit in director.map_root.get_unit_layer().get_children():
		var data: Dictionary = unit.get_meta("unit_data", {})
		if data.get("typeId", "") == "hpea" and int(data.get("owner", -1)) == 1 and UnitLife.get_life(unit) > 0.0:
			result.append(unit)
	return result

func owned_type_count(director: GameDirector, type_id: String) -> int:
	var count := 0
	for unit in director.map_root.get_unit_layer().get_children():
		var data: Dictionary = unit.get_meta("unit_data", {})
		if data.get("typeId", "") == type_id and int(data.get("owner", -1)) == 1 and CombatQuery.is_alive_in_world(unit) and not UnitLife.is_under_construction(unit):
			count += 1
	return count
