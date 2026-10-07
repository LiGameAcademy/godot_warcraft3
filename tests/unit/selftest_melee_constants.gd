extends SceneTree

const Rules = preload("res://packages/gameplay/catalog/melee_game_constants.gd")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MELEE CONSTANTS: " + label)

func run() -> void:
	var parsed := Rules.parse_misc("\ufeff[Other]\nWrong=1\n[Misc]\n Value = .40 // note\nList=80,70,60,50,0\n[Other]\nValue=9")
	check(parsed == {"Value": ".40", "List": "80,70,60,50,0"}, "只读取Misc节并保留列表，处理注释与BOM")
	check(Rules.number("HeroMaxReviveCostGold", -1) == 700, "当前补丁金币上限700")
	check(Rules.number("HeroMaxReviveTime", -1) == 150, "当前补丁时间上限150")
	check(Rules.revive_gold(1000, 10) == 700, "昂贵英雄应用导入金币上限")
	check(Rules.revive_seconds(90, 10) == 150, "长训练英雄应用导入时间上限")
	check(Rules.revive_seconds(55, 10) == 110, "原始训练时间两倍仍会更早封顶")
	check(Rules.revive_gold(425, 3) == 255, "小数因子不产生少扣1金的浮点截断")
	print("selftest_melee_constants: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
