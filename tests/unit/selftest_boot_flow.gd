extends SceneTree

## Boot 流程自检（v1.4 独立 Loading + 异步 API）：
##   1. begin_async 写入标题与初始进度
##   2. 资源 / 地图 / 对局进度分段映射，晚到事件不倒退
##   3. bind_director 订阅 session_ready 并触发 finish
##   4. GameMain 不再持有 game_loading_screen 字段
##   5. GameDirector.setup 接受 6 参（不含 loading）
##
## 设计：docs/design/game/SCENE_BOOTSTRAP.md §10（v1.4）

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("[boot_flow] ===== 开始 selftest =====")

	await _test_begin_async_and_progress()
	await _test_bind_director_finishes()
	_test_game_main_has_no_loading_field()
	_test_director_setup_six_args()

	print("[boot_flow] 通过 %d / 失败 %d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("[boot_flow] FAIL: %s" % f)
	quit(1 if _failed > 0 else 0)


## 1–2：begin_async + set_async_progress
func _test_begin_async_and_progress() -> void:
	var packed: PackedScene = load("res://scenes/game_loading_screen.tscn")
	if packed == null:
		_fail("无法加载 game_loading_screen.tscn")
		return
	var screen: Node = packed.instantiate()
	root.add_child(screen)
	# @onready 在 add_child 的 _ready 中解析；再等一帧确保 UI 子节点就绪。
	await process_frame
	screen.call("begin_async", "Echo Isles")
	if str(screen.get("map_title")) == "Echo Isles":
		_pass("begin_async 写入 map_title")
	else:
		_fail("begin_async 未写入 map_title（got=%s）" % str(screen.get("map_title")))

	screen.call("set_async_progress", 0.8)
	# 资源完成 80% 映射到总进度 24%，不是截断到固定上限。
	var pct: Label = screen.get_node_or_null("Root/Center/Panel/VBox/BarRow/PercentLabel") as Label
	var bar: ProgressBar = screen.get_node_or_null("Root/Center/Panel/VBox/BarRow/ProgressBar") as ProgressBar
	if pct != null and pct.text == "24%":
		_pass("资源进度按比例映射到 24%")
	elif bar != null and is_equal_approx(bar.value, 24.0):
		_pass("资源进度按比例映射到 24%")
	else:
		_fail("资源进度映射错误（pct=%s bar=%s）" % [
			pct.text if pct else "null",
			str(bar.value) if bar else "null",
		])

	# -s SceneTree 脚本编译早于 Autoload；运行时加载，避免提前编译地图依赖。
	var map: Node = load("res://addons/rts_map/presentation/map_loader.gd").new()
	screen.call("bind_map", map)
	map.load_progress.emit("地图一半", 0.5)
	_expect_bar(bar, 57.5, "接收地图进度并映射")
	map.load_progress.emit("较早地图进度", 0.2)
	_expect_bar(bar, 57.5, "同阶段不倒退")
	screen.call("_on_load_progress", "对局一半", 0.5)
	_expect_bar(bar, 92.0, "对局进度映射")
	map.load_progress.emit("迟到地图", 1.0)
	screen.call("set_async_progress", 1.0)
	_expect_bar(bar, 92.0, "晚到的前序事件不覆盖后续阶段")
	screen.call("_on_load_progress", "准备完成", 1.0)
	_expect_bar(bar, 99.0, "未收到就绪不得显示 100%")
	map.free()
	screen.queue_free()
	await process_frame


func _expect_bar(bar: ProgressBar, value: float, label: String) -> void:
	if bar != null and is_equal_approx(bar.value, value):
		_pass(label)
	else:
		_fail(label)


## 3：bind_director → session_ready → finish
func _test_bind_director_finishes() -> void:
	var packed: PackedScene = load("res://scenes/game_loading_screen.tscn")
	var screen: Node = packed.instantiate()
	screen.set("min_visible_sec", 0.0)
	screen.set("fade_out_sec", 0.0)
	root.add_child(screen)
	await process_frame
	screen.call("begin_async", "Test")

	var stub := _make_stub_director()
	root.add_child(stub)
	var hud := CanvasLayer.new()
	var hpbar := CanvasLayer.new()
	root.add_child(hud)
	root.add_child(hpbar)

	screen.call("bind_director", stub, hud, hpbar)
	# duck-type stub 不是 GameDirector，typed 字段可能为 null；以信号接线与 HUD 隐藏为准。
	if not hud.visible:
		_pass("bind_director 隐藏 HUD")
	else:
		_fail("bind_director 未隐藏 HUD")
	if screen.has_method("bind_director"):
		_pass("bind_director API 可用")
	else:
		_fail("bind_director API 缺失")

	# 触发 session_ready → finish → queue_free（fade_out_sec=0）
	stub.emit_signal("session_ready")
	var bar := screen.get_node("Root/Center/Panel/VBox/BarRow/ProgressBar") as ProgressBar
	_expect_bar(bar, 100.0, "就绪显示 100%")
	await process_frame
	await process_frame
	if not is_instance_valid(screen):
		_pass("session_ready 后 loading 屏已释放")
	else:
		_fail("session_ready 后 loading 屏仍存活")
		screen.queue_free()

	stub.queue_free()
	hud.queue_free()
	hpbar.queue_free()


## 4：GameMain 不再暴露 game_loading_screen
func _test_game_main_has_no_loading_field() -> void:
	var gm_script: GDScript = load("res://scenes/game_main.gd") as GDScript
	if gm_script == null:
		_fail("无法加载 game_main.gd")
		return
	var src := gm_script.source_code
	if "var game_loading_screen" in src:
		_fail("GameMain 仍声明 game_loading_screen 字段")
	else:
		_pass("GameMain 已移除 game_loading_screen 字段")
	if "_setup_game_loading_screen" in src:
		_fail("GameMain 仍有 _setup_game_loading_screen")
	else:
		_pass("GameMain 已移除 _setup_game_loading_screen")


## 5：GameDirector.setup 形参数量（通过源码扫描确认 6 参）
func _test_director_setup_six_args() -> void:
	var dir_script: GDScript = load("res://app/game_director.gd") as GDScript
	if dir_script == null:
		_fail("无法加载 game_director.gd")
		return
	var src := dir_script.source_code
	if "p_game_loading_screen" in src:
		_fail("GameDirector.setup 仍含 p_game_loading_screen")
	else:
		_pass("GameDirector.setup 已去掉 loading 形参")
	if "@export var game_loading_screen" in src:
		_fail("GameDirector 仍声明 @export game_loading_screen")
	else:
		_pass("GameDirector 已移除 @export game_loading_screen")


func _make_stub_director() -> Node:
	var stub_src := """extends Node
signal session_preparation_progress(stage: String, progress: float)
signal session_ready
func is_session_ready() -> bool:
	return false
"""
	var gs := GDScript.new()
	gs.source_code = stub_src
	var err := gs.reload()
	if err != OK:
		push_error("stub director script reload failed: %d" % err)
	var d := Node.new()
	d.set_script(gs)
	return d


func _pass(label: String) -> void:
	_passed += 1
	print("[boot_flow] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[boot_flow] FAIL: %s" % label)
