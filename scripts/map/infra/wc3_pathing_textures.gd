class_name Wc3PathingTextures
extends RefCounted
## PathTextures\\*.tga 缓存。通道：R=不可走 G=不可飞 B=不可建（>250）。


static var _cache: Dictionary = {} # logical lower → Image


static func clear_cache() -> void:
	_cache.clear()


static func is_valid_path_tex(path_tex: String) -> bool:
	var s := path_tex.strip_edges()
	if s.is_empty() or s == "_" or s.to_lower() == "none":
		return false
	return true


static func load_image(path_tex: String) -> Image:
	if not is_valid_path_tex(path_tex):
		return null
	var logical := path_tex.replace("\\", "/")
	while logical.begins_with("/"):
		logical = logical.substr(1)
	var key := logical.to_lower()
	if _cache.has(key):
		return _cache[key] as Image
	var disk := RuntimeAssets.resolve(logical)
	if disk.is_empty():
		# 兼容仅写文件名
		disk = RuntimeAssets.resolve("PathTextures/%s" % logical.get_file())
	if disk.is_empty():
		return null
	var img: Image = null
	if disk.to_lower().ends_with(".tga"):
		img = Wc3Tga.load_file(disk)
	if img == null:
		img = RuntimeAssets.load_image(disk)
	if img == null:
		return null
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_cache[key] = img
	return img
