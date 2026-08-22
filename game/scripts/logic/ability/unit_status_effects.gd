class_name UnitStatusEffects
extends RefCounted

## 短时状态（Logic）：眩晕 / 减速。P0 meta + 时间戳，供战斗/导航查询。

const META_STUN_UNTIL := "status_stun_until"
const META_SLOW_UNTIL := "status_slow_until"
const META_SLOW_MUL := "status_slow_mul"
const META_BONUS_ARMOR := "bonus_armor"


static func is_stunned(unit: Node3D) -> bool:
	return _time_left(unit, META_STUN_UNTIL) > 0.0


static func apply_stun(unit: Node3D, duration_sec: float) -> void:
	if unit == null or duration_sec <= 0.0:
		return
	_set_until(unit, META_STUN_UNTIL, duration_sec)
	var nav := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
	var ac := unit.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()


static func apply_slow(unit: Node3D, duration_sec: float, move_mul: float) -> void:
	if unit == null or duration_sec <= 0.0:
		return
	_set_until(unit, META_SLOW_UNTIL, duration_sec)
	unit.set_meta(META_SLOW_MUL, clampf(move_mul, 0.05, 1.0))
	_sync_nav_speed(unit)


static func tick(unit: Node3D, delta: float) -> void:
	if unit == null or delta <= 0.0:
		return
	var changed := false
	if _time_left(unit, META_STUN_UNTIL) <= 0.0 and unit.has_meta(META_STUN_UNTIL):
		unit.remove_meta(META_STUN_UNTIL)
		changed = true
	if _time_left(unit, META_SLOW_UNTIL) <= 0.0:
		if unit.has_meta(META_SLOW_UNTIL):
			unit.remove_meta(META_SLOW_UNTIL)
		if unit.has_meta(META_SLOW_MUL):
			unit.remove_meta(META_SLOW_MUL)
		changed = true
	if changed:
		_sync_nav_speed(unit)


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
	if unit == null:
		return 0.0
	return maxf(float(unit.get_meta(META_BONUS_ARMOR, 0.0)), 0.0)


static func set_bonus_armor(unit: Node3D, amount: float) -> void:
	if unit == null:
		return
	if amount <= 0.0:
		if unit.has_meta(META_BONUS_ARMOR):
			unit.remove_meta(META_BONUS_ARMOR)
		return
	unit.set_meta(META_BONUS_ARMOR, amount)


static func _set_until(unit: Node3D, key: String, duration_sec: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var until := now + duration_sec
	if unit.has_meta(key):
		until = maxf(float(unit.get_meta(key, until)), until)
	unit.set_meta(key, until)


static func _time_left(unit: Node3D, key: String) -> float:
	if unit == null or not unit.has_meta(key):
		return 0.0
	var now := Time.get_ticks_msec() / 1000.0
	return maxf(float(unit.get_meta(key, 0.0)) - now, 0.0)


static func _sync_nav_speed(unit: Node3D) -> void:
	var nav := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav == null:
		return
	var mul := 1.0
	if _time_left(unit, META_SLOW_UNTIL) > 0.0 and unit.has_meta(META_SLOW_MUL):
		mul *= float(unit.get_meta(META_SLOW_MUL, 1.0))
	var dc := DefendController.of(unit)
	if dc != null:
		mul *= dc.speed_mul()
	nav.speed_mul = maxf(mul, 0.05)
