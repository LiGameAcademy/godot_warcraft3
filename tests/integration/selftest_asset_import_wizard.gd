extends Node

const Wizard: PackedScene = preload("res://client/asset_import/asset_import_wizard.tscn")
const Index: GDScript = preload("res://app/asset_import_index.gd")
var ready_count: int = 0
var completion: Dictionary = {}
var events: Array[Dictionary] = []
var frames: int = 0
var _cancelled: bool = false
var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var mode: String = args[args.find("--mode") + 1]
	var cache: String = args[args.find("--cache") + 1]
	var game_dir: String = args[args.find("--source") + 1]
	var report: String = args[args.find("--report") + 1]
	var wizard: Control = Wizard.instantiate() as Control
	wizard.cache_root = cache
	wizard.request_resource = "res://config/development_asset_request.source" if "--development" in args else "res://config/asset_import_samples.source"
	wizard.auto_resume = mode in ["warm", "rebuild"]
	wizard.ready_to_play.connect(func() -> void: ready_count += 1)
	add_child(wizard)
	wizard.job.finished.connect(func(result: Dictionary) -> void: completion = result)
	wizard.job.progress_changed.connect(func(stage: String, completed: int, total: int) -> void:
		events.append({"stage": stage, "completed": completed, "total": total})
		if mode == "cancel-compile" and stage == "编译场景缓存" and completed == 1:
			call_deferred("_cancel", wizard))
	await get_tree().process_frame
	if "--capture" in args:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(report + ".initial.png")
	if mode == "warm":
		_check(ready_count == 1 and not wizard.job.active)
		completion = {"ok": true, "resumed": true}
	else:
		_check(ready_count == 0, "Invalid index must return to setup")
		wizard.directory.text = cache.path_join("missing-install") if mode == "retry" else game_dir
		wizard.start_button.pressed.emit()
		if mode != "source-overlap":
			_check(wizard.start_button.disabled and not wizard.cancel_button.disabled)
		if mode == "cancel-source":
			_cancel(wizard)
		await _wait(wizard)
		if mode == "retry":
			_check(not completion.ok and wizard.directory.editable and not wizard.start_button.disabled)
			wizard.directory.text = game_dir
			wizard.start_button.pressed.emit()
			await _wait(wizard)
		if mode == "source-overlap":
			_check(not completion.ok and not wizard.start_button.disabled and wizard.play_button.disabled)
		elif mode.begins_with("cancel"):
			_check(completion.get("cancelled", false) and wizard.play_button.disabled and not wizard.start_button.disabled)
		else:
			_check(completion.ok and not wizard.play_button.disabled and frames > 10)
			_check(not Index.latest(cache, wizard.request_resource).is_empty())
			wizard.play_button.pressed.emit()
			_check(ready_count == 1)
	if "--capture" in args:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(report + ".png")
	var file: FileAccess = FileAccess.open(report, FileAccess.WRITE)
	file.store_string(JSON.stringify({"mode": mode, "result": completion, "events": events, "frames": frames, "status": wizard.status.text, "failures": _failures}, "  "))
	file.close()
	wizard.queue_free()
	await get_tree().process_frame
	print("PASS: import wizard " + mode)
	get_tree().quit(0 if _failures.is_empty() else 1)

func _wait(wizard: Control) -> void:
	var deadline: int = Time.get_ticks_msec() + (1800000 if "--development" in OS.get_cmdline_user_args() else 180000)
	while wizard.job.active and Time.get_ticks_msec() < deadline:
		frames += 1
		await get_tree().process_frame
	_check(not wizard.job.active, "Background import timeout")

func _cancel(wizard: Control) -> void:
	if not _cancelled and wizard.job.active:
		_cancelled = true
		wizard.cancel_button.pressed.emit()

func _check(condition: bool, message: String = "Wizard validation failed") -> void:
	if not condition:
		_failures.append(message)
		push_error(message)
