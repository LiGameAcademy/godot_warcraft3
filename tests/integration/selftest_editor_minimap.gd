extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	var cat := Wc3IdCatalog.new()
	cat.load_default()
	var tiles := Wc3TerrainTileCatalog.new()
	tiles.load_default()
	var cliffs := Wc3CliffCatalog.new()
	cliffs.load_default()
	var doc = preload("res://editor/scripts/map_document.gd").new()
	check(doc.load_from_map_dir("res://assets/map-parsed/losttemple") == OK, "LT loads")
	var window = preload("res://editor/ui/editor_inspect_window.tscn").instantiate()
	add_child(window)
	window.setup(cat, MapModelCache.new())
	window.show()
	window.refresh_minimap(doc.heightfield, "", tiles, cliffs)
	window.set_minimap_units(doc.unit_entries())
	window.set_minimap_doodads(doc.doodad_entries())
	var counts := {}
	for icon in window._live_icons:
		counts[icon.type] = counts.get(icon.type, 0) + 1
	check(counts.get(0, 0) == 12, "all 12 LT gold mines marked")
	check(counts.get(1, 0) == 5, "all 5 LT neutral buildings marked")
	check(counts.get(3, 0) > 10, "hostile creeps marked")
	window.set_viewport_uv_quad(PackedVector2Array([Vector2(-0.5, -2), Vector2(1.5, -2), Vector2(0.55, 0.55), Vector2(0.45, 0.55)]))
	check(window._viewport_quad.size() >= 3, "partially visible camera footprint retained")
	for uv in window._viewport_quad:
		check(uv.x >= 0 and uv.x <= 1 and uv.y >= 0 and uv.y <= 1, "camera clipped inside map")
	var camera := Camera3D.new()
	add_child(camera)
	camera.position = Vector3(0, 15, 14)
	camera.look_at(Vector3.ZERO)
	var rig := Node3D.new()
	add_child(rig)
	window.set_viewport_uv_quad(MapMinimapUtils.compute_camera_minimap_uv_quad(camera, rig, doc.heightfield))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	window.get_texture().get_image().save_png("res://tmp/editor-minimap-fixed.png")
	window.set_minimap_units([])
	check(window._live_icons.is_empty() and window._has_live_units, "deleting all units does not resurrect disk icons")
	doc.create_from_options({"width": 64, "height": 32, "main_tileset": "L"})
	window._game_preview = true
	window.refresh_minimap(doc.heightfield, "", tiles, cliffs)
	check(not window._using_baked, "missing preview falls back to live")
	check(window._minimap_image.get_width() > window._minimap_image.get_height(), "live rectangular image contains no baked padding")
	await get_tree().process_frame
	var rect: Rect2 = window._minimap_drawn_rect()
	check(window.control_pos_to_minimap_uv(rect.get_center()).distance_to(Vector2(0.5, 0.5)) < 0.001, "rectangular map center maps correctly")
	check(window.control_pos_to_minimap_uv(rect.position - Vector2(0, 2)).x < 0, "letterbox click rejected")
	var previous: Image = window._minimap_image
	window.refresh_minimap_live(doc.heightfield, tiles, cliffs)
	check(window._minimap_image != previous, "missing baked preview does not block live updates")
	print("selftest_editor_minimap: %s failures=%d icons=%s" % ["PASS" if failures == 0 else "FAIL", failures, counts])
	get_tree().quit(0 if failures == 0 else 1)
