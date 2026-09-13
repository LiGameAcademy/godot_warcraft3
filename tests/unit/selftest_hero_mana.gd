extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO MANA: " + label)

func _ready() -> void:
	var hero := Node3D.new()
	hero.set_meta("unit_data", {"typeId": "Hamg", "owner": 1})
	add_child(hero)
	check(UnitMana.get_max_mana(hero) == 285 and UnitMana.get_mana(hero) == 285, "一级大法师19智力对应285魔法")
	UnitMana.spend(hero, 100)
	HeroProgression.set_level(hero, 2)
	check(UnitMana.get_max_mana(hero) == 330 and UnitMana.get_mana(hero) == 230, "升级取整智力并保留已消耗魔法")
	var expected := [375, 420, 465, 525, 570, 615, 660, 705]
	for i in range(expected.size()):
		HeroProgression.set_level(hero, i + 3)
		check(UnitMana.get_max_mana(hero) == expected[i], "大法师%d级魔法对照" % (i + 3))
	var before := UnitMana.get_mana(hero)
	HeroProgression.set_level(hero, 10)
	UnitMana.sync_hero_max(hero)
	check(UnitMana.get_mana(hero) == before, "同级重复同步不补充魔法")
	check(not UnitMana.spend(hero, 1000), "余额不足仍不能施法")
	print("selftest_hero_mana: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
