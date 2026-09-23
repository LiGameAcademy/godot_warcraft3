class_name ItemInstance
extends RefCounted

## 动态实例不写回 ItemDef。冷却截止时间仅用于本次进程内的死亡/复活。
static var next_id: int = 1
var instance_id: int = 0
var type_id: String = ""
var charges: int = 0
var cooldown_until: float = 0.0
## 0=未持有/地面；背包用宿主 instance_id 防止同一对象被重复领取。
var holder_id: int = 0

static func create(id: String) -> ItemInstance:
	var d := ItemCatalog.data(id)
	if d == null:
		return null
	var item := ItemInstance.new()
	item.instance_id = next_id
	next_id += 1
	item.type_id = id
	item.charges = maxi(d.uses, 0)
	return item

static func now() -> float:
	return Time.get_ticks_msec() / 1000.0

func snapshot() -> Dictionary:
	return {"instance_id": instance_id, "type_id": type_id, "charges": charges, "cooldown_until": cooldown_until}

static func from_snapshot(raw: Dictionary) -> ItemInstance:
	if ItemCatalog.data(str(raw.get("type_id", ""))) == null:
		return null
	var item := ItemInstance.new()
	item.instance_id = int(raw.get("instance_id", 0))
	if item.instance_id <= 0:
		return null
	next_id = maxi(next_id, item.instance_id + 1)
	item.type_id = str(raw["type_id"])
	item.charges = maxi(int(raw.get("charges", 0)), 0)
	item.cooldown_until = float(raw.get("cooldown_until", 0.0))
	return item
