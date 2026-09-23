extends RefCounted
## Shared background sources; adapters decide when a document/runtime change invalidates them.
static func load_baked(map_dir: String) -> Image:
	if map_dir.is_empty():
		return null
	for name in ["war3mapMap.png", "war3mapMap.tga"]:
		var path := RuntimeAssets.project_abs(map_dir.replace("\\", "/").path_join(name))
		if path.is_empty() or not FileAccess.file_exists(path):
			continue
		var image := Image.new()
		if image.load(path) == OK:
			return image
	return null
