extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO REVIVE: " + label)

func run() -> void:
	check(BuildingCatalog.get_gold_cost("Hamg") == 425, "大法师原始价格425金")
	check(BuildingCatalog.get_build_time("Hamg") == 55, "大法师原始训练55秒")
	var gold := [170, 212, 255, 297, 340, 382, 425, 467, 510, 552]
	var seconds := [35.75, 71.5, 107.25, 110.0, 110.0, 110.0, 110.0, 110.0, 110.0, 110.0]
	for i in 10:
		check(HeroDeathRegistry.revive_cost(i + 1, "Hamg") == gold[i], "等级%d金币" % (i + 1))
		check(is_equal_approx(HeroDeathRegistry.revive_time_sec(i + 1, "Hamg"), seconds[i]), "等级%d时间" % (i + 1))
	check(HeroDeathRegistry.revive_cost(0, "Hamg") == 170, "低等级边界")
	check(HeroDeathRegistry.revive_cost(99, "Hamg") == 552, "高等级边界")
	var card := CommandCard.for_unit("halt", {"dead_heroes": [{"type_id": "Hamg", "level": 6}]})
	var tooltip := ""
	for button in card:
		if str(button.get("id", "")) == CommandCard.ACTION_REVIVE_PREFIX + "Hamg":
			tooltip = str(button.get("tooltip", ""))
	check(tooltip.contains("382金") and tooltip.contains("110s"), "祭坛命令卡显示相同六级报价与时间")
	for building_id in ["htow", "hbar", "hhou"]:
		var other_card := CommandCard.for_unit(building_id, {"dead_heroes": [{"type_id": "Hamg", "level": 6}]})
		var has_revive := false
		for button in other_card:
			has_revive = has_revive or str(button.get("id", "")).begins_with(CommandCard.ACTION_REVIVE_PREFIX)
		check(not has_revive, "%s不显示不可执行的复活按钮" % building_id)
	print("selftest_hero_revive_rules: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
