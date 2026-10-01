extends RefCounted

const DefinitionLayers: GDScript = preload("res://addons/rts_content/definitions/definition_layers.gd")
var _units: Dictionary
var _destructables: Dictionary
var _doodads: Dictionary
var _store: Node

func _init(units: Dictionary, destructables: Dictionary, doodads: Dictionary, store: Node) -> void:
	_units = units
	_destructables = destructables
	_doodads = doodads
	_store = store

func load_default() -> void:
	_load_unit_ui()
	_merge_unit_data()
	_load_unit_display_names()
	_inject_start_location()
	_inject_patch_critters()
	_load_destructables()
	_load_doodads()

## Same Func/Strings profile as gameplay catalogs; empty values intentionally clear.
func _load_unit_display_names() -> void:
	for race: String in ["Human", "Orc", "Undead", "NightElf", "Neutral", "Campaign"]:
		var names: Dictionary = DefinitionLayers.read_rows("Units/%sUnitStrings.txt" % race)
		var funcs: Dictionary = DefinitionLayers.read_rows("Units/%sUnitFunc.txt" % race)
		for id: String in _units:
			var entry: Dictionary = _units[id]
			var name_row: Dictionary = names.get(id, {})
			var func_row: Dictionary = funcs.get(id, {})
			if name_row.has("name"):
				entry["name"] = str(name_row["name"])
				entry["name_key"] = id
			if func_row.has("art"):
				entry["art"] = str(func_row["art"]).replace("\\", "/")
			if func_row.has("buttonpos"):
				var parts: PackedStringArray = str(func_row["buttonpos"]).split(",")
				entry["button_pos"] = Vector2i(int(parts[0]) if parts.size() > 0 else 0,
					int(parts[1]) if parts.size() > 1 else 0)

## 合并 UnitData：race / moveHeight / pathTex 等。
func _merge_unit_data() -> void:
	var store: Node = _store
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 UnitData")
		return
	store.ensure_table(UnitDataDef.TABLE_NAME)
	for id: String in store.get_ids(UnitDataDef.TABLE_NAME):
		if not _units.has(id):
			continue
		var d: UnitDataDef = store.get_row(UnitDataDef.TABLE_NAME, id) as UnitDataDef
		if d == null:
			continue
		var e: Dictionary = _units[id]
		var race: String = d.race.strip_edges().to_lower()
		e["race"] = race if not race.is_empty() else "other"
		e["move_height"] = d.move_height
		var path_tex: String = d.path_tex.strip_edges()
		e["path_tex"] = path_tex if not path_tex.is_empty() else "_"
		if str(e.get("name", "")).is_empty():
			var comment: String = d.comment.strip_edges()
			if not comment.is_empty() and comment != "_":
				e["name"] = comment
		_units[id] = e
	_merge_unit_balance()


func _merge_unit_balance() -> void:
	var store: Node = _store
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 UnitBalance")
		return
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	for id: String in store.get_ids(UnitBalanceDef.TABLE_NAME):
		if not _units.has(id):
			continue
		var d: UnitBalanceDef = store.get_row(UnitBalanceDef.TABLE_NAME, id) as UnitBalanceDef
		if d == null:
			continue
		var e: Dictionary = _units[id]
		e["is_building"] = d.isbldg
		e["level"] = d.level
		var ts: String = d.tilesets.strip_edges()
		if ts.is_empty() or ts == "-" or ts == "_":
			ts = "*"
		e["tilesets"] = ts
		e["collision"] = d.collision
		_units[id] = e


## WE 编辑器专用「开始点」(sloc)：不在 UnitUI.slk，由 WorldEditData 注入。
## 参考 HiveWE / WorldEditData：模型 Objects\StartLocation、脚印 16x16、图标 StartingLocation。
## path_tex 仅作编辑器占位预览；运行时寻路见 Wc3PathingMap.apply_entity_pathing（显式跳过 sloc）。
func _inject_start_location() -> void:
	if _units.has("sloc"):
		return
	_units["sloc"] = {
		"id": "sloc",
		"name": "Start Location",
		"name_key": "WESTRING_STARTLOCATION",
		"file": "Objects\\StartLocation\\StartLocation",
		"kind": "unit",
		"num_var": 1,
		"unit_class": "0StartLoc",
		"sort_ui": "0",
		"campaign": false,
		"special": false,
		"in_editor": true,
		"hidden_in_editor": false,
		"hostile_pal": "",
		"tileset_specific": false,
		"use_click_helper": false,
		"model_scale": 1.0,
		"def_scale": 5.0,
		"race": "*",
		"move_height": 0.0,
		"path_tex": "PathTextures\\16x16Simple.tga",
		"is_building": true,
		"nbmm_icon": false,
		"level": -1,
		"tilesets": "*",
		"art": "ReplaceableTextures\\WorldEditUI\\StartingLocation",
		"button_pos": Vector2i.ZERO,
		"collision": 50.0,
		"is_start_location": true,
	}


## 补丁单位（1.17+）：主 unitUI.slk / 解包 listfile 常缺，Echo Isles 等图仍会用到。
## 浣熊 nrac：模型在 War3Patch.mpq（listfile 无条目，需按路径强制解包）。
func _inject_patch_critters() -> void:
	if not _units.has("nrac"):
		_units["nrac"] = {
			"id": "nrac",
			"name": "浣熊",
			"name_key": "",
			"file": "units\\critters\\Raccoon\\Raccoon",
			"kind": "unit",
			"num_var": 1,
			"unit_class": "animal",
			"sort_ui": "o2",
			"campaign": false,
			"special": false,
			"in_editor": true,
			"hidden_in_editor": false,
			"hostile_pal": "",
			"tileset_specific": false,
			"use_click_helper": false,
			"model_scale": 1.0,
			"def_scale": 1.0,
			"race": "critters",
			"move_height": 0.0,
			"path_tex": "_",
			"is_building": false,
			"nbmm_icon": false,
			"level": 1,
			"tilesets": "*",
			"art": "ReplaceableTextures\\CommandButtons\\BTNRacoon",
			"button_pos": Vector2i.ZERO,
			"collision": 16.0,
		}


func _load_unit_ui() -> void:
	var store: Node = _store
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 UnitUI")
		return
	store.ensure_table(UnitUiDef.TABLE_NAME)
	for id: String in store.get_ids(UnitUiDef.TABLE_NAME):
		var d: UnitUiDef = store.get_row(UnitUiDef.TABLE_NAME, id) as UnitUiDef
		if d == null or d.unit_uiid.is_empty():
			continue
		# name 先用 SLK name 列（常为键/占位）；正式显示名由 *UnitStrings 覆盖
		var name: String = d.name_key.strip_edges()
		if name.is_empty() or name == "_":
			name = id
		_units[id] = {
			"id": id,
			"name": name,
			"file": d.file,
			"file_ver_flags": d.file_ver_flags,
			"kind": "unit",
			"num_var": 1,
			"unit_class": d.unit_class,
			"sort_ui": d.sort_ui,
			"campaign": d.campaign,
			"special": d.special,
			"in_editor": d.in_editor,
			"hidden_in_editor": d.hidden_in_editor,
			# 保留字符串形态以兼容注入条目；Def 已把 "-" / 0 / 1 规范为 bool
			"hostile_pal": "1" if d.hostile_pal else "",
			"tileset_specific": d.tileset_specific,
			"use_click_helper": d.use_click_helper,
			"model_scale": d.model_scale if d.model_scale > 0.0 else 1.0,
			"def_scale": d.scale if d.scale > 0.0 else 1.0,
			"race": "other",
			"move_height": 0.0,
			"path_tex": "_",
			"is_building": false,
			"nbmm_icon": d.nbmm_icon,
			"level": -1,
			"tilesets": "*",
			"art": "",
			"button_pos": Vector2i.ZERO,
		}


func _load_destructables() -> void:
	var store: Node = _store
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 DestructableData")
		return
	store.ensure_table(DestructableDataDef.TABLE_NAME)
	for id: String in store.get_ids(DestructableDataDef.TABLE_NAME):
		var d: DestructableDataDef = store.get_row(DestructableDataDef.TABLE_NAME, id) as DestructableDataDef
		if d == null or d.destructable_id.is_empty():
			continue
		var tilesets: String = d.tilesets.strip_edges()
		if tilesets.is_empty():
			tilesets = "*"
		_destructables[id] = {
			"id": id,
			"name": d.display_name(),
			"name_key": d.name_key,
			"file": d.file,
			"kind": "destructable",
			"category": d.category.to_upper(),
			"tilesets": tilesets,
			"num_var": d.num_var if d.num_var > 0 else 1,
			"tex_file": d.tex_file,
			"tex_id": d.tex_id,
			# 可破坏物无独立 defScale；WE 放置默认用 minScale
			"def_scale": d.min_scale if d.min_scale > 0.0 else 1.0,
			"min_scale": d.min_scale if d.min_scale > 0.0 else 1.0,
			"max_scale": d.max_scale if d.max_scale > 0.0 else 1.0,
			"can_place_rand_scale": d.can_place_rand_scale,
			"use_click_helper": d.use_click_helper,
			"sel_size": d.sel_size,
			"path_tex": d.path_tex,
			"fixed_rot": d.fixed_rot,
			# DestructableData 无 visRadius；Catalog 预览距离沿用旧默认 50
			"vis_radius": 50.0,
			"ignore_model_click": false,
		}


func _load_doodads() -> void:
	var store: Node = _store
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 Doodads")
		return
	store.ensure_table(DoodadDataDef.TABLE_NAME)
	for id: String in store.get_ids(DoodadDataDef.TABLE_NAME):
		var d: DoodadDataDef = store.get_row(DoodadDataDef.TABLE_NAME, id) as DoodadDataDef
		if d == null or d.dood_id.is_empty():
			continue
		var tilesets: String = d.tilesets.strip_edges()
		if tilesets.is_empty():
			tilesets = "*"
		_doodads[id] = {
			"id": id,
			"name": d.display_name(),
			"name_key": d.name_key,
			"file": d.file,
			"kind": "doodad",
			"category": d.category.to_upper(),
			"tilesets": tilesets,
			"num_var": d.num_var if d.num_var > 0 else 1,
			"def_scale": d.def_scale if d.def_scale > 0.0 else 1.0,
			"min_scale": d.min_scale if d.min_scale > 0.0 else 1.0,
			"max_scale": d.max_scale if d.max_scale > 0.0 else 1.0,
			"can_place_rand_scale": d.can_place_rand_scale,
			"use_click_helper": d.use_click_helper,
			"sel_size": d.sel_size,
			"path_tex": d.path_tex,
			"fixed_rot": d.fixed_rot,
			"vis_radius": d.vis_radius if d.vis_radius > 0.0 else 50.0,
			"ignore_model_click": d.ignore_model_click,
		}


