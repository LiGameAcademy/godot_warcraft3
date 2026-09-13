extends Node

var failures := 0
var checks := 0
var notifications := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MATCH SESSION: " + label)

func building(player: int) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": "htow", "owner": player})
	node.set_meta("life", 1500.0)
	add_child(node)
	return node

func _ready() -> void:
	var session := GameSession.new()
	session.match_finished.connect(func(result: Dictionary) -> void:
		notifications += 1
		result.winner_team = 99
		result.defeated_teams.clear()
	)
	check(not session.evaluate_match(self).finished, "未启用时空场景不会结束")
	var first := building(0)
	var second := building(1)
	var teams := {0: 0, 1: 1}
	session.arm_match(teams)
	teams[1] = 0
	check(not session.evaluate_match(self).finished, "双方有建筑时保持进行中")
	UnitLife.set_life(first, 0)
	var result := session.evaluate_match(self)
	check(result.finished and result.winner_team == 1 and result.defeated_teams == [0], "外部队伍及信号载荷修改不污染结算")
	check(notifications == 1, "结束时通知一次")
	result.winner_team = 88
	result.defeated_teams.clear()
	check(session.get_match_result().winner_team == 1 and session.get_match_result().defeated_teams == [0], "返回结果为独立副本")
	UnitLife.set_life(second, 0)
	UnitLife.set_life(first, 1500)
	session.arm_match({0: 5, 1: 6})
	check(session.evaluate_match(self).winner_team == 1 and notifications == 1, "后续死亡复活与重复启用不能反转结果或重复通知")
	var view := session.get_match_result()
	view.winner_team = 77
	check(session.get_match_result().winner_team == 1, "读取结果不暴露内部字典")
	var solo := GameSession.new()
	solo.arm_match({0: 0})
	check(not solo.evaluate_match(self).finished and solo.get_match_result().is_empty(), "单方地图不产生终局")
	print("selftest_match_session: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
