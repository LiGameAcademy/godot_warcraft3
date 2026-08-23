class_name AbilityAutoCast
extends RefCounted

## 自动/手动施法切换（Logic）：读 UnitAbilities.auto + Func Unart。

const META := "ability_autocast" ## abil_id → bool


static func supports(abil_id: String) -> bool:
	var id := abil_id.strip_edges()
	if id.is_empty():
		return false
	var row := CommandButtonCatalog.get_shared().get_ability(id)
	return not str(row.get("unart", "")).strip_edges().is_empty()


static func ensure_defaults(unit: Node3D) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	if unit.has_meta(META):
		return
	var tid := str(unit.get_meta("unit_data", {}).get("typeId", "")).strip_edges()
	var default_auto := _default_auto_for_type(tid)
	var map := {}
	var abil_ids := CommandButtonCatalog.get_shared().get_all_abil_list(tid)
	if abil_ids.is_empty():
		abil_ids = _ability_ids_from_store(tid)
	for abil_id in abil_ids:
		var id := str(abil_id).strip_edges()
		if not supports(id):
			continue
		map[id] = id == default_auto
	unit.set_meta(META, map)


static func map_of(unit: Node3D) -> Dictionary:
	ensure_defaults(unit)
	if unit == null or not unit.has_meta(META):
		return {}
	var m: Variant = unit.get_meta(META)
	return m as Dictionary if m is Dictionary else {}


static func is_enabled(unit: Node3D, abil_id: String) -> bool:
	var id := abil_id.strip_edges()
	if id.is_empty() or not supports(id):
		return false
	return bool(map_of(unit).get(id, false))


static func set_enabled(unit: Node3D, abil_id: String, enabled: bool) -> void:
	var id := abil_id.strip_edges()
	if id.is_empty() or not supports(id):
		return
	ensure_defaults(unit)
	var m := map_of(unit).duplicate(true)
	# WC3：同一单位同一时刻最多一个自动施法开启。
	if enabled:
		for other in m.keys():
			m[str(other)] = str(other) == id
	else:
		m[id] = false
	unit.set_meta(META, m)


static func toggle(unit: Node3D, abil_id: String) -> bool:
	var id := abil_id.strip_edges()
	if id.is_empty() or not supports(id):
		return false
	var next := not is_enabled(unit, id)
	set_enabled(unit, id, next)
	return next


static func enabled_ability_ids(unit: Node3D) -> PackedStringArray:
	var out := PackedStringArray()
	for id in map_of(unit).keys():
		if bool(map_of(unit).get(id, false)):
			out.append(str(id))
	return out


static func _default_auto_for_type(type_id: String) -> String:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		return ""
	var store := _def_store()
	if store == null:
		return ""
	store.ensure_table(UnitAbilitiesDef.TABLE_NAME)
	var def := store.get_row(UnitAbilitiesDef.TABLE_NAME, tid) as UnitAbilitiesDef
	if def == null:
		return ""
	return def.auto.strip_edges()


static func _ability_ids_from_store(type_id: String) -> PackedStringArray:
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	store.ensure_table(UnitAbilitiesDef.TABLE_NAME)
	var def := store.get_row(UnitAbilitiesDef.TABLE_NAME, type_id) as UnitAbilitiesDef
	if def == null:
		return PackedStringArray()
	return def.all_ability_ids()


static func _def_store() -> Node:
	var tree := Engine.get_main_loop()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")
