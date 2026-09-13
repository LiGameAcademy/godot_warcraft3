extends Node

## 真实 game_main 接线：输入拾取、取消、HUD、死亡→祭坛复活。
var failed := 0
var checks := 0
var game: Node

func _ready() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("ITEM INTEGRATION: " + label)
	else:
		print("  OK: " + label)

func click(screen: Vector2, button: MouseButton = MOUSE_BUTTON_RIGHT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = screen
	motion.global_position = screen
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var event := InputEventMouseButton.new()
	event.position = screen
	event.global_position = screen
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	var release := event.duplicate() as InputEventMouseButton
	release.pressed = false
	Input.parse_input_event(release)

func wait_until(predicate: Callable, seconds: float) -> bool:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if predicate.call():
			return true
		await get_tree().process_frame
	return false

func find_hero(host: Node) -> Node3D:
	for child in host.get_children():
		if child is Node3D and CombatQuery.is_alive_in_world(child) and str(child.get_meta("unit_data", {}).get("typeId", "")) == "Hamg":
			return child
	return null

func run() -> void:
	get_window().size = Vector2i(1280, 800)
	game = load("res://game/scenes/game_main.tscn").instantiate()
	add_child(game)
	var director := game.get_node("GameDirector") as GameDirector
	var ready := await wait_until(director.is_session_ready, 180.0)
	check(ready, "game session ready")
	if not ready:
		get_tree().quit(1)
		return
	# session_ready 之后 Loading 仍会挡鼠标直到淡出完成。
	check(await wait_until(func() -> bool: return game.get_node_or_null("GameLoadingScreen") == null, 5.0), "loading overlay finished before input")
	var host := director.map_root.get_unit_layer()
	await wait_until(func() -> bool: return find_hero(host) != null, 30.0)
	var hero := find_hero(host)
	check(hero != null, "development hero available")
	if hero == null:
		get_tree().quit(1)
		return
	director.unit_selector.call("select_node", hero)
	director.rts_camera.edge_pan_enabled = false
	director.rts_camera.focus_on_position(hero.global_position, 0.0)
	await get_tree().create_timer(0.1).timeout
	var hud := director.game_hud
	check(hud.inventory_panel.visible, "selected hero shows inventory")
	var service := director.get_node("ItemService") as ItemService
	var xy := Wc3Coords.godot_to_wc3_xy(hero.global_position)
	var ground := service.spawn(ItemInstance.create("rde1"), xy)
	var camera := director.rts_camera.get_camera()
	await get_tree().process_frame
	await click(camera.unproject_position(ground.global_position))
	var picked := await wait_until(func() -> bool: return Inventory.of(hero).item_at(0) != null, 5.0)
	check(picked, "right click flows through SmartTarget and pickup controller")
	check(is_equal_approx(BuffQuery.bonus_armor(hero), 2.0), "picked ring contributes combat armor")
	if not picked:
		print("hero xy=", xy, " screen=", camera.unproject_position(ground.global_position))
		print("after xy=", Wc3Coords.godot_to_wc3_xy(hero.global_position), " status=", hud.get_node("%DebugStatusLabel").text)
	var inv := Inventory.of(hero)
	inv.insert(ItemInstance.create("phea"), 1)
	director.gm_item_test_vitals()
	var life_before := UnitLife.get_life(hero)
	await get_tree().process_frame
	await click(hud.inventory_panel.buttons[1].get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	await get_tree().process_frame
	check(UnitLife.get_life(hero) > life_before and inv.item_at(1) == null, "HUD use request heals and consumes")
	await click(hud.inventory_panel.buttons[0].get_global_rect().get_center())
	await get_tree().process_frame
	check(inv.item_at(0) == null and BuffQuery.bonus_armor(hero) == 0.0, "HUD drop removes equipment bonus")
	# 远距离拾取被 S 取消后不得继续捡。
	var far := service.spawn(ItemInstance.create("pman"), xy + Vector2(700.0, 0.0))
	await get_tree().process_frame
	await click(camera.unproject_position(far.global_position))
	await get_tree().process_frame
	var order_queue := hero.get_meta("order_queue") as OrderQueue
	check(order_queue != null and order_queue.current != null and order_queue.current.kind == UnitOrder.Kind.PICKUP_ITEM, "far item starts pickup order")
	var stop := InputEventKey.new()
	stop.keycode = KEY_S
	stop.physical_keycode = KEY_S
	stop.pressed = true
	Input.parse_input_event(stop)
	stop = stop.duplicate() as InputEventKey
	stop.pressed = false
	Input.parse_input_event(stop)
	await get_tree().create_timer(0.3).timeout
	check(is_instance_valid(far) and not far.claimed, "Stop cancels pending pickup")
	# 准备一个实际祭坛，走同一 HUD 复活动作与训练完成回调。
	inv.insert(ItemInstance.create("rde1"), 4)
	var snapshot := inv.snapshot()
	var altar_entry := {
		"typeId": "halt", "owner": 0, "flags": 2, "variation": 0,
		"position": {"x": xy.x + 400.0, "y": xy.y - 400.0, "z": 0.0},
		"angle": 0.0, "scale": {"x": 1.0, "y": 1.0, "z": 1.0}, "creationNumber": 987650,
	}
	var altar := director.map_root.add_unit_instance(altar_entry, director.map_root.get_heightfield_dict())
	UnitLife.ensure(altar)
	director.gm_item_test_death()
	check(HeroDeathRegistry.dead_count(0) == 1, "actual death registers hero")
	director.unit_selector.call("select_node", altar)
	director.get_session().local_stock().add_gold(1000)
	hud.command_action.emit(CommandCard.ACTION_REVIVE_PREFIX + "Hamg")
	var queue := altar.get_node_or_null("TrainQueue") as TrainQueue
	check(queue != null and queue.is_training(), "altar queues revive from HUD")
	if queue != null and queue.is_training():
		Engine.time_scale = 60.0
		var returned := await wait_until(func() -> bool: return find_hero(host) != null, 20.0)
		Engine.time_scale = 1.0
		check(returned, "revive completion spawns hero")
		if returned:
			var revived := find_hero(host)
			check(Inventory.of(revived).snapshot() == snapshot, "revive restores exact inventory snapshot")
			director.unit_selector.call("select_node", revived)
			director.rts_camera.focus_on_position(revived.global_position, 0.0)
			Inventory.of(revived).insert(ItemInstance.create("phea"), 0)
			Inventory.of(revived).insert(ItemInstance.create("pman"), 1)
			director.gm_item_test_kit()
			director.gm_item_test_creep()
			check(game.get_node("GroundItems").get_child_count() >= 7, "GM kit spawns ground items")
			# 调试层关闭后检查正式玩法的背包布局。
			director.map_root.set_view_grid_level(0)
			director.map_root.set_show_pathing_ground(false)
			await get_tree().process_frame
			check(hud.inventory_panel.get_global_rect().end.y < hud.get_node("Root/MarginContainer3/CommandPanel").get_global_rect().position.y, "inventory does not overlap command panel")
	# 可选图像验证，需图形渲染器。
	if DisplayServer.get_name() != "headless":
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.cache/item-system-tests")
		get_viewport().get_texture().get_image().save_png("res://.cache/item-system-tests/inventory_preview.png")
	print("selftest_items_game: %s (%d checks)" % ["PASS" if failed == 0 else "FAIL", checks])
	game.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(0 if failed == 0 else 1)
