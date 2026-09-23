extends Node

var checks := 0
var failures := 0
var notifications := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("NAVIGATION MODULE: " + label)

func _ready() -> void:
	var map_a := TestMap.new()
	var map_b := TestMap.new()
	var module := NavigationModule.new()
	add_child(module)
	module.initialize(map_a, Callable())
	var query := module.path_query
	var reservations := module.cell_reservation
	check(query.reservation == reservations, "query shares match reservations")
	check(module.pathing == map_a.test_pathing, "map binding")
	var body := Node3D.new()
	add_child(body)
	var nav := module.ensure_navigator(body)
	check(nav == module.ensure_navigator(body), "ensure reuses unit navigator")
	check(module.path_query == query, "ensure preserves query identity")
	module.locomotion_changed.connect(func(_moving: bool) -> void: notifications += 1)
	nav.locomotion_changed.emit(true)
	check(notifications == 1, "repeated ensure does not duplicate signal")
	reservations.set_owner_cells(body.get_instance_id(), [Vector2i(2, 2)])
	module.initialize(map_b, Callable())
	check(not reservations.is_blocked_for(2, 2, 999), "rebind releases old reservations")
	check(nav._query == null and nav._reservation == null, "old navigators detach before rebind")
	check(module.path_query != query and module.cell_reservation != reservations, "new match owns fresh services")
	check(module.pathing == map_b.test_pathing, "replacement map binding")
	module.ensure_navigator(body)
	nav.locomotion_changed.emit(true)
	check(notifications == 2, "rebind reconnects exactly once")
	var fresh_reservations := module.cell_reservation
	fresh_reservations.set_owner_cells(body.get_instance_id(), [Vector2i(3, 3)])
	body.free()
	check(module._navigators.is_empty(), "unit removal releases module tracking")
	check(not fresh_reservations.is_blocked_for(3, 3, 999), "unit removal releases reservation")
	module.shutdown()
	module.shutdown()
	check(module.path_query == null and module.crowd_query == null, "shutdown is idempotent")
	module.initialize(map_a, Callable())
	check(module.path_query != null, "module can initialize after shutdown")
	module.shutdown()
	map_a.free()
	map_b.free()
	print("selftest_navigation_module: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)

class TestMap extends MapLoader:
	var test_pathing := Wc3PathingMap.new()
	var layer := MapUnitLayer.new()
	func _init() -> void:
		add_child(layer)
	func get_pathing_map() -> Wc3PathingMap:
		return test_pathing
	func get_heightfield_dict() -> Dictionary:
		return {}
	func get_unit_layer() -> MapUnitLayer:
		return layer
	func get_id_catalog() -> Wc3IdCatalog:
		return null
