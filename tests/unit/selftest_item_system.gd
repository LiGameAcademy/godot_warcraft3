extends Node

## 场景入口确保 Autoload 正常初始化；验证真实 SLK + 事务与死亡/掉落。
var failed := 0
var checks := 0

class TestNavigator extends UnitNavigator:
	var moving := false
	var path_requests := 0
	func _ready() -> void:
		set_process(false)
	func go_to_wc3(_goal: Vector2) -> bool:
		path_requests += 1
		moving = true
		return true
	func stop() -> void:
		moving = false
	func is_moving() -> bool:
		return moving

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failed += 1
		push_error("ITEM TEST: " + message)

func hero() -> Node3D:
	var unit := Node3D.new()
	unit.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	unit.set_meta("life", 100.0)
	unit.set_meta("max_life", 1000.0)
	unit.set_meta("mana", 10)
	unit.set_meta("max_mana", 500)
	add_child(unit)
	Inventory.ensure_on(unit)
	return unit

func run() -> void:
	var unit := hero()
	var inv := Inventory.of(unit)
	check(inv != null, "英雄应有背包")
	var worker := Node3D.new()
	worker.set_meta("unit_data", {"typeId": "hpea", "owner": 0})
	add_child(worker)
	check(Inventory.ensure_on(worker) == null, "普通工人不能有背包")
	check(ItemInstance.create("missing") == null, "未知 ID 不生成伪道具")
	var potion := ItemInstance.create("phea")
	check(potion != null and potion.charges == 1, "真实药水次数")
	check(inv.insert(potion), "插入")
	check(not inv.insert(potion), "同一实例不能重复插入")
	var other := hero()
	check(not Inventory.of(other).insert(potion), "同一实例不能跨背包重复持有")
	inv.insert(ItemInstance.create("phea"))
	inv.insert(ItemInstance.create("pman"))
	inv.insert(ItemInstance.create("rde1"))
	inv.insert(ItemInstance.create("rde1"))
	inv.insert(ItemInstance.create("pman"))
	var extra := ItemInstance.create("phea")
	check(not inv.insert(extra) and extra.holder_id == 0, "满包插入失败保留物品")
	check(is_equal_approx(BuffQuery.bonus_armor(unit), 4.0), "两个 +2 指环叠加到战斗查询")
	var used := inv.try_use(0)
	check(used.ok and UnitLife.get_life(unit) == 350.0, "药水按真实数据恢复250生命")
	check(inv.item_at(0) == null, "耗尽移除")
	check(not inv.try_use(1).ok and inv.item_at(1).charges == 1, "同组冷却阻止第二瓶且不扣次数")
	check(inv.try_use(2).ok and UnitMana.get_mana(unit) == 160, "魔法药水恢复150且不与生命组共用")
	var cooldown := inv.cooldown_remaining(1)
	inv.swap_slots(1, 0)
	check(inv.cooldown_remaining(0) > cooldown - 0.1, "换槽不清冷却")
	var transferred := inv.remove_at(0)
	check(Inventory.of(other).insert(transferred), "转交")
	check(Inventory.of(other).cooldown_remaining(0) > 19.0, "跨英雄转交保留共享冷却")
	var ring := inv.remove_at(3)
	check(is_equal_approx(BuffQuery.bonus_armor(unit), 2.0), "移除一件只减少自己的加成")
	check(not inv.try_use(4).ok, "装备不可主动消耗")
	var full := hero()
	UnitLife.set_life(full, 1000.0)
	Inventory.of(full).insert(ItemInstance.create("phea"))
	check(not Inventory.of(full).try_use(0).ok and Inventory.of(full).item_at(0).charges == 1, "满血不浪费药水")
	check(Inventory.of(full).cooldown_remaining(0) == 0.0, "失败不启动冷却")
	UnitLife.set_life(full, 900.0)
	check(Inventory.of(full).try_use(0).ok and UnitLife.get_life(full) == 1000.0, "治疗不超过上限")
	var snap := inv.snapshot()
	HeroDeathRegistry.clear_owner(0)
	HeroDeathRegistry.register_death(unit)
	var dead := HeroDeathRegistry.take_for_revive(0, "Hamg")
	check(dead.get("inventory", {}) == snap, "死亡登记含背包")
	inv.clear()
	var revived := hero()
	Inventory.of(revived).restore(dead.inventory)
	check(Inventory.of(revived).snapshot() == snap, "复活保持槽位实例次数与冷却")
	HeroDeathRegistry.restore_dead(dead)
	check(HeroDeathRegistry.dead_count(0) == 1, "取消复活仍保留死亡登记")
	HeroDeathRegistry.clear_owner(0)
	var host := Node3D.new()
	add_child(host)
	var service := ItemService.new()
	add_child(service)
	service.configure(host, null, "")
	var ground := service.spawn(ring, Vector2.ZERO)
	check(ground != null, "丢弃实例生成地面物品")
	check(service.spawn(ring, Vector2.ONE) == null, "地面实例不重复生成")
	var creep := Node3D.new()
	creep.set_meta("unit_data", {"droppedItemSets": [[{"id": "phea", "chance": 100}], [{"id": "rde1", "chance": 100}]]})
	add_child(creep)
	service.on_unit_died(creep)
	var count := host.get_child_count()
	check(count == 3, "每个互斥组各掉一件")
	service.on_unit_died(creep)
	check(host.get_child_count() == count, "重复死亡通知不重复掉落")
	var table := ItemDropTable.new()
	table.tables = [{"tableNumber": 7, "sets": [[{"id": "pman", "chance": 100}]]}]
	check(table.roll({"itemTablePtr": 7}) == ["pman"], "引用全局掉落表")
	check(table.roll({"droppedItemSets": [[{"id": "phea", "chance": 0}]]}).is_empty(), "零概率不掉落")
	table.rng.seed = 42
	var first := table.resolve_id("YiI2")
	table.rng.seed = 42
	check(first == table.resolve_id("YiI2"), "同 seed 可复现")
	var definition := ItemCatalog.data(first)
	check(definition != null and definition.item_class == "Permanent" and definition.level == 2, "随机池遵循类别等级")
	check(table.resolve_id("BAD!").is_empty() and not table.diagnostics.is_empty(), "未知随机代码显式诊断")
	check(not table.resolve_id("YYI/").is_empty(), "任意类别任意等级随机编码")
	var guaranteed := table.roll({"droppedItemSets": [[{"id": "phea", "chance": 100}, {"id": "pman", "chance": 100}]]})
	check(guaranteed.size() == 1, "同一互斥组不能掉两件")
	var drop_hero := hero()
	var death_item := ItemInstance.create("rde1")
	Inventory.of(drop_hero).insert(death_item)
	var item_def := ItemCatalog.data("rde1")
	var previous_drop := item_def.drop
	item_def.drop = true
	service.prepare_hero_death(drop_hero)
	item_def.drop = previous_drop
	check(Inventory.of(drop_hero).item_at(0) == null and death_item.holder_id == 0, "死亡掉落标记生效")
	check(service.spawn(death_item, Vector2.ZERO) == null, "必掉道具已经在地面，没有再次生成")
	await test_pickup(service)
	check_pickup_lifecycle(service)
	check_death_drop_rollback()
	# 皮肤资源可以缺省，但既有三款图标应可解析。
	for id in ItemCatalog.TEST_ITEMS:
		check(not RuntimeAssets.resolve(ItemCatalog.icon(id)).is_empty(), "道具图标路径 " + id)
	print("selftest_item_system: %s (%d checks)" % ["PASS" if failed == 0 else "FAIL", checks])
	get_tree().quit(0 if failed == 0 else 1)

func begin_pickup(unit: Node3D, ground: GroundItem) -> ItemPickupController:
	var nav := TestNavigator.new()
	nav.name = "UnitNavigator"
	unit.add_child(nav)
	var q := OrderQueue.new()
	var order := UnitOrder.new()
	order.kind = UnitOrder.Kind.PICKUP_ITEM
	order.source = UnitOrder.Source.SMART_RMB
	q.set_current(order)
	unit.set_meta("order_queue", q)
	var controller := ItemPickupController.new()
	unit.add_child(controller)
	controller.begin(ground, nav, order)
	return controller

func test_pickup(service: ItemService) -> void:
	var a := hero()
	var b := hero()
	var ground := service.spawn(ItemInstance.create("phea"), Vector2.ZERO)
	begin_pickup(a, ground)
	begin_pickup(b, ground)
	await get_tree().process_frame
	await get_tree().process_frame
	var held := int(Inventory.of(a).item_at(0) != null) + int(Inventory.of(b).item_at(0) != null)
	check(held == 1, "两个英雄同帧抢一件道具只能一人获得")
	check((a.get_node("UnitNavigator") as TestNavigator).path_requests == 0, "范围内拾取不启动寻路脱困")
	var far := service.spawn(ItemInstance.create("pman"), Vector2(1000, 0))
	var c := hero()
	var controller := begin_pickup(c, far)
	(c.get_meta("order_queue") as OrderQueue).set_current(UnitOrder.stop())
	await get_tree().process_frame
	await get_tree().process_frame
	check(not controller.is_processing() and Inventory.of(c).item_at(0) == null and not far.claimed, "Stop 替换后不延迟拾取")
	var full := hero()
	for i in range(Inventory.CAPACITY):
		Inventory.of(full).insert(ItemInstance.create("rde1"))
	var nearby := service.spawn(ItemInstance.create("phea"), Vector2.ZERO)
	begin_pickup(full, nearby)
	await get_tree().process_frame
	await get_tree().process_frame
	check(not nearby.claimed and nearby.item.holder_id == 0, "到达时满包仍保留地面物品")
	check((full.get_meta("order_queue") as OrderQueue).is_idle(), "拾取失败释放订单")

func pickup_controller(unit: Node3D, ground: GroundItem) -> ItemPickupController:
	var nav := UnitNavigator.new()
	unit.add_child(nav)
	var controller := ItemPickupController.new()
	unit.add_child(controller)
	var queue := OrderQueue.new()
	var pickup := UnitOrder.new()
	pickup.kind = UnitOrder.Kind.PICKUP_ITEM
	queue.set_current(pickup)
	unit.set_meta("order_queue", queue)
	controller.begin(ground, nav, pickup)
	return controller

## 直接推进交互逻辑；远近位置显式给定，不冒充寻路集成测试。
func check_pickup_lifecycle(service: ItemService) -> void:
	var first := hero()
	var second := hero()
	var item := ItemInstance.create("phea")
	var ground := service.spawn(item, Vector2.ZERO)
	var a := pickup_controller(first, ground)
	var b := pickup_controller(second, ground)
	a._process(0.1)
	b._process(0.1)
	check(Inventory.of(first).item_at(0) == item, "先到英雄取得原实例")
	check(Inventory.of(second).item_at(0) == null and ground.claimed, "同帧争抢只有一个成功")
	check(not a.is_processing() and not b.is_processing(), "争抢双方订单均结束")
	var far := service.spawn(ItemInstance.create("pman"), Vector2(1024, 0))
	var c := pickup_controller(second, far)
	c._process(0.1)
	check(not far.claimed and Inventory.of(second).item_at(0) == null, "远距离不瞬间拾取")
	var queue := second.get_meta("order_queue") as OrderQueue
	var replacement := UnitOrder.move(Vector2(2048, 0))
	queue.set_current(replacement)
	second.global_position = far.global_position
	c._process(0.1)
	check(not far.claimed and queue.current == replacement and not c.is_processing(), "新命令取消拾取且不被旧订单清除")
	var full := hero()
	for i in range(Inventory.CAPACITY):
		Inventory.of(full).insert(ItemInstance.create("rde1"))
	var waiting := service.spawn(ItemInstance.create("phea"), Vector2.ZERO)
	var d := pickup_controller(full, waiting)
	d._process(0.1)
	check(not waiting.claimed and waiting.item.holder_id == 0, "满包时地面物品保留")
	var blocked := pickup_controller(hero(), far)
	blocked._process(1.1)
	check(not blocked.is_processing() and not far.claimed, "无路径时结束订单并保留物品")
	var dying := hero()
	var e := pickup_controller(dying, waiting)
	UnitLife.set_life(dying, 0.0)
	e._process(0.1)
	check(not waiting.claimed and not e.is_processing(), "死亡英雄不能继续拾取")

func check_death_drop_rollback() -> void:
	var drop_id := ""
	for id in ItemCatalog.all_ids():
		if ItemCatalog.data(id).drop:
			drop_id = id
			break
	check(not drop_id.is_empty(), "真实数据包含死亡掉落物")
	if drop_id.is_empty():
		return
	var unit := hero()
	var item := ItemInstance.create(drop_id)
	var inv := Inventory.of(unit)
	inv.insert(item, 2)
	var service := ItemService.new()
	add_child(service)
	# 未配置地面容器模拟掉落失败：必须保留物品供随后死亡登记保存。
	service.prepare_hero_death(unit)
	check(inv.item_at(2) == item and item.holder_id == unit.get_instance_id(), "死亡掉落失败恢复原槽位与所有者")
	var host := Node3D.new()
	add_child(host)
	service.configure(host, null, "")
	service.prepare_hero_death(unit)
	check(inv.item_at(2) == null and host.get_child_count() == 1, "有效容器下死亡掉落成功")
	service.prepare_hero_death(unit)
	check(host.get_child_count() == 1, "重复准备死亡不复制掉落物")
