extends CanvasLayer

signal exit_requested
signal restart_requested

var title_label: Label
var exit_button: Button
var restart_button: Button

func show_result(result: Dictionary, local_team: int) -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.035, 0.055, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 24)
	center.add_child(panel)
	title_label = Label.new()
	title_label.text = "平局" if bool(result.draw) else ("胜利" if int(result.winner_team) == local_team else "失败")
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	panel.add_child(title_label)
	var detail := Label.new()
	detail.text = "所有参战队伍的建筑均已被摧毁。" if bool(result.draw) else "对局结束，败方队伍的建筑已全部被摧毁。"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(detail)
	restart_button = Button.new()
	restart_button.text = "重新开始"
	restart_button.custom_minimum_size = Vector2(280, 52)
	restart_button.pressed.connect(func() -> void:
		restart_button.disabled = true
		restart_requested.emit()
	)
	panel.add_child(restart_button)
	exit_button = Button.new()
	exit_button.text = "退出游戏"
	exit_button.custom_minimum_size = Vector2(280, 52)
	exit_button.pressed.connect(func() -> void: exit_requested.emit())
	panel.add_child(exit_button)
	exit_button.grab_focus()
