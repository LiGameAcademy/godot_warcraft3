extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("HERO COMBAT: " + label)

func unit(id: String, player: int) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": id, "owner": player})
	add_child(node)
	UnitLife.ensure(node)
	return node

func _ready() -> void:
	var hero := unit("Hamg", 1)
	var footman := unit("hfoo", 0)
	var bal := CombatQuery.balance_of(hero)
	var weapon := CombatQuery.weapons_of(hero)
	print("hero raw: def=", bal.def, " realdef=", bal.realdef, " primary=", bal.primary_attr, " plus=", weapon.dmgplus1, " dice=", weapon.dice1, " sides=", weapon.sides1, " cooldown=", weapon.cool1)
	var pipeline := DamagePipeline.new()
	pipeline.rng.push_sequence([1])
	var hit := pipeline.apply({"attacker": hero, "target": footman})
	check(hit.roll == 21, "一级大法师普通攻击下限21包含19主属性")
	pipeline.rng.push_sequence([100])
	hit = pipeline.apply({"attacker": hero, "target": footman})
	check(hit.roll == 27, "一级大法师普通攻击上限27")
	var defended := pipeline.apply({"attacker": footman, "target": hero})
	check(is_equal_approx(float(defended.armor), 3.1), "一级大法师17敏捷形成3.1实际护甲")
	check(is_equal_approx(CombatQuery.cooldown_sec(hero), weapon.cool1 / 1.34), "17敏捷提高34%攻击速度")
	check(is_equal_approx(CombatQuery.damage_point_sec(hero), weapon.dmgpt1 / 1.34), "攻击前摇同步敏捷攻速")
	HeroProgression.set_level(hero, 10)
	pipeline.rng.push_sequence([1])
	UnitLife.set_ratio(footman, 1)
	hit = pipeline.apply({"attacker": hero, "target": footman})
	check(hit.roll == 49, "十级大法师普通攻击下限49随主属性成长")
	defended = pipeline.apply({"attacker": footman, "target": hero})
	check(is_equal_approx(float(defended.armor), 5.8), "十级26敏捷护甲5.8")
	check(is_equal_approx(CombatQuery.cooldown_sec(hero), weapon.cool1 / 1.52), "十级敏捷攻速随等级同步")
	var spell := pipeline.apply({"attacker": hero, "target": footman, "source_kind": "spell", "dmgplus": 10, "dice": 0, "sides": 1})
	check(spell.roll == 10, "固定技能伤害不加英雄主属性")
	var explicit_weapon := pipeline.apply({"attacker": hero, "target": footman, "dmgplus": 10, "dice": 0, "sides": 1})
	check(explicit_weapon.roll == 10, "显式武器伤害参数保持调用方给定值")
	check(is_equal_approx(CombatQuery.cooldown_sec(footman), CombatQuery.weapons_of(footman).cool1), "非英雄不获得敏捷攻速")
	var info := SelectionInfoBuilder.build(hero, [hero])
	check(info.attack.value == "49–55", "选中面板显示当前十级攻击")
	check(info.armor.value == "5.8", "选中面板护甲与实际伤害结算一致")
	check("主智力 · 力30 敏26 智47" in info.special_lines, "属性文本随英雄等级更新")
	print("selftest_hero_combat_stats: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
