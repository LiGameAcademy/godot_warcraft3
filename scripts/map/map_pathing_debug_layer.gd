class_name MapPathingDebugLayer
extends Node3D
## 寻路调试：GPU 三级栅格挂在地面 shader（贴合地形/斜坡表面）。
## 小灰(32) → 中白(128) → 大黄(512)。


## 大黄网 512u
@export var show_tile_grid: bool = true
## 中白网 128u
@export var show_path_grid: bool = true
## 小灰网 32u
@export var show_fine_grid: bool = true

var _terrain: MapTerrainLayer


func build(_ctx) -> void:
	_terrain = get_node_or_null("../Terrain") as MapTerrainLayer
	_apply_gpu_grid(true)
	print(
		"Pathing debug (GPU): tile=%s path=%s fine=%s"
		% [show_tile_grid, show_path_grid, show_fine_grid]
	)


func _apply_gpu_grid(enabled: bool) -> void:
	if _terrain == null:
		return
	var t := show_tile_grid if enabled else false
	var p := show_path_grid if enabled else false
	var f := show_fine_grid if enabled else false
	_terrain.set_debug_grid(t, p, f)
