extends Node

## D3：ContentSnapshot / Registry 契约；DefStore clear；overlay 注册不崩。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CONTENT SNAPSHOT: " + label)


func _ready() -> void:
	var reg := ContentRegistry.new()
	var base := reg.commit_base_snapshot()
	check(base != null and base.frozen, "base 快照冻结")
	check(base.content_hash == "base", "base hash")
	check(reg.current_snapshot() == base, "current 指向 base")

	var sample := ProjectSettings.globalize_path("res://content/samples/demo_mod")
	reg.register_package("demo_mod", sample)
	var snap := reg.commit_snapshot("demo")
	check(snap.frozen, "demo 冻结")
	var has_demo := false
	for pid in snap.package_ids:
		if str(pid) == "demo_mod":
			has_demo = true
			break
	check(has_demo, "含 demo_mod")
	check(snap.content_hash != "base", "hash 变化")

	var store: Node = get_node_or_null("/root/Wc3DefStore")
	if store != null and store.has_method("clear_loaded_tables"):
		store.call("clear_loaded_tables")
		check(true, "DefStore clear_loaded_tables")
	else:
		check(false, "DefStore 可用")

	var again := reg.commit_base_snapshot()
	check(again.package_ids.is_empty(), "卸载后无包")

	print("selftest_content_snapshot: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
