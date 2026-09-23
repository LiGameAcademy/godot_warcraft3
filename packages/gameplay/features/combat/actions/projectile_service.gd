class_name ProjectileService
extends RefCounted

## Logic 弹道推进（Game Logic · combat）。
## - 真 missile：恒速制导追目标，进入命中半径后再 DamagePipeline（禁 Present 回调扣血）
## - instant 远程：visual_only 壳同速飞完；伤害已在 AttackController dmgpt 结算

signal projectile_launched(info: Dictionary) ## Present 镜像用
signal projectile_resolved(result: Dictionary) ## 命中结算后（含 visual_only 空结果）

## 命中半径（WC3 单位）；到点即结算，不靠物理碰撞体。
const HIT_RADIUS_WC3 := 32.0
## 最长飞行（防目标无限风筝）
const MAX_FLIGHT_SEC := 6.0

var pipeline: DamagePipeline = null
var _next_id: int = 1
var _flights: Array[Dictionary] = []


## 发射。visual_only=true 时到点不结算伤害。
func fire(attacker: Node3D, target: Node3D, visual_only: bool = false) -> int:
	if attacker == null or target == null:
		return -1
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return -1
	var from_full := Wc3Coords.godot_to_wc3(attacker.global_position)
	var to_full := Wc3Coords.godot_to_wc3(target.global_position)
	var launch := CombatQuery.launch_offset_wc3(attacker)
	var impact_z := CombatQuery.impact_z_wc3(attacker)
	# launch/impact Z 相对单位原点；须叠在地形高度上（勿写死 66）。
	var from_wc3 := Vector3(
		from_full.x + launch.x, from_full.y + launch.y, from_full.z + launch.z
	)
	var to_wc3 := Vector3(to_full.x, to_full.y, to_full.z + impact_z)
	var dist := _horiz_dist(from_wc3, to_wc3)
	var speed := CombatQuery.missile_speed_wc3(attacker)
	var duration := CombatQuery.travel_time_sec(dist, speed)
	var id := _next_id
	_next_id += 1
	var info := {
		"id": id,
		"attacker": attacker,
		"target": target,
		"from_wc3": from_wc3,
		"to_wc3": to_wc3,
		"pos_wc3": from_wc3,
		"speed_wc3": speed,
		"duration": duration, ## 初值估计；Present 作超时兜底
		"elapsed": 0.0,
		"visual_only": visual_only,
		"alive": true,
		"homing": true,
		"hit_radius_wc3": HIT_RADIUS_WC3,
		"impact_z": impact_z,
	}
	_flights.append(info)
	projectile_launched.emit(info.duplicate())
	if dist <= HIT_RADIUS_WC3:
		_resolve_flight(info)
		_remove_flight(id)
	return id


## 技能弹道：命中后走 spell_req（固定伤害等），info 可带 spell_abil_id / missile_art。
func fire_spell(
	caster: Node3D,
	target: Node3D,
	spell_req: Dictionary,
	speed_wc3: float = 1000.0,
	extra: Dictionary = {}
) -> int:
	if caster == null or target == null:
		return -1
	if not is_instance_valid(caster) or not is_instance_valid(target):
		return -1
	var from_full := Wc3Coords.godot_to_wc3(caster.global_position)
	var to_full := Wc3Coords.godot_to_wc3(target.global_position)
	var launch := CombatQuery.launch_offset_wc3(caster)
	var impact_z := CombatQuery.impact_z_wc3(caster)
	var from_wc3 := Vector3(
		from_full.x + launch.x, from_full.y + launch.y, from_full.z + launch.z
	)
	var to_wc3 := Vector3(to_full.x, to_full.y, to_full.z + impact_z)
	var dist := _horiz_dist(from_wc3, to_wc3)
	var speed := maxf(speed_wc3, 1.0)
	var duration := CombatQuery.travel_time_sec(dist, speed)
	var id := _next_id
	_next_id += 1
	var info := {
		"id": id,
		"attacker": caster,
		"target": target,
		"from_wc3": from_wc3,
		"to_wc3": to_wc3,
		"pos_wc3": from_wc3,
		"speed_wc3": speed,
		"duration": duration,
		"elapsed": 0.0,
		"visual_only": false,
		"alive": true,
		"homing": true,
		"hit_radius_wc3": HIT_RADIUS_WC3,
		"impact_z": impact_z,
		"spell_req": spell_req.duplicate(true),
		"is_spell": true,
	}
	for k in extra.keys():
		info[k] = extra[k]
	_flights.append(info)
	projectile_launched.emit(info.duplicate())
	if dist <= HIT_RADIUS_WC3:
		_resolve_flight(info)
		_remove_flight(id)
	return id


func tick(delta: float) -> void:
	if _flights.is_empty():
		return
	var i := 0
	while i < _flights.size():
		var f: Dictionary = _flights[i]
		if not bool(f.get("alive", false)):
			_flights.remove_at(i)
			continue
		f["elapsed"] = float(f.get("elapsed", 0.0)) + delta
		if float(f["elapsed"]) >= MAX_FLIGHT_SEC:
			f["visual_only"] = true
			_resolve_flight(f)
			_flights.remove_at(i)
			continue
		var target: Node3D = f.get("target") as Node3D
		if target == null or not is_instance_valid(target):
			f["visual_only"] = true
			_resolve_flight(f)
			_flights.remove_at(i)
			continue
		var impact_z := float(f.get("impact_z", CombatQuery.impact_z_wc3(f.get("attacker") as Node)))
		var to_full := Wc3Coords.godot_to_wc3(target.global_position)
		var to_wc3 := Vector3(to_full.x, to_full.y, to_full.z + impact_z)
		f["to_wc3"] = to_wc3
		var pos: Vector3 = f.get("pos_wc3", f.get("from_wc3", Vector3.ZERO))
		var speed := maxf(float(f.get("speed_wc3", 900.0)), 1.0)
		var step := speed * delta
		var dist := pos.distance_to(to_wc3)
		if dist <= float(f.get("hit_radius_wc3", HIT_RADIUS_WC3)) or dist <= step:
			f["pos_wc3"] = to_wc3
			_resolve_flight(f)
			_flights.remove_at(i)
			continue
		f["pos_wc3"] = pos.move_toward(to_wc3, step)
		# 刷新估计剩余时长，供 Present 超时对齐
		f["duration"] = float(f.get("elapsed", 0.0)) + dist / speed
		i += 1


func cancel_attacker(attacker: Node3D) -> void:
	if attacker == null:
		return
	for f in _flights:
		if f.get("attacker") == attacker:
			f["alive"] = false
			f["visual_only"] = true


func _horiz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.y).distance_to(Vector2(b.x, b.y))


func _remove_flight(id: int) -> void:
	for i in range(_flights.size()):
		if int(_flights[i].get("id", -1)) == id:
			_flights.remove_at(i)
			return


func _resolve_flight(f: Dictionary) -> void:
	f["alive"] = false
	var visual_only := bool(f.get("visual_only", false))
	var attacker: Node3D = f.get("attacker") as Node3D
	var target: Node3D = f.get("target") as Node3D
	if visual_only or pipeline == null:
		projectile_resolved.emit(
			{"ok": false, "visual_only": true, "id": int(f.get("id", -1)), "attacker": attacker, "target": target}
		)
		return
	if (
		attacker == null
		or target == null
		or not is_instance_valid(attacker)
		or not is_instance_valid(target)
	):
		projectile_resolved.emit(
			{"ok": false, "visual_only": true, "id": int(f.get("id", -1)), "attacker": attacker, "target": target}
		)
		return
	var result: Dictionary
	if bool(f.get("is_spell", false)):
		var req: Dictionary = f.get("spell_req", {}) as Dictionary
		req["attacker"] = attacker
		req["target"] = target
		result = pipeline.apply(req)
		result["is_spell"] = true
		result["spell_abil_id"] = str(f.get("spell_abil_id", ""))
		var stun_sec := float(f.get("stun_sec", 0.0))
		if stun_sec > 0.0 and target != null and is_instance_valid(target):
			UnitStatusEffects.apply_stun(target, stun_sec)
	else:
		result = pipeline.apply({"attacker": attacker, "target": target, "source_kind": "weapon"})
	result["id"] = int(f.get("id", -1))
	result["visual_only"] = false
	projectile_resolved.emit(result)
