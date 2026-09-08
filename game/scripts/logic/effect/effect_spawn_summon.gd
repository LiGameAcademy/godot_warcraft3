class_name EffectSpawnSummon
extends RefCounted

## 召唤原子：在 goal 处 add_unit_instance + 可选寿命。


static func run(ec: EffectContext, goal_wc3: Vector2) -> Node3D:
	if ec == null or ec.caster == null or not is_instance_valid(ec.caster):
		return null
	var ab := AbilityCatalog.data(ec.abil_id)
	if ab == null:
		return null
	var unit_id := ab.summon_unit_id_at(ec.level)
	if unit_id.is_empty():
		return null
	var map_root: Node = ec.ctx.get("map_root")
	var hf: Variant = ec.ctx.get("heightfield")
	if map_root == null or hf == null or not map_root.has_method("add_unit_instance"):
		return null
	var owner := int(ec.caster.get_meta("unit_data", {}).get("owner", 0))
	var entry := {
		"typeId": unit_id,
		"position": {"x": goal_wc3.x, "y": goal_wc3.y, "z": 0.0},
		"angle": _caster_facing_wc3(ec.caster),
		"scale": {"x": 1.0, "y": 1.0, "z": 1.0},
		"owner": owner,
		"flags": 2,
		"creationNumber": int(ec.ctx.get("creation_number", 0)),
		"variation": 0,
		"spawn_anim": "Birth",
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
		return null
	UnitLife.ensure(node)
	UnitMana.ensure(node)
	var ensure_ai: Callable = ec.ctx.get("ensure_unit_ai", Callable())
	if ensure_ai.is_valid():
		ensure_ai.call(node)
	InteractionSetup.attach(node)
	var dur := ab.duration_at(ec.level)
	if dur > 0.0:
		var life := SummonLifetime.new()
		life.name = "SummonLifetime"
		node.add_child(life)
		var kill_cb: Callable = ec.ctx.get("kill_unit", Callable())
		life.configure(dur, kill_cb)
	node.set_meta("summon_caster_id", ec.caster.get_instance_id())
	ec.result["unit"] = node
	return node


static func goal_in_front(caster: Node3D, abil_id: String, level: int) -> Vector2:
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


## 以当前模型朝向为准（unit_data.angle 多为出生朝向，移动后会过期）。
static func _caster_facing_wc3(caster: Node3D) -> float:
	if caster == null:
		return 0.0
	return float(caster.rotation.y)
