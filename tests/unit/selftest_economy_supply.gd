extends Node

class RecordingEconomy extends "res://packages/gameplay/features/ai/logic/player_economy_ai.gd":
	var requested: Array[String] = []
	func _build_one(_workers: Array[Node3D], building_id: String) -> void:
		requested.append(building_id)

var failures := 0
var checks := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("ECONOMY SUPPLY: " + label)

func _ready() -> void:
	var host := Node3D.new()
	add_child(host)
	var economy := RecordingEconomy.new()
	var session := GameSession.new()
	var commands := CommandRouter.new()
	commands.configure(null, null, Callable(), Callable(), Callable(), session, Callable(), Callable(), Callable(), 1)
	economy.configure(commands, host, null, 1)
	economy.stock = session.ensure_stock(1)
	economy.stock.food_used = 8
	economy.stock.food_cap = 12
	add_child(economy)
	economy._ensure_supply([])
	check(economy.requested == ["hhou"], "四剩余人口不足首英雄时主动建农场")
	economy.requested.clear()
	economy.stock.food_cap = 13
	economy._ensure_supply([])
	check(economy.requested.is_empty(), "恰好够英雄五人口不提前造农场")
	economy.stock.food_cap = 12
	economy.develop_army = false
	economy._ensure_supply([])
	check(economy.requested.is_empty(), "关闭军备时不为英雄预留人口")
	economy.develop_army = true
	var hero := Node3D.new()
	hero.set_meta("unit_data", {"typeId": "Hamg", "owner": 1})
	hero.set_meta("life", 100.0)
	host.add_child(hero)
	economy._ensure_supply([])
	check(economy.requested.is_empty(), "已有英雄时按常规人口余量规划")
	economy.stock.food_used = 11
	economy._ensure_supply([])
	check(economy.requested == ["hhou"], "余量不足步兵时仍补农场")
	economy.requested.clear()
	economy.stock.food_used = 8
	hero.free()
	var altar := Node3D.new()
	altar.set_meta("unit_data", {"typeId": "halt", "owner": 1})
	altar.set_meta("life", 900.0)
	host.add_child(altar)
	var queue := TrainQueue.new()
	queue.name = "TrainQueue"
	altar.add_child(queue)
	check(queue.enqueue("Hamg", 60, 0, 0, 5, Vector2.ZERO, 1), "英雄队列夹具入队")
	economy._ensure_supply([])
	check(economy.requested.is_empty(), "在训英雄已预占人口，不重复规划五人口")
	print("selftest_economy_supply: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	get_tree().quit(0 if failures == 0 else 1)
