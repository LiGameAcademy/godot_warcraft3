extends SceneTree

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO XP GAIN: " + label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var hero := Node3D.new()
	hero.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	UnitLife.ensure(hero)
	UnitMana.ensure(hero)
	UnitLife.set_life(hero, 400)
	UnitMana.spend(hero, 35)
	check(HeroProgression.add_experience(hero, 199).gained == 199 and AbilityCatalog.hero_level_of(hero) == 1, "未到门槛不升级")
	var first := HeroProgression.add_experience(hero, 1)
	check(first.levels_gained == 1 and AbilityCatalog.hero_level_of(hero) == 2, "恰到200经验升级")
	check(UnitLife.get_max_life(hero) == 475 and UnitLife.get_life(hero) == 425, "升级同步生命并保留伤害")
	check(UnitMana.get_max_mana(hero) == 330 and UnitMana.get_mana(hero) == 295, "升级同步魔法并保留消耗")
	check(HeroSkill.points_available(hero) == 2, "升级增加可用技能点")
	var jump := HeroProgression.add_experience(hero, 1200)
	check(jump.levels_gained == 3 and AbilityCatalog.hero_level_of(hero) == 5 and HeroProgression.xp_of(hero) == 1400, "一次奖励可跨越多级")
	check(HeroProgression.add_experience(hero, -5).gained == 0 and HeroProgression.xp_of(hero) == 1400, "负经验不扣减")
	UnitLife.set_life(hero, 0)
	check(HeroProgression.add_experience(hero, 100).gained == 0, "死亡英雄不入账")
	UnitLife.set_life(hero, 625)
	check(HeroProgression.add_experience(hero, 999999).gained == 4000 and AbilityCatalog.hero_level_of(hero) == 10, "奖励封顶十级")
	check(HeroProgression.add_experience(hero, 100).gained == 0 and HeroProgression.xp_of(hero) == 5400, "满级不再积累经验")
	var footman := Node3D.new()
	footman.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	check(HeroProgression.add_experience(footman, 100).gained == 0 and not footman.has_meta("hero_xp"), "非英雄不创建成长状态")
	hero.free()
	footman.free()
	check(HeroProgression.add_experience(null, 100).gained == 0, "空引用安全拒绝")
	print("selftest_hero_xp_gain: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
