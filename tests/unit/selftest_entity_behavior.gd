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

	var behaviors := BehaviorRegistry.new()
	check(behaviors.register_factory("demo_pulse", func(_ctx): return {"ok": true}), "register")
	check(behaviors.has_behavior("demo_pulse"), "has")
	var inst: Variant = behaviors.create("demo_pulse", {})
	check(inst is Dictionary and bool(inst.get("ok", false)), "create")
	behaviors.freeze()
	check(behaviors.register_factory("other", func(_c): return null) == false, "frozen reject")

	print("selftest_entity_behavior: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
