extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO LIFE: " + label)

func unit(id: String, percent: float = -1) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": id, "owner": 1, "hitPoints": percent})
	add_child(node)
	return node

func _ready() -> void:
	var hero := unit("Hamg")
	check(UnitLife.get_max_life(hero) == 450 and UnitLife.get_life(hero) == 450, "一级大法师基础生命加力量得到450")
	var partial := unit("Hamg", 50)
	check(UnitLife.get_life(partial) == 225, "地图出生血量百分比应用于完整英雄上限")
	var footman := unit("hfoo")
	check(UnitLife.get_max_life(footman) == 420, "非英雄生命不受英雄公式影响")
	UnitLife.set_life(hero, 350)
	HeroProgression.set_level(hero, 2)
	check(UnitLife.get_max_life(hero) == 475 and UnitLife.get_life(hero) == 375, "升级力量取整并保持已受100点伤害")
	var expected := [525, 575, 625, 675, 700, 750, 800, 850]
	for i in range(expected.size()):
		HeroProgression.set_level(hero, i + 3)
		check(UnitLife.get_max_life(hero) == expected[i], "大法师%d级生命对照" % (i + 3))
	var before := UnitLife.get_life(hero)
	HeroProgression.set_level(hero, 10)
	check(UnitLife.get_life(hero) == before, "重复设置同等级不回血")
	UnitLife.set_life(hero, 0)
	HeroProgression.set_level(hero, 1)
	HeroProgression.set_level(hero, 10)
	check(UnitLife.get_life(hero) == 0, "属性刷新不复活死亡英雄")
	print("selftest_hero_life: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
