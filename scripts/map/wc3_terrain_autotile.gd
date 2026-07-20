class_name Wc3TerrainAutotile
extends RefCounted
## WC3 地表「平滑过渡贴图」——以顶点（tilepoint）染色，以 Tile 为单位查图集。
##
## 编辑器点击某个顶点时写入 groundTexture；渲染时每个 Tile 看四角：
##   左下(BL)=1  右下(BR)=2  左上(TL)=4  右上(TR)=8
## 对某一种地表类型，把「有该类型的角」权重相加 → 图集编号 0..15，
## 直接取素材表中预先画好的过渡块（不必拼接 1 与 8）。
##
## 多纹理时：索引最小的类型做底层（整格 fill variation）；
## 其余类型各算自己的 bitmask，按 alpha 叠在上层（mdx-m3-viewer / 经典客户端同款）。
##
## 注意：WC3 官方图集的 bit 布局与「BL=1」的教学口诀不同，实际采样用 ATLAS_* 常量
##（与 mdx-m3-viewer 一致）：BR=1, BL=2, TR=4, TL=8。


const ATLAS_W := 512
const ATLAS_H := 256

## 与官方图集格子对应的角权重（不要改成教学口诀里的 BL=1）
const ATLAS_BR := 1
const ATLAS_BL := 2
const ATLAS_TR := 4
const ATLAS_TL := 8


## 返回 { mesh: ArrayMesh, ground_tilesets: Array, gap_count: int }
static func build_ground_mesh(hf: Dictionary, extended_flags: PackedByteArray) -> Dictionary:
	var meta := HeightfieldMeshBuilder.read_heightfield_meta(hf)
	var width: int = meta["width"]
	var height: int = meta["height"]
	var heights: Array = meta["heights"]
	var ground_tex: Array = meta["ground_textures"]
	var ground_var: Array = meta["ground_variations"]
	var layer_heights: Array = meta["layer_heights"]
	var flags: Array = meta["flags"]
	var center: Vector2 = meta["center"]
	var tile_size: float = meta["tile_size"]

	if width < 2 or height < 2 or heights.size() < width * height:
		push_error("Wc3TerrainAutotile: heightfield 尺寸无效")
		return {}

	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array() # 格内局部坐标 0..1（供调试；着色器主要用预计算 UV）
	var uv2s := PackedVector2Array() # 未用，占位
	var custom0 := PackedFloat32Array() # 每顶点：tex0,tex1,tex2,tex3（0-based 层；-1=无）
	var custom1 := PackedFloat32Array() # 每顶点：var0,var1,var2,var3（图集编号）
	var indices := PackedInt32Array()
	var gap_count := 0

	for iy in range(height - 1):
		for ix in range(width - 1):
			# 悬崖 / 斜坡格：不生成地面三角，留缝给后续模型
			if Wc3CliffTiles.should_leave_gap(layer_heights, flags, width, ix, iy):
				gap_count += 1
				continue

			var i00 := iy * width + ix
			var i10 := i00 + 1
			var i01 := i00 + width
			var i11 := i01 + 1

			# 四角纹理（顶点染色）
			var t_bl := _tex_at(ground_tex, i00)
			var t_br := _tex_at(ground_tex, i10)
			var t_tl := _tex_at(ground_tex, i01)
			var t_tr := _tex_at(ground_tex, i11)

			var layers := _build_layers(
				t_bl, t_br, t_tl, t_tr,
				_var_at(ground_var, i00),
				extended_flags
			)

			var p_bl := HeightfieldMeshBuilder.sample_vert(ix, iy, float(heights[i00]), center, tile_size)
			var p_br := HeightfieldMeshBuilder.sample_vert(ix + 1, iy, float(heights[i10]), center, tile_size)
			var p_tl := HeightfieldMeshBuilder.sample_vert(ix, iy + 1, float(heights[i01]), center, tile_size)
			var p_tr := HeightfieldMeshBuilder.sample_vert(ix + 1, iy + 1, float(heights[i11]), center, tile_size)

			var n0 := (p_tl - p_bl).cross(p_tr - p_bl).normalized()
			var n1 := (p_tr - p_bl).cross(p_br - p_bl).normalized()
			if n0.is_zero_approx():
				n0 = Vector3.UP
			if n1.is_zero_approx():
				n1 = Vector3.UP

			# 三角形：BL-TL-TR，BL-TR-BR；局部 UV 与 viewer a_position 一致
			_emit_tri(
				verts, norms, uvs, uv2s, custom0, custom1, indices,
				p_bl, p_tl, p_tr, n0,
				Vector2(0, 0), Vector2(0, 1), Vector2(1, 1),
				layers
			)
			_emit_tri(
				verts, norms, uvs, uv2s, custom0, custom1, indices,
				p_bl, p_tr, p_br, n1,
				Vector2(0, 0), Vector2(1, 1), Vector2(1, 0),
				layers
			)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	var fmt := (
		(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)

	return {
		"mesh": mesh,
		"ground_tilesets": meta["ground_tilesets"],
		"gap_count": gap_count,
	}


## 对某一地表类型，根据四角是否属于该类型累加 bitmask（教学口诀：BL1 BR2 TL4 TR8）。
## 返回值同时给出官方图集编号（ATLAS_* 布局）。
static func corner_mask_for_type(t_bl: int, t_br: int, t_tl: int, t_tr: int, terrain_type: int) -> Dictionary:
	var pedagogical := 0 # BL=1 BR=2 TL=4 TR=8（便于对照你的描述）
	var atlas := 0 # 官方图集
	if t_bl == terrain_type:
		pedagogical |= 1
		atlas |= ATLAS_BL
	if t_br == terrain_type:
		pedagogical |= 2
		atlas |= ATLAS_BR
	if t_tl == terrain_type:
		pedagogical |= 4
		atlas |= ATLAS_TL
	if t_tr == terrain_type:
		pedagogical |= 8
		atlas |= ATLAS_TR
	return {"pedagogical": pedagogical, "atlas": atlas}


static func build_tileset_array(ground_tilesets: Array, tiles: Wc3TerrainTiles) -> Texture2DArray:
	var images: Array[Image] = []
	for i in range(ground_tilesets.size()):
		var png := tiles.png_for_ground_index(ground_tilesets, i)
		var img := RuntimeAssets.load_image(png)
		if img == null:
			push_warning("Wc3TerrainAutotile: 缺少贴图 %s" % png)
			img = Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.4, 0.45, 0.35, 1))
		else:
			img = _pad_to_atlas(img)
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		images.append(img)

	var tex := Texture2DArray.new()
	var err := tex.create_from_images(images)
	if err != OK:
		push_error("Wc3TerrainAutotile: Texture2DArray 失败 %s" % error_string(err))
		return null
	return tex


static func build_extended_flags(ground_tilesets: Array, tiles: Wc3TerrainTiles) -> PackedByteArray:
	var extended := PackedByteArray()
	extended.resize(ground_tilesets.size())
	for i in range(ground_tilesets.size()):
		var png := tiles.png_for_ground_index(ground_tilesets, i)
		var img := RuntimeAssets.load_image(png)
		extended[i] = 1 if (img and img.get_width() > img.get_height()) else 0
	return extended


static func _build_layers(
	t_bl: int, t_br: int, t_tl: int, t_tr: int,
	ground_variation: int,
	extended_flags: PackedByteArray
) -> Dictionary:
	var unique: Array[int] = []
	for t in [t_bl, t_br, t_tl, t_tr]:
		if not unique.has(t):
			unique.append(t)
	unique.sort()

	# tex: 0-based 层索引；-1 = 该槽未使用
	var tex := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
	var vars := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])

	# 底层：整格 fill（variation 来自西南角 tilepoint）
	var base: int = unique[0]
	tex[0] = float(base)
	vars[0] = float(_fill_variation(base, ground_variation, extended_flags))

	# 上层：每种其余纹理用四角 bitmask 查过渡块
	var slot := 1
	for i in range(1, unique.size()):
		if slot >= 4:
			break
		var t: int = unique[i]
		var mask: Dictionary = corner_mask_for_type(t_bl, t_br, t_tl, t_tr, t)
		var atlas_id: int = int(mask["atlas"])
		if atlas_id == 0:
			continue
		tex[slot] = float(t)
		vars[slot] = float(atlas_id)
		slot += 1

	return {"tex": tex, "var": vars}


static func _fill_variation(ground_texture: int, variation: int, extended_flags: PackedByteArray) -> int:
	var extended := false
	if ground_texture >= 0 and ground_texture < extended_flags.size():
		extended = extended_flags[ground_texture] != 0
	# 与 mdx-m3-viewer getVariation 一致
	if extended:
		if variation < 16:
			return 16 + variation
		if variation == 16:
			return 15
		return 0
	if variation == 0:
		return 0
	return 15


static func _pad_to_atlas(src: Image) -> Image:
	if src.get_width() == ATLAS_W and src.get_height() == ATLAS_H:
		return src.duplicate()
	var out := Image.create(ATLAS_W, ATLAS_H, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	out.blit_rect(
		src,
		Rect2i(0, 0, mini(src.get_width(), ATLAS_W), mini(src.get_height(), ATLAS_H)),
		Vector2i(0, 0)
	)
	return out


static func _tex_at(ground_tex: Array, i: int) -> int:
	if i < 0 or i >= ground_tex.size():
		return 0
	return int(ground_tex[i])


static func _var_at(ground_var: Array, i: int) -> int:
	if ground_var.is_empty() or i < 0 or i >= ground_var.size():
		return 0
	return int(ground_var[i])


static func _emit_tri(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	custom0: PackedFloat32Array,
	custom1: PackedFloat32Array,
	indices: PackedInt32Array,
	pa: Vector3, pb: Vector3, pc: Vector3,
	normal: Vector3,
	uva: Vector2, uvb: Vector2, uvc: Vector2,
	layers: Dictionary
) -> void:
	_append_vert(verts, norms, uvs, uv2s, custom0, custom1, indices, pa, normal, uva, layers)
	_append_vert(verts, norms, uvs, uv2s, custom0, custom1, indices, pb, normal, uvb, layers)
	_append_vert(verts, norms, uvs, uv2s, custom0, custom1, indices, pc, normal, uvc, layers)


static func _append_vert(
	verts: PackedVector3Array,
	norms: PackedVector3Array,
	uvs: PackedVector2Array,
	uv2s: PackedVector2Array,
	custom0: PackedFloat32Array,
	custom1: PackedFloat32Array,
	indices: PackedInt32Array,
	pos: Vector3,
	normal: Vector3,
	local_uv: Vector2,
	layers: Dictionary
) -> void:
	var base := verts.size()
	verts.append(pos)
	norms.append(normal)
	uvs.append(local_uv)
	uv2s.append(Vector2.ZERO)
	var tex: PackedFloat32Array = layers["tex"]
	var vars: PackedFloat32Array = layers["var"]
	for k in range(4):
		custom0.append(tex[k])
		custom1.append(vars[k])
	indices.append(base)
