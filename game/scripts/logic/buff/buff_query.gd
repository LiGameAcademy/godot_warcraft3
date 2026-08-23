class_name BuffQuery
extends RefCounted

## Buff 统一查询门面（Logic）：战斗 / 导航 / AI 读此处。


static func host_of(unit: Node3D) -> BuffHost:
	return BuffHost.of(unit)


static func is_stunned(unit: Node3D) -> bool:
	var h := BuffHost.of(unit)
	return h != null and h.is_stunned()


static func is_slowed(unit: Node3D) -> bool:
	var h := BuffHost.of(unit)
	return h != null and h.is_slowed()


static func damage_mul(unit: Node3D) -> float:
	var h := BuffHost.of(unit)
	if h == null:
		return 1.0
	return h.damage_mul()


static func bonus_armor(unit: Node3D) -> float:
	var h := BuffHost.of(unit)
	if h == null:
		return 0.0
	return h.bonus_armor()


static func move_speed_mul(unit: Node3D) -> float:
	var h := BuffHost.of(unit)
	if h == null:
		return 1.0
	return h.move_speed_mul()


static func attack_speed_mul(unit: Node3D) -> float:
	var h := BuffHost.of(unit)
	if h == null:
		return 1.0
	return h.attack_speed_mul()


static func tick(unit: Node3D, delta: float) -> void:
	var h := BuffHost.of(unit)
	if h != null:
		h.tick(delta)


static func hud_entries(unit: Node3D) -> Array:
	var out: Array = []
	if unit == null or not is_instance_valid(unit):
		return out
	var h := BuffHost.of(unit)
	if h == null:
		return out
	for raw in h.list_active():
		if typeof(raw) != TYPE_DICTIONARY:
			continue
		var e := raw as Dictionary
		var id := str(e.get("id", "")).strip_edges()
		if id.is_empty():
			continue
		var left := float(e.get("left", 0.0))
		var params: Dictionary = e.get("params", {}) as Dictionary
		out.append({
			"id": id,
			"icon": BuffCatalog.icon_path(id),
			"tooltip": BuffCatalog.tooltip_text(id, params, left),
			"short": BuffCatalog.display_name(id),
			"left": left,
		})
	return out
