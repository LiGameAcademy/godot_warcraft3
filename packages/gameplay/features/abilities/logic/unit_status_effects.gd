class_name UnitStatusEffects
extends RefCounted

## 短时状态门面（Logic）：委托 BuffHost；保留旧 API 以免大面积改调用方。
## 新代码请直接用 BuffHost / BuffQuery。


static func is_stunned(unit: Node3D) -> bool:
	return BuffQuery.is_stunned(unit)


static func apply_stun(unit: Node3D, duration_sec: float) -> void:
	if unit == null or duration_sec <= 0.0:
		return
	BuffHost.ensure_on(unit).apply(BuffCatalog.ID_STUN, duration_sec)


static func is_slowed(unit: Node3D) -> bool:
	return BuffQuery.is_slowed(unit)


static func apply_slow(unit: Node3D, duration_sec: float, move_mul: float) -> void:
	if unit == null or duration_sec <= 0.0:
		return
	var h := BuffHost.ensure_on(unit)
	var params := h.get_params(BuffCatalog.ID_SLOW) if h.has_buff(BuffCatalog.ID_SLOW) else {}
	params["move_mul"] = clampf(move_mul, 0.05, 1.0)
	h.apply(BuffCatalog.ID_SLOW, duration_sec, params)


static func apply_attack_slow(unit: Node3D, duration_sec: float, attack_mul: float) -> void:
	if unit == null or duration_sec <= 0.0:
		return
	var h := BuffHost.ensure_on(unit)
	var params := h.get_params(BuffCatalog.ID_SLOW) if h.has_buff(BuffCatalog.ID_SLOW) else {}
	params["attack_mul"] = clampf(attack_mul, 0.05, 1.0)
	h.apply(BuffCatalog.ID_SLOW, duration_sec, params)


static func attack_speed_mul(unit: Node3D) -> float:
	return BuffQuery.attack_speed_mul(unit)


static func set_inner_fire(unit: Node3D, armor: float, dmg_mul: float) -> void:
	if unit == null:
		return
	var h := BuffHost.ensure_on(unit)
	if armor <= 0.0 and dmg_mul <= 1.0:
		h.remove(BuffCatalog.ID_INNER_FIRE)
		return
	h.apply(BuffCatalog.ID_INNER_FIRE, 86400.0, {
		"armor": maxf(armor, 0.0),
		"dmg_mul": maxf(dmg_mul, 1.0),
	})


static func clear_inner_fire(unit: Node3D) -> void:
	if unit == null:
		return
	var h := BuffHost.of(unit)
	if h != null:
		h.remove(BuffCatalog.ID_INNER_FIRE)


static func damage_mul(unit: Node3D) -> float:
	return BuffQuery.damage_mul(unit)


static func tick(unit: Node3D, delta: float) -> void:
	BuffQuery.tick(unit, delta)


static func stun_duration_for(
	ab: AbilityDataDef,
	level: int,
	target: Node3D
) -> float:
	if ab == null:
		return 0.0
	var tid := CombatQuery.type_id_of(target)
	if TechPresence.is_hero_id(tid):
		return maxf(ab.hero_duration_at(level), 0.0)
	return maxf(ab.duration_at(level), 0.0)


static func bonus_armor(unit: Node3D) -> float:
	return BuffQuery.bonus_armor(unit)


static func set_bonus_armor(unit: Node3D, amount: float) -> void:
	if unit == null:
		return
	var h := BuffHost.ensure_on(unit)
	if amount <= 0.0:
		h.remove(BuffCatalog.ID_BONUS_ARMOR)
		return
	h.apply(BuffCatalog.ID_BONUS_ARMOR, 86400.0, {"amount": amount})
