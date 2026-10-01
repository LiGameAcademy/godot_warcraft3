extends SceneTree

## Boot / Loading View 流程自检（纯 View）：
##   1. begin 写入标题；set_progress 绝对进度 + 不倒退
##   2. finish → queue_free
##   3. GameMain / GameDirector 不再持有 loading 字段
##
## 设计：docs/design/game/SCENE_BOOTSTRAP.md §10（v1.4）

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("[boot_flow] ===== 开始 selftest =====")

	await _test_begin_and_progress()
	await _test_finish_releases()
	_test_game_main_has_no_loading_field()
	_test_director_setup_six_args()
	_test_loading_has_no_business_refs()

	print("[boot_flow] 通过 %d / 失败 %d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("[boot_flow] FAIL: %s" % f)
	quit(1 if _failed > 0 else 0)


## 1：begin + set_progress（绝对进度，只升不降）
func _test_begin_and_progress() -> void:
	var packed: PackedScene = load("res://scenes/game_loading_screen.tscn")
	if packed == null:
		_fail("无法加载 game_loading_screen.tscn")
		return
	var screen: Node = packed.instantiate()
	root.add_child(screen)
	await process_frame
	screen.call("begin", "Echo Isles")
	if str(screen.get("map_title")) == "Echo Isles":
		_pass("begin 写入 map_title")
	else:
		_fail("begin 未写入 map_title（got=%s）" % str(screen.get("map_title")))

	# 编排方已把资源 80% 映射为总进度 24%（0.8 * 0.30）后再推送。
	screen.call("set_progress", "正在加载资源…", 0.24)
	var bar: ProgressBar = screen.get_node_or_null("Root/Center/Panel/VBox/BarRow/ProgressBar") as ProgressBar
	_expect_bar(bar, 24.0, "绝对进度 0.24 → bar 24")

	screen.call("set_progress", "地图一半", 0.575)
	_expect_bar(bar, 57.5, "接收地图段绝对进度")
	screen.call("set_progress", "较早地图进度", 0.40)
	_expect_bar(bar, 57.5, "同阶段不倒退")
	screen.call("set_progress", "对局一半", 0.92)
	_expect_bar(bar, 92.0, "对局段绝对进度")
	screen.call("set_progress", "迟到地图", 0.85)
	_expect_bar(bar, 92.0, "晚到的前序事件不覆盖后续")
	screen.call("set_progress", "准备完成", 0.99)
	_expect_bar(bar, 99.0, "未 finish 前可达 99%")
	screen.queue_free()
	await process_frame


func _expect_bar(bar: ProgressBar, value: float, label: String) -> void:
	if bar != null and is_equal_approx(bar.value, value):
		_pass(label)
	else:
		_fail(label)


## 2：finish → 释放
func _test_finish_releases() -> void:
	var packed: PackedScene = load("res://scenes/game_loading_screen.tscn")
	var screen: Node = packed.instantiate()
	screen.set("min_visible_sec", 0.0)
	screen.set("fade_out_sec", 0.0)
	root.add_child(screen)
	await process_frame
	screen.call("begin", "Test")
	screen.call("finish")
	var bar := screen.get_node("Root/Center/Panel/VBox/BarRow/ProgressBar") as ProgressBar
	_expect_bar(bar, 100.0, "finish 显示 100%")
	await process_frame
	await process_frame
	if not is_instance_valid(screen):
		_pass("finish 后 loading 屏已释放")
	else:
		_fail("finish 后 loading 屏仍存活")
		screen.queue_free()


## 3：GameMain 不再暴露 game_loading_screen
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


## 4：GameDirector.setup 无 loading 形参
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


## 5：Loading View 无业务字段；boot 经 GameMain Facade 接线
func _test_loading_has_no_business_refs() -> void:
	var scr: GDScript = load("res://client/hud/game_loading_screen.gd") as GDScript
	if scr == null:
		_fail("无法加载 game_loading_screen.gd")
		return
	var src := scr.source_code
	if "var map_root" in src or "var game_director" in src:
		_fail("Loading 仍声明 map_root / game_director")
	else:
		_pass("Loading 已移除业务节点字段")
	if "func bind_map" in src or "func bind_director" in src:
		_fail("Loading 仍暴露 bind_map / bind_director")
	else:
		_pass("Loading 已移除 bind_* API")
	if "func begin(" in src and "func set_progress(" in src and "func finish(" in src:
		_pass("Loading 暴露 begin / set_progress / finish")
	else:
		_fail("Loading 缺少纯 View API")

	var boot_src: String = (load("res://boot.gd") as GDScript).source_code
	if 'get_node("MapRoot")' in boot_src or 'get_node("GameDirector")' in boot_src:
		_fail("boot 仍 get_node 子节点")
	else:
		_pass("boot 不再 get_node MapRoot/GameDirector")
	var main_src: String = (load("res://scenes/game_main.gd") as GDScript).source_code
	if "func wire_external_hooks" in main_src and "signal preparation_progress" in main_src:
		_pass("GameMain 暴露 Facade API")
	else:
		_fail("GameMain 缺少 Facade API")


func _pass(label: String) -> void:
	_passed += 1
	print("[boot_flow] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[boot_flow] FAIL: %s" % label)
