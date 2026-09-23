extends Node

## D5：EntityId / EntityRegistry / BehaviorRegistry 契约。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ENTITY BEHAVIOR: " + label)


func _ready() -> void:
	var id := EntityId.from_creation_number(42)
	check(id.is_valid() and id.value == 42, "EntityId from cn")
	check(EntityId.invalid().is_valid() == false, "invalid")

	var reg := EntityRegistry.new()
	var node := Node3D.new()
	add_child(node)
	reg.register_unit(id, node)
	check(reg.count() == 1, "registry count")
	check(reg.get_node(id) == node, "get_node")
	check(reg.id_of(node).value == 42, "id_of")
	reg.unregister(id)
	check(reg.count() == 0, "unregister")

	var replacement := Node3D.new()
	add_child(replacement)
	reg.register_unit(id, node)
	reg.register_unit(id, replacement)
	check(not reg.id_of(node).is_valid(), "replacement removes old reverse index")
	replacement.free()
	check(reg.get_node(id) == null and reg.count() == 0, "freed node safely removed")
	reg.unregister(id)
	var detached := Node.new()
	reg.register_unit(id, detached)
	detached.free()
	check(reg.get_node(id) == null and reg.count() == 0, "free outside tree is safe")
	var host := Node.new()
	add_child(host)
	reg.bind_host(host)
	var imported := Node3D.new()
	imported.set_meta("unit_data", {"creationNumber": 0})
	host.add_child(imported)
	var imported_id := reg.id_of(imported)
	check(imported_id.is_valid(), "imported zero creation number assigned valid id")
	reg.bind_host(host)
	check(reg.get_node(imported_id) == imported, "host rebind preserves identity")
	host.remove_child(imported)
	check(reg.count() == 0, "removed unit leaves registry")
	imported.free()
	reg.clear()
	host.queue_free()

	var behaviors := BehaviorRegistry.new()
	check(behaviors.register_factory("demo_pulse", func(_ctx): return {"ok": true}), "register")
	check(behaviors.has_behavior("demo_pulse"), "has")
	var inst: Variant = behaviors.create("demo_pulse", {})
	check(inst is Dictionary and bool(inst.get("ok", false)), "create")
	behaviors.freeze()
	check(behaviors.register_factory("other", func(_c): return null) == false, "frozen reject")

	print("selftest_entity_behavior: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
