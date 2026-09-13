extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("BUILDING RANGE: " + label)

func _ready() -> void:
	var attacker := Node3D.new()
	attacker.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	add_child(attacker)
	var target := Node3D.new()
	target.set_meta("unit_data", {"typeId": "htow", "owner": 0})
	target.set_meta("life", 1500.0)
	add_child(target)
	var half := Vector2(BuildingCatalog.get_footprint("htow")) * Wc3Coords.PATHING_CELL * 0.5
	var reach := CombatQuery.attack_range_wc3(attacker)
	check(half.x > reach and reach > 0, "真实主城占地大于步兵射程")
	attacker.position = Wc3Coords.wc3_xy_to_godot(half.x + reach - 1, 0, 0)
	check(CombatQuery.in_attack_range(attacker, target), "建筑外沿射程内可出手")
	check(CombatQuery.in_engage_range(attacker, target), "出手位置也在交战范围")
	check(CombatQuery.find_acquire_target(attacker, self, reach) == target, "Hold 射程索敌与建筑出手距离一致")
	attacker.position = Wc3Coords.wc3_xy_to_godot(half.x + reach + 1, 0, 0)
	check(not CombatQuery.in_attack_range(attacker, target), "建筑外沿超射程不可出手")
	attacker.position = Wc3Coords.wc3_xy_to_godot(half.x + reach * 0.8, half.y + reach * 0.8, 0)
	check(not CombatQuery.in_attack_range(attacker, target), "建筑角落使用欧氏距离而非方形射程")
	target.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	attacker.position = Wc3Coords.wc3_xy_to_godot(reach + 1, 0, 0)
	check(not CombatQuery.in_attack_range(attacker, target), "移动单位既有射程保持不变")
	check(CombatQuery.in_attack_range(attacker, target, 2), "显式射程容差有效")
	print("selftest_building_attack_range: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
