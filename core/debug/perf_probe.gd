extends Node
## PerfProbe — 给 Panku Expression Monitor / Interactive Shell 用的性能探针。
## 注册为表达式环境名 `perf`，例：perf.summary()、perf.fps()

const _HELP_fps = "Engine.get_frames_per_second()"
const _HELP_mem_mb = "Static memory (MB)"
const _HELP_process_ms = "Main thread process time (ms)"
const _HELP_physics_ms = "Physics process time (ms)"
const _HELP_draw_calls = "Draw calls this frame"
const _HELP_primitives = "Primitives this frame"
const _HELP_nodes = "Node count"
const _HELP_objects = "Object count"
const _HELP_video_mem_mb = "Video memory (MB)"
const _HELP_summary = "One-line FPS/CPU/draw/nodes/mem"
const _HELP_team_summary = "TeamRegistry player/camp member counts"
const _HELP_log_path = "Absolute path of current godot.log"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_toggle_action()
	call_deferred("_register_with_panku")


func fps() -> int:
	return int(Engine.get_frames_per_second())


func mem_mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0


func process_ms() -> float:
	return Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0


func physics_ms() -> float:
	return Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0


func draw_calls() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func primitives() -> int:
	return int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))


func nodes() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))


func objects() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_COUNT))


func video_mem_mb() -> float:
	return Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0


func summary() -> String:
	return "FPS:%d | CPU:%.1fms | Phy:%.1fms | Draw:%d | Nodes:%d | Mem:%.1fMB" % [
		fps(),
		process_ms(),
		physics_ms(),
		draw_calls(),
		nodes(),
		mem_mb(),
	]


func team_summary() -> String:
	var reg := _find_team_registry()
	if reg == null:
		return "TeamRegistry: n/a"
	var d: Dictionary = reg.debug_summary()
	var players: Dictionary = d.get("players", {})
	var camps: Dictionary = d.get("camps", {})
	var player_units := 0
	for k in players.keys():
		player_units += int(players[k])
	var camp_units := 0
	for k in camps.keys():
		var c: Variant = camps[k]
		if typeof(c) == TYPE_DICTIONARY:
			camp_units += int((c as Dictionary).get("members", 0))
	return "players:%d units=%d | camps:%d units=%d" % [
		players.size(),
		player_units,
		camps.size(),
		camp_units,
	]


func log_path() -> String:
	return OS.get_user_data_dir().path_join("logs").path_join("godot.log")


func _ensure_toggle_action() -> void:
	# GM 面板占用 ` / F4；Panku 控制台改用 F3，避免抢键。
	const ACTION := "toggle_console"
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_F3
	InputMap.action_add_event(ACTION, ev)


func _register_with_panku() -> void:
	var panku := get_node_or_null("/root/Panku")
	if panku == null:
		return
	var env: Variant = panku.get("gd_exprenv")
	if env == null or not env.has_method("register_env"):
		return
	env.register_env("perf", self)
	print("[PerfProbe] registered as Panku env `perf` — try perf.summary()")
	print("[PerfProbe] log file: %s" % log_path())


func _find_team_registry() -> TeamRegistry:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var director: Node = scene.get_node_or_null("GameDirector")
	if director == null:
		return null
	# TeamRegistry.attach 挂在 UnitsModule 的 registry_host（常为 GameDirector 自身）
	var found: Node = director.get_node_or_null("TeamRegistry")
	if found is TeamRegistry:
		return found as TeamRegistry
	for c in director.get_children():
		if c is TeamRegistry:
			return c as TeamRegistry
		var nested := c.get_node_or_null("TeamRegistry")
		if nested is TeamRegistry:
			return nested as TeamRegistry
	return null


## Opt-in CPU hotpath sampling, exposed through Panku as perf.
func set_hotpaths_enabled(on: bool) -> void:
	MatchHotpathMetrics.drain()
	MatchHotpathMetrics.enabled = on


## Returns one bounded window and resets its counters.
func hotpaths() -> Dictionary:
	return MatchHotpathMetrics.drain()
