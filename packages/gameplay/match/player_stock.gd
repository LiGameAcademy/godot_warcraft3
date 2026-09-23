class_name PlayerStock
extends RefCounted

## 玩家库存（金/木/人口）。故意不用 Resource 基类，避免与 Godot Resource 混淆。

signal changed(stock: PlayerStock)

## 经典 Melee 开局（可后改表驱动）
const MELEE_GOLD := 500
const MELEE_LUMBER := 150
## 人族主城 fmade
const MELEE_TOWN_HALL_FOOD := 12
## 农民 fused
const MELEE_WORKER_FOOD := 1

var gold: int = 0
var lumber: int = 0
var food_used: int = 0
var food_cap: int = 0
## upgradeid → 已研究等级（未研究不在表内）
var _upgrades: Dictionary = {}


static func melee_start(worker_count: int = 5, hall_food: int = MELEE_TOWN_HALL_FOOD) -> PlayerStock:
	var s := PlayerStock.new()
	s.gold = MELEE_GOLD
	s.lumber = MELEE_LUMBER
	s.food_used = maxi(0, worker_count) * MELEE_WORKER_FOOD
	s.food_cap = maxi(0, hall_food)
	return s


func notify_changed() -> void:
	changed.emit(self)


func set_all(p_gold: int, p_lumber: int, p_food_used: int, p_food_cap: int) -> void:
	gold = p_gold
	lumber = p_lumber
	food_used = p_food_used
	food_cap = p_food_cap
	notify_changed()


func try_spend(gold_cost: int, lumber_cost: int = 0) -> bool:
	if gold < gold_cost or lumber < lumber_cost:
		return false
	gold -= gold_cost
	lumber -= lumber_cost
	notify_changed()
	return true


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	notify_changed()


func add_lumber(amount: int) -> void:
	lumber = maxi(0, lumber + amount)
	notify_changed()


func add_food_cap(delta: int) -> void:
	food_cap = maxi(0, food_cap + delta)
	notify_changed()


func add_food_used(delta: int) -> void:
	food_used = maxi(0, food_used + delta)
	notify_changed()


func can_afford_food(extra: int = 1) -> bool:
	return food_used + extra <= food_cap


func has_upgrade(upgrade_id: String) -> bool:
	return upgrade_level(upgrade_id) > 0


func upgrade_level(upgrade_id: String) -> int:
	return int(_upgrades.get(upgrade_id.strip_edges(), 0))


func grant_upgrade(upgrade_id: String, level: int = 1) -> void:
	var uid := upgrade_id.strip_edges()
	if uid.is_empty():
		return
	_upgrades[uid] = maxi(upgrade_level(uid), maxi(1, level))
	notify_changed()


## {upgradeid: level} 副本，供命令卡 Requires。
func upgrade_map() -> Dictionary:
	return _upgrades.duplicate()
