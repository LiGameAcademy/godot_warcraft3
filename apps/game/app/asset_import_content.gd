extends RefCounted

const Validation: GDScript = preload("res://app/asset_cache_validation.gd")

## Validate the entire loose-content generation before publishing any runtime paths.
static func validate(content: Dictionary, validation: RefCounted = null) -> bool:
	var checker: RefCounted = validation if validation != null else Validation.new()
	return checker.validate_content(content)

## Opt-in measurements; no file writes or cache policy changes.
static func trace(stage: String, started_usec: int, count: int, details: Dictionary = {}) -> void:
	if "--asset-import-profile" in OS.get_cmdline_user_args():
		var record: Dictionary = {"stage": stage, "milliseconds": (Time.get_ticks_usec() - started_usec) / 1000.0, "count": count}
		record.merge(details)
		print("ASSET_IMPORT_PROFILE " + JSON.stringify(record))
