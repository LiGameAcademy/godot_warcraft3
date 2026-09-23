extends Node

## Package smoke test, not a full gameplay/editor entry point yet.
func _ready() -> void:
	var session_script = load("res://addons/rts_runtime/game/match/game_session.gd")
	if session_script == null or not session_script.can_instantiate():
		push_error("Runtime package failed to load GameSession")
		get_tree().quit(1)
		return
	var session = session_script.new()
	var stock = session.ensure_stock(0)
	if stock == null:
		get_tree().quit(1)
		return
	var result = session.evaluate_match(null)
	if not result is Dictionary or not result.has("finished"):
		get_tree().quit(1)
		return
	print("runtime package smoke PASS: GameSession + PlayerStock")
	if DisplayServer.get_name() == "headless":
		get_tree().quit(0)
