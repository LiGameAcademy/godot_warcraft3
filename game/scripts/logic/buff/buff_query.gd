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


## 光环等额外回蓝（点/秒），与 UnitBalance 自然回蓝叠加。
static func mana_regen_bonus(unit: Node3D) -> float:
	var h := BuffHost.of(unit)
	if h == null or not h.has_buff(BuffCatalog.ID_BRILLIANCE):
		return 0.0
	return maxf(float(h.get_params(BuffCatalog.ID_BRILLIANCE).get("mana_regen", 0.0)), 0.0)


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
		# 光环：HUD 用 left=-1，避免续期导致「即将结束」闪烁
		var is_aura := bool(params.get("aura", false)) or id == BuffCatalog.ID_BRILLIANCE
		if is_aura:
			left = -1.0
		out.append({
			"id": id,
			"icon": BuffCatalog.icon_path(id),
			"tooltip": BuffCatalog.tooltip_text(id, params, left),
			"short": BuffCatalog.display_name(id),
			"left": left,
		})
	return out
