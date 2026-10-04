extends RefCounted

## Validate the entire loose-content generation before publishing any runtime paths.
static func validate(content: Dictionary) -> bool:
	if content.is_empty():
		return true
	if not content.get("root") is String or not content.get("files") is Array or content.files.is_empty():
		return false
	var root: String = str(content.root).replace("\\", "/").simplify_path()
	if not root.is_absolute_path() or not DirAccess.dir_exists_absolute(root):
		return false
	var seen: Dictionary[String, bool] = {}
	for entry: Variant in content.files:
		if not entry is Dictionary or not entry.get("path") is String or not entry.get("sha256") is String:
			return false
		var relative: String = str(entry.path).replace("\\", "/")
		if relative.is_empty() or relative.is_absolute_path() or relative.split("/").has("..") or seen.has(relative.to_lower()):
			return false
		seen[relative.to_lower()] = true
		var filename: String = root.path_join(relative)
		if not FileAccess.file_exists(filename) or FileAccess.get_sha256(filename) != str(entry.sha256):
			return false
	return true
