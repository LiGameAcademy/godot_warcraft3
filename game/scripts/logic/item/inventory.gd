class_name Inventory
extends Node

## 六格背包。槽位变化事件驱动；护甲按实例汇总，不通过同名 Buff 合并。
signal changed
const CAPACITY := 6
var slots: Array[ItemInstance] = []
var cooldown_groups: Dictionary = {}

func _init() -> void:
	slots.resize(CAPACITY)

static func of(unit: Node) -> Inventory:
	return unit.get_node_or_null("Inventory") as Inventory if is_instance_valid(unit) else null

static func ensure_on(unit: Node3D) -> Inventory:
	if not is_instance_valid(unit):
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	var ud: Dictionary = unit.get_meta("unit_data", {})
	if not TechPresence.is_hero_id(str(ud.get("typeId", ""))):
		return null
	var inv := Inventory.new()
	inv.name = "Inventory"
	unit.add_child(inv)
	# 地图预置 inventory 使用零基槽位；未知 ID 不静默替换。
	for entry in ud.get("inventory", []):
		if entry is Dictionary:
			var item := ItemInstance.create(str(entry.get("id", "")))
			if item != null:
				inv.insert(item, int(entry.get("slot", -1)))
	return inv

func item_at(slot: int) -> ItemInstance:
	return slots[slot] if slot >= 0 and slot < CAPACITY else null

func is_full() -> bool:
	return not slots.has(null)

func insert(item: ItemInstance, preferred: int = -1) -> bool:
	if item == null or item.holder_id != 0 or get_parent() == null:
		return false
	for held in slots:
		if held != null and held.instance_id == item.instance_id:
			return false
	var slot := preferred if preferred >= 0 and preferred < CAPACITY else slots.find(null)
	if slot < 0 or slots[slot] != null:
		return false
	slots[slot] = item
	item.holder_id = get_parent().get_instance_id()
	var d := ItemCatalog.data(item.type_id)
	if d != null and not d.cooldown_id.is_empty():
		cooldown_groups[d.cooldown_id] = maxf(float(cooldown_groups.get(d.cooldown_id, 0.0)), item.cooldown_until)
	changed.emit()
	return true

func remove_at(slot: int) -> ItemInstance:
	var item := item_at(slot)
	if item == null:
		return null
	# 将持有者的共享组剩余冷却带到地面，转交也不能刷新。
	item.cooldown_until = ItemInstance.now() + cooldown_remaining(slot)
	item.holder_id = 0
	slots[slot] = null
	changed.emit()
	return item

func swap_slots(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= CAPACITY or b >= CAPACITY:
		return false
	var item := slots[a]
	slots[a] = slots[b]
	slots[b] = item
	changed.emit()
	return true

func cooldown_remaining(slot: int) -> float:
	var item := item_at(slot)
	if item == null:
		return 0.0
	var d := ItemCatalog.data(item.type_id)
	if d == null or d.ignore_cd:
		return 0.0
	return maxf(maxf(item.cooldown_until, float(cooldown_groups.get(d.cooldown_id, 0.0))) - ItemInstance.now(), 0.0)

func bonus_armor() -> float:
	var total := 0.0
	for item in slots:
		if item == null:
			continue
		var ab := ItemCatalog.effect(item.type_id)
		if ab != null and ab.code_id == "AIde":
			total += ab.data_a_at(1)
	return total

func try_use(slot: int) -> Dictionary:
	var unit := get_parent() as Node3D
	var item := item_at(slot)
	if item == null or not CombatQuery.is_alive_in_world(unit):
		return {"ok": false, "reason": "无可用道具或英雄已阵亡"}
	if UnitStatusEffects.is_stunned(unit):
		return {"ok": false, "reason": "眩晕中无法使用道具"}
	var d := ItemCatalog.data(item.type_id)
	var ab := ItemCatalog.effect(item.type_id)
	if ab == null:
		return {"ok": false, "reason": "该道具效果尚未实现"}
	if not d.usable:
		return {"ok": false, "reason": "携带时已生效，无需使用"}
	if d.uses > 0 and item.charges <= 0:
		return {"ok": false, "reason": "使用次数已耗尽"}
	if cooldown_remaining(slot) > 0.0:
		return {"ok": false, "reason": "同类道具冷却中"}
	var amount := maxf(ab.data_a_at(1), 0.0)
	var actual := 0.0
	match ab.code_id:
		"AIhe":
			var result := Wc3AbilityEffects.heal(unit, unit, amount)
			actual = result.actual_amount
		"AIma":
			actual = minf(amount, maxf(float(UnitMana.get_max_mana(unit) - UnitMana.get_mana(unit)), 0.0))
			if actual > 0.0:
				UnitMana.regenerate(unit, actual)
	if actual <= 0.0:
		return {"ok": false, "reason": "生命或魔法已满，未消耗道具"}
	if not d.ignore_cd:
		item.cooldown_until = ItemInstance.now() + ab.cool_at(1)
		cooldown_groups[d.cooldown_id] = item.cooldown_until
	if d.uses > 0:
		item.charges -= 1
		if item.charges == 0 and d.perishable:
			remove_at(slot)
	changed.emit()
	return {"ok": true, "reason": "%s：恢复 %.0f" % [ItemCatalog.title(item.type_id), actual], "amount": actual}

func snapshot() -> Dictionary:
	var entries: Array = []
	for item in slots:
		entries.append(item.snapshot() if item != null else {})
	return {"slots": entries, "cooldown_groups": cooldown_groups.duplicate(true)}

## 恢复只用于空背包（复活先清除地图模板）；调用方持有快照的唯一消费权。
func restore(raw: Dictionary) -> void:
	clear()
	cooldown_groups = raw.get("cooldown_groups", {}).duplicate(true)
	var entries: Array = raw.get("slots", [])
	for i in range(mini(entries.size(), CAPACITY)):
		if entries[i] is Dictionary and not entries[i].is_empty():
			insert(ItemInstance.from_snapshot(entries[i]), i)
	changed.emit()

func clear() -> void:
	for item in slots:
		if item != null:
			item.holder_id = 0
	slots.fill(null)
	cooldown_groups.clear()
	changed.emit()
