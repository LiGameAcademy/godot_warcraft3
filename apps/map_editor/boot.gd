extends Node

## D4 地图编辑器应用最小启动桩。

func _ready() -> void:
	print("apps/map_editor boot ok — sync packages with tools/workspace/Sync-Packages.ps1")
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		get_tree().quit(0)
