extends SceneTree

## GameLoadingScreen 纯 View 自检：
##   1. begin 写入标题
##   2. set_progress 只升不降
##   3. finish 幂等且可重复调用不抛错
##
## 不依赖 MapLoader / GameDirector。设计：docs/design/game/SCENE_BOOTSTRAP.md §10。

const GameLoadingScreenScript := preload("res://client/hud/game_loading_screen.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []


func _initialize() -> void:
	print("[loading_screen_view] ===== 开始 selftest =====")

	var loading: CanvasLayer = CanvasLayer.new()
	loading.set_script(GameLoadingScreenScript)

	loading.begin("TestMap")
	if str(loading.get("map_title")) == "TestMap":
		_pass("begin 写入 map_title")
	else:
		_fail("begin 未写入 map_title（got=%s）" % str(loading.get("map_title")))

	loading.set_progress("阶段A", 0.4)
	if is_equal_approx(float(loading.get("_display_progress")), 0.4):
		_pass("set_progress 写入 0.4")
	else:
		_fail("set_progress 未写入 0.4")

	loading.set_progress("较早", 0.2)
	if is_equal_approx(float(loading.get("_display_progress")), 0.4):
		_pass("set_progress 不倒退")
	else:
		_fail("set_progress 发生倒退（got=%s）" % str(loading.get("_display_progress")))

	loading.set_progress("阶段B", 0.9)
	if is_equal_approx(float(loading.get("_display_progress")), 0.9):
		_pass("set_progress 可继续上升")
	else:
		_fail("set_progress 上升失败")

	loading.set("min_visible_sec", 0.0)
	loading.set("fade_out_sec", 0.0)
	loading.finish()
	if bool(loading.get("_finished")):
		_pass("finish 标记 _finished")
	else:
		_fail("finish 未标记 _finished")
	loading.finish()
	_pass("finish 幂等（二次调用不抛错）")

	loading.free()

	print("[loading_screen_view] 通过 %d / 失败 %d" % [_passed, _failed])
	if _failed > 0:
		for f in _failures:
			print("[loading_screen_view] FAIL: %s" % f)
	quit(1 if _failed > 0 else 0)


func _pass(label: String) -> void:
	_passed += 1
	print("[loading_screen_view] PASS: %s" % label)


func _fail(label: String) -> void:
	_failed += 1
	_failures.append(label)
	print("[loading_screen_view] FAIL: %s" % label)
