extends Node
const Diagnostics := preload("res://editor/scripts/asset_diagnostics.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		push_error(label)
func _ready() -> void:
	call_deferred("_run")
	get_tree().create_timer(60).timeout.connect(func(): get_tree().quit(1))
func _run() -> void:
	var scene = preload("res://editor/scenes/editor_main.tscn").instantiate()
	get_tree().root.add_child(scene)
	var editor = scene.get_node("Editor")
	while editor._tool_palettes.is_empty():
		await get_tree().process_frame
	var catalog: Wc3IdCatalog = editor.map_root.get_id_catalog()
	var doc = editor.get_document()
	doc.add_unit(doc.make_unit_entry("hpea", 0, 0))
	for i in range(7):
		doc.add_unit(doc.make_unit_entry("QQQQ", i * 32, 0))
	catalog._doodads["Qbad"] = {"id": "Qbad", "kind": "doodad", "file": "MissingFixture/Absent.mdx"}
	doc.add_doodad(doc.make_doodad_entry("Qbad", 0, 128))
	var before := JSON.stringify(doc.file_data())
	var issues: Array = Diagnostics.scan(doc.file_data(), catalog)
	check(issues.size() == 2, "known asset passes; unknown ID and missing model reported")
	check(issues[0].count == 7 and issues[0].instances.size() == 5, "instances grouped with bounded examples")
	check(issues[1].source == "MissingFixture/Absent.mdx", "missing model source preserved")
	var view_menu: PopupMenu
	for child in editor.menu.get_children():
		if child is PopupMenu and child.get_item_index(435) >= 0:
			view_menu = child
	check(not view_menu.is_item_disabled(view_menu.get_item_index(435)), "resource menu action enabled")
	view_menu.index_pressed.emit(view_menu.get_item_index(435))
	var dialog: AcceptDialog
	for child in editor.get_children():
		if child is AcceptDialog and child.title == "地图资源检查":
			dialog = child
	check(dialog != null and dialog.visible, "resource menu opens report")
	var text: TextEdit = dialog.get_child(0)
	check("QQQQ" in text.text and "MissingFixture/Absent.mdx" in text.text and not text.editable, "read-only report identifies objects and paths")
	check(JSON.stringify(doc.file_data()) == before, "diagnostics never changes map")
	if "--capture" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		dialog.get_texture().get_image().save_png("res://tmp/asset-diagnostics.png")
	dialog.confirmed.emit()
	await get_tree().process_frame
	print("selftest_asset_diagnostics: %s (%d failures)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
