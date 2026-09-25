extends Node

var failures: int = 0
var checks: int = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("PORTRAIT WARMUP: " + label)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var director: GameDirector = GameDirector.new()
	check(not director.is_session_ready(), "New session not ready")
	director._bootstrapped = true
	check(not director.is_session_ready(), "Business bootstrap alone does not open match")
	director._presentation_ready = true
	check(director.is_session_ready(), "Presentation completion opens match")
	director.free()
	var cache: MapModelCache = MapModelCache.new()
	var catalog: Wc3IdCatalog = Wc3IdCatalog.new()
	catalog.load_default()
	var host: Control = Control.new()
	add_child(host)
	var view: UnitPortraitView = load("res://client/hud/unit_portrait_view.tscn").instantiate() as UnitPortraitView
	host.add_child(view)
	view.configure(cache, catalog)
	host.process_mode = Node.PROCESS_MODE_DISABLED
	await view.prepare_types(PackedStringArray(["hpea", "htow"]), 0)
	check(not view._warming and view._type_id.is_empty(), "Preparation leaves no selected type")
	check(not view._vp_host.visible and view._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Preparation leaves portrait hidden and inactive")
	check(host.process_mode == Node.PROCESS_MODE_DISABLED, "View does not unpause gameplay")
	if DisplayServer.get_name() != "headless":
		check(view._pool.size() == 2, "Both real models retained in bounded pool")
		var path: String = catalog.portrait_glb_path("hpea")
		var prepared: Node3D = view._pool.get(path) as Node3D
		view.show_type("hpea", 0)
		await get_tree().process_frame
		await get_tree().process_frame
		check(view._model_root == prepared, "First real selection reuses prepared instance")
		check(view._vp_host.visible, "Real selection displays portrait")
		view.clear_portrait()
		# Cancel while a preparation coroutine is waiting; it must not select the next type.
		view.call_deferred("clear_portrait")
		await view.prepare_types(PackedStringArray(["hpea", "htow"]), 0)
		check(not view._warming and view._model_root == null and view._type_id.is_empty(), "Cancellation stops preparation")
	else:
		check(view._pool.is_empty(), "Headless skips GPU preparation")
	view.configure(MapModelCache.new(), catalog)
	check(view._pool.is_empty() and view._model_root == null, "Rebinding releases old portraits")
	host.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("selftest_portrait_warmup: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
