extends Node

const OverlayScene: PackedScene = preload("res://client/selection/selector_overlay_layer.tscn")
const RingScene: PackedScene = preload("res://packages/map/scenes/selection/selection_ring.tscn")
var _failures: int = 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var icons: HudIconCache = HudIconCache.new()
	for logical: String in ["ReplaceableTextures/CommandButtons/BTNPeasant.png", "ReplaceableTextures/CommandButtons/BTNFootman.png", "ReplaceableTextures/CommandButtons/BTNMove.png"]:
		_check(icons.load_icon(logical) != null, "Missing HUD icon: " + logical)
	_check(RuntimeAssets.load_converted_texture("ReplaceableTextures/Selection/SelectionCircleMed.png") != null, "Missing selection circle PNG")
	var overlay: SelectorOverlayLayer = OverlayScene.instantiate() as SelectorOverlayLayer
	add_child(overlay)
	var marquee: MarqueeSelection = MarqueeSelection.new()
	overlay.bind_marquee(marquee)
	var drawing: MarqueeOverlay = overlay.marquee_overlay()
	_check(drawing != null, "Nested marquee drawing node must resolve")
	if drawing == null:
		get_tree().quit(1)
		return
	marquee.begin(Vector2(120, 100))
	marquee.update(Vector2(520, 380))
	_check(drawing.visible and drawing._drawing, "Dragging must show the selection box")
	_check(drawing._rect == Rect2(120, 100, 400, 280), "Drawing must receive marquee coordinates")
	marquee.finish()
	_check(not drawing.visible, "Release must hide the selection box")
	overlay.bind_marquee(marquee)
	_check(marquee.changed.get_connections().size() == 1, "Rebinding must not duplicate handlers")
	var world: Node3D = Node3D.new()
	add_child(world)
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.0
	camera.position = Vector3(0, 10, 0)
	camera.look_at(Vector3.ZERO, Vector3.BACK)
	camera.make_current()
	var ring_a: SelectionRing = RingScene.instantiate() as SelectionRing
	var ring_b: SelectionRing = RingScene.instantiate() as SelectionRing
	world.add_child(ring_a)
	world.add_child(ring_b)
	ring_a.show_selected(3.0, Color.GREEN)
	ring_b.show_selected(1.5, Color.YELLOW)
	_check((ring_a.material_override as StandardMaterial3D).albedo_texture != null, "Selection ring must use its alpha texture")
	_check(ring_a.material_override != ring_b.material_override and ring_a.mesh != ring_b.mesh, "Selection ring mutable resources must be per instance")
	ring_a.set_ring_color(Color.CYAN)
	_check(ring_b.get_ring_color() == Color.YELLOW and is_equal_approx(ring_b.get_diameter(), 1.5), "Changing A must preserve B")
	ring_b.hide_selected()
	if "--capture" in OS.get_cmdline_user_args():
		var icon: TextureRect = TextureRect.new()
		icon.texture = icons.load_icon("ReplaceableTextures/CommandButtons/BTNPeasant.png")
		icon.position = Vector2(40, 40)
		icon.size = Vector2(64, 64)
		add_child(icon)
		marquee.begin(Vector2(120, 100))
		marquee.update(Vector2(520, 380))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var output: String = ProjectSettings.globalize_path("res://tmp/selection-feedback.png")
		get_viewport().get_texture().get_image().save_png(output)
		print("Capture: " + output)
	print("selftest_selection_feedback: %s" % ["PASS" if _failures == 0 else "FAIL"])
	get_tree().quit(0 if _failures == 0 else 1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
