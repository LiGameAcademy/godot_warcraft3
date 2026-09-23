extends Node

## D4 游戏应用最小启动桩。完整对局仍以仓库根 project 为准，直至切流完成。

func _ready() -> void:
	print("apps/game boot ok — sync packages with tools/workspace/Sync-Packages.ps1")
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		get_tree().quit(0)
