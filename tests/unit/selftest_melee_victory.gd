extends Node

const VictoryRules = preload("res://addons/rts_gameplay/match/rules/melee_victory_rules.gd")

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MELEE VICTORY: " + label)

func unit(id: String, player: int) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": id, "owner": player})
	node.set_meta("life", 100.0)
	add_child(node)
	return node

func _ready() -> void:
	var teams := {0: 0, 1: 1}
	check(not VictoryRules.evaluate(self, teams).finished, "开局未完成时不判空地图为平局")
	var first := unit("htow", 0)
	var second := unit("htow", 1)
	check(not VictoryRules.evaluate(self, teams, true).finished, "双方有建筑时继续")
	UnitLife.set_life(first, 0)
	var farm := unit("hhou", 0)
	check(not VictoryRules.evaluate(self, teams, true).finished, "主城已毁但农场仍在时继续")
	UnitLife.set_under_construction(farm, true)
	check(not VictoryRules.evaluate(self, teams, true).finished, "未完工工地仍算存活建筑")
	UnitLife.set_life(farm, 0)
	unit("hpea", 0)
	unit("ngol", 15)
	var won := VictoryRules.evaluate(self, teams, true)
	check(won.finished and won.winner_team == 1 and won.defeated_teams == [0], "工人与中立建筑不能阻止建筑清场判负")
	var ally := unit("hhou", 2)
	teams[2] = 0
	check(not VictoryRules.evaluate(self, teams, true).finished, "盟友建筑仍在则团队未败")
	UnitLife.set_life(ally, 0)
	UnitLife.set_life(second, 0)
	var draw := VictoryRules.evaluate(self, teams, true)
	check(draw.finished and draw.draw and draw.winner_team == -1, "双方建筑同时归零按项目规则判和")
	check(not VictoryRules.evaluate(self, {0: 0}, true).finished, "单方测试地图不自动结束")
	print("selftest_melee_victory: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
