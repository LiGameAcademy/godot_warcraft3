extends Node

## Runtime counterpart of tools/workspace/check_layout.py (canonical source boundary gate).
func _ready() -> void:
	var checks := 0
	var failures := 0
	for path in [
		"res://app/game_director.gd",
		"res://client/selection/unit_selector.gd",
		"res://packages/foundation/infra/app_log.gd",
		"res://packages/content/runtime/content_registry.gd",
		"res://packages/map/presentation/map_loader.gd",
		"res://packages/gameplay/match/game_session.gd",
		"res://packages/gameplay/entities/commands/command_request.gd",
		"res://packages/gameplay/features/combat/actions/attack_controller.gd",
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
