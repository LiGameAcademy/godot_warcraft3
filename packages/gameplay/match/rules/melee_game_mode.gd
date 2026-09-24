class_name MeleeGameMode
extends GameMode

## 经典近战：Melee 初始资源/工人人口；首名英雄训练不扣金木（仍占人口）。
## 对齐 WE「Melee Initialization」里常见的 First Hero Free 语义；复活价不受影响。

## owner_id → 本局是否已享受过首英雄免费。
var _first_hero_claimed: Dictionary = {}


func create_starting_stock(worker_count: int, hall_food: int) -> PlayerStock:
	return PlayerStock.melee_start(worker_count, hall_food)


func adjust_train_cost(
	owner_id: int,
	unit_id: String,
	gold: int,
	lumber: int,
	unit_host: Node = null
) -> Dictionary:
	if not TechPresence.is_hero_id(unit_id):
		return {"gold": gold, "lumber": lumber, "waived": false}
	var oid := clampi(owner_id, 0, 15)
	if bool(_first_hero_claimed.get(oid, false)):
		return {"gold": gold, "lumber": lumber, "waived": false}
	if unit_host != null and TechPresence.count_heroes(unit_host, oid) > 0:
		return {"gold": gold, "lumber": lumber, "waived": false}
	## 已有阵亡待复活英雄：不算「首训」，应走复活价；训练第二名仍收钱。
	if HeroDeathRegistry.dead_count(oid) > 0:
		return {"gold": gold, "lumber": lumber, "waived": false}
	return {"gold": 0, "lumber": 0, "waived": true}


func notify_train_issued(owner_id: int, unit_id: String, waived: bool) -> void:
	if waived and TechPresence.is_hero_id(unit_id):
		_first_hero_claimed[clampi(owner_id, 0, 15)] = true


func reset() -> void:
	_first_hero_claimed.clear()
