extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ARMY GAME: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	# 战斗测试夹具单独布置四个步兵；经济生产闭环由 two_player_start 另测。
	var game: Node = load("res://game/scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.spawn_opponent_base = true
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	director.enable_opponent_army = true
	director.random_start_location = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "真实战斗场景初始化")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	var halls: Dictionary = {}
	for unit in director.map_root.get_unit_layer().get_children():
		var data: Dictionary = unit.get_meta("unit_data", {})
		if data.get("typeId", "") == "htow":
			halls[int(data.get("owner", -1))] = unit
	check(halls.has(0) and halls.has(1), "双方基地存在")
	if not halls.has(0) or not halls.has(1):
		get_tree().quit(1)
		return
	var enemy: Node3D = halls[0]
	var home: Node3D = halls[1]
	var home_xy := Wc3Coords.godot_to_wc3_xy(home.global_position)
	var full_route := "--full-route" in OS.get_cmdline_user_args()
	# 默认隔离基地附近的真实接敌链路；跨地图远征保留为独立验收模式。
	var spawn_xy := home_xy if full_route else Wc3Coords.godot_to_wc3_xy(enemy.global_position) + Vector2(1000, 0)
	print("army fixture: ", "full_route" if full_route else "base_approach")
	var troops: Array[Node3D] = []
	var initial_positions: Array[Vector3] = []
	for i in range(4):
		var soldier := director._spawn_trained_unit("hfoo", spawn_xy, 1)
		if soldier != null:
			troops.append(soldier)
			initial_positions.append(soldier.global_position)
	check(troops.size() == 4, "四步兵战斗夹具生成")
	director._setup_opponent_economy()
	director.get_node("OpponentEconomy").set_process(false)
	var army := director.get_node("OpponentArmy")
	var initial_life := UnitLife.get_life(enemy)
	var moved := false
	deadline = Time.get_ticks_msec() + 180000
	var next_report := Time.get_ticks_msec() + 15000
	while is_instance_valid(enemy) and UnitLife.get_life(enemy) >= initial_life and Time.get_ticks_msec() < deadline:
		for i in range(troops.size()):
			if is_instance_valid(troops[i]) and troops[i].global_position.distance_to(initial_positions[i]) > 2.0:
				moved = true
		if Time.get_ticks_msec() >= next_report:
			next_report += 15000
			print("army progress: ", army.last_status, " moved=", moved, " target_hp=", UnitLife.get_life(enemy))
			for soldier in troops:
				if not is_instance_valid(soldier):
					continue
				var attack := soldier.get_node_or_null("AttackController") as AttackController
				var target: Node3D = attack.get_target() if attack != null else null
				print("  soldier hp=", UnitLife.get_life(soldier), " xy=", Wc3Coords.godot_to_wc3_xy(soldier.global_position), " target=", CombatQuery.type_id_of(target) if target != null else "none", " state=", attack.get_state() if attack != null else -1)
		await get_tree().process_frame
	check(moved, "军队经真实寻路离开出生位置")
	check(not is_instance_valid(enemy) or UnitLife.get_life(enemy) < initial_life, "真实攻击降低敌方主城生命")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("selftest_player_army_game: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
