class_name MapWaterLayer
extends Node3D
## 水体层：复用 HeightfieldMesh，高度取 waterHeights，仅绘制含水格。


@onready var _water: HeightfieldMesh = $Surface


func build(hf: Dictionary) -> void:
	_water.clear_mesh()
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var water_heights: Array = meta["water_heights"]
	var heights: Array = meta["heights"]
	var flags: Array = meta["flags"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]

	# 旧 heightfield 无 waterHeights 时回退地面高度
	var use_heights: Array = water_heights if not water_heights.is_empty() else heights
	if width < 2 or height < 2 or use_heights.is_empty():
		return

	var mesh := HeightfieldMeshBuilder.build_uniform_mesh(
		width,
		height,
		use_heights,
		center,
		tile_size,
		func(ix: int, iy: int) -> bool:
			var i00 := iy * width + ix
			return i00 < flags.size() and (int(flags[i00]) & 1) != 0
	)
	if mesh.get_surface_count() == 0:
		return

	_water.set_array_mesh(mesh)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.42, 0.72, 0.72)
	mat.roughness = 0.25
	mat.metallic = 0.05
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water.apply_uniform_material(mat)
