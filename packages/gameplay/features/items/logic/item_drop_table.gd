class_name ItemDropTable
extends RefCounted

## 每个 set 为一次互斥概率抽取；不足 100 的余量表示不掉落。
const RANDOM_CLASSES := {"i": "Permanent", "j": "Charged", "k": "PowerUp", "l": "Artifact", "m": "Purchasable", "n": "Campaign", "o": "Miscellaneous"}
var rng := RandomNumberGenerator.new()
var tables: Array = []
var diagnostics: Array[String] = []

func _init() -> void:
	rng.randomize()

func roll(placement: Dictionary) -> Array[String]:
	diagnostics.clear()
	var sets: Array = placement.get("droppedItemSets", [])
	var pointer := int(placement.get("itemTablePtr", -1))
	if pointer >= 0:
		var found := false
		for table in tables:
			if table is Dictionary and int(table.get("tableNumber", -1)) == pointer:
				sets = table.get("sets", [])
				found = true
				break
		if not found:
			diagnostics.append("未找到掉落表 %d" % pointer)
			return []
	var result: Array[String] = []
	for group in sets:
		if not group is Array:
			continue
		var roll_value := rng.randi_range(1, 100)
		var cumulative := 0
		for entry in group:
			if not entry is Dictionary:
				continue
			cumulative += clampi(int(entry.get("chance", 0)), 0, 100)
			if roll_value <= cumulative:
				var id := resolve_id(str(entry.get("id", "")))
				if not id.is_empty():
					result.append(id)
				break
	return result

func resolve_id(id: String) -> String:
	if id.is_empty() or id == "-1":
		return ""
	if ItemCatalog.data(id) != null:
		return id
	# 已核对 War3Net RandomItemProvider：Y=任意类别，'0'-1='/'=任意等级。
	# https://github.com/Drake53/War3Net/blob/master/src/War3Net.Build.Core/Providers/RandomItemProvider.cs
	if id.length() == 4 and id[0] == "Y" and id[2] == "I" and (RANDOM_CLASSES.has(id[1]) or id[1] == "Y"):
		var level := id.unicode_at(3) - 48
		var pool: Array[String] = []
		for candidate in ItemCatalog.all_ids():
			var d := ItemCatalog.data(str(candidate))
			if d != null and d.pick_random and (id[1] == "Y" or d.item_class == RANDOM_CLASSES[id[1]]) and (level == -1 or d.level == level):
				pool.append(str(candidate))
		pool.sort()
		if not pool.is_empty():
			return pool[rng.randi_range(0, pool.size() - 1)]
	diagnostics.append("无法解析掉落 %s（保留原始规则，未替换）" % id)
	return ""
