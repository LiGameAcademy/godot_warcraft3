extends Node

## D2：CommandRequest → CommandRouter.submit_request 契约（无场景依赖）。

var failures := 0
var checks := 0


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("COMMAND REQUEST: " + label)


func _ready() -> void:
	var router := CommandRouter.new()
	var empty := CommandRequest.move_to([], Vector2(1, 2))
	var r0 := router.submit_request(empty)
	check(r0.ok == false, "空单位失败")
	check(r0.error == CommandRequest.ErrorCode.EMPTY_SELECTION, "空单位错误码")

	var dummy := Node3D.new()
	add_child(dummy)
	var bad_goal := CommandRequest.move_to([dummy], Vector2.INF)
	var r1 := router.submit_request(bad_goal)
	check(r1.ok == false, "无效落点失败")
	check(r1.error == CommandRequest.ErrorCode.INVALID_GOAL, "无效落点错误码")
	var queue := router.queue_for(dummy)
	var original := UnitOrder.move(Vector2(10, 20))
	queue.set_current(original)
	var wrong := CommandRequest.stop_units([dummy], UnitOrder.Source.PANEL, 1)
	check(router.submit_request(wrong).error == CommandRequest.ErrorCode.WRONG_PLAYER, "wrong owner rejected")
	var append := CommandRequest.move_to([dummy], Vector2.ZERO)
	append.queue_append = true
	check(router.submit_request(append).error == CommandRequest.ErrorCode.APPEND_UNSUPPORTED, "unsupported append rejected")
	check(queue.current == original, "rejected requests preserve current order")
	check(router.submit_request(CommandRequest.move_to([dummy], Vector2(NAN, 0))).error == CommandRequest.ErrorCode.INVALID_GOAL, "NaN rejected")
	dummy.queue_free()

	var stop_req := CommandRequest.stop_units([])
	check(stop_req.kind == UnitOrder.Kind.STOP, "stop kind")
	var atk := CommandRequest.attack_target([], null)
	check(atk.kind == UnitOrder.Kind.ATTACK, "attack kind")

	var fail := CommandResult.fail(CommandRequest.ErrorCode.REJECTED, "x")
	check(fail.ok == false and fail.detail == "x", "CommandResult.fail")

	print("selftest_command_request: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
