class_name BuffHost
extends Node

## 单位 Buff 容器（Logic）：施加 / tick / 查询 / 驱散。技能与战斗只通过本类或 BuffQuery 访问。

const NODE_NAME := "BuffHost"

## buff_id → { until: float, params: Dictionary }
var _entries: Dictionary = {}


static func of(unit: Node3D) -> BuffHost:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as BuffHost


static func ensure_on(unit: Node3D) -> BuffHost:
	if unit == null:
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	var h := BuffHost.new()
	h.name = NODE_NAME
	unit.add_child(h)
	return h


func apply(buff_id: String, duration_sec: float, params: Dictionary = {}) -> void:
	var id := buff_id.strip_edges()
	if id.is_empty() or duration_sec <= 0.0:
		return
	var until := _now() + duration_sec
	if _entries.has(id):
		until = maxf(float((_entries[id] as Dictionary).get("until", until)), until)
		var prev := (_entries[id] as Dictionary).get("params", {}) as Dictionary
		var merged := prev.duplicate()
		for k in params.keys():
			merged[k] = params[k]
		_entries[id] = {"until": until, "params": merged}
	else:
		_entries[id] = {"until": until, "params": params.duplicate()}
	_on_applied(id)


func remove(buff_id: String) -> void:
	var id := buff_id.strip_edges()
	if not _entries.has(id):
		return
	_entries.erase(id)
	_on_removed(id)


func clear_all() -> void:
	var ids := _entries.keys()
	_entries.clear()
	for id in ids:
		_on_removed(str(id))


func has_buff(buff_id: String) -> bool:
	return _time_left(buff_id.strip_edges()) > 0.0


func time_left(buff_id: String) -> float:
	return _time_left(buff_id.strip_edges())


func get_params(buff_id: String) -> Dictionary:
	var id := buff_id.strip_edges()
	if not _entries.has(id):
		return {}
	return ((_entries[id] as Dictionary).get("params", {}) as Dictionary).duplicate()


func list_active() -> Array:
	var out: Array = []
	for id in _entries.keys():
		var sid := str(id)
		var left := _time_left(sid)
		if left <= 0.0:
			continue
		out.append({
			"id": sid,
			"left": left,
			"params": get_params(sid),
		})
	return out


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	var expired: PackedStringArray = PackedStringArray()
	for id in _entries.keys():
		if _time_left(str(id)) <= 0.0:
			expired.append(str(id))
	for id in expired:
		_entries.erase(id)
		_on_removed(id)


func dispel_magic() -> int:
	var removed := 0
	for id in _entries.keys():
		if BuffCatalog.is_dispellable(str(id)):
			_entries.erase(id)
			_on_removed(str(id))
			removed += 1
	return removed


func is_stunned() -> bool:
	return has_buff(BuffCatalog.ID_STUN)


func is_slowed() -> bool:
	return has_buff(BuffCatalog.ID_SLOW)


func damage_mul() -> float:
	var mul := 1.0
	if has_buff(BuffCatalog.ID_INNER_FIRE):
		var p := get_params(BuffCatalog.ID_INNER_FIRE)
		mul = maxf(float(p.get("dmg_mul", 1.0)), 1.0)
	return mul


func bonus_armor() -> float:
	var total := 0.0
	if has_buff(BuffCatalog.ID_BONUS_ARMOR):
		total += maxf(float(get_params(BuffCatalog.ID_BONUS_ARMOR).get("amount", 0.0)), 0.0)
	if has_buff(BuffCatalog.ID_AVATAR):
		total += maxf(float(get_params(BuffCatalog.ID_AVATAR).get("armor", 0.0)), 0.0)
	if has_buff(BuffCatalog.ID_INNER_FIRE):
		total += maxf(float(get_params(BuffCatalog.ID_INNER_FIRE).get("armor", 0.0)), 0.0)
	return total


func move_speed_mul() -> float:
	if not has_buff(BuffCatalog.ID_SLOW):
		return 1.0
	return clampf(float(get_params(BuffCatalog.ID_SLOW).get("move_mul", 1.0)), 0.05, 1.0)


func attack_speed_mul() -> float:
	if not has_buff(BuffCatalog.ID_SLOW):
		return 1.0
	var atk := float(get_params(BuffCatalog.ID_SLOW).get("attack_mul", 1.0))
	if atk <= 0.0:
		return 1.0
	return clampf(atk, 0.05, 1.0)


func _time_left(buff_id: String) -> float:
	if buff_id.is_empty() or not _entries.has(buff_id):
		return 0.0
	return maxf(float((_entries[buff_id] as Dictionary).get("until", 0.0)) - _now(), 0.0)


func _on_applied(buff_id: String) -> void:
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return
	match buff_id:
		BuffCatalog.ID_STUN:
			var nav := host.get_node_or_null("UnitNavigator") as UnitNavigator
			if nav != null:
				nav.stop()
			var ac := host.get_node_or_null("AttackController") as AttackController
			if ac != null:
				ac.cancel()
		BuffCatalog.ID_SLOW:
			_sync_nav_speed(host)


func _on_removed(buff_id: String) -> void:
	var host := get_parent() as Node3D
	if host == null or not is_instance_valid(host):
		return
	if buff_id == BuffCatalog.ID_SLOW:
		_sync_nav_speed(host)


func _sync_nav_speed(host: Node3D) -> void:
	var nav := host.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav == null:
		return
	var mul := move_speed_mul()
	var dc := DefendController.of(host)
	if dc != null:
		mul *= dc.speed_mul()
	nav.speed_mul = maxf(mul, 0.05)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
