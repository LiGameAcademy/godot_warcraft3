extends Node

## Runtime counterpart of tools/workspace/check_layout.py (canonical source boundary gate).
func _ready() -> void:
	var checks := 0
	var failures := 0
	for path in [
		"res://app/game_director.gd",
		"res://client/selection/unit_selector.gd",
		"res://addons/rts_foundation/infra/app_log.gd",
		"res://addons/rts_content/runtime/content_registry.gd",
		"res://addons/rts_map/presentation/map_loader.gd",
		"res://addons/rts_gameplay/match/game_session.gd",
		"res://addons/rts_gameplay/entities/commands/command_request.gd",
		"res://addons/rts_gameplay/features/combat/actions/attack_controller.gd",
	]:
		checks += 1
		if not FileAccess.file_exists(path):
			failures += 1
			push_error("Missing canonical runtime resource: " + path)
	checks += 1
	if DirAccess.dir_exists_absolute("res://addons/rts_runtime"):
		failures += 1
		push_error("Transitional monolithic package still exists")
	print("selftest_dependency_bounds: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
