class_name SummonUnitAbility
extends RefCounted

## 召唤单位（Logic）：AHwe 水元素等在施法者面前即时召唤（非点目标）。

const ABIL_WATER_ELEMENTAL := "AHwe"


static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var id := abil_id.strip_edges()
	if id == ABIL_WATER_ELEMENTAL:
		return try_cast_instant(caster, id, ctx)
	return {"ok": false, "reason": "未实现的召唤技能", "unit": null}


static func try_cast_instant(caster: Node3D, abil_id: String, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	if caster == null or not is_instance_valid(caster):
		out["reason"] = "无施法者"
		return out
	var id := abil_id.strip_edges()
	var lv := AbilityCatalog.level_for(caster, id)
	var check := AbilityCastRules.can_cast_self(caster, id, lv)
	if not bool(check.get("ok", false)):
		return check
	var goal := summon_goal_in_front(caster, id, lv)
	return _spawn_at(caster, id, lv, goal, ctx)


static func summon_goal_in_front(caster: Node3D, abil_id: String, level: int) -> Vector2:
	var ab := AbilityCatalog.data(abil_id)
	var offset := 128.0
	if ab != null:
		var area := ab.area_at(ab.clamp_level(level))
		if area > 0.0:
			offset = area
	var caster_xy := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var facing := _caster_facing_wc3(caster)
	var dir := Vector2(cos(facing), sin(facing))
	if dir.length_squared() < 0.0001:
		dir = Vector2(0.0, -1.0)
	return caster_xy + dir.normalized() * offset


static func _caster_facing_wc3(caster: Node3D) -> float:
	var ud: Dictionary = caster.get_meta("unit_data", {})
	if ud.has("angle"):
		return float(ud.get("angle", 0.0))
	return float(caster.rotation.y)


static func _spawn_at(
	caster: Node3D,
	abil_id: String,
	lv: int,
	goal_wc3: Vector2,
	ctx: Dictionary
) -> Dictionary:
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	var unit_id := ab.summon_unit_id_at(lv)
	if unit_id.is_empty():
		return {"ok": false, "reason": "无召唤单位"}
	var map_root: Node = ctx.get("map_root")
	var hf: Variant = ctx.get("heightfield")
	if map_root == null or hf == null or not map_root.has_method("add_unit_instance"):
		return {"ok": false, "reason": "地图未就绪"}
	var owner := int(caster.get_meta("unit_data", {}).get("owner", 0))
	var entry := {
		"typeId": unit_id,
		"position": {"x": goal_wc3.x, "y": goal_wc3.y, "z": 0.0},
		"angle": _caster_facing_wc3(caster),
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner,
		"flags": 2,
		"creationNumber": int(ctx.get("creation_number", 0)),
		"variation": 0,
	}
	var hf_dict: Dictionary = {}
	if hf is Dictionary:
		hf_dict = hf as Dictionary
	elif hf != null and hf.has_method("as_dict_view"):
		hf_dict = hf.call("as_dict_view") as Dictionary
	elif hf != null and hf.has_method("to_dict"):
		hf_dict = hf.call("to_dict") as Dictionary
	var node := map_root.call("add_unit_instance", entry, hf_dict) as Node3D
	if node == null:
		return {"ok": false, "reason": "召唤失败"}
	UnitLife.ensure(node)
	UnitMana.ensure(node)
	var ensure_ai: Callable = ctx.get("ensure_unit_ai", Callable())
	if ensure_ai.is_valid():
		ensure_ai.call(node)
	InteractionSetup.attach(node)
	var dur := ab.duration_at(lv)
	if dur > 0.0:
		var life := SummonLifetime.new()
		life.name = "SummonLifetime"
		node.add_child(life)
		var kill_cb: Callable = ctx.get("kill_unit", Callable())
		life.configure(dur, kill_cb)
	node.set_meta("summon_caster_id", caster.get_instance_id())
	AbilityCastRules.commit_cost(caster, abil_id, lv)
	return {"ok": true, "reason": "", "unit": node}
