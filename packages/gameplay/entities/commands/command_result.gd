class_name CommandResult
extends RefCounted

## 命令请求的接受结果（D2）。失败时无部分扣费/入队副作用由各 issue_* 自行保证。

var ok: bool = false
var error: int = CommandRequest.ErrorCode.REJECTED
var moved: int = 0
var failed: int = 0
var affected: int = 0
var goal_wc3: Vector2 = Vector2.INF
var detail: String = ""


static func success(affected_count: int = 0, goal: Vector2 = Vector2.INF) -> CommandResult:
	var r := CommandResult.new()
	r.ok = true
	r.error = CommandRequest.ErrorCode.OK
	r.affected = affected_count
	r.moved = affected_count
	r.goal_wc3 = goal
	return r


static func from_move_dict(d: Dictionary) -> CommandResult:
	var r := CommandResult.new()
	r.moved = int(d.get("moved", 0))
	r.failed = int(d.get("failed", 0))
	r.goal_wc3 = d.get("goal_wc3", Vector2.INF) as Vector2
	r.affected = r.moved
	r.ok = r.moved > 0 or r.failed > 0
	r.error = CommandRequest.ErrorCode.OK if r.ok else CommandRequest.ErrorCode.NO_MOVERS
	return r


static func fail(code: int, message: String = "") -> CommandResult:
	var r := CommandResult.new()
	r.ok = false
	r.error = code
	r.detail = message
	return r
