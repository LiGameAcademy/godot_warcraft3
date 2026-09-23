extends Node
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	var editor = preload("res://ui/editor_inspect_window.tscn").instantiate()
	add_child(editor)
	var game = preload("res://client/hud/game_minimap.tscn").instantiate()
	add_child(game)
	var image := Image.create(128, 64, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.5, 0.3))
	editor._apply_minimap_texture(image)
	game.set_background_texture(ImageTexture.create_from_image(image))
	var a = editor._minimap_overlay
	var b = game._overlay
	check(a.get_script() == b.get_script(), "both surfaces instantiate the same shared view")
	a.set_anchors_preset(Control.PRESET_TOP_LEFT)
	b.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var clicks: Array = []
	game.clicked.connect(func(uv: Vector2): clicks.append(uv))
	for dimensions in [Vector2(256, 256), Vector2(400, 200), Vector2(180, 300)]:
		a.size = dimensions
		b.size = dimensions
		for uv in [Vector2.ZERO, Vector2(0.25, 0.75), Vector2.ONE]:
			check(a.uv_to_position(uv).distance_to(b.uv_to_position(uv)) < 0.001, "editor/game marker coordinates agree")
			check(a.position_to_uv(a.uv_to_position(uv)).distance_to(uv) < 0.001, "mapping round trip")
		var point: Vector2 = b.uv_to_position(Vector2(0.25, 0.75))
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = point
		b._on_input(press)
		check(clicks.back().distance_to(Vector2(0.25, 0.75)) < 0.001, "shared input reaches game signal")
		var motion := InputEventMouseMotion.new()
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
		motion.position = b.uv_to_position(Vector2(0.7, 0.3))
		b._on_input(motion)
		check(clicks.back().distance_to(Vector2(0.7, 0.3)) < 0.001, "shared drag navigation")
		press.pressed = false
		b._on_input(press)
		var before := clicks.size()
		b._emit_at(Vector2(-10, -10))
		check(clicks.size() == before, "outside click rejected")
	var clipped := MapMinimapUtils.clip_uv_polygon(PackedVector2Array([Vector2(-1, -1), Vector2(2, -1), Vector2(2, 2), Vector2(-1, 2)]))
	check(clipped.size() == 4, "oversized footprint clips to map")
	var cat := Wc3IdCatalog.new()
	cat.load_default()
	game.set_id_catalog(cat)
	check(game._shows_neutral_building_icon("ngme", 15), "shared neutral shop classification")
	check(not game._shows_neutral_building_icon("nmh0", 15), "explicit no-minimap-icon honored")
	await get_tree().process_frame
	print("selftest_shared_minimap: %s failures=%d" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(0 if failures == 0 else 1)
