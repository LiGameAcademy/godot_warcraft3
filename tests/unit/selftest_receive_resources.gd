extends SceneTree

## 未完工建筑不能交货（伐木场半成品不收木）。
## godot --headless --path . -s res://tests/unit/selftest_receive_resources.gd

var failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_complete_mill_accepts_lumber()
	_test_building_mill_rejects_lumber()
	_test_deposit_building_mill_no_credit()
	_test_nearest_skips_building_mill()
	_test_complete_hall_still_accepts()
	if failed == 0:
		print("selftest_receive_resources: PASS")
		quit(0)
	else:
		push_error("selftest_receive_resources: FAIL (%d)" % failed)
		quit(1)


func _fail(msg: String) -> void:
	failed += 1
	push_error(msg)


func _make_building(type_id: String, under: bool, pos: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.set_meta("unit_data", {"typeId": type_id, "owner": 0})
	n.set_meta("under_construction", under)
	return n


func _test_complete_mill_accepts_lumber() -> void:
	var mill := _make_building("hlum", false)
	if not ReceiveResources.can_receive(mill, ReceiveResources.Kind.LUMBER):
		_fail("完工 hlum 应能收木")
	if ReceiveResources.can_receive(mill, ReceiveResources.Kind.GOLD):
		_fail("hlum 不应收金")
	mill.free()


func _test_building_mill_rejects_lumber() -> void:
	var mill := _make_building("hlum", true)
	if ReceiveResources.can_receive(mill, ReceiveResources.Kind.LUMBER):
		_fail("未完工 hlum 不应收木")
	mill.free()


func _test_deposit_building_mill_no_credit() -> void:
	var mill := _make_building("hlum", true)
	var stock := PlayerStock.new()
	stock.lumber = 0
	var out := ReceiveResources.deposit(mill, stock, 0, 10)
	if int(out.get("lumber", -1)) != 0:
		_fail("未完工 hlum deposit lumber 应为 0")
	if stock.lumber != 0:
		_fail("未完工 hlum 不应入账木材")
	mill.free()


func _test_nearest_skips_building_mill() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var mill := _make_building("hlum", true, Vector3(0, 0, 0))
	var hall := _make_building("htow", false, Vector3(20, 0, 0))
	host.add_child(mill)
	host.add_child(hall)
	var found := ReceiveResources.find_nearest_dropoff(
		host, Vector2.ZERO, 0, ReceiveResources.Kind.LUMBER
	)
	if found != hall:
		_fail("最近交货应跳过未完工 hlum，落到 htow")
	host.queue_free()


func _test_complete_hall_still_accepts() -> void:
	var hall := _make_building("htow", false)
	if not ReceiveResources.can_receive(hall, ReceiveResources.Kind.LUMBER):
		_fail("完工 htow 应能收木")
	if not ReceiveResources.can_receive(hall, ReceiveResources.Kind.GOLD):
		_fail("完工 htow 应能收金")
	hall.set_meta("under_construction", true)
	if ReceiveResources.can_receive(hall, ReceiveResources.Kind.GOLD):
		_fail("未完工 htow 不应收金")
	hall.free()
