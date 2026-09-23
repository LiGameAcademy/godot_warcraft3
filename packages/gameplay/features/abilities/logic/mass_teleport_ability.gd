class_name MassTeleportAbility
extends RefCounted

## 群体传送（Logic · AHmt）：施法者周围 Area 内友军（含自身）传送到点目标。
## 读条时长见 AbilityCastCatalog.cast_time_sec（DataB；CastN 在 SLK 为 0）。

const ABIL_MASS_TELEPORT := "AHmt"


static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null, "teleported_count": 0}
	if abil_id.strip_edges() != ABIL_MASS_TELEPORT:
		out["reason"] = "未实现的技能"
		return out
	if caster == null or not is_instance_valid(caster) or goal_wc3 == Vector2.INF:
		out["reason"] = "无效施法"
		return out
	var lv := AbilityCatalog.level_for(caster, ABIL_MASS_TELEPORT)
	var check := AbilityCastRules.can_cast_point(caster, ABIL_MASS_TELEPORT, goal_wc3, lv)
	if not bool(check.get("ok", false)):
		out["reason"] = str(check.get("reason", "无法施法"))
		return out
	var ab := AbilityCatalog.data(ABIL_MASS_TELEPORT)
	if ab == null:
		out["reason"] = "无技能数据"
		return out
	var host_cb: Callable = ctx.get("unit_host", Callable())
	if not host_cb.is_valid():
		out["reason"] = "单位层未就绪"
		return out
	var unit_host: Node = host_cb.call() as Node
	if unit_host == null:
		out["reason"] = "单位层未就绪"
		return out
	var teleport_cb: Callable = ctx.get("teleport_unit_wc3", Callable())
	if not teleport_cb.is_valid():
		out["reason"] = "传送服务未就绪"
		return out
	var path_query: PathQuery = ctx.get("path_query") as PathQuery
	var crowd: UnitCrowdQuery = ctx.get("crowd_query") as UnitCrowdQuery
	var radius := maxf(ab.area_at(lv), 1.0)
	var max_units := maxi(int(round(ab.data_a_at(lv))), 1)
	var center := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var candidates := _gather_candidates(unit_host, caster, center, radius)
	candidates.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var da := center.distance_squared_to(Wc3Coords.godot_to_wc3_xy(a.global_position))
		var db := center.distance_squared_to(Wc3Coords.godot_to_wc3_xy(b.global_position))
		return da < db
	)
	if candidates.is_empty():
		out["reason"] = "范围内无可传送单位"
		return out
	var take := mini(candidates.size(), max_units)
	var batch: Array = []
	for i in range(take):
		var unit: Node3D = candidates[i]
		if unit == null or not is_instance_valid(unit):
			continue
		_halt_unit(unit)
		batch.append(unit)
	if batch.is_empty():
		out["reason"] = "传送失败"
		return out
	MassTeleportPresenter.play_departures(batch, ctx)
	var moved := 0
	for unit in batch:
		var u := unit as Node3D
		if u == null or not is_instance_valid(u):
			continue
		var tid := str(u.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
		var dest := TrainSpawn.resolve_with_displace(goal_wc3, goal_wc3, u, tid, path_query, crowd)
		teleport_cb.call(u, dest)
		moved += 1
	if moved <= 0:
		out["reason"] = "传送失败"
		return out
	MassTeleportPresenter.play_arrival(caster, goal_wc3, ctx)
	AbilityCastRules.commit_cost(caster, ABIL_MASS_TELEPORT, lv)
	out["ok"] = true
	out["teleported_count"] = moved
	return out


static func _gather_candidates(
	unit_host: Node,
	caster: Node3D,
	center_wc3: Vector2,
	radius_wc3: float
) -> Array[Node3D]:
	var raw := CombatQuery.units_friendly_in_radius(unit_host, caster, center_wc3, radius_wc3)
	var out: Array[Node3D] = []
	for n in raw:
		if not (n is Node3D) or not is_instance_valid(n):
			continue
		var unit := n as Node3D
		if not _can_teleport(unit):
			continue
		out.append(unit)
	return out


static func _can_teleport(unit: Node3D) -> bool:
	if unit == null or not is_instance_valid(unit):
		return false
	var tid := str(unit.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	if tid.is_empty() or BuildingCatalog.is_building(tid):
		return false
	if unit.has_meta("life"):
		if float(unit.get_meta("life", 0.0)) <= 0.0:
			return false
	elif UnitLife.ratio(unit) <= 0.0:
		return false
	return true


static func _halt_unit(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var nav := unit.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
	var hc := unit.get_node_or_null("HarvestController") as HarvestController
	if hc != null:
		hc.abort()
	var ac := unit.get_node_or_null("AttackController") as AttackController
	if ac != null:
		ac.cancel()
	var bc := unit.get_node_or_null("BuildController") as BuildController
	if bc != null:
		bc.leave_or_abort()
	var uai := UnitAI.of(unit)
	if uai != null:
		uai.yield_to_player()
