extends Node

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CHASE FACING: " + label)

func _ready() -> void:
	var attacker := Node3D.new()
	attacker.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	attacker.set_meta("life", 420.0)
	add_child(attacker)
	var target := Node3D.new()
	target.set_meta("unit_data", {"typeId": "hfoo", "owner": 0})
	target.set_meta("life", 420.0)
	add_child(target)
	target.position = Wc3Coords.wc3_xy_to_godot(1000, 0, 0)
	var attack := AttackController.new()
	attacker.add_child(attack)
	attack._target = target
	attack._mode = AttackController.Mode.ATTACK
	attack._repath_cd = 1.0
	# 敌人在东边，但绕障路径需要先向西走；导航已将单位转向西。
	attacker.rotation.y = PI
	attack._chase_or_strike(0.016)
	check(attack.get_state() == AttackController.State.CHASE, "射程外进入追击")
	check(absf(angle_difference(attacker.rotation.y, PI)) < 0.001, "追击不覆盖导航绕障朝向")
	target.position = Wc3Coords.wc3_xy_to_godot(80, 0, 0)
	attack._chase_or_strike(0.016)
	check(attack.get_state() == AttackController.State.WINDUP, "进入射程开始前摇")
	check(absf(attacker.rotation.y) < 0.001, "实际出手时面向目标")
	target.position = Wc3Coords.wc3_xy_to_godot(1000, 0, 0)
	attacker.rotation.y = PI
	var nav := UnitNavigator.new()
	attacker.add_child(nav)
	check(nav.go_waypoints_wc3([Vector2(-300, 0)]), "真实导航接收绕障首段路点")
	for frame in range(60):
		attack._chase_or_strike(1.0 / 60.0)
		nav._process(1.0 / 60.0)
	check(Wc3Coords.godot_to_wc3_xy(attacker.global_position).x < -200, "追击与导航共同步进时能沿绕障方向推进")
	print("selftest_attack_chase_facing: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
