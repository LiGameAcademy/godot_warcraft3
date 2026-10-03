extends Node

## 游戏启动编排（v1.4：Loading 纯 View + GameMain Facade）。
##
## 职责：
## [br]1. 先实例化 Loading View，立刻显示。
## [br]2. 异步加载 [code]game_main.tscn[/code]，资源进度推给 Loading。
## [br]3. instantiate 后只通过 [GameMain] Facade 接线（不 [code]get_node[/code] 子节点）。
## [br]4. [signal GameMain.session_ready] → [method GameLoadingScreen.finish]，淡出后退出。
##
## 设计文档：docs/design/game/SCENE_BOOTSTRAP.md §10。

const SourceImport: GDScript = preload("res://app/game_source_import.gd")
const AssetImport: GDScript = preload("res://app/game_asset_import.gd")

const GAME_MAIN_PATH: String = "res://scenes/game_main.tscn"
const LOADING_SCREEN_PATH: String = "res://scenes/game_loading_screen.tscn"

## Async loading 超时（msec）。
const ASYNC_LOAD_TIMEOUT_MSEC: int = 180000


func _ready() -> void:
	call_deferred("_start")


func _start() -> void:
	if not _prepare_asset_import():
		return
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_start()
		return
	_async_start()


## --smoke-test：跳过 loading，经 Facade 配置并等待 session。
func _smoke_start() -> void:
	var packed: PackedScene = ResourceLoader.load(GAME_MAIN_PATH) as PackedScene
	if not is_instance_valid(packed):
		push_error("boot: 同步加载 game_main 失败")
		get_tree().quit(1)
		return
	var scene: GameMain = packed.instantiate() as GameMain
	# spawn_opponent_base 必须在 add_child → _boot_scene 之前写入。
	scene.configure_match({"spawn_opponent_base": true})
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene

	var deadline: int = Time.get_ticks_msec() + ASYNC_LOAD_TIMEOUT_MSEC
	while is_instance_valid(scene) and not scene.is_session_ready() \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(scene) or not scene.is_session_ready():
		push_error("Game startup timed out")
		get_tree().quit(1)
		return
	if not scene.has_playable_match():
		push_error("Game startup did not create a playable match")
		get_tree().quit(1)
		return

	print("APP startup PASS: game")
	get_tree().quit(0)


## 正常启动：Loading View + GameMain Facade。
func _async_start() -> void:
	var loading_packed: PackedScene = ResourceLoader.load(LOADING_SCREEN_PATH) as PackedScene
	if not is_instance_valid(loading_packed):
		push_error("boot: 加载 game_loading_screen.tscn 失败")
		get_tree().quit(1)
		return
	var loading: GameLoadingScreen = loading_packed.instantiate()
	get_tree().root.add_child(loading)
	get_tree().current_scene = loading
	loading.begin(_initial_map_title())

	var err: Error = ResourceLoader.load_threaded_request(GAME_MAIN_PATH)
	if err != OK:
		push_error("boot: load_threaded_request 失败 err=%d" % err)
		get_tree().quit(1)
		return

	# 资源阶段：boot 映射到 0 .. GameMain.RESOURCE_END（GameMain 尚未存在）。
	var progress: Array = [0.0]
	var deadline: int = Time.get_ticks_msec() + ASYNC_LOAD_TIMEOUT_MSEC
	var timed_out: bool = true
	while Time.get_ticks_msec() < deadline:
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(GAME_MAIN_PATH, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				loading.set_progress(
					"正在加载资源…",
					clampf(float(progress[0]), 0.0, 1.0) * GameMain.RESOURCE_END,
				)
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				timed_out = false
				break
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_error("boot: game_main.tscn 异步加载失败 status=%d" % status)
				get_tree().quit(1)
				return
			_:
				await get_tree().process_frame
	if timed_out:
		push_error("boot: game_main.tscn 异步加载超时")
		get_tree().quit(1)
		return

	loading.set_progress("正在加载资源…", GameMain.RESOURCE_END)

	var main_packed: PackedScene = ResourceLoader.load_threaded_get(GAME_MAIN_PATH) as PackedScene
	if not is_instance_valid(main_packed):
		push_error("boot: load_threaded_get 拿到非 PackedScene")
		get_tree().quit(1)
		return
	var scene: GameMain = main_packed.instantiate() as GameMain
	# 先订 Facade 信号，再 wire（wire 末尾可能立刻 emit 初始进度 / 已就绪）。
	scene.preparation_progress.connect(
		func(stage: String, p: float) -> void:
			if is_instance_valid(loading):
				loading.set_progress(stage, p)
	)
	scene.session_ready.connect(
		func() -> void:
			if is_instance_valid(loading):
				loading.finish()
	)
	scene.wire_external_hooks()
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene

	var ready_deadline: int = Time.get_ticks_msec() + ASYNC_LOAD_TIMEOUT_MSEC
	while is_instance_valid(scene) and not scene.is_session_ready() \
			and Time.get_ticks_msec() < ready_deadline:
		await get_tree().process_frame
	if not is_instance_valid(scene) or not scene.is_session_ready():
		push_error("boot: GameDirector session_ready 超时")
		get_tree().quit(1)
		return

	while is_instance_valid(loading):
		await get_tree().process_frame

	queue_free()


func _initial_map_title() -> String:
	return "Echo Isles"

## 启动参数仅编排导入，不承载解析/编译实现。
func _prepare_asset_import() -> bool:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var manifest_path: String = ""
	var result_path: String = ""
	var game_dir: String = ""
	var request_path: String = ""
	var cache_root: String = "user://wc3-cache/source-import"
	var index: int = 0
	while index < args.size():
		if args[index] in ["--asset-root", "--asset-import-manifest", "--asset-import-result", "--warcraft-dir", "--asset-import-request", "--asset-import-cache"]:
			if index + 1 >= args.size():
				get_tree().quit(2)
				return false
			var flag: String = args[index]
			index += 1
			match flag:
				"--asset-root": ProjectSettings.set_setting("warcraft3/asset_root", args[index])
				"--asset-import-manifest": manifest_path = args[index]
				"--asset-import-result": result_path = args[index]
				"--warcraft-dir": game_dir = args[index]
				"--asset-import-request": request_path = args[index]
				"--asset-import-cache": cache_root = args[index]
		index += 1
	if manifest_path.is_empty() and game_dir.is_empty():
		if "--asset-import-only" in args:
			get_tree().quit(2)
			return false
		return true
	var importer: RefCounted = AssetImport.new()
	var result: Dictionary
	if not game_dir.is_empty():
		if not manifest_path.is_empty():
			get_tree().quit(2)
			return false
		var source_importer: RefCounted = SourceImport.new()
		result = source_importer.run_source(game_dir, request_path, cache_root, AssetProvider.runtime_content_sealed)
	else:
		result = importer.run_manifest(manifest_path, AssetProvider.runtime_content_sealed)
	if not result_path.is_empty():
		var file: FileAccess = FileAccess.open(result_path, FileAccess.WRITE)
		if file == null:
			get_tree().quit(2)
			return false
		file.store_string(JSON.stringify(result, "  ") + "\n")
		file.close()
	print("GAME asset import %s" % ["PASS" if result.ok else "FAIL"])
	if not result.ok or "--asset-import-only" in args:
		get_tree().quit(0 if result.ok else 1)
		return false
	return true
