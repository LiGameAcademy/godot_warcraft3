extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("UNIT FX ANIMATION: " + label)

func player(names: Array) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	var library := AnimationLibrary.new()
	for name in names:
		library.add_animation(name, Animation.new())
	ap.add_animation_library("", library)
	return ap

func run() -> void:
	# 与原始 glTF 单位相同：Model 是普通 Node3D；命中特效有烘焙门面。
	var unit := Unit.new()
	var model := Node3D.new()
	model.name = Unit.MODEL_NODE_NAME
	var body_ap := player(["Stand", "Attack", "Death"])
	model.add_child(body_ap)
	unit.add_child(model)
	root.add_child(unit)
	unit.bind_animation_player(body_ap)
	var impact := Node3D.new()
	impact.name = "CombatImpactFx"
	unit.add_child(impact)
	var fx := Wc3ModelScene.new()
	var fx_ap := player(["Birth", "Stand", "Death"])
	fx.add_child(fx_ap)
	impact.add_child(fx)
	fx_ap.play("Stand")
	check(unit._model_scene() == null, "原始模型不误认兄弟命中特效为自身门面")
	unit.set_combat_attack(true)
	check(body_ap.current_animation == "Attack", "挂特效后仍播放身体攻击")
	check(fx_ap.current_animation == "Stand", "单位动作不改变特效播放")
	unit._ap = null
	check(unit._animation_player() == body_ap, "未注入播放器时只查身体模型")
	unit.free()
	var baked_unit := Unit.new()
	var baked := Wc3ModelScene.new()
	baked.name = Unit.MODEL_NODE_NAME
	var baked_ap := player(["Stand", "Attack"])
	baked.add_child(baked_ap)
	baked_unit.add_child(baked)
	root.add_child(baked_unit)
	check(baked_unit._model_scene() == baked, "烘焙单位仍找到自身门面")
	baked_unit.set_combat_attack(true)
	check(baked_ap.current_animation == "Attack", "烘焙单位攻击保持可用")
	baked_unit.free()
	print("selftest_unit_fx_animation: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
