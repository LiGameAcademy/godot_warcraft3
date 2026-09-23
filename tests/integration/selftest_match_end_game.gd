extends Node

var failures := 0
var checks := 0
var notifications := 0
var expired := false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MATCH END GAME: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://game/scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.spawn_opponent_base = true
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	director.random_start_location = false
	var standalone := "--main-scene" in OS.get_cmdline_user_args()
	var host: Node = get_tree().root if standalone else self
	host.add_child(game)
	if standalone:
		get_tree().current_scene = game
		check(get_tree().current_scene == game and game.get_parent() == get_tree().root, "对局作为根视口下的活动主场景")
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "真实双人地图就绪")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	var old_navigation: WeakRef = weakref(director._navigation)
	var old_reservations := director._cell_reservation
	var session := director.get_session()
	session.match_finished.connect(func(_result: Dictionary) -> void: notifications += 1)
	var halls: Dictionary = {}
	for unit in director.map_root.get_unit_layer().get_children():
		if CombatQuery.type_id_of(unit) == "htow":
			halls[CombatQuery.owner_of(unit)] = unit
	check(halls.has(0) and halls.has(1), "两方主城存在")
	if not halls.has(0) or not halls.has(1):
		get_tree().quit(1)
		return
	await get_tree().process_frame
	check(session.get_match_result().is_empty() and director.can_process(), "双主城存活时不会提前结束")
	# 结算夹具：真实出生与伤害/死亡入口；不冒充自然经营远征。
	var attacker := director._spawn_trained_unit("hfoo", Wc3Coords.godot_to_wc3_xy(halls[1].global_position), 1)
	var delayed := preload("res://scripts/shared/infra/scene_delay.gd").create_timer(attacker, 0.5)
	delayed.timeout.connect(func() -> void: expired = true)
	var hit := director._damage_pipeline.apply({"attacker": attacker, "target": halls[0], "dmgplus": 100000, "dice": 0, "sides": 1})
	check(hit.ok and hit.killed, "真实伤害入口摧毁最后一栋建筑")
	await get_tree().process_frame
	await get_tree().process_frame
	check(session.get_match_result().get("winner_team", -1) == 1 and notifications == 1, "实际会话自动结算且仅通知一次")
	check(not director.can_process() and not attacker.can_process() and not game.get_node("UnitSelector").can_process(), "模拟和游戏输入节点停止处理")
	var screen: Node = game.get_node_or_null("MatchResultScreen")
	check(screen != null and screen.can_process(), "结算层在冻结的对局中仍可操作")
	if screen != null:
		check(screen.title_label.text == "失败" and screen.exit_button.text == "退出游戏", "本地败方显示正确结果和退出按钮")
	var gold: int = session.stocks[1].gold
	var position := attacker.global_position
	await get_tree().create_timer(1.0).timeout
	check(session.stocks[1].gold == gold and attacker.global_position == position and notifications == 1, "结算后位置资源与通知保持稳定")
	check(not expired and is_instance_valid(delayed), "结算冻结待执行延迟回调")
	check(not get_tree().paused and can_process(), "外层场景不被对局冻结")
	if "--restart" in OS.get_cmdline_user_args() and screen != null:
		var game_name := game.name
		session.stocks[1].gold = 17
		HeroDeathRegistry.restore_dead({"type_id": "Hamg", "owner": 1, "level": 3})
		check(HeroDeathRegistry.dead_count(1) > 0, "旧局确有待复活记录")
		screen.restart_button.pressed.emit()
		check(screen.restart_button.disabled, "重开请求后阻止重复点击")
		await get_tree().process_frame
		await get_tree().process_frame
		check(not is_instance_valid(game) and not is_instance_valid(delayed), "重开销毁旧对局及等待回调")
		game = host.get_node(NodePath(game_name))
		if standalone:
			check(get_tree().current_scene == game and game.get_parent() == get_tree().root, "主场景重开更新活动场景指针")
		director = game.get_node("GameDirector") as GameDirector
		deadline = Time.get_ticks_msec() + 180000
		while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
			await get_tree().process_frame
		check(director.is_session_ready() and director.can_process(), "新局完成加载并恢复处理")
		check(old_navigation.get_ref() == null, "restart destroys old navigation module")
		check(director._cell_reservation != old_reservations, "restart creates fresh navigation reservations")
		var fresh := director.get_session()
		check(fresh != session and fresh.get_match_result().is_empty(), "新会话不继承胜负结果")
		check(fresh.stocks.has(1) and fresh.stocks[1].gold == 500 and fresh.stocks[1].lumber == 150, "新局恢复正常初始资源")
		check(HeroDeathRegistry.dead_count(1) == 0, "旧局英雄阵亡记录不串入新局")
		check(director.spawn_opponent_base and not director.random_start_location and not director.dev_spawn_archmage and not director.dev_spawn_priest, "重开保留双方及调试出生配置")
		check(game.get_node_or_null("MatchResultScreen") == null and not get_tree().paused, "新局不残留结算层或全局暂停")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	check(not is_instance_valid(delayed) and not expired, "卸载对局取消其延迟回调")
	if standalone:
		check(get_tree().current_scene == null and can_process(), "卸载主场景清空指针且外部观察仍运行")
	print("selftest_match_end_game: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
