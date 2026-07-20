class_name MapCliffLayer
extends Node3D
## 悬崖层：独立 Mesh（非高度图地表）。占位为竖直面，后续换官方 cliff 模型瓦片。


@onready var _cliffs: MeshInstance3D = $Mesh


func build(hf: Dictionary, tiles: Wc3TerrainTiles) -> void:
	_cliffs.mesh = null
	var built := Wc3CliffBuilder.build_cliff_mesh(hf)
	if built.is_empty():
		return

	var mesh: ArrayMesh = built["mesh"]
	var surface_cliff: PackedInt32Array = built["surface_cliff"]
	var cliff_tilesets: Array = built["cliff_tilesets"]
	_cliffs.mesh = mesh

	for s in range(mesh.get_surface_count()):
		var cliff_idx := surface_cliff[s] if s < surface_cliff.size() else 0
		var mat := StandardMaterial3D.new()
		mat.roughness = 0.95
		mat.metallic = 0.0
		var png := tiles.png_for_cliff_index(cliff_tilesets, cliff_idx)
		var tex := RuntimeAssets.load_texture(png) if not png.is_empty() else null
		if tex:
			mat.albedo_texture = tex
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		else:
			mat.albedo_color = Color(0.35, 0.32, 0.28)
		_cliffs.set_surface_override_material(s, mat)
