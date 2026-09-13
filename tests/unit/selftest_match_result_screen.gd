extends Node

const Screen = preload("res://game/scripts/presentation/match_result_screen.gd")
var failures := 0
var checks := 0
var exit_events := 0
var restart_events := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("MATCH RESULT SCREEN: " + label)

func _ready() -> void:
	for data in [
		{"draw": false, "winner_team": 0, "title": "胜利", "file": "victory"},
		{"draw": false, "winner_team": 1, "title": "失败", "file": "defeat"},
		{"draw": true, "winner_team": -1, "title": "平局", "file": "draw"},
	]:
		var screen := Screen.new()
		add_child(screen)
		screen.show_result(data, 0)
		screen.exit_requested.connect(func() -> void: exit_events += 1)
		screen.restart_requested.connect(func() -> void: restart_events += 1)
		check(screen.title_label.text == data.title, "显示" + str(data.title))
		check(screen.exit_button.has_focus() and not screen.exit_button.disabled, "退出按钮可聚焦操作")
		screen.exit_button.pressed.emit()
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var screenshot := get_viewport().get_texture().get_image()
			check(screenshot.save_png("res://tmp/match-result-" + str(data.file) + ".png") == OK, "保存结算画面")
		check(screen.restart_button.text == "重新开始" and not screen.restart_button.disabled, "显示可用的重开按钮")
		screen.restart_button.pressed.emit()
		screen.queue_free()
		await get_tree().process_frame
	check(exit_events == 3, "三种结局均发出退出请求")
	check(restart_events == 3, "三种结局均发出重开请求")
	print("selftest_match_result_screen: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
