class_name Wc3Tga
extends RefCounted
## 未压缩 TGA（WC3 PathTextures 常用 24/32bpp type 2）→ Image。
## Godot Image.load 对 .tga 支持不完整时的回退。


static func load_file(abs_path: String) -> Image:
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		return null
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	if bytes.is_empty():
		return null
	return decode(bytes)


static func decode(bytes: PackedByteArray) -> Image:
	if bytes.size() < 18:
		return null
	var id_len: int = bytes[0]
	var color_map_type: int = bytes[1]
	var image_type: int = bytes[2]
	if color_map_type != 0:
		return null
	# 2 = uncompressed true-color；10 = RLE（暂不支持，PathTextures 多为 type 2）
	if image_type != 2:
		return null
	var width: int = bytes[12] | (bytes[13] << 8)
	var height: int = bytes[14] | (bytes[15] << 8)
	var bpp: int = bytes[16]
	var desc: int = bytes[17]
	if width <= 0 or height <= 0:
		return null
	if bpp != 24 and bpp != 32:
		return null
	var src_off: int = 18 + id_len
	var channels: int = int(bpp / 8.0)
	var need: int = width * height * channels
	if bytes.size() < src_off + need:
		return null
	var top_origin: bool = (desc & 0x20) != 0
	var rgba := PackedByteArray()
	rgba.resize(width * height * 4)
	for row in range(height):
		var src_row: int = row if top_origin else (height - 1 - row)
		for col in range(width):
			var si: int = src_off + (src_row * width + col) * channels
			var b: int = bytes[si]
			var g: int = bytes[si + 1]
			var r: int = bytes[si + 2]
			var a: int = bytes[si + 3] if channels == 4 else 255
			var di: int = (row * width + col) * 4
			rgba[di] = r
			rgba[di + 1] = g
			rgba[di + 2] = b
			rgba[di + 3] = a
	var img := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, rgba)
	return img
