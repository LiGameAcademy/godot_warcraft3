extends Node

## BuildModule 集成：脚本侧触发一次完整的建造生命周期，确认
## - 半成品入图
## - 工地注册表更新
## - 完工后 half-finished → full building
## - BuildModule 的信号各阶段都触发

var failures := 0
var checks := 0
var completed_count := 0
var started_count := 0
var cancelled_count := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BUILD GAME: " + label)


func _on_started(_order: BuildOrder) -> void:
	started_count += 1


func _on_completed(_order: BuildOrder, _site: Vector2, _owner: int) -> void:
	completed_count += 1


func _on_cancelled(_order: BuildOrder) -> void:
	cancelled_count += 1


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var game: Node = load("res://scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.spawn_opponent_base = true
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	director.enable_opponent_army = false
	director.random_start_location = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 120000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "真实对局初始化")
	if not director.is_session_ready():
		get_tree().quit(1)
		return

	# 找出本地主城作为建工地出发点。
	var home: Node3D = null
	for unit in director.map_root.get_unit_layer().get_children():
		var data: Dictionary = unit.get_meta("unit_data", {})
		if data.get("typeId", "") == "htow" and int(data.get("owner", -1)) == director.local_player:
			home = unit
			break
	check(home != null, "找到本地主城")
	if home == null:
		game.queue_free()
		get_tree().quit(1)
		return

	var module := director._ensure_build_module()
	check(module != null, "_ensure_build_module 返回 BuildModule")
	module.construction_started.connect(_on_started)
	module.construction_completed.connect(_on_completed)
	module.construction_cancelled.connect(_on_cancelled)

	var home_xy := Wc3Coords.godot_to_wc3_xy(home.global_position)
	var site_xy := home_xy + Vector2(640.0, 0.0)

	# 1. 直接调用 BuildController 路径：BuildController 会 emit build_started；
	#    Director._on_build_started → module.on_construction_started。
	# 简化起见：直接调用 module.on_construction_started 来刷半成品。
	var order := BuildOrder.new()
	order.building_id = "hfoo"
	order.site_wc3 = site_xy
	order.owner = director.local_player
	# 让 BuildSite 真实存在：构造并 configure_session。
	var session := director.get_session()
	var site := BuildSite.new()
	site.name = "BuildSiteTest"
	module.add_child(site)
	site.configure_session(session)
	site.start(order, director.local_player)
	module.register_site(site, null, order)

	# 半成品入图（无 builder；走无 builder 分支）。
	module.on_construction_started(order)
	check(started_count == 1, "construction_started 信号触发")

	check(director._find_build_site(site_xy, "hfoo") == site, "Director adapter uses authoritative registry")
	check(director._command_router._find_site_at(site_xy, "hfoo") == site, "command router sees registered site")
	check(get_tree().get_nodes_in_group("build_sites_host").size() == 1, "one site host per match")
	# 半成品是否在场景里。
	var half_found := false
	for unit in director.map_root.get_unit_layer().get_children():
		if unit.has_meta("unit_data") and int(unit.get_meta("unit_data", {}).get("owner", -1)) == director.local_player and str(unit.get_meta("unit_data", {}).get("typeId", "")) == "hfoo" and UnitLife.is_under_construction(unit):
			check(director._command_router._find_site_for_building_node(unit) == site, "router finds site by building")
			half_found = true
			break
	check(half_found, "半成品 hfoo 已入图且 under_construction")

	# 完工：直接通过 site.build_completed 触发（BuildController / 计时器通常会发）。
	site._elapsed = site.total()
	site.emit_signal("build_completed", order, site_xy, director.local_player)
	# 双重去重：Director 和 Module 都监听同一个信号，期望 completed_count = 1（状态机去重）。
	await get_tree().process_frame
	check(completed_count == 1, "construction_completed 信号触发一次")
	# 半成品应已转正：还在原位、但不再 under_construction。
	var promoted := false
	for unit in director.map_root.get_unit_layer().get_children():
		if unit.has_meta("unit_data") and int(unit.get_meta("unit_data", {}).get("owner", -1)) == director.local_player and str(unit.get_meta("unit_data", {}).get("typeId", "")) == "hfoo" and not UnitLife.is_under_construction(unit):
			promoted = true
			break
	check(promoted, "半成品已转正（满血、under_construction=false）")
	# 完工后 BuildModule 应已 unregister site。
	check(module.find_site(site_xy, "hfoo") == null, "完工后 site 注册已清")

	check(director._command_router._find_site_at(site_xy, "hfoo") == null, "completed site unavailable to router")
	game.queue_free()
	await get_tree().process_frame
	print("selftest_build_module_game: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)