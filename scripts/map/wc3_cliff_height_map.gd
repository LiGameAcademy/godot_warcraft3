class_name Wc3CliffHeightMap
extends RefCounted
## 构建悬崖顶点变形用 groundHeight 纹理（对齐 mdx-m3-viewer cliffHeightMap）。


static func build_image(hf: Dictionary, meta: Dictionary = {}) -> Image:
	if meta.is_empty():
		meta = Wc3Heightfield.build_meta_from_dict(hf)
	var tp_w: int = meta["width"]
	var tp_h: int = meta["height"]
	var heights: Array = meta["heights"]
	var layers: Array = meta["layer_heights"]

	var img := Image.create(tp_w, tp_h, false, Image.FORMAT_RF)
	for iy in range(tp_h):
		for ix in range(tp_w):
			var i := iy * tp_w + ix
			var layer := int(layers[i]) if i < layers.size() else 2
			var final_h := float(heights[i]) if i < heights.size() else 0.0
			# final = ground*128 + (layer-2)*128 → ground（tile 单位）
			var ground_tiles := (final_h - float(layer - 2) * 128.0) / 128.0
			img.set_pixel(ix, iy, Color(ground_tiles, 0.0, 0.0, 1.0))
	return img


static func build_texture(hf: Dictionary, meta: Dictionary = {}) -> ImageTexture:
	var img := build_image(hf, meta)
	return ImageTexture.create_from_image(img)
