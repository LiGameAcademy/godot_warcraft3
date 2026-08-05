class_name GameSession
extends RefCounted
## 对局会话态：地图、本地玩家、各族玩家库存。权威在此，Present/HUD 只读。

const _Stock := preload("res://game/scripts/session/player_stock.gd")

var map_dir: String = ""
var local_player: int = 0
var local_race: String = "human"
## owner_id → PlayerStock 实例
var stocks: Dictionary = {}


func ensure_stock(owner_id: int):
	var key := clampi(owner_id, 0, 15)
	if stocks.has(key):
		return stocks[key]
	var s = _Stock.new()
	stocks[key] = s
	return s


func set_stock(owner_id: int, stock) -> void:
	if stock == null:
		return
	stocks[clampi(owner_id, 0, 15)] = stock


func local_stock():
	return ensure_stock(local_player)


static func from_melee_bootstrap(
	p_map_dir: String,
	p_local_player: int,
	p_race: String,
	worker_count: int,
	hall_food: int = -1
):
	var food_cap := hall_food if hall_food >= 0 else int(_Stock.MELEE_TOWN_HALL_FOOD)
	var session := GameSession.new()
	session.map_dir = p_map_dir
	session.local_player = clampi(p_local_player, 0, 15)
	session.local_race = p_race
	session.set_stock(session.local_player, _Stock.melee_start(worker_count, food_cap))
	return session
