class_name MatchLifecycleModule
extends Node

## 对局结束判定接线、结算屏与重开。
## 不持有 GameDirector 类型；导出设置从 settings_source 复制。

const MatchResultScreenScript = preload("res://game/scripts/presentation/match_result_screen.gd")
const MatchRestartScript = preload("res://game/scripts/session/match_restart.gd")

var _session: GameSession
var _game_root: Node
var _settings_source: Node
var _armed: bool = false


func configure(deps: Dictionary) -> void:
	_game_root = deps.get("game_root") as Node
	_settings_source = deps.get("settings_source") as Node


func shutdown() -> void:
	if _session != null and _session.match_finished.is_connected(_on_match_finished):
		_session.match_finished.disconnect(_on_match_finished)
	_session = null
	_game_root = null
	_settings_source = null
	_armed = false


func _exit_tree() -> void:
	shutdown()


## 双人开局后武装胜负判定。spawn_opponent_base=false 时跳过。
func setup_match_end(session: GameSession, spawn_opponent_base: bool) -> void:
	_session = session
	if _session == null or not spawn_opponent_base:
		return
	if _armed:
		return
	# 当前双人开局各自为队；后续房间/地图队伍配置需从正式槽位注入。
	var teams: Dictionary = {}
	for player in _session.stocks:
		teams[player] = player
	_session.arm_match(teams)
	if not _session.match_finished.is_connected(_on_match_finished):
		_session.match_finished.connect(_on_match_finished)
	_armed = true


func _on_match_finished(result: Dictionary) -> void:
	# 只冻结本局节点，避免暂停编辑器宿主或外层测试场景。
	if _game_root == null or _session == null:
		return
	_disable_match_processing(_game_root)
	var screen := MatchResultScreenScript.new()
	screen.name = "MatchResultScreen"
	_game_root.add_child(screen)
	screen.show_result(result, _session.local_player)
	screen.exit_requested.connect(func() -> void: get_tree().quit())
	screen.restart_requested.connect(restart_match, CONNECT_ONE_SHOT)


func restart_match() -> void:
	if _game_root == null or _session == null:
		return
	var packed := load(_game_root.scene_file_path) as PackedScene
	if packed == null:
		push_error("无法重新加载对局场景")
		return
	var restart := MatchRestartScript.new()
	restart.old_game = _game_root
	restart.packed = packed
	restart.players = _session.stocks.keys()
	# 复制导出的值配置，节点引用由新场景自行绑定，运行时状态不复制。
	if _settings_source != null:
		for property in _settings_source.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE and int(property.usage) & PROPERTY_USAGE_STORAGE:
				var value: Variant = _settings_source.get(property.name)
				if not value is Object and not value is NodePath:
					restart.settings[property.name] = value
	var parent_n := _game_root.get_parent()
	if parent_n != null:
		parent_n.add_child(restart)


func _disable_match_processing(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	for child in node.get_children():
		_disable_match_processing(child)
