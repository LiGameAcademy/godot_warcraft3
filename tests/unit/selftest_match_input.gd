extends Node
var checks := 0
var failures := 0
var toggles := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)
func _ready() -> void:
	var selector := SelectorStub.new()
	add_child(selector)
	var aim := InteractionModule.new()
	add_child(aim)
	aim.configure({"unit_selector": selector})
	var commands := CommandInputModule.new()
	add_child(commands)
	commands.configure({"interaction": aim})
	var build := BuildModule.new()
	add_child(build)
	var card := CommandCardModule.new()
	add_child(card)
	var feedback := InteractionFeedback.new()
	add_child(feedback)
	feedback.configure(null, selector, null, null, "human", 0, Callable(), Callable())
	var input := MatchInputController.new()
	add_child(input)
	input.configure({"commands": commands, "interaction": aim, "build": build, "card": card, "selector": selector, "feedback": feedback})
	input.path_debug_toggle_requested.connect(func() -> void: toggles += 1)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(123, 45)
	input.handle_input(motion)
	check(input.last_screen_pos == motion.position and selector.pointers == 1, "pointer forwarded and position owned by input")
	aim.begin_aim(InteractionModule.Aim.MOVE)
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_RIGHT
	input.handle_input(click)
	check(not aim.is_aiming() and selector.pointers == 1, "right click cancels aim before selector")
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	aim.begin_aim(InteractionModule.Aim.ATTACK)
	input.handle_unhandled(key, true, false)
	check(not aim.is_aiming() and selector.enabled, "escape clears aim and restores selection")
	key.keycode = KEY_TAB
	key.shift_pressed = true
	input.handle_unhandled(key, true, false)
	check(selector.step == -1, "shift tab selects previous primary")
	key.shift_pressed = false
	key.keycode = KEY_F9
	input.handle_unhandled(key, true, false)
	check(toggles == 1, "debug toggle emitted once")
	key.echo = true
	input.handle_unhandled(key, true, false)
	check(toggles == 1, "key echo ignored")
	check(feedback.pointer_over_blocking_gui(Vector2(123, 45)), "GUI blocking uses supplied screen coordinate")
	check(not feedback.pointer_over_blocking_gui(Vector2.ZERO), "world pointer not blocked")
	var nav := NavigationModule.new()
	add_child(nav)
	nav.heightfield = FlatField.new()
	var picker := WorldPicker.new()
	picker.configure(null, nav)
	check(picker.ground_at_screen(Vector2.ZERO) == Vector3.INF, "missing camera safe")
	var hit := picker.ray_heightfield(Vector3(0, 2, 0), Vector3.DOWN)
	check(hit != Vector3.INF and absf(hit.y) < 0.001, "heightfield ray intersects flat ground")
	check(picker.ray_heightfield(Vector3(0, 2, 0), Vector3.RIGHT) == Vector3.INF, "ray above ground misses")
	input.shutdown()
	input.handle_input(motion)
	check(input.last_screen_pos == Vector2.ZERO, "shutdown rejects further input")
	print("selftest_match_input: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
class SelectorStub extends Node:
	var enabled := true
	var pointers := 0
	var step := 0
	func handle_pointer_event(_event: InputEvent) -> bool:
		pointers += 1
		return false
	func cycle_primary(value: int) -> bool:
		step = value
		return true
	func _hud_blocks_screen(pos: Vector2, _unused: bool) -> bool:
		return pos == Vector2(123, 45)
class FlatField extends Wc3Heightfield:
	func is_valid() -> bool:
		return true
	func interpolated_height(_x: float, _y: float) -> float:
		return 0.0
