class_name AbilityCooldowns
extends RefCounted

## 技能冷却（Logic）：存 caster meta，不另挂节点。

const META_CD := "ability_cd" ## abil_id → 剩余秒


static func remaining(caster: Node3D, abil_id: String) -> float:
	if caster == null:
		return 0.0
	var id := abil_id.strip_edges()
	if id.is_empty() or not caster.has_meta(META_CD):
		return 0.0
	var m: Variant = caster.get_meta(META_CD)
	if not (m is Dictionary):
		return 0.0
	return maxf(float((m as Dictionary).get(id, 0.0)), 0.0)


static func is_ready(caster: Node3D, abil_id: String) -> bool:
	return remaining(caster, abil_id) <= 0.0


static func start(caster: Node3D, abil_id: String, cool_sec: float) -> void:
	if caster == null:
		return
	var id := abil_id.strip_edges()
	if id.is_empty():
		return
	var dur := maxf(cool_sec, 0.0)
	var m: Dictionary = {}
	if caster.has_meta(META_CD):
		var raw: Variant = caster.get_meta(META_CD)
		if raw is Dictionary:
			m = (raw as Dictionary).duplicate(true)
	if dur <= 0.0:
		m.erase(id)
	else:
		m[id] = dur
	caster.set_meta(META_CD, m)


static func tick_all(caster: Node3D, delta: float) -> void:
	if caster == null or delta <= 0.0 or not caster.has_meta(META_CD):
		return
	var raw: Variant = caster.get_meta(META_CD)
	if not (raw is Dictionary):
		return
	var m := (raw as Dictionary).duplicate(true)
	var changed := false
	for k in m.keys():
		var left := maxf(float(m[k]) - delta, 0.0)
		if left <= 0.0:
			m.erase(k)
		else:
			m[k] = left
		changed = true
	if changed:
		caster.set_meta(META_CD, m)
