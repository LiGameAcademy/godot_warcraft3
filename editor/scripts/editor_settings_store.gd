class_name EditorSettingsStore
extends RefCounted
## 编辑器偏好：Godot ConfigFile，持久化到 user://（符合引擎习惯，不进版本库）。


const PATH := "user://editor_settings.cfg"
const SECTION := "editor"

## 与 MapLoader.ViewGridLevel 一致：0 none / 1 large / 2 medium / 3 small
const KEY_VIEW_GRID := "view_grid_level"
const DEFAULT_VIEW_GRID := 2 ## MEDIUM：中级白栅格


static func load_view_grid_level() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return DEFAULT_VIEW_GRID
	return clampi(int(cfg.get_value(SECTION, KEY_VIEW_GRID, DEFAULT_VIEW_GRID)), 0, 3)


static func save_view_grid_level(level: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(PATH) # 忽略失败，空文件亦可
	cfg.set_value(SECTION, KEY_VIEW_GRID, clampi(level, 0, 3))
	cfg.save(PATH)
