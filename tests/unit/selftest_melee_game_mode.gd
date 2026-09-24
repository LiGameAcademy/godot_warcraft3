extends SceneTree

## MeleeGameMode：开局库存 + 首英雄免费（一次性）。

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_starting_stock()
	_test_first_hero_free()
	if failed == 0:
		print("selftest_melee_game_mode: PASS")
		quit(0)
	else:
		push_error("selftest_melee_game_mode: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _test_starting_stock() -> void:
	var mode := MeleeGameMode.new()
	var stock := mode.create_starting_stock(5, 12)
	if stock.gold != PlayerStock.MELEE_GOLD or stock.lumber != PlayerStock.MELEE_LUMBER:
		_fail("开局金木应为 %d/%d" % [PlayerStock.MELEE_GOLD, PlayerStock.MELEE_LUMBER])
		return
	if stock.food_used != 5 or stock.food_cap != 12:
		_fail("开局人口应为 5/12，实际 %d/%d" % [stock.food_used, stock.food_cap])
		return
	print("  starting stock OK")


func _test_first_hero_free() -> void:
	var mode := MeleeGameMode.new()
	var a := mode.adjust_train_cost(0, "Hamg", 425, 0, null)
	if int(a.get("gold", -1)) != 0 or not bool(a.get("waived", false)):
		_fail("首英雄应免费 waived，实际 %s" % str(a))
		return
	mode.notify_train_issued(0, "Hamg", true)
	var b := mode.adjust_train_cost(0, "Hamg", 425, 0, null)
	if int(b.get("gold", 0)) != 425 or bool(b.get("waived", true)):
		_fail("第二次训英雄应收费，实际 %s" % str(b))
		return
	var foot := mode.adjust_train_cost(0, "hfoo", 135, 0, null)
	if int(foot.get("gold", 0)) != 135:
		_fail("步兵造价不应被改写")
		return
	print("  first hero free OK")
