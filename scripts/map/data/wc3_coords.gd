class_name Wc3Coords
extends RefCounted
## Warcraft III 地图坐标 ↔ Godot 坐标。
## WC3：X/Y 水平面，Z 高度；Godot：Y-up，Z 朝向用 -WC3.Y。

const TILE_SIZE := 128.0
## 寻路格边长（WC3 单位）。PathTextures\4x4* ≈ 1 地形格。
const PATHING_CELL := 32.0
## 与 tools/asset-convert 中 MODEL_SCALE 一致，便于日后挂 GLB。
const WORLD_SCALE := 0.01

## 渲染层：地形收 UberSplat Decal；单位不收，避免脚印印到墙体上。
const RENDER_LAYER_TERRAIN := 1 ## bit 0（Godot 默认）
const RENDER_LAYER_UNITS := 2 ## bit 1

## war3map.w3e tilepoint flags
## 位分配（不要冲突；改前先看这里）：
##   bit 0 (1)    FLAG_WATER
##   bit 1 (2)    FLAG_BLIGHT       — 污染（亡灵的腐地）
##   bit 2 (4)    FLAG_RAMP
##   bit 3 (8)    FLAG_BOUNDARY     — Nothing 笔刷边界（flags 字节 0x80 / boundary2）
##   bit 4 (16)   FLAG_MAP_EDGE     — 实用区外缘（water short 0x4000 / boundary1）
##   bit 5..31    保留
const FLAG_WATER := 1
const FLAG_BLIGHT := 2
const FLAG_RAMP := 4
const FLAG_BOUNDARY := 8
const FLAG_MAP_EDGE := 16

## 新建图默认 cameraBoundsComplements（Blizzard / HiveWE：L6 R6 B4 T8，合计每轴 −12）
const DEFAULT_BOUNDS_LEFT := 6
const DEFAULT_BOUNDS_RIGHT := 6
const DEFAULT_BOUNDS_BOTTOM := 4
const DEFAULT_BOUNDS_TOP := 8


## 不可玩区判定：cell 以左下角（BL）flag 为准（HiveWE cell-as-corner）。
static func is_unplayable_cell_flags(bl_flags: int) -> bool:
	return (bl_flags & (FLAG_BOUNDARY | FLAG_MAP_EDGE)) != 0


static func default_camera_bounds_complements() -> Dictionary:
	return {
		"left": DEFAULT_BOUNDS_LEFT,
		"right": DEFAULT_BOUNDS_RIGHT,
		"bottom": DEFAULT_BOUNDS_BOTTOM,
		"top": DEFAULT_BOUNDS_TOP,
	}


static func wc3_to_godot(wc3: Vector3) -> Vector3:
	return Vector3(wc3.x, wc3.z, -wc3.y) * WORLD_SCALE


static func wc3_xy_to_godot(x: float, y: float, z: float = 0.0) -> Vector3:
	return wc3_to_godot(Vector3(x, y, z))


## Godot 世界点 → WC3 (x,y 水平, z 高度)。与 wc3_to_godot 互逆。
static func godot_to_wc3(g: Vector3) -> Vector3:
	var inv := 1.0 / WORLD_SCALE
	return Vector3(g.x * inv, -g.z * inv, g.y * inv)


static func godot_to_wc3_xy(g: Vector3) -> Vector2:
	var w := godot_to_wc3(g)
	return Vector2(w.x, w.y)


static func tilepoint_wc3(
	ix: int,
	iy: int,
	center_offset: Vector2,
	tile_size: float = TILE_SIZE
) -> Vector2:
	return Vector2(
		center_offset.x + float(ix) * tile_size,
		center_offset.y + float(iy) * tile_size
	)


static func yaw_wc3_to_godot(angle_rad: float) -> float:
	## Doodad / 装饰物：WC3 绕 Z → Godot 绕 Y，并补偿 -Y 镜像（-a+π）。
	## 单位模型请用 yaw_wc3_unit_to_godot（MDX→GLTF 后前进轴为本地 +X）。
	return -angle_rad + PI


static func yaw_wc3_unit_to_godot(angle_rad: float) -> float:
	## 单位 / 建筑：与 UnitNavigator._face_dir 一致。
	## 转换后模型本地前进为 +X；yaw = WC3 facing（atan2(dy,dx)），勿再 -a+π。
	## -a+π 会在东/西向（0°/180°）多转 180°，北/南向碰巧一致。
	return angle_rad
