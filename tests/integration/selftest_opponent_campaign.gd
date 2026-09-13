extends Node

var failures := 0
var checks := 0
var army_damage := 0.0
var army_killed_base := false
var battle_started_ms := -1
var battle_sim_seconds := 0.0

func _process(delta: float) -> void:
	if battle_started_ms >= 0:
		battle_sim_seconds += delta

func record_damage(result: Dictionary, target_id: int) -> void:
	var target: Node3D = result.get("target") as Node3D
	var attacker: Node3D = result.get("attacker") as Node3D
	if not is_instance_valid(target) or target.get_instance_id() != target_id or not is_instance_valid(attacker):
		return
	if not bool(result.get("ok", false)) or CombatQuery.owner_of(attacker) != 1 or CombatQuery.type_id_of(attacker) not in ["hfoo", "Hamg"]:
		return
	var first_hit := army_damage == 0.0
	army_damage += float(result.get("amount", 0.0))
	army_killed_base = army_killed_base or bool(result.get("killed", false))
	if first_hit or army_killed_base:
		print("campaign verified damage: attacker=", CombatQuery.type_id_of(attacker), " owner=1 total=", army_damage, " killed=", army_killed_base, " wall_s=", (Time.get_ticks_msec() - battle_started_ms) / 1000.0, " sim_s=", battle_sim_seconds)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("OPPONENT CAMPAIGN: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	# 正常对战开局：不生成测试军队、不补资源、不加速或直接下作战命令。
	var game: Node = load("res://game/scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.spawn_opponent_base = true
	director.enable_opponent_economy = true
	director.enable_opponent_army = true
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	director.random_start_location = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "真实地图完成初始化")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	var enemy: Node3D = null
	var home: Node3D = null
	var host := director.map_root.get_unit_layer()
	for unit in host.get_children():
		if CombatQuery.type_id_of(unit) == "htow":
			if CombatQuery.owner_of(unit) == 0:
				enemy = unit
			elif CombatQuery.owner_of(unit) == 1:
				home = unit
	check(enemy != null and home != null, "两方初始基地存在")
	if enemy == null or home == null:
		get_tree().quit(1)
		return
	var initial_life := UnitLife.get_life(enemy)
	director._damage_pipeline.damage_applied.connect(record_damage.bind(enemy.get_instance_id()))
	var seen: Dictionary = {}
	var marched := false
	var max_hero_xp := 0
	var max_hero_level := 1
	var stock := director.get_session().stocks[1] as PlayerStock
	battle_started_ms = Time.get_ticks_msec()
	deadline = battle_started_ms + 900000
	var next_report := Time.get_ticks_msec()
	while is_instance_valid(enemy) and UnitLife.get_life(enemy) > 0.0 and Time.get_ticks_msec() < deadline:
		var counts: Dictionary = {}
		for unit in host.get_children():
			if CombatQuery.owner_of(unit) != 1 or not CombatQuery.is_alive_in_world(unit) or UnitLife.is_under_construction(unit):
				continue
			var id := CombatQuery.type_id_of(unit)
			counts[id] = int(counts.get(id, 0)) + 1
			seen[id] = true
			if id == "Hamg":
				max_hero_xp = maxi(max_hero_xp, HeroProgression.xp_of(unit))
				max_hero_level = maxi(max_hero_level, AbilityCatalog.hero_level_of(unit))
			if id in ["hfoo", "Hamg"] and CombatQuery.distance_wc3(unit, home) > 2000:
				marched = true
		if Time.get_ticks_msec() >= next_report:
			next_report += 30000
			print("campaign: wall_s=", (Time.get_ticks_msec() - battle_started_ms) / 1000.0, " sim_s=", battle_sim_seconds, " units=", counts, " gold=", stock.gold, " lumber=", stock.lumber, " food=", stock.food_used, "/", stock.food_cap, " army=", director.get_node("OpponentArmy").last_status, " target_hp=", UnitLife.get_life(enemy))
			for soldier in host.get_children():
				if CombatQuery.owner_of(soldier) != 1 or CombatQuery.type_id_of(soldier) not in ["hfoo", "Hamg"] or not CombatQuery.is_alive_in_world(soldier):
					continue
				var attack := soldier.get_node_or_null("AttackController") as AttackController
				var nav := soldier.get_node_or_null("UnitNavigator") as UnitNavigator
				var target: Node3D = attack.get_target() if attack != null else null
				print("  tactical id=", soldier.get_instance_id(), " type=", CombatQuery.type_id_of(soldier), " hp=", UnitLife.get_life(soldier), " xy=", Wc3Coords.godot_to_wc3_xy(soldier.global_position), " attack=", attack.get_state() if attack != null else -1, " target=", CombatQuery.type_id_of(target) if is_instance_valid(target) else "none", " target_xy=", Wc3Coords.godot_to_wc3_xy(target.global_position) if is_instance_valid(target) else Vector2.INF, " moving=", nav.is_moving() if nav != null else false, " path=", nav.get_remaining_waypoints_wc3() if nav != null else [])
		await get_tree().process_frame
	check(seen.has("hbar") and seen.has("halt"), "正常经营建成兵营与祭坛")
	check(seen.has("Hamg") and seen.has("hfoo"), "正常付费生产英雄与步兵")
	check(marched, "自产军队自行离开基地远征")
	check(not is_instance_valid(enemy) or UnitLife.get_life(enemy) < initial_life, "自产军队进攻使敌方主城受伤")
	check(army_damage > 0, "伤害事件证实攻击者为电脑自产军队")
	check(army_killed_base, "电脑军队实际摧毁敌方主城")
	check(max_hero_xp > 0, "自产英雄从自然战斗获得经验")
	check(max_hero_level >= 2, "自产英雄在本局自然升级")
	print("campaign hero progression: xp=", max_hero_xp, " level=", max_hero_level)
	print("campaign final: wall_s=", (Time.get_ticks_msec() - battle_started_ms) / 1000.0, " sim_s=", battle_sim_seconds, " verified_damage=", army_damage, " base_life=", UnitLife.get_life(enemy) if is_instance_valid(enemy) else 0.0)
	battle_started_ms = -1
	# 等待 Director 在后续帧观察死亡快照，不由测试直接触发结算。
	await get_tree().process_frame
	await get_tree().process_frame
	var outcome := director.get_session().get_match_result()
	check(bool(outcome.get("finished", false)) and int(outcome.get("winner_team", -1)) == 1, "自然进攻后实际会话判电脑获胜")
	var result_screen: Node = game.get_node_or_null("MatchResultScreen")
	check(result_screen != null and result_screen.can_process() and result_screen.title_label.text == "失败", "同一自然对局显示本地失败结算")
	check(not director.can_process() and not director.get_node("OpponentArmy").can_process() and not director.get_node("OpponentEconomy").can_process(), "结算冻结对局与电脑控制器")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("selftest_opponent_campaign: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
