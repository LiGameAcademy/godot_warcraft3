extends Node

## 游戏启动编排（v1.4 独立 Loading + 异步加载主场景）。
##
## 职责：
## [br]1. 先实例化 [code]game_loading_screen.tscn[/code] 作为顶层可见 scene，
## 立刻显示进度条（玩家第一帧就看到 UI）。
## [br]2. 调 [code]ResourceLoader.load_threaded_request[/code] 后台加载
## [code]game_main.tscn[/code]，每帧 poll 推进 loading 屏进度。
## [br]3. 加载完成后 instantiate + add_child game_main，
## 切到 game_main 作 [code]current_scene[/code]，调用 [code]bind_director[/code] 把
## session 阶段进度接入 loading 屏。
## [br]4. 等 [code]director.is_session_ready()[/code] 后等 loading 屏自然 fade 完，自身退出。
##
## --smoke-test 模式（命令形参含 --smoke-test）下沿用直接同步路径跑冒烟：
## 不走 loading 屏，跳过异步加载，直接 instantiate game_main，session_ready 后退出 0。
##
## 设计文档：docs/design/game/SCENE_BOOTSTRAP.md §10（v1.4）。

const GAME_MAIN_PATH := "res://scenes/game_main.tscn"
const LOADING_SCREEN_PATH := "res://scenes/game_loading_screen.tscn"

## Async loading 超时（msec）；超时则强制走错误退出，避免编辑器卡死。
const ASYNC_LOAD_TIMEOUT_MSEC := 180000


func _ready() -> void:
	call_deferred("_start")


## 启动入口：检测 --smoke-test 走快速同步路径，否则走完整异步加载 + loading 屏。
func _start() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args():
		_smoke_start()
		return
	_async_start()


## --smoke-test 模式：跳过 loading 屏直接 instantiate game_main；session_ready 后退出。
## [br]用于 CI / 自动化校验主流程，不引入异步与额外 UI 节点。
func _smoke_start() -> void:
	var packed := ResourceLoader.load(GAME_MAIN_PATH) as PackedScene
	if not is_instance_valid(packed):
		push_error("boot: 同步加载 game_main 失败")
		get_tree().quit(1)
		return
	var scene := packed.instantiate() as GameMain
	# spawn_opponent_base 必须在 add_child 触发 _ready/_boot_match 之前写入。
	var director_pre: GameDirector = scene.get_node("GameDirector") as GameDirector
	if director_pre != null:
		director_pre.spawn_opponent_base = true
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene
	var director: GameDirector = scene.game_director

	var deadline := Time.get_ticks_msec() + ASYNC_LOAD_TIMEOUT_MSEC
	while is_instance_valid(director) and not director.is_session_ready() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	if not is_instance_valid(director) or not director.is_session_ready():
		push_error("Game startup timed out")
		get_tree().quit(1)
		return
	if director.get_session() == null or \
			director.map_root.get_unit_layer().get_child_count() < 12:
		push_error("Game startup did not create a playable match")
		get_tree().quit(1)
		return

	print("APP startup PASS: game")
	get_tree().quit(0)


## 正常启动：实例化 loading 屏 + 异步加载 game_main。
func _async_start() -> void:
	# 1. 先把 loading 屏作为顶层可见 scene 挂入；玩家第一帧就有 UI。
	var loading_packed := ResourceLoader.load(LOADING_SCREEN_PATH) as PackedScene
	if not is_instance_valid(loading_packed):
		push_error("boot: 加载 game_loading_screen.tscn 失败")
		get_tree().quit(1)
		return
	var loading: GameLoadingScreen = loading_packed.instantiate()
	get_tree().root.add_child(loading)
	get_tree().current_scene = loading
	loading.begin_async(_initial_map_title())

	# 2. 启动后台加载 game_main.tscn。
	var err := ResourceLoader.load_threaded_request(GAME_MAIN_PATH)
	if err != OK:
		push_error("boot: load_threaded_request 失败 err=%d" % err)
		get_tree().quit(1)
		return

	# 3. poll 加载进度：每帧查一次 status，把 [0,1] 推到 loading 屏。
	var progress: Array = [0.0]
	var deadline := Time.get_ticks_msec() + ASYNC_LOAD_TIMEOUT_MSEC
	var timed_out := true
	while Time.get_ticks_msec() < deadline:
		var status := ResourceLoader.load_threaded_get_status(GAME_MAIN_PATH, progress)
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				loading.set_async_progress(progress[0])
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

	loading.set_async_progress(1.0)
	# 4. instantiate game_main 并接入 loading 屏。
	var main_packed := ResourceLoader.load_threaded_get(GAME_MAIN_PATH) as PackedScene
	if not is_instance_valid(main_packed):
		push_error("boot: load_threaded_get 拿到非 PackedScene")
		get_tree().quit(1)
		return
	var scene := main_packed.instantiate() as GameMain
	# 必须先订阅再入树：MapRoot/Director 可能在 _ready 中上报进度。
	# 此时 @onready 尚未解析，使用场景中已实例化的节点。
	loading.bind_map(scene.get_node("MapRoot") as MapLoader)
	var director := scene.get_node("GameDirector") as GameDirector
	loading.bind_director(
		director,
		scene.get_node("GameHud") as CanvasLayer,
		scene.get_node("HealthBarManager") as CanvasLayer,
	)
	get_tree().root.add_child(scene)
	get_tree().current_scene = scene

	# 5. 等待 session_ready（fallback：180s 内未就绪则报错退出）。
	var ready_deadline := Time.get_ticks_msec() + ASYNC_LOAD_TIMEOUT_MSEC
	while is_instance_valid(director) and not director.is_session_ready() \
			and Time.get_ticks_msec() < ready_deadline:
		await get_tree().process_frame
	if not is_instance_valid(director) or not director.is_session_ready():
		push_error("boot: GameDirector session_ready 超时")
		get_tree().quit(1)
		return

	# 6. session_ready 后等 loading 屏自然 fade；loading 屏自己 queue_free。
	# 这里只负责 boot 节点退出；如果想极短延迟释放可用 is_instance_valid(loading) 循环。
	while is_instance_valid(loading):
		await get_tree().process_frame

	# boot.gd 自身不再保留引用；它曾作为 current_scene 已被 game_main 替换。
	queue_free()


## 从 [code]project.godot[/code] / [code]game_main.tscn[/code] 默认 map_dir 推导初始标题。
## [br]当前 game_main.tscn 用的是 "echoisles"；这里固定返回 "Echo Isles"
## 保持与原 loading 屏显示一致；后续若需动态化可改成读 [code]project.godot[/code]。
func _initial_map_title() -> String:
	return "Echo Isles"
