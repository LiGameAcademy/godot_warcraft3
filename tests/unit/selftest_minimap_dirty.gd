extends SceneTree
const Document := preload("res://documents/map_document.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var doc = Document.new()
	doc.create_from_options({"width": 64, "height": 32,
		"ground_tilesets": ["Ldrt", "Lgrs"], "cliff_tilesets": ["CLdi", "CLgr"]})
	var raster := MapMinimapRaster.new(doc.heightfield)
	var reference := MapMinimapRaster.new(doc.heightfield)
	var colors := PackedColorArray([Color(0.6, 0.3, 0.1), Color(0.1, 0.7, 0.2)])
	raster.setup_terrain(colors)
	reference.setup_terrain(colors)
	raster.rasterize()
	var before := raster.get_image().get_data()
	var failed := 0
	for p in [Vector2i(0, 0), Vector2i(64, 32), Vector2i(0, 32), Vector2i(64, 0), Vector2i(20, 12)]:
		doc.paint_corner(p.x, p.y, 1)
		var index: int = doc.heightfield.index_at(p.x, p.y)
		doc.heightfield.flags_packed[index] |= Wc3Coords.FLAG_WATER
		doc.heightfield.water_heights[index] = 96
		raster.mark_dirty(Rect2i(p, Vector2i.ONE))
		raster.mark_dirty(Rect2i(p, Vector2i.ONE)) # overlap must be harmless
	raster.mark_dirty(Rect2i(-3, -3, 3, 3))
	raster.mark_dirty(Rect2i(999, 999, 1, 1))
	var actual := raster.rasterize_dirty()
	var expected := reference.rasterize()
	if actual.get_data() != expected.get_data() or actual.get_data() == before:
		push_error("dirty minimap must equal full raster and include edited colors/water/boundaries")
		failed += 1
	var stable := actual.get_data()
	if raster.rasterize_dirty().get_data() != stable:
		push_error("empty dirty set changes image")
		failed += 1
	if raster.get_display_image().get_data() != reference.get_display_image().get_data():
		push_error("rectangular minimap display differs")
		failed += 1
	var fresh := MapMinimapRaster.new(doc.heightfield)
	fresh.setup_terrain(colors)
	if fresh.rasterize_dirty().get_data() != expected.get_data():
		push_error("uninitialized raster must render all pixels")
		failed += 1
	var recolored := PackedColorArray([Color.WHITE, Color.BLACK])
	raster.setup_terrain(recolored)
	reference.setup_terrain(recolored)
	if raster.rasterize_dirty().get_data() != reference.rasterize().get_data():
		push_error("changing terrain palette must invalidate the full raster")
		failed += 1
	print("selftest_minimap_dirty: %s (%d failures)" % ["PASS" if failed == 0 else "FAIL", failed])
	quit(0 if failed == 0 else 1)
