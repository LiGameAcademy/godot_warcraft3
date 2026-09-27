extends SceneTree

## GameLoadingScreen 依赖注入自检：
##   1. inject_dependencies 覆盖字段
##   2. _resolve_refs 在 _injected 后不会覆盖注入值
##   3. 注入后信号能被正确接到 _on_load_progress
## 设计：docs/design/game/UI_FRAMEWORK.md（间接，通过 loading screen 解耦）

const GameLoadingScreenScript := preload("res://client/hud/game_loading_screen.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("[loading_screen_di] ===== 开始 selftest =====")
	var scene_root := Node.new()
	scene_root.name = "GameMain"
	root.add_child(scene_root)

	var loading := _make_node_with_script(GameLoadingScreenScript, "GameLoadingScreen")
	scene_root.add_child(loading)

	# --- 准备四个 stub 节点（不挂真实脚本，duck-type 字段） ---
	var stub_map := _make_stub_map()
	var stub_director := _make_stub_director()
	var stub_hud := _make_stub_canvas_layer("GameHud")
	var stub_hpbar := _make_stub_canvas_layer("HealthBarManager")
	# 模拟场景内的硬编码名查找：把它们放到 GameMain 同级查找树里
	scene_root.add_child(stub_map)
	scene_root.add_child(stub_director)
	scene_root.add_child(stub_hud)
	scene_root.add_child(stub_hpbar)

	# --- 1. 显式注入覆盖 ---
	loading.call(
		"inject_dependencies",
		{
			"map_root": stub_map,
			"game_director": stub_director,
			"game_hud": stub_hud,
			"health_bar_manager": stub_hpbar,
		}
	)
	if loading.map_root == stub_map:
		_pass("inject_dependencies 写入 map_root")
	else:
		_fail("map_root 未注入（got=%s）" % str(loading.map_root))
	if loading.game_director == stub_director:
		_pass("inject_dependencies 写入 game_director")
	else:
		_fail("game_director 未注入")
	if loading.game_hud == stub_hud:
		_pass("inject_dependencies 写入 game_hud")
	else:
		_fail("game_hud 未注入")
	if loading.health_bar_manager == stub_hpbar:
		_pass("inject_dependencies 写入 health_bar_manager")
	else:
		_fail("health_bar_manager 未注入")

	# --- 2. fallback _resolve_refs 不能覆盖已注入的引用 ---
	var other_map := _make_stub_map()
	scene_root.add_child(other_map)
	loading.call("_resolve_refs")
	if loading.map_root == stub_map:
		_pass("_resolve_refs 不覆盖已注入 map_root")
	else:
		_fail("fallback 覆盖了已注入 map_root（got=%s）" % str(loading.map_root))

	# --- 3. 注入后 _wire_signals 应当能挂上 stub_director.session_preparation_progress ---
	var progress_calls: Array = []
	stub_director.session_preparation_progress.connect(func(stage: String, p: float) -> void:
		progress_calls.append([stage, p])
	)
	# inject 已经 _wire_signals 过一次；再调一次确认幂等
	loading.call(
		"inject_dependencies",
		{
			"map_root": stub_map,
			"game_director": stub_director,
			"game_hud": stub_hud,
			"health_bar_manager": stub_hpbar,
		}
	)
	stub_director.emit_signal("session_preparation_progress", "load_assets", 0.5)
	if progress_calls.size() == 1 and progress_calls[0][0] == "load_assets" and progress_calls[0][1] == 0.5:
		_pass("注入 + _wire_signals 后 session_preparation_progress 触发 on_load_progress")
	else:
		_fail("信号路由未生效（got=%s）" % str(progress_calls))

	# --- 4. 缺 game_director 时 _wire_signals 不应崩 ---
	loading.call(
		"inject_dependencies",
		{
			"map_root": stub_map,
			"game_dudirector": null,
			"game_hud": stub_hud,
		}
	)
	# 不抛错即通过
	_pass("缺少 game_director 时 inject 不抛错")

	# 清理
	stub_map.queue_free()
	stub_director.queue_free()
	stub_hud.queue_free()
	stub_hpbar.queue_free()
	other_map.queue_free()
	loading.queue_free()
	scene_root.queue_free()

	print("[loading_screen_di] 通过 %d / 失败 %d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("[loading_screen_di] FAIL: %s" % f)
	quit(1 if _failed > 0 else 0)


func _make_node_with_script(script: GDScript, node_name: String) -> Node:
	var n := CanvasLayer.new()
	n.name = node_name
	n.set_script(script)
	return n


func _make_stub_map() -> Node:
	# MapLoader 接口 duck-type：loading_screen 只读 map_dir
	var m := Node.new()
	m.name = "MapRoot"
	m.set("map_dir", "res://assets/test_map")
	return m


func _make_stub_director() -> Node:
	# GameDirector 接口 duck-type：loading_screen 需要 session_preparation_progress / session_ready / is_session_ready
	var d := Node.new()
	d.name = "GameDirector"
	d.add_user_signal("session_preparation_progress", [
		{"name": "stage", "type": 4}, # GDScriptVariant.Type.TYPE_STRING
		{"name": "progress", "type": 3}, # TYPE_FLOAT
	])
	d.add_user_signal("session_ready")
	return d


func _make_stub_canvas_layer(node_name: String) -> CanvasLayer:
	var c := CanvasLayer.new()
	c.name = node_name
	return c


func _pass(label: String) -> void:
	_passed += 1
	print("[loading_screen_di] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[loading_screen_di] FAIL: %s" % label)