extends Node

## SelectionHud：己方英雄可操作背包；敌方英雄只读展示；非英雄不显示。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("INV HUD: " + label)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	var fake_hud := _FakeHud.new()
	var mod := SelectionHudModule.new()
	add_child(mod)
	add_child(fake_hud)
	mod.configure({
		"game_hud": fake_hud,
		"is_controllable": func(node: Node) -> bool:
			return CombatQuery.is_controllable(node, 0),
	})

	var ally := Node3D.new()
	ally.set_meta("unit_data", {"typeId": "Hamg", "owner": 0})
	add_child(ally)
	var ally_inv := Inventory.ensure_on(ally)
	ally_inv.insert(ItemInstance.create("phea"))

	var enemy := Node3D.new()
	enemy.set_meta("unit_data", {"typeId": "Hamg", "owner": 1})
	add_child(enemy)
	var enemy_inv := Inventory.ensure_on(enemy)
	enemy_inv.insert(ItemInstance.create("rde1"))

	var footman := Node3D.new()
	footman.set_meta("unit_data", {"typeId": "hfoo", "owner": 1})
	add_child(footman)

	mod.bind_inventory_for(ally)
	check(fake_hud.last_inv == ally_inv, "己方英雄绑定背包")
	check(fake_hud.last_read_only == false, "己方英雄可操作")

	mod.bind_inventory_for(enemy)
	check(fake_hud.last_inv == enemy_inv, "敌方英雄绑定背包")
	check(fake_hud.last_read_only == true, "敌方英雄只读")

	mod.bind_inventory_for(footman)
	check(fake_hud.last_inv == null, "敌方步兵不显示背包")

	mod.bind_inventory_for(null)
	check(fake_hud.last_inv == null, "清空选中隐藏背包")

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.bind_inventory(enemy_inv, true)
	check(panel.visible and panel.read_only, "面板只读可见")
	var used := false
	panel.use_requested.connect(func(_s: int) -> void: used = true)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	panel._on_slot_input(e, 0)
	check(not used, "只读不发 use_requested")

	print("selftest_enemy_inventory_hud: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)


class _FakeHud extends Node:
	var last_inv: Inventory = null
	var last_read_only: bool = false

	func bind_inventory(inv: Inventory, is_read_only: bool = false) -> void:
		last_inv = inv
		last_read_only = is_read_only
