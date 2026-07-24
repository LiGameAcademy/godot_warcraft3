class_name HeightfieldMeshBuilder
extends RefCounted

## 表现层格点采样。meta 请用 Wc3Heightfield.to_build_meta() / build_meta_from_dict()。


static func sample_vert(ix: int, iy: int, h: float, center: Vector2, tile_size: float) -> Vector3:
	var xy := Wc3Coords.tilepoint_wc3(ix, iy, center, tile_size)
	return Wc3Coords.wc3_xy_to_godot(xy.x, xy.y, h)


## 兼容旧调用：委托数据层，不再维护第二份 meta 逻辑。
static func read_heightfield_meta(hf: Dictionary) -> Dictionary:
	return Wc3Heightfield.build_meta_from_dict(hf)
