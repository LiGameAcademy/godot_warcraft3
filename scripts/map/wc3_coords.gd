class_name Wc3Coords
extends RefCounted
## Warcraft III 地图坐标 ↔ Godot 坐标。
## WC3：X/Y 水平面，Z 高度；Godot：Y-up，Z 朝向用 -WC3.Y。

const TILE_SIZE := 128.0
## 与 tools/asset-convert 中 MODEL_SCALE 一致，便于日后挂 GLB。
const WORLD_SCALE := 0.01

## war3map.w3e tilepoint flags
const FLAG_WATER := 1
const FLAG_RAMP := 4


static func wc3_to_godot(wc3: Vector3) -> Vector3:
	return Vector3(wc3.x, wc3.z, -wc3.y) * WORLD_SCALE


static func wc3_xy_to_godot(x: float, y: float, z: float = 0.0) -> Vector3:
	return wc3_to_godot(Vector3(x, y, z))


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
	## WC3 绕 Z 的朝向 → Godot 绕 Y；再补偿 -Y 镜像。
	return -angle_rad + PI
