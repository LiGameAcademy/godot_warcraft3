extends Node3D

## 已废弃。场景壳用 `editor_shell.gd`，总管用子节点 `editor.gd`（MapEditor）。
func _ready() -> void:
	push_warning("editor_app.gd 已废弃，请打开 editor_main.tscn（Editor 子节点）")
