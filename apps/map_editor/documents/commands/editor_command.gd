class_name EditorCommand
extends RefCounted

## 编辑命令基类。execute 改数据；undo 恢复。表现重建由 History / MapEditor 触发。


func get_label() -> String:
	return "Command"


## 是否影响悬崖/水面（决定 rebuild 路径）。
func affects_cliffs_water() -> bool:
	return false


## 是否影响装饰物层（撤销/重做时刷新 doodads Present）。
func affects_doodads() -> bool:
	return false


## 是否影响单位层（撤销/重做时刷新 units Present）。
func affects_units() -> bool:
	return false


func execute(_document) -> void:
	pass


func undo(_document) -> void:
	pass
