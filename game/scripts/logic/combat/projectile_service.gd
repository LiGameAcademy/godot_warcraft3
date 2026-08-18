class_name ProjectileService
extends RefCounted

## Logic 弹道推进（Game Logic · combat）。
## - missile 投送：飞行结束后 DamagePipeline（禁止 Present 回调扣血）
## - instant 远程：仅登记视觉壳（visual_only），伤害已在 AttackController dmgpt 结算

signal projectile_launched(info: Dictionary) ## Present 镜像用
signal projectile_resolved(result: Dictionary) ## 命中结算后（含 visual_only 空结果）

var pipeline: DamagePipeline = null
var _next_id: int = 1
var _flights: Array[Dictionary] = []


## 发射。visual_only=true 时到点不结算伤害。
func fire(attacker: Node3D, target: Node3D, visual_only: bool = false) -> int:
	if attacker == null or target == null:
		return -1
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return -1
	var from_xy := Wc3Coords.godot_to_wc3_xy(attacker.global_position)
	var to_xy := Wc3Coords.godot_to_wc3_xy(target.global_position)
	var launch := CombatQuery.launch_offset_wc3(attacker)
	var impact_z := CombatQuery.impact_z_wc3(attacker)
	var from_wc3 := Vector3(from_xy.x + launch.x, from_xy.y + launch.y, launch.z)
	var to_wc3 := Vector3(to_xy.x, to_xy.y, impact_z)
	var dist := Vector2(from_wc3.x, from_wc3.y).distance_to(Vector2(to_wc3.x, to_wc3.y))
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
		"speed_wc3": speed,
		"duration": duration,
		"elapsed": 0.0,
		"visual_only": visual_only,
		"alive": true,
	}
	_flights.append(info)
	projectile_launched.emit(info.duplicate())
	if duration <= 0.001:
		_resolve_flight(info)
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
		if float(f["elapsed"]) >= float(f.get("duration", 0.0)):
			_resolve_flight(f)
			_flights.remove_at(i)
			continue
		i += 1


func cancel_attacker(attacker: Node3D) -> void:
	if attacker == null:
		return
	for f in _flights:
		if f.get("attacker") == attacker:
			f["alive"] = false
			f["visual_only"] = true


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
		return
	var result := pipeline.apply({"attacker": attacker, "target": target, "source_kind": "weapon"})
	result["id"] = int(f.get("id", -1))
	result["visual_only"] = false
	projectile_resolved.emit(result)
