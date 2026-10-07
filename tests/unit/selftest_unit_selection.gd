extends Node
const PickVolume := preload("res://client/selection/unit_pick_volume.gd")
var checks := 0
var failures := 0
var changes := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _ready() -> void:
	call_deferred("run")

func unit(host: Node, type_id: String, at: Vector3, size: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = at
	node.set_meta("unit_data", {"typeId": type_id, "owner": 0})
	host.add_child(node)
	var model := Node3D.new()
	model.name = "Model"
	node.add_child(model)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position.y = size.y * 0.5
	model.add_child(mesh)
	return node

func button(pos: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = pos
	return event

func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1000, 800)
	viewport.own_world_3d = true
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 10, 14)
	camera.look_at(Vector3.ZERO)
	camera.fov = 50
	var host := Node3D.new()
	world.add_child(host)
	var worker := unit(host, "hpea", Vector3.ZERO, Vector3(0.8, 4.0, 0.8))
	var building := unit(host, "htow", Vector3(5, 0, 0), Vector3(3, 6, 3))
	var selector := UnitSelector.new()
	viewport.add_child(selector)
	selector.setup(camera, host)
	selector.selection_changed.connect(func(_primary: Node3D, _selected: Array) -> void: changes += 1)
	var torso := camera.unproject_position(Vector3(0, 3.5, 0))
	check(selector.screen_foot_distance(worker, torso) > 52, "body test lies outside old foot pixel fallback")
	check(selector.pick_at(torso) == worker, "clicking upper body selects unit")
	check(selector.pick_at(camera.unproject_position(Vector3(5, 5.0, 0))) == building, "clicking building roof selects building")
	worker.position = Vector3(5, 0, 0)
	check(selector.pick_at(camera.unproject_position(Vector3(5, 5.0, 0))) == building, "unit foot fallback cannot steal a building body hit")
	worker.position = Vector3.ZERO
	check(worker.get_node_or_null("Selectable") == null and building.get_node_or_null("Selectable") == null, "pick query does not instantiate selection components")
	worker.hide()
	check(selector.pick_at(torso) != worker, "hidden units cannot intercept picks")
	worker.show()
	worker.set_meta(WorldMembership.META_IN_WORLD, false)
	check(selector.pick_at(torso) != worker, "off-world units cannot intercept picks")
	worker.set_meta(WorldMembership.META_IN_WORLD, true)
	selector.handle_pointer_event(button(torso, true))
	check(selector.get_primary() == worker and changes == 1, "selection feedback occurs on press")
	# The target walks while the mouse is held; slight hand jitter is not a marquee.
	worker.position.x += 2
	selector.handle_pointer_event(button(torso + Vector2(5, 1), false))
	check(selector.get_primary() == worker and changes == 1, "release preserves moving target and emits no duplicate selection")
	selector.select_node(worker)
	check(changes == 1, "reselecting same unit does not rebuild HUD")
	var ring := worker.get_node("SelectionRing") as SelectionRing
	check(ring.visible and (ring.material_override as BaseMaterial3D).no_depth_test, "selection feedback bypasses terrain depth")
	var diameter := ring.get_diameter()
	worker.scale = Vector3(0.2, 0.4, 0.3)
	worker.rotation.x = 0.4
	ring._process(0.016)
	check(ring.global_basis.is_equal_approx(Basis.IDENTITY) and is_equal_approx(ring.get_diameter(), diameter), "ring does not inherit host scale or tilt")
	check(ring.global_position.is_equal_approx(worker.global_position + Vector3.UP * SelectionRing.Y_BIAS), "ring follows host in world space")
	selector.handle_pointer_event(button(torso, true))
	check(selector._marqueeing, "gesture active before entering aim mode")
	selector.enabled = false
	check(not selector._marqueeing and not selector._marquee.active, "aim mode cancels pending selection gesture")
	selector.enabled = true
	worker.scale = Vector3.ONE
	worker.rotation = Vector3.ZERO
	worker.position = Vector3.ZERO
	# Clicking visible world between HUD panels near the bottom must work.
	check(not selector.is_blocked_at(Vector2(300, 760)), "bottom world is not an invisible dead strip")
	var panel := Panel.new()
	panel.position = Vector2(50, 650)
	panel.size = Vector2(150, 150)
	panel.add_to_group("world_input_blockers")
	viewport.add_child(panel)
	check(selector.is_blocked_at(Vector2(100, 700)), "actual HUD rectangle blocks first click")
	check(not selector.is_blocked_at(Vector2(300, 700)), "HUD gaps allow world clicks")
	panel.hide()
	check(not selector.is_blocked_at(Vector2(100, 700)), "hidden HUD does not block world")
	# Model replacement must not reuse the previous geometry's bounds.
	var old := worker.get_node("Model")
	old.name = "Model_Old"
	old.queue_free()
	var replacement := Node3D.new()
	replacement.name = "Model"
	worker.add_child(replacement)
	check(selector.pick_at(torso) != worker, "model replacement invalidates pick bounds")
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 4, 1)
	mesh.mesh = box
	mesh.position.y = 2
	replacement.add_child(mesh)
	check(selector.pick_at(torso) == worker, "late model arrival invalidates empty bounds")
	var input := MatchInputController.new()
	viewport.add_child(input)
	input.configure({"selector": selector})
	check(not selector.is_processing_input(), "central input ownership disables duplicate receiver")
	input.shutdown()
	check(not selector.is_processing_input(), "detached receiver cannot steal replacement input")
	selector.set_external_input(false)
	check(selector.is_processing_input(), "standalone receiver can be explicitly restored")
	# Real drag still selects multiple friendly units.
	var start := camera.unproject_position(Vector3(-2, 0, 2))
	var finish := camera.unproject_position(Vector3(7, 0, -2))
	selector.handle_pointer_event(button(start, true))
	selector.handle_pointer_event(button(finish, false))
	check(selector.get_selected().has(worker) and not selector.get_selected().has(building), "marquee retains units-over-buildings rule")
	# Independent overlap fixture: the building's aggregate box contains empty space.
	var overlap_host := Node3D.new()
	world.add_child(overlap_host)
	var exposed := unit(overlap_host, "hpea", Vector3.ZERO, Vector3.ONE)
	var gate := unit(overlap_host, "htow", Vector3(0, 0, 2), Vector3(1, 4, 1))
	var gate_model := gate.get_node("Model") as Node3D
	var left := gate_model.get_child(0) as MeshInstance3D
	left.position.x = -2
	var right := left.duplicate() as MeshInstance3D
	right.position.x = 2
	gate_model.add_child(right)
	camera.position = Vector3(0, 0.5, 10)
	camera.look_at(Vector3(0, 0.5, 0))
	selector.setup(camera, overlap_host)
	var center := Vector2(500, 400)
	var ray_origin := camera.project_ray_origin(center)
	var ray_direction := camera.project_ray_normal(center)
	var inverse := gate_model.global_transform.affine_inverse()
	check(PickVolume.model_bounds(gate_model).intersects_ray(inverse * ray_origin, inverse.basis * ray_direction) != null, "regression ray crosses building bounds")
	check(selector.pick_at(center) == exposed, "visible worker in building bounds wins through geometric gap")
	# A real front face must still occlude the worker.
	var panel_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(4, 4)
	panel_mesh.mesh = quad
	panel_mesh.position.y = 2
	gate_model.add_child(panel_mesh)
	check(selector.pick_at(center) == gate, "solid building face occludes worker")
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var alpha_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	alpha_image.fill(Color(1, 1, 1, 0))
	material.albedo_texture = ImageTexture.create_from_image(alpha_image)
	panel_mesh.material_override = material
	check(selector.pick_at(center) == exposed, "alpha cutout exposes worker behind building face")
	alpha_image.fill(Color.WHITE)
	material.albedo_texture = ImageTexture.create_from_image(alpha_image)
	check(selector.pick_at(center) == gate, "opaque texture pixel occludes worker")
	panel_mesh.hide()
	# Imported WC3 geometry uses tiny Model scales with large source coordinates.
	var small_model := exposed.get_node("Model") as Node3D
	small_model.scale = Vector3.ONE * 0.005
	var small_mesh := small_model.get_child(0) as MeshInstance3D
	(small_mesh.mesh as BoxMesh).size = Vector3.ONE * 200.0
	small_mesh.position.y = 100.0
	small_model.remove_meta(PickVolume.CACHE_KEY)
	check(selector.pick_at(center) == exposed, "tiny imported model scale still has a pickable body")
	check(is_finite(PickVolume.ray_distance(exposed, ray_origin, ray_direction)), "tiny scale uses mesh hit rather than foot fallback")
	small_model.scale = Vector3.ZERO
	check(is_inf(PickVolume.ray_distance(exposed, ray_origin, ray_direction)), "truly singular model transform is safely ignored")
	viewport.queue_free()
	await get_tree().process_frame
	print("selftest_unit_selection: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
