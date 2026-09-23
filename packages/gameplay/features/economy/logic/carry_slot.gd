class_name CarrySlot
extends RefCounted
## 单位负重：单一资源类型 + 数量（采到异类时整槽替换 = 丢弃旧资源）。
## 扩展新资源只需加 ID，不必再拆 _carry_gold / _carry_lumber。

const ID_NONE := ""
const ID_GOLD := "gold"
const ID_LUMBER := "lumber"


var id: String = ID_NONE
var amount: int = 0


func is_empty() -> bool:
	return id.is_empty() or amount <= 0


func clear() -> void:
	id = ID_NONE
	amount = 0


func set_resource(new_id: String, new_amount: int) -> void:
	if new_id.is_empty() or new_amount <= 0:
		clear()
		return
	id = new_id
	amount = new_amount


## 采到资源：异类丢弃旧负重后替换；同类累加至 capacity。
func gather(new_id: String, add: int, capacity: int) -> void:
	if new_id.is_empty() or add <= 0:
		return
	var cap: int = maxi(1, capacity)
	if id != new_id:
		id = new_id
		amount = mini(add, cap)
	else:
		amount = mini(amount + add, cap)


func is_full(capacity: int) -> bool:
	if is_empty():
		return false
	return amount >= maxi(1, capacity)


func gold() -> int:
	return amount if id == ID_GOLD else 0


func lumber() -> int:
	return amount if id == ID_LUMBER else 0


func receive_mask() -> int:
	match id:
		ID_GOLD:
			return int(ReceiveResources.Kind.GOLD)
		ID_LUMBER:
			return int(ReceiveResources.Kind.LUMBER)
		_:
			return int(ReceiveResources.Kind.NONE)
