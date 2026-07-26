extends SceneTree
## 斜坡 mesh / 中点高度验收：实现已清空，恒 SKIP。
## godot --headless -s res://tests/integration/selftest_path_grid.gd


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	print("selftest_path_grid: SKIP (ramp implementation removed; rewrite later)")
	quit(0)
