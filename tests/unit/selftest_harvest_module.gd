extends Node
var checks := 0
var failures := 0
var deposits := 0
var expired := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	var nav := NavigationModule.new()
	add_child(nav)
	var module := HarvestModule.new()
	add_child(module)
	var session := GameSession.new()
	session.ensure_stock(0)
	session.ensure_stock(1)
	module.configure(null, nav, session, null, Callable(), Callable())
	var worker := Node3D.new()
	worker.set_meta("unit_data", {"typeId": "hpea", "owner": 1})
	add_child(worker)
	var hc := module.ensure_controller(worker)
	check(module.ensure_controller(worker) == hc, "component reused")
	check(module._stock_for_unit(worker) == session.stocks[1], "worker owner selects ledger")
	worker.set_meta("unit_data", {"typeId": "hpea", "owner": 15})
	check(module._stock_for_unit(worker) == null and not session.stocks.has(15), "neutral does not create ledger")
	module.deposited.connect(func(_g: int, _l: int) -> void: deposits += 1)
	hc.deposited.emit(10, 0)
	check(deposits == 1, "deposit signal forwarded once")
	var mine := Node3D.new()
	mine.set_meta("unit_data", {"typeId": "ngol"})
	add_child(mine)
	module.wire_mine(mine)
	module.wire_mine(mine)
	var rt := GoldMineRuntime.ensure(mine)
	check(rt.depleted.get_connections().size() == 1, "mine subscription idempotent")
	var old_generation := module._generation
	module.shutdown()
	hc.deposited.emit(10, 0)
	check(deposits == 1 and rt.depleted.get_connections().is_empty(), "shutdown disconnects external signals")
	check(not hc._get_stock.is_valid(), "shutdown clears controller dependency")
	module.shutdown()
	module.configure(null, nav, session, null, Callable(), func(_mine: Node3D) -> void: expired += 1)
	module._finish_collapse(weakref(mine), old_generation)
	check(expired == 0, "old collapse callback cannot expire mine after rebind")
	module.ensure_controller(worker)
	hc.deposited.emit(10, 0)
	check(deposits == 2, "rebind forwards once")
	worker.free()
	check(module._controllers.is_empty(), "removed worker releases tracking")
	print("selftest_harvest_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
