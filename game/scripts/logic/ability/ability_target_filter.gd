class_name AbilityTargetFilter
extends RefCounted

## AbilityData.targs 目标过滤器（Logic）。
## 各分类内 OR、分类间 AND（对齐 WC3 对象编辑器语义）。

const _TYPE_FLAGS := [
	"ground", "air", "structure", "ward", "item", "tree", "wall", "debris",
]
const _AFFIL_FLAGS := ["friend", "enemy", "neutral", "self", "player", "allies"]
const _CLASS_FLAGS := ["organic", "mechanical", "hero", "nonhero", "ancient", "nonancient"]
const _STATE_FLAGS := ["vuln", "invu"]


static func matches(caster: Node, target: Node, abil_id: String) -> bool:
	var ab := _ability_data(abil_id)
	if ab == null:
		return true
	return matches_targs(caster, target, ab.targs)


static func _ability_data(abil_id: String) -> AbilityDataDef:
	var id := abil_id.strip_edges()
	if id.is_empty():
		return null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var store := tree.root.get_node_or_null("Wc3DefStore")
	if store == null:
		return null
	store.ensure_table(AbilityDataDef.TABLE_NAME)
	return store.get_row(AbilityDataDef.TABLE_NAME, id) as AbilityDataDef


static func matches_targs(caster: Node, target: Node, targs: String) -> bool:
	var raw := targs.strip_edges().to_lower()
	if raw.is_empty() or raw == "-":
		return true
	var flags := _parse_flags(raw)
	if _category_active(flags, _TYPE_FLAGS) and not _matches_type(target, flags):
		return false
	if _category_active(flags, _AFFIL_FLAGS) and not _matches_affiliation(caster, target, flags):
		return false
	if _category_active(flags, _CLASS_FLAGS) and not _matches_class(target, flags):
		return false
	if _category_active(flags, _STATE_FLAGS) and not _matches_state(target, flags):
		return false
	return true


static func _parse_flags(raw: String) -> Dictionary:
	var out := {}
	for part in raw.split(",", false):
		var f := part.strip_edges()
		if not f.is_empty():
			out[f] = true
	return out


static func _category_active(flags: Dictionary, category: Array) -> bool:
	for f in category:
		if flags.has(f):
			return true
	return false


static func _target_profile(target: Node) -> Dictionary:
	var ud := CombatQuery.unit_data_of(target)
	var tid := CombatQuery.type_id_of(target)
	var targ := ""
	var type_tags := ""
	if ud != null:
		targ = ud.targ_type.strip_edges().to_lower()
		type_tags = ud.type_name.strip_edges()
	var is_struct := (
		targ == "structure"
		or BuildingCatalog.is_building(tid)
		or BuildingVisual.is_building(tid)
	)
	var is_air := targ == "air"
	var is_ground := targ == "ground" or (targ.is_empty() and not is_struct)
	return {
		"targ": targ,
		"type_tags": type_tags,
		"type_tags_lc": type_tags.to_lower(),
		"is_structure": is_struct,
		"is_air": is_air,
		"is_ground": is_ground,
	}


static func _matches_type(target: Node, flags: Dictionary) -> bool:
	var p := _target_profile(target)
	if flags.has("ground") and bool(p.get("is_ground", false)):
		return true
	if flags.has("air") and bool(p.get("is_air", false)):
		return true
	if flags.has("structure") and bool(p.get("is_structure", false)):
		return true
	if flags.has("ward") and str(p.get("targ", "")) == "ward":
		return true
	if flags.has("item") and str(p.get("targ", "")) == "item":
		return true
	if flags.has("tree") and str(p.get("targ", "")) == "tree":
		return true
	if flags.has("wall") and str(p.get("targ", "")) == "wall":
		return true
	if flags.has("debris") and str(p.get("targ", "")) == "debris":
		return true
	return false


static func _matches_affiliation(caster: Node, target: Node, flags: Dictionary) -> bool:
	if caster == target:
		return flags.has("self")
	var oa := CombatQuery.owner_of(caster)
	var ob := CombatQuery.owner_of(target)
	if flags.has("friend") and oa >= 0 and oa == ob:
		return true
	if flags.has("enemy") and CombatQuery.is_hostile(caster, target):
		return true
	if flags.has("neutral") and CombatQuery.is_neutral_owner(ob):
		return true
	if flags.has("allies") and oa >= 0 and oa == ob:
		return true
	if flags.has("player") and ob >= 0 and ob < CombatQuery.NEUTRAL_OWNER_MIN:
		return true
	return false


static func _matches_class(target: Node, flags: Dictionary) -> bool:
	var p := _target_profile(target)
	var tid := CombatQuery.type_id_of(target)
	var is_struct := bool(p.get("is_structure", false))
	var type_lc := str(p.get("type_tags_lc", ""))
	var is_mech := type_lc.contains("mechanical")
	var is_organic := not is_struct and not is_mech
	var is_hero := TechPresence.is_hero_id(tid)
	var is_ancient := type_lc.contains("ancient")
	if flags.has("organic") and is_organic:
		return true
	if flags.has("mechanical") and is_mech:
		return true
	if flags.has("hero") and is_hero:
		return true
	if flags.has("nonhero") and not is_hero:
		return true
	if flags.has("ancient") and is_ancient:
		return true
	if flags.has("nonancient") and not is_ancient:
		return true
	return false


static func _matches_state(_target: Node, _flags: Dictionary) -> bool:
	# 竖切暂无无敌/ vulnerability 模型；不据此拦截。
	return true
