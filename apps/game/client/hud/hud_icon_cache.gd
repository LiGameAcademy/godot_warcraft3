class_name HudIconCache
extends RefCounted

## HUD 图标磁盘加载缓存（asset-converted 有 .gdignore，不能 ResourceLoader.load）。

var _cache: Dictionary = {}
## 测试注入：非空时优先走此 Callable(path) -> Texture2D。
var load_override: Callable = Callable()


func load_icon(rel_or_res: String) -> Texture2D:
	if load_override.is_valid():
		return load_override.call(rel_or_res) as Texture2D
	if rel_or_res.is_empty():
		return null
	var path := RuntimeAssets.converted_path(rel_or_res)
	if _cache.has(path):
		return _cache[path] as Texture2D
	var tex := RuntimeAssets.load_texture(path)
	if tex != null:
		_cache[path] = tex
	return tex


func clear() -> void:
	_cache.clear()
