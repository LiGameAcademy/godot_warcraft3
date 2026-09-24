class_name GameMode
extends RefCounted

## 对局规则抽象：开局库存、训练造价调整等。
## 具体模式（近战 / 战役）派生实现；无 Node 依赖，便于 headless 单测。


## 开局库存（金/木/人口）。派生类覆盖；默认近战常数。
func create_starting_stock(worker_count: int, hall_food: int) -> PlayerStock:
	return PlayerStock.melee_start(worker_count, hall_food)


## 调整训兵造价。返回 {gold, lumber, waived: bool}。
## unit_host 可为 null（仅按模式内部状态判断）。
func adjust_train_cost(
	_owner_id: int,
	_unit_id: String,
	gold: int,
	lumber: int,
	_unit_host: Node = null
) -> Dictionary:
	return {"gold": gold, "lumber": lumber, "waived": false}


## 训兵入队成功后通知（用于消费「首英雄免费」等一次性权益）。
func notify_train_issued(_owner_id: int, _unit_id: String, _waived: bool) -> void:
	pass


func reset() -> void:
	pass
