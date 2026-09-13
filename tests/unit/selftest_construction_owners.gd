extends Node

var failed := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("CONSTRUCTION OWNERS: " + label)

func _ready() -> void:
	call_deferred("run")

func worker(owner: int) -> Node3D:
	var unit := Node3D.new()
	unit.set_meta("unit_data", {"typeId": "hpea", "owner": owner})
	add_child(unit)
	var nav := UnitNavigator.new()
	nav.name = "UnitNavigator"
	unit.add_child(nav)
	return unit

func run() -> void:
	var session := GameSession.new()
	var human := session.ensure_stock(0)
	var computer := session.ensure_stock(1)
	human.set_all(500, 150, 0, 12)
	computer.set_all(500, 150, 0, 12)
	var pathing := Wc3PathingMap.new()
	pathing.width = 64
	pathing.height = 64
	pathing.cells.resize(4096)
	pathing.cells.fill(Wc3PathingMap.FLAG_NO_WATER)
	var builder := worker(1)
	var controller := BuildController.new()
	builder.add_child(controller)
	controller.configure(session, pathing)
	var order := BuildOrder.create("hhou", Vector2(1024, 1024), builder)
	check(controller.start_build(order), "电脑工人可接受合法建造")
	var gold := BuildingCatalog.get_gold_cost("hhou")
	var lumber := BuildingCatalog.get_lumber_cost("hhou")
	check(computer.gold == 500 - gold and computer.lumber == 150 - lumber, "开工只扣工人所属玩家")
	check(human.gold == 500 and human.lumber == 150, "电脑开工不影响本地库存")
	builder.set_meta("unit_data", {"typeId": "hpea", "owner": 0})
	check(controller.cancel(), "行进中可取消建造")
	check(computer.gold == 500 - gold + int(round(gold * BuildController.CANCEL_REFUND_RATIO)) and human.gold == 500, "工人换主后退款仍归原付款玩家")
	check(not controller.cancel(), "重复取消不重复退款")
	var site := BuildSite.new()
	add_child(site)
	site.configure_session(session)
	var accelerated := BuildOrder.create("hhou", Vector2.ZERO, builder)
	accelerated.gold_spent = 100
	accelerated.lumber_spent = 100
	accelerated.build_time_sec = 100
	site.start(accelerated, 1)
	site.add_builder(worker(1))
	site.add_builder(worker(1))
	site._powerbuild_cost = 0.15
	var before := computer.gold
	site._settle_powerbuild_cost(0.0, 1.0, 2)
	check(computer.gold == before - 15 and human.gold == 500, "加速建造只扣工地所属玩家")
	var poor := worker(1)
	var poor_controller := BuildController.new()
	poor.add_child(poor_controller)
	poor_controller.configure(session, pathing)
	computer.gold = 0
	check(not poor_controller.start_build(BuildOrder.create("hhou", Vector2(1024, 1024), poor)) and human.gold == 500, "电脑不足不能借本地资金开工")
	print("selftest_construction_owners: %s (%d checks)" % ["PASS" if failed == 0 else "FAIL", checks])
	get_tree().quit(0 if failed == 0 else 1)
