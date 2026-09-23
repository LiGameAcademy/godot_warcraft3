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
	if snap == null:
		check(false, "demo fixture mounted: " + reg.last_error)
		get_tree().quit(1)
		return
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

	var dir_a := "res://tmp/content-test-a"
	var dir_b := "res://tmp/content-test-b"
	for dir in [dir_a, dir_b]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var file := FileAccess.open(dir.path_join("data.json"), FileAccess.WRITE)
		file.store_string("one")
		file.close()
	reg.register_package("same", ProjectSettings.globalize_path(dir_a))
	var first := reg.commit_snapshot("first")
	var saved_id := first.snapshot_id
	first.snapshot_id = "illegal"
	first.content_hash = "illegal"
	var ids := first.package_ids
	ids.append("illegal")
	check(first.snapshot_id == saved_id and first.content_hash != "illegal" and not first.package_ids.has("illegal"), "frozen metadata and defensive arrays")
	reg.register_package("same", ProjectSettings.globalize_path(dir_b))
	var relocated := reg.commit_snapshot("relocated")
	check(first.content_hash == relocated.content_hash, "relocation keeps content hash")
	var changed := FileAccess.open(dir_b.path_join("data.json"), FileAccess.WRITE)
	changed.store_string("two")
	changed.close()
	var updated := reg.commit_snapshot("updated")
	check(updated.content_hash != first.content_hash, "in place file edit changes hash")
	reg.register_package("missing", ProjectSettings.globalize_path("res://tmp/absent-package"))
	check(reg.commit_snapshot() == null and reg.current_snapshot() == updated, "invalid package leaves active snapshot intact")
	reg.clear_packages()
	reg.commit_base_snapshot()
	var provider := get_node("/root/AssetProvider")
	provider.seal_runtime_content()
	reg.register_package("same", ProjectSettings.globalize_path(dir_a))
	check(reg.commit_snapshot() == null and not reg.last_error.is_empty(), "runtime content changes require restart")
	provider.register_overlay("bypass", ProjectSettings.globalize_path(dir_a))
	check(provider.get_overlay_ids().is_empty(), "direct overlay mutation cannot bypass runtime seal")

	print("selftest_content_snapshot: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
