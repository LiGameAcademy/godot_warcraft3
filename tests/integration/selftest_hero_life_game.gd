extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO LIFE GAME: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var game: Node = load("res://scenes/game_main.tscn").instantiate()
	var director := game.get_node("GameDirector") as GameDirector
	director.dev_spawn_archmage = false
	director.dev_spawn_priest = false
	add_child(game)
	var deadline := Time.get_ticks_msec() + 180000
	while not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	check(director.is_session_ready(), "真实地图就绪")
	if not director.is_session_ready():
		get_tree().quit(1)
		return
	var hall: Node3D = null
	for node in director.map_root.get_unit_layer().get_children():
		if CombatQuery.type_id_of(node) == "htow" and CombatQuery.owner_of(node) == director.local_player:
			hall = node
			break
	check(hall != null, "找到出生建筑")
	if hall == null:
		get_tree().quit(1)
		return
	# 生命周期夹具：调用正常训练完工的出生入口，不冒充付费训练验收。
	var hero := director._spawn_trained_unit("Hamg", Wc3Coords.godot_to_wc3_xy(hall.global_position), director.local_player, hall)
	check(hero != null, "真实英雄模型出生")
	if hero != null:
		await get_tree().process_frame
		check(UnitLife.get_max_life(hero) == 450 and UnitLife.get_life(hero) == 450, "真实出生及运行时初始化后450生命")
		check(UnitMana.get_max_mana(hero) == 285 and UnitMana.get_mana(hero) == 285, "真实出生后285魔法")
		director._apply_revived_hero_state(hero, {"revive_level": 6, "revive_xp": HeroProgression.xp_threshold(6)})
		check(UnitLife.get_max_life(hero) == 675 and UnitLife.get_life(hero) == 675, "新生英雄恢复六级后获得完整675生命")
		check(UnitMana.get_max_mana(hero) == 525 and UnitMana.get_mana(hero) == 100, "祭坛复活恢复100魔法，上限仍为525")
		UnitLife.set_life(hero, 500)
		UnitMana.spend(hero, 100)
		director._ensure_hero_runtime(hero)
		check(UnitLife.get_life(hero) == 500, "重复运行时初始化不抹掉伤害")
		check(UnitMana.get_mana(hero) == 0, "重复运行时初始化不抹掉魔法消耗")
		var opponent := director._spawn_trained_unit("hfoo", Wc3Coords.godot_to_wc3_xy(hall.global_position), 1 - director.local_player)
		check(opponent != null, "真实受击单位出生")
		if opponent != null:
			director._damage_pipeline.rng.push_sequence([1])
			var hit := director._damage_pipeline.apply({"attacker": hero, "target": opponent})
			check(hit.ok and hit.roll == 37, "真实六级大法师伤害含35智力")
			var defended := director._damage_pipeline.apply({"attacker": opponent, "target": hero})
			check(defended.ok and is_equal_approx(float(defended.armor), 4.6), "真实六级英雄受击使用敏捷成长护甲")
			var xp_before := HeroProgression.xp_of(hero)
			UnitLife.set_life(opponent, 1)
			var kill_hit := director._damage_pipeline.apply({"attacker": hero, "target": opponent})
			check(kill_hit.killed and HeroProgression.xp_of(hero) == xp_before + 40, "真实伤害死亡入口给英雄40经验")
			director._death_service.kill(opponent, hero)
			check(HeroProgression.xp_of(hero) == xp_before + 40, "真实死亡重报不重复发奖")
		# 复活下单夹具：真实祭坛、阵亡入口及队列；验证扣费和计时，不快进宣称自然复活。
		var xy := Wc3Coords.godot_to_wc3_xy(hall.global_position)
		var altar := director.map_root.add_unit_instance({
			"typeId": "halt", "owner": director.local_player, "flags": 2,
			"position": {"x": xy.x + 400.0, "y": xy.y - 400.0, "z": 0.0},
			"angle": 0.0, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "creationNumber": 987651,
		}, director.map_root.get_heightfield_dict())
		check(altar != null, "真实祭坛创建")
		if altar != null:
			director._death_service.kill(hero)
			check(HeroDeathRegistry.dead_count(director.local_player) == 1, "真实阵亡登记")
			director.unit_selector.call("select_node", altar)
			var stock := director.get_session().local_stock()
			stock.add_gold(1000)
			var before := stock.gold
			director._try_issue_revive("Hamg")
			var queue := altar.get_node_or_null("TrainQueue") as TrainQueue
			check(queue != null and queue.is_training(), "六级英雄进入复活队列")
			check(before - stock.gold == 382, "实际复活扣382金")
			if queue != null and queue.is_training():
				var queued := queue.snapshot()[0]
				check(queued.gold == 382 and queued.lumber == 0 and is_equal_approx(queued.remaining_sec, 110.0), "实际队列报价与110秒时长")
	# 静止、无技能冷却时，升级必须主动刷新已选中英雄的技能点。
	if "--diagnose-material" in OS.get_cmdline_user_args(): print("material phase: spawn ui units")
	var ui_hero := director._spawn_trained_unit("Hamg", Wc3Coords.godot_to_wc3_xy(hall.global_position), director.local_player, hall)
	var ui_target := director._spawn_trained_unit("hfoo", Wc3Coords.godot_to_wc3_xy(hall.global_position), 1 - director.local_player)
	check(ui_hero != null and ui_target != null, "升级界面夹具单位出生")
	if ui_hero != null and ui_target != null:
		HeroProgression.set_level(ui_hero, 1, 190)
		if "--diagnose-material" in OS.get_cmdline_user_args(): print("material phase: select hero")
		director.unit_selector.call("select_node", ui_hero)
		if "--diagnose-material" in OS.get_cmdline_user_args(): print("material phase: selected")
		var skill_button := director.game_hud._command_grid.get_child(7) as Button
		check(skill_button.tooltip_text.contains("可用技能点：1"), "升级前显示1技能点")
		UnitLife.set_life(ui_target, 1)
		director._damage_pipeline.apply({"attacker": ui_hero, "target": ui_target})
		if "--diagnose-material" in OS.get_cmdline_user_args(): print("material phase: killed")
		check(AbilityCatalog.hero_level_of(ui_hero) == 2, "实际击杀跨越二级门槛")
		check(skill_button.tooltip_text.contains("可用技能点：2"), "不重选单位即显示新增技能点")
	if "--diagnose-material" in OS.get_cmdline_user_args():
		for node in game.find_children("*", "MeshInstance3D", true, false):
			var mesh_instance := node as MeshInstance3D
			if mesh_instance.material_override != null and mesh_instance.mesh != null:
				for surface in mesh_instance.mesh.get_surface_count():
					if mesh_instance.get_surface_override_material(surface) != null:
						print("material duplicate: ", mesh_instance.get_path(), " surface=", surface)
	if "--diagnose-material" in OS.get_cmdline_user_args(): print("material phase: queue free")
	if "--diagnose-hud-free" in OS.get_cmdline_user_args():
		game.process_mode = Node.PROCESS_MODE_DISABLED
		print("material phase: free HUD")
		director.game_hud.free()
		director.game_hud = null
		await get_tree().process_frame
		await get_tree().process_frame
		print("material phase: HUD freed; free remaining game")
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("selftest_hero_life_game: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
