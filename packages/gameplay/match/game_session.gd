class_name GameSession
extends RefCounted

signal match_finished(result: Dictionary)

const VictoryRules = preload("res://packages/gameplay/match/rules/melee_victory_rules.gd")

## 对局会话态：地图、本地玩家、各族玩家库存。权威在此，Present/HUD 只读。

var map_dir: String = ""
var local_player: int = 0
var local_race: String = "human"
## owner_id → PlayerStock 实例
var stocks: Dictionary = {}
## 对局模式规则（近战首英雄免费、开局库存等）；空则用默认 MeleeGameMode。
var game_mode: GameMode = null

var _match_teams: Dictionary = {}
var _match_armed := false
var _match_result: Dictionary = {}


## 开局完成后显式启用。队伍配置与结果均复制，调用方不能改写已结算状态。
func arm_match(player_teams: Dictionary) -> void:
	if _match_armed:
		return
	_match_teams = player_teams.duplicate(true)
	_match_armed = true


func evaluate_match(unit_host: Node) -> Dictionary:
	if not _match_result.is_empty():
		return _match_result.duplicate(true)
	var snapshot: Dictionary = VictoryRules.evaluate(unit_host, _match_teams, _match_armed)
	if bool(snapshot.finished):
		_match_result = snapshot.duplicate(true)
		match_finished.emit(_match_result.duplicate(true))
	return snapshot


func get_match_result() -> Dictionary:
	return _match_result.duplicate(true)


func ensure_stock(owner_id: int) -> PlayerStock:
	var key := clampi(owner_id, 0, 15)
	if stocks.has(key):
		return stocks[key] as PlayerStock
	var s := PlayerStock.new()
	stocks[key] = s
	return s


func set_stock(owner_id: int, stock: PlayerStock) -> void:
	if stock == null:
		return
	stocks[clampi(owner_id, 0, 15)] = stock


func local_stock() -> PlayerStock:
	return ensure_stock(local_player)


func ensure_game_mode() -> GameMode:
	if game_mode == null:
		game_mode = MeleeGameMode.new()
	return game_mode


static func from_melee_bootstrap(
	p_map_dir: String,
	p_local_player: int,
	p_race: String,
	worker_count: int,
	hall_food: int = -1,
	p_mode: GameMode = null
) -> GameSession:
	var food_cap := hall_food if hall_food >= 0 else PlayerStock.MELEE_TOWN_HALL_FOOD
	var session := GameSession.new()
	session.map_dir = p_map_dir
	session.local_player = clampi(p_local_player, 0, 15)
	session.local_race = p_race
	session.game_mode = p_mode if p_mode != null else MeleeGameMode.new()
	session.set_stock(
		session.local_player,
		session.game_mode.create_starting_stock(worker_count, food_cap)
	)
	return session
