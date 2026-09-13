extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INVULNERABLE TARGET: " + label)

func unit(id: String, player: int, x: float) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": id, "owner": player})
	node.position = Wc3Coords.wc3_xy_to_godot(x, 0, 0)
	add_child(node)
	UnitLife.ensure(node)
	return node

func _ready() -> void:
	var attacker := unit("hfoo", 1, 0)
	var market := unit("nmrk", 15, 50)
	var hall := unit("htow", 0, 300)
	check("Avul" in AbilityCatalog.ability_ids_for_unit("nmrk"), "真实市场数据包含永久无敌能力")
	check(not CombatQuery.is_auto_acquire_target(attacker, market), "自动索敌跳过无敌市场")
	check(not CombatQuery.is_valid_attack_target(attacker, market), "显式攻击也不能攻击无敌目标")
	check(not CombatQuery.is_valid_spell_aoe_target(attacker, market), "伤害技能排除无敌目标")
	var pipeline := DamagePipeline.new()
	var hp := UnitLife.get_life(market)
	var hit := pipeline.apply({"attacker": attacker, "target": market})
	check(not hit.ok and UnitLife.get_life(market) == hp, "伤害入口不扣除无敌目标生命")
	check(CombatQuery.find_acquire_target(attacker, self) == hall, "更近市场不干扰敌方建筑索敌")
	market.set_meta("unit_data", {"typeId": "nmrk", "owner": 1})
	check(CombatQuery.is_valid_ally_spell_target(attacker, market), "无敌伤害过滤不误伤友军技能基础查询")
	market.set_meta("unit_data", {"typeId": "nmrk", "owner": 15})
	var attack := AttackController.new()
	attacker.add_child(attack)
	attack.configure(Callable(), func() -> Node: return self, pipeline)
	var hall_hp := UnitLife.get_life(hall)
	attack.start_attack_move(Vector2(300, 0))
	for frame in range(180):
		attack._process(1.0 / 60.0)
	check(UnitLife.get_life(hall) < hall_hp and UnitLife.get_life(market) == hp, "真实攻击移动跳过市场并对敌方主城结算伤害")
	print("selftest_invulnerable_targets: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
