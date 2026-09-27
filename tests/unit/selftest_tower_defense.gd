extends Node

## 人族瞭望塔竖切：升守卫塔 + 有武器建筑 HOLD 站桩开火。
## 同步：python tools/workspace/sync_packages.py --app game --test unit/selftest_tower_defense.tscn

var failures: int = 0
var checks: int = 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("TOWER: " + label)


func unit(type_id: String, owner_id: int, x: float) -> Node3D:
	var node := Node3D.new()
	node.set_meta("unit_data", {"typeId": type_id, "owner": owner_id})
	node.position = Wc3Coords.wc3_xy_to_godot(x, 0.0, 0.0)
	add_child(node)
	UnitLife.ensure(node)
	return node


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_upgrade_chain()
	_test_weapons_and_hold()
	print(
		"selftest_tower_defense: %s (%d checks)"
		% [("PASS" if failures == 0 else "FAIL"), checks]
	)
	get_tree().quit(0 if failures == 0 else 1)


func _test_upgrade_chain() -> void:
	check(
		TechPresence.building_upgrade_target("hwtw") == "hgtw",
		"hwtw 竖切升本目标应为 hgtw"
	)
	var locked := CommandCard.for_unit(
		"hwtw", {"include_locomotion": false, "owned_buildings": {"hwtw": 1}}
	)
	var entry := _card_entry(locked, "upgrade:hgtw")
	check(not entry.is_empty(), "瞭望塔命令卡应有升守卫塔按钮")
	if not entry.is_empty():
		check(not bool(entry.get("enabled", true)), "无伐木场时升守卫塔应置灰")
	var unlocked := CommandCard.for_unit(
		"hwtw",
		{"include_locomotion": false, "owned_buildings": {"hwtw": 1, "hlum": 1}}
	)
	entry = _card_entry(unlocked, "upgrade:hgtw")
	check(
		not entry.is_empty() and bool(entry.get("enabled", false)),
		"有伐木场时升守卫塔应可点"
	)


func _test_weapons_and_hold() -> void:
	var scout := unit("hwtw", 0, 0.0)
	var guard := unit("hgtw", 0, 400.0)
	check(not CombatQuery.has_weapon(scout), "瞭望塔无武器，不应开火")
	check(CombatQuery.has_weapon(guard), "守卫塔应有武器数据")
	var modules := Node.new()
	add_child(modules)
	var units := UnitsModule.new()
	modules.add_child(units)
	units.configure({
		"ensure_attack_controller": Callable(self, "_make_attack_controller"),
		"unit_host": Callable(self, "_host"),
	})
	check(units.ensure_combat_ai(scout) == null, "无武器瞭望塔不挂 AI")
	check(scout.get_node_or_null("AttackController") == null, "无武器瞭望塔不挂 AttackController")
	check(units.ensure_combat_ai(guard) == null, "有武器建筑用 HOLD，不挂 UnitAI")
	var ac := guard.get_node_or_null("AttackController") as AttackController
	check(ac != null, "守卫塔应挂 AttackController")
	if ac != null:
		check(ac.get_mode() == AttackController.Mode.HOLD, "守卫塔默认 HOLD 站桩")
		## HOLD 空闲时 state=IDLE，is_active() 为 false 是正常的；有目标后才非 IDLE。
	var foe := unit("hfoo", 1, 400.0 + CombatQuery.attack_range_wc3(guard) * 0.5)
	var foe_hp := UnitLife.get_life(foe)
	if ac != null:
		for _i in range(240):
			ac._process(1.0 / 60.0)
	check(UnitLife.get_life(foe) < foe_hp, "射程内敌方单位应被守卫塔打到")
	var far := unit("hfoo", 1, 400.0 + CombatQuery.attack_range_wc3(guard) + 200.0)
	var far_hp := UnitLife.get_life(far)
	if ac != null:
		for _i in range(120):
			ac._process(1.0 / 60.0)
	check(UnitLife.get_life(far) == far_hp, "超射程单位不应被追击伤害")


func _host() -> Node:
	return self


func _make_attack_controller(u: Node3D) -> AttackController:
	var existing := u.get_node_or_null("AttackController") as AttackController
	if existing != null:
		return existing
	var ac := AttackController.new()
	ac.name = "AttackController"
	var pipeline := DamagePipeline.new()
	ac.configure(Callable(), Callable(self, "_host"), pipeline)
	u.add_child(ac)
	return ac


func _card_entry(card: Array, action_id: String) -> Dictionary:
	for e in card:
		if e is Dictionary and str((e as Dictionary).get("id", "")) == action_id:
			return e as Dictionary
	return {}
