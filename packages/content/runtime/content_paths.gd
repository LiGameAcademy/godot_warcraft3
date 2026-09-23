class_name ContentPaths
extends RefCounted

## External loose assets are a deployment input, independent of the application res:// root.
static func resolve(path: String) -> String:
	if path.begins_with("res://assets/"):
		var root := str(ProjectSettings.get_setting("warcraft3/asset_root", ""))
		if not root.is_empty():
			return root.path_join(path.trim_prefix("res://assets/")).replace("\\", "/")
	return ProjectSettings.globalize_path(path).replace("\\", "/")
