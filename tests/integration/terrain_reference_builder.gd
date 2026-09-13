extends MapTerrainLayer
# Independent pre-optimization mesh loop for numerical equivalence tests.
func _build_ground_mesh(
	hf: Wc3Heightfield,
	extended_flags: PackedByteArray,
	gap_mask: PackedByteArray,
	cliff_to_ground: PackedInt32Array = PackedInt32Array()
) -> int:
	var width: int = hf.width
	var height: int = hf.height
	if width < 2 or height < 2:
		push_error("MapTerrainLayer: heightfield 无效")
		return 0

	_ground.begin_build(true)
	var gap_count := 0
	var center: Vector2 = hf.center_offset
	var tile_size: float = hf.tile_size
	var map_w: int = width - 1
	var ground_tex: Array = hf.ground_textures
	var layer_heights: Array = hf.layer_heights
	var cliff_tex: Array = hf.cliff_textures
	_cell_first_vertex.resize(map_w * (height - 1))
	_cell_first_vertex.fill(-1)
	var next_vertex := 0

	for iy in range(height - 1):
		for ix in range(width - 1):
			var i00 := iy * width + ix
			var gi: int = iy * map_w + ix
			if gi >= 0 and gi < gap_mask.size() and gap_mask[gi] != 0:
				gap_count += 1
				continue

			var t_bl: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix, iy
			)
			var t_br: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix + 1, iy
			)
			var t_tl: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix, iy + 1
			)
			var t_tr: int = corner_texture(
				ground_tex, layer_heights, cliff_tex, cliff_to_ground, width, height, ix + 1, iy + 1
			)

			var slots: LayerSlots = _build_layers(
				t_bl, t_br, t_tl, t_tr,
				_var_at(hf.ground_variations, i00),
				extended_flags
			)

			var positions := PackedVector3Array([
				HeightfieldMesh.sample_vert(
					ix, iy, _corner_h(hf, i00), center, tile_size
				),
				HeightfieldMesh.sample_vert(
					ix + 1, iy, _corner_h(hf, i00 + 1), center, tile_size
				),
				HeightfieldMesh.sample_vert(
					ix, iy + 1, _corner_h(hf, i00 + width), center, tile_size
				),
				HeightfieldMesh.sample_vert(
					ix + 1, iy + 1, _corner_h(hf, i00 + width + 1), center, tile_size
				),
			])
			_ground.add_quad(positions, slots.tex, slots.variation)
			_cell_first_vertex[gi] = next_vertex
			next_vertex += 6

	_ground.commit_build()
	return gap_count
