class_name UiSurface
extends Node

## UI 壳契约：对局 HUD / 加载屏等实现本类或提供同名方法后注册到 UiManager。
## 默认空实现，便于渐进接入；子类覆盖所需 push_*。

func surface_id() -> StringName:
	return &""


func on_surface_activated() -> void:
	pass


func on_surface_deactivated() -> void:
	pass


func push_resources(_vm: Dictionary) -> void:
	pass


func push_selection(_vm: Dictionary) -> void:
	pass


func push_command_card(_entries: Array) -> void:
	pass


func push_status(_text: String) -> void:
	pass


func show_tip(_text: String) -> void:
	pass
