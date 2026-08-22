class_name SummonUnitAbility
extends RefCounted

## 点目标召唤（Logic · P0 具体实现：AHwe 水元素）。
## 依赖由 Director 注入，避免 map 层反向引用。

const ABIL_WATER_ELEMENTAL := "AHwe"


static func try_cast(caster: Node3D, abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": "", "unit": null}
	if abil_id.strip_edges() != ABIL_WATER_ELEMENTAL:
		out["reason"] = "未实现的技能"
		return out
	return _cast_water_elemental(caster, goal_wc3, ctx)


static func _cast_water_elemental(caster: Node3D, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var abil_id := ABIL_WATER_ELEMENTAL
	var lv := AbilityCatalog.level_for(caster, abil_id)
	var check := AbilityCastRules.can_cast_point(caster, abil_id, goal_wc3, lv)
	if not bool(check.get("ok", false)):
		return check
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
		"angle": MeleeBootstrap.UNIT_FACING_RAD,
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner,
		"flags": 2,
		"creationNumber": int(ctx.get("creation_number", 0)),
		"variation": 0,
	}
	var hf_dict: Dictionary = hf.as_dict_view() if hf.has_method("as_dict_view") else hf as Dictionary
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
		life.configure(dur)
	node.set_meta("summon_caster_id", caster.get_instance_id())
	AbilityCastRules.commit_cost(caster, abil_id, lv)
	return {"ok": true, "reason": "", "unit": node}
