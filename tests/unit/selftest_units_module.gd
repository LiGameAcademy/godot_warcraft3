extends Node

## UnitsModule 契约：CN 分配、英雄装配、teleport、shutdown 清依赖。
## 不拉地图 / GameDirector；训练出生由生产回归覆盖。

var failures := 0
var checks := 0
var inventory_signals := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("UNITS MODULE: " + label)


func _on_inventory_changed() -> void:
	inventory_signals += 1


func _ready() -> void:
	var module := UnitsModule.new()
	add_child(module)
	var host := Node.new()
	host.name = "UnitHost"
	add_child(host)

	var cn0 := module.alloc_creation_number()
	var cn1 := module.alloc_creation_number()
	check(cn0 == 900000 and cn1 == 900001, "creationNumber 自增")

	module.configure({
		"registry_host": self,
		"unit_host": func() -> Node: return host,
		"on_inventory_changed": Callable(self, "_on_inventory_changed"),
		"ensure_hero_passives": Callable(),
		"next_runtime_cn": 910000,
	})
	check(module.alloc_creation_number() == 910000, "configure 可覆盖 CN 起点")

	var hero := Node3D.new()
	hero.name = "HeroStub"
	hero.set_meta("unit_data", {"typeId": "Hamg", "owner": 0, "position": {"x": 0.0, "y": 0.0, "z": 0.0}})
	host.add_child(hero)
	module.ensure_hero(hero)
	var inv := Inventory.of(hero)
	check(inv != null, "ensure_hero 挂 Inventory")
	if inv != null:
		var potion := ItemInstance.create("phea")
		if potion != null:
			inv.insert(potion)
	check(inventory_signals >= 1, "Inventory.changed 接到注入回调")

	module.teleport_wc3(hero, Vector2(64.0, 96.0))
	var data: Dictionary = hero.get_meta("unit_data", {})
	var pos: Dictionary = data.get("position", {})
	check(is_equal_approx(float(pos.get("x", -1.0)), 64.0) and is_equal_approx(float(pos.get("y", -1.0)), 96.0),
		"teleport 同步 unit_data 坐标")

	var bentry := module.build_building_entry("hhou", Vector2(10.0, 20.0), 0, 42)
	check(str(bentry.get("typeId", "")) == "hhou", "build_building_entry typeId")
	check(bool(bentry.get("isBuilding", false)), "build_building_entry isBuilding")
	check(int(bentry.get("creationNumber", -1)) == 42, "build_building_entry 保留 CN")

	var uentry := module.build_unit_entry("hfoo", Vector2(1.0, 2.0), 0)
	check(str(uentry.get("typeId", "")) == "hfoo", "build_unit_entry typeId")
	check(int(uentry.get("owner", -1)) == 0, "build_unit_entry owner")

	var hall := Node3D.new()
	hall.name = "TownHall"
	hall.set_meta("unit_data", {"typeId": "htow", "owner": 0})
	host.add_child(hall)
	var found := module.find_owned_unit_by_types(0, PackedStringArray(["htow", "hkee"]))
	check(found == hall, "find_owned_unit_by_types 找到主城")

	var sentry_entry := module.build_unit_entry("hfoo", Vector2(3.0, 4.0), 0, {"spawn_anim": "Birth"})
	# 无 map_root 时 spawn_summon 返回 null（契约：不崩）
	var summoned := module.spawn_summon(sentry_entry, 1.0, Callable(), hero)
	check(summoned == null, "无地图时 spawn_summon 返回 null")

	module.shutdown()
	check(not module._on_inventory_changed.is_valid(), "shutdown 清空注入 Callable")
	module.free()

	print("selftest_units_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
