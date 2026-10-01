extends SceneTree

const Experience = preload("res://packages/gameplay/features/heroes/logic/hero_experience.gd")
var failures := 0
var checks := 0
var host: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("DEATH XP: " + label)

func unit(id: String, owner: int, xy := Vector2.ZERO) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": id, "owner": owner})
	host.add_child(node)
	node.position = Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, 0)
	UnitLife.ensure(node)
	return node

func kill(victim: Node3D, killer: Node3D) -> void:
	UnitLife.set_life(victim, 0)
	Experience.award_death(victim, killer, host)
	victim.free()

func run() -> void:
	host = Node3D.new()
	root.add_child(host)
	check(Experience.reward_for_level(1, false) == 25 and Experience.reward_for_level(10, false) == 340, "普通单位经验递推")
	check(Experience.reward_for_level(6, true) == 400 and Experience.reward_for_level(10, true) == 800, "英雄经验表及递推")
	var hero := unit("Hamg", 0)
	var soldier := unit("hfoo", 0)
	HeroProgression.add_experience(hero, 190)
	var victim := unit("hpea", 12)
	var death := DeathService.new()
	death.unit_died.connect(func(v: Node3D, k: Node3D): Experience.award_death(v, k, host))
	death.kill(victim, soldier)
	check(HeroProgression.xp_of(hero) == 210 and AbilityCatalog.hero_level_of(hero) == 2, "部队清野20经验推动升级")
	death.kill(victim, soldier)
	Experience.award_death(victim, soldier, host)
	check(HeroProgression.xp_of(hero) == 210, "重复死亡与重复分配不重复入账")
	victim.free()
	HeroProgression.set_level(hero, 1)
	var far := unit("Hpal", 0, Vector2(3000, 0))
	kill(unit("hpea", 1), soldier)
	check(HeroProgression.xp_of(hero) == 25 and HeroProgression.xp_of(far) == 0, "近处英雄独享经验")
	hero.position = Wc3Coords.wc3_xy_to_godot(3000, 0, 0)
	kill(unit("hpea", 1), soldier)
	check(HeroProgression.xp_of(hero) == 37 and HeroProgression.xp_of(far) == 12, "无近处英雄时全局均分并取整")
	far.free()
	HeroProgression.set_level(hero, 5)
	var before := HeroProgression.xp_of(hero)
	kill(unit("hpea", 12), soldier)
	check(HeroProgression.xp_of(hero) == before, "五级英雄不获野怪经验")
	kill(unit("hpea", 0), soldier)
	check(HeroProgression.xp_of(hero) == before, "击杀友军不获经验")
	kill(unit("hpea", 1), unit("hgtw", 0))
	check(HeroProgression.xp_of(hero) == before, "建筑击杀不发经验")
	kill(unit("htow", 1), soldier)
	check(HeroProgression.xp_of(hero) == before, "无攻击建筑死亡不发经验")
	var summon := unit("hpea", 1)
	summon.set_meta("summon_caster_id", 123)
	kill(summon, soldier)
	check(HeroProgression.xp_of(hero) == before + 12, "召唤物经验乘以导入系数")
	host.free()
	print("selftest_hero_death_xp: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
