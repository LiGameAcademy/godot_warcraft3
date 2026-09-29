extends RefCounted
## Read-only command line selection. Paths never alter project configuration.
static func report_path(default_path: String) -> String:
	return argument("--preview-report", default_path)

static func argument(flag: String, fallback: String = "") -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = arguments.find(flag)
	return arguments[index + 1] if index >= 0 and index + 1 < arguments.size() else fallback

static func preview_record(file_path: String) -> Dictionary:
	if not file_path.is_absolute_path() or file_path.get_extension().to_lower() != "scn":
		return {}
	return {"logical_path": file_path.get_file(), "scn_path": file_path.get_file(), "preview_absolute_path": file_path, "severity": "unknown", "issues": []}
