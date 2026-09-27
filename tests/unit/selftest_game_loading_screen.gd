extends SceneTree

## GameLoadingScreen 依赖注入自检：
##   1. setup(4 参) 写入字段
##   2. setup 重复调用幂等（不重复连接信号）
##   3. 缺 game_director 时 setup 不抛错
##
## 仅验证 inject 字段写入与信号幂等；不实例化完整 GameLoadingScreen（避免依赖 %TitleLabel/%StageLabel/%ProgressBar/%PercentLabel 子节点）。
## 设计：docs/design/game/SCENE_BOOTSTRAP.md（GameMain 强类型 setup 编排）

const GameLoadingScreenScript := preload("res://client/hud/game_loading_screen.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("[loading_screen_di] ===== 开始 selftest =====")

	# --- 1. 显式 setup(4 参) 注入字段 ---
	# 用空 CanvasLayer + set_script 的方式加载脚本；@onready 字段不实例化即可（仅测试 setup 注入字段）。
	var loading: CanvasLayer = CanvasLayer.new()
	loading.set_script(GameLoadingScreenScript)

	var stub_map := _make_stub_map()
	var stub_director := _make_stub_director()
	var stub_hud := CanvasLayer.new()
	var stub_hpbar := CanvasLayer.new()

	loading.setup(stub_map, stub_director, stub_hud, stub_hpbar)

	if loading.map_root == stub_map:
		_pass("setup 写入 map_root")
	else:
		_fail("map_root 未注入（got=%s）" % str(loading.map_root))
	if loading.game_director == stub_director:
		_pass("setup 写入 game_director")
	else:
		_fail("game_director 未注入")
	if loading.game_hud == stub_hud:
		_pass("setup 写入 game_hud")
	else:
		_fail("game_hud 未注入")
	if loading.health_bar_manager == stub_hpbar:
		_pass("setup 写入 health_bar_manager")
	else:
		_fail("health_bar_manager 未注入")

	# --- 2. 重复 setup 不重复连接 session_preparation_progress ---
	# 监听 stub_director 的信号两次：一次在 setup 后，一次在再次 setup 后。
	# 若 setup 重复挂信号，emit 一次会触发 2 次回调（双倍 size），则断言失败。
	var progress_calls: Array = []
	var handler := func(stage: String, p: float) -> void:
		progress_calls.append([stage, p])
	stub_director.session_preparation_progress.connect(handler)
	stub_director.emit_signal("session_preparation_progress", "load_assets", 0.5)
	var size_after_first := progress_calls.size()

	# 重复 setup（参数不变）
	loading.setup(stub_map, stub_director, stub_hud, stub_hpbar)
	stub_director.emit_signal("session_preparation_progress", "stage2", 0.7)

	if size_after_first == 1 and progress_calls.size() == 2:
		_pass("重复 setup 不重复连接 session_preparation_progress（每次 emit 只新增 1 个回调）")
	else:
		_fail("重复 setup 后信号被多次挂接（first=%d, second emit size=%d）" % [size_after_first, progress_calls.size()])

	# --- 3. 缺 game_director 时 setup 不应崩 ---
	var loading2: CanvasLayer = CanvasLayer.new()
	loading2.set_script(GameLoadingScreenScript)
	loading2.setup(stub_map, null, stub_hud, stub_hpbar)
	if loading2.map_root == stub_map:
		_pass("缺 game_director 时 setup 仍写入 map_root")
	else:
		_fail("缺 game_director 时 setup 未写入 map_root")

	# 清理
	stub_map.free()
	stub_director.free()
	stub_hud.free()
	stub_hpbar.free()
	loading.free()
	loading2.free()

	print("[loading_screen_di] 通过 %d / 失败 %d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("[loading_screen_di] FAIL: %s" % f)
	quit(1 if _failed > 0 else 0)


func _make_stub_map() -> Node:
	# MapLoader 接口 duck-type：loading_screen 只读 map_dir
	var m := Node.new()
	m.set("map_dir", "res://assets/test_map")
	return m


func _make_stub_director() -> Node:
	# GameDirector 接口 duck-type：loading_screen 需要 session_preparation_progress / session_ready / is_session_ready
	var d := Node.new()
	d.add_user_signal("session_preparation_progress", [
		{"name": "stage", "type": 4}, # TYPE_STRING
		{"name": "progress", "type": 3}, # TYPE_FLOAT
	])
	d.add_user_signal("session_ready")
	d.set_script(load("res://app/game_director.gd") if false else null)
	return d


func _pass(label: String) -> void:
	_passed += 1
	print("[loading_screen_di] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[loading_screen_di] FAIL: %s" % label)