extends Node

var failures := 0
var checks := 0

class CountingBars extends HealthBarManager:
	var resolves := 0
	var bounds_queries := 0
	func _resolve_attach(node: Node3D) -> Dictionary:
		resolves += 1
		return {"attach": node.get_node_or_null("Model/Anchor"), "skeleton": null, "bone_idx": -1}
	func _estimate_height(_node: Node3D) -> float:
		bounds_queries += 1
		return 2.0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	var bars := CountingBars.new()
	add_child(bars)
	bars.set_process(false)
	var unit := Node3D.new()
	add_child(unit)
	var entry: Dictionary = {}
	var position := bars._bar_world_pos(entry, unit)
	for i in range(60):
		check(bars._bar_world_pos(entry, unit) == position, "fallback position stable")
	check(bars.resolves == 1 and bars.bounds_queries == 1, "negative attachment lookup and mesh bounds cached")
	entry.retry_at = 0
	bars._bar_world_pos(entry, unit)
	check(bars.resolves == 2, "missing anchor retries after expiry")
	var model := Node3D.new()
	model.name = "Model"
	unit.add_child(model)
	var anchor := Node3D.new()
	anchor.name = "Anchor"
	model.add_child(anchor)
	anchor.position.y = 4.0
	var anchored := bars._bar_world_pos(entry, unit)
	check(bars.resolves == 3 and anchored.y > 4.0, "late model binding invalidates fallback immediately")
	anchor.position.y = 5.0
	check(bars._bar_world_pos(entry, unit).y > 5.0 and bars.resolves == 3, "cached anchor still follows live animation")
	model.free()
	model = Node3D.new()
	model.name = "Model"
	unit.add_child(model)
	bars._bar_world_pos(entry, unit)
	check(bars.resolves == 4 and bars.bounds_queries == 3, "model replacement drops freed anchor and rebuilds fallback")

	var chip := preload("res://client/hud/unit_combat_stat_chip.tscn").instantiate() as UnitCombatStatChip
	add_child(chip)
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var path := ProjectSettings.globalize_path("user://selftest_stat_icon.png")
	check(image.save_png(path) == OK, "test icon written")
	chip.set_stat({"value": "10", "icon": path})
	var texture := chip._icon.texture
	check(texture != null, "icon loaded")
	chip.set_stat({"value": "20", "icon": path})
	check(chip._icon.texture == texture and chip._value.text == "20", "stat change reuses texture and updates text")
	chip.clear()
	chip.set_stat({"value": "30", "icon": path})
	check(chip._icon.texture != null, "clear and reselect restores icon")
	chip.set_stat({"value": "40", "icon": ""})
	check(chip._icon.texture == null and not chip._icon.visible, "empty icon clears old texture")
	DirAccess.remove_absolute(path)

	var host := Node3D.new()
	add_child(host)
	var crowd := UnitCrowdQuery.new()
	crowd.configure(host, null)
	var other := Node3D.new()
	other.set_meta("unit_data", {"typeId": "hfoo"})
	host.add_child(other)
	other.position = Wc3Coords.wc3_xy_to_godot(-10000, 10000, 0)
	check(crowd.neighbors_of(null, Vector2.ZERO).is_empty(), "far units rejected")
	other.position = Wc3Coords.wc3_xy_to_godot(-32, -32, 0)
	check(crowd.neighbors_of(null, Vector2.ZERO).size() == 1, "same-frame movement and negative coordinates are live")
	check(crowd.neighbors_of(other, Vector2.ZERO).is_empty(), "self excluded")
	other.set_meta(WorldMembership.META_IN_WORLD, false)
	check(crowd.neighbors_of(null, Vector2.ZERO).is_empty(), "same-frame world exit excluded")
	other.set_meta(WorldMembership.META_IN_WORLD, true)
	other.set_meta("unit_data", {"typeId": "htow"})
	check(crowd.neighbors_of(null, Vector2.ZERO).is_empty(), "buildings excluded by default")
	check(crowd.neighbors_of(null, Vector2.ZERO, 192, true).size() == 1, "buildings included when requested")
	other.set_meta("unit_data", {"typeId": "sloc"})
	check(crowd.neighbors_of(null, Vector2.ZERO, 192, true).is_empty(), "start locations still excluded")
	print("selftest_match_hotpath_cache: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
