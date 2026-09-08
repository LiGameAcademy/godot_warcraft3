class_name Wc3IdCatalog
extends RefCounted
## 从 slk-exported JSON 建立四字符 ID → 显示信息 / GLB 路径。


var _units: Dictionary = {}
var _destructables: Dictionary = {}
var _doodads: Dictionary = {}


func load_default() -> void:
	_load_unit_ui()
	_merge_unit_data()
	_load_unit_display_names()
	_inject_start_location()
	_inject_patch_critters()
	_load_destructables()
	_load_doodads()


func lookup(type_id: String) -> Dictionary:
	if _units.has(type_id):
		return _units[type_id]
	if _destructables.has(type_id):
		return _destructables[type_id]
	if _doodads.has(type_id):
		return _doodads[type_id]
	return {"id": type_id, "name": type_id, "file": "", "kind": "unknown", "num_var": 1}


## 可放置物列表（装饰物 + 可破坏物），按显示名排序。
## 每项为 lookup() 同形 Dictionary。
func list_placeables(include_doodads: bool = true, include_destructables: bool = true) -> Array:
	return list_placeables_filtered("", "", include_doodads, include_destructables)


## 按地形集字母 + 分类码筛选。
## tileset_letter 空/"*" = 不限；条目 tilesets 含 "*" 或含该字母才通过。
## category_code 空/"*" = 不限；否则精确匹配 entry.category。
func list_placeables_filtered(
	tileset_letter: String = "",
	category_code: String = "",
	include_doodads: bool = true,
	include_destructables: bool = true,
) -> Array:
	var out: Array = []
	var ts := tileset_letter.strip_edges().to_upper()
	var cat := category_code.strip_edges().to_upper()
	if include_doodads:
		for id in _doodads.keys():
			var e: Dictionary = _doodads[id]
			if _entry_matches(e, ts, cat):
				out.append(e)
	if include_destructables:
		for id in _destructables.keys():
			var e2: Dictionary = _destructables[id]
			if _entry_matches(e2, ts, cat):
				out.append(e2)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out


## WE 单位面板种族下拉（固定桶；勿直接展开 UnitData.race，否则 critters/commoner 会重复成两个「中立无敌意」）。
## 对齐经典 WE：人族 / 兽族 / 不死 / 暗夜 / 中立 / 中立-娜迦。
const UNIT_PALETTE_RACE_BUCKETS: Array = [
	{"id": "human", "name_key": "WESTRING_RACE_HUMAN", "races": ["human"]},
	{"id": "orc", "name_key": "WESTRING_RACE_ORC", "races": ["orc"]},
	{"id": "undead", "name_key": "WESTRING_RACE_UNDEAD", "races": ["undead"]},
	{"id": "nightelf", "name_key": "WESTRING_RACE_NIGHTELF", "races": ["nightelf"]},
	{
		"id": "neutral",
		"name_key": "WESTRING_RACE_NEUTRAL",
		"races": ["creeps", "critters", "commoner", "demon", "other"],
	},
	{"id": "naga", "name_key": "WESTRING_RACE_NEUTRAL_NAGA", "races": ["naga"]},
]


## 单位列表筛选（对齐 WE 单位面板）。
## race 空/"*" = 不限；可为面板桶 id（human/neutral/…）或原始 UnitData.race。
## group: ""|"*"|"standard"|"melee"|"campaign"|"special"。
## 仅 in_editor 且非 hidden。
func list_units_filtered(race: String = "", group: String = "standard") -> Array:
	var out: Array = []
	var want_races := _expand_palette_race(race)
	var want_group := group.strip_edges().to_lower()
	if want_group.is_empty():
		want_group = "*"
	for id in _units.keys():
		var e: Dictionary = _units[id]
		if not bool(e.get("in_editor", true)):
			continue
		if bool(e.get("hidden_in_editor", false)):
			continue
		if not want_races.is_empty():
			var ur := str(e.get("race", "")).to_lower()
			if not want_races.has(ur):
				continue
		var is_campaign: bool = bool(e.get("campaign", false))
		var is_special: bool = bool(e.get("special", false))
		match want_group:
			"campaign":
				if not is_campaign:
					continue
			"special":
				if not is_special:
					continue
			"standard", "melee":
				if is_campaign:
					continue
			"*":
				pass
			_:
				pass
		out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out


## 面板种族桶 id 列表（仅含当前有可编辑单位的项）。
func list_unit_races() -> PackedStringArray:
	var present: Dictionary = {}
	for id in _units.keys():
		var e: Dictionary = _units[id]
		if not bool(e.get("in_editor", true)) or bool(e.get("hidden_in_editor", false)):
			continue
		var r := str(e.get("race", "other")).to_lower()
		if r.is_empty():
			r = "other"
		present[r] = true
	var out := PackedStringArray()
	for bucket in UNIT_PALETTE_RACE_BUCKETS:
		var has_any := false
		for raw in bucket.get("races", []):
			if present.has(str(raw)):
				has_any = true
				break
		if has_any:
			out.append(str(bucket.get("id", "")))
	return out


## 面板种族桶 → 显示名 WESTRING key。
func unit_palette_race_name_key(palette_race_id: String) -> String:
	var pid := palette_race_id.strip_edges().to_lower()
	for bucket in UNIT_PALETTE_RACE_BUCKETS:
		if str(bucket.get("id", "")) == pid:
			return str(bucket.get("name_key", ""))
	return "WESTRING_RACE_OTHER"


## 面板种族桶 → UnitData.race 集合；空/"*" → 空 Dictionary（表示不限）。
func _expand_palette_race(race: String) -> Dictionary:
	var want := race.strip_edges().to_lower()
	var out: Dictionary = {}
	if want.is_empty() or want == "*":
		return out
	for bucket in UNIT_PALETTE_RACE_BUCKETS:
		if str(bucket.get("id", "")) == want:
			for raw in bucket.get("races", []):
				out[str(raw)] = true
			return out
	# 兼容直接传 UnitData.race
	out[want] = true
	return out


func unit_count() -> int:
	return _units.size()


func doodad_count() -> int:
	return _doodads.size()


func destructable_count() -> int:
	return _destructables.size()


func model_base_path(type_id: String) -> String:
	var info: Dictionary = lookup(type_id)
	var file := str(info.get("file", "")).replace("\\", "/")
	if file.is_empty() or file == "_":
		return ""
	if file.to_lower().ends_with(".mdx") or file.to_lower().ends_with(".mdl"):
		file = file.substr(0, file.length() - 4)
	return file


## UnitUI.fileVerFlags（0 = 仅基模；非 0 = 有 expansion 变体如 _V1）。
func model_file_ver_flags(type_id: String) -> int:
	return int(lookup(type_id).get("file_ver_flags", 0))


## 按内容包 Edition 解析模型 stem（可含 _V1）；再交给 converted_glb_path 拼 variation。
## 见 docs/data/CONTENT_PACKS.md · ContentPackRules。
func resolve_model_stem(type_id: String) -> String:
	var base := model_base_path(type_id)
	if base.is_empty():
		return ""
	var flags := model_file_ver_flags(type_id)
	for stem in ContentPackRules.expansion_model_candidates(base, flags):
		if _converted_stem_exists(stem):
			return stem
	return base


func _converted_stem_exists(stem: String) -> bool:
	if stem.is_empty():
		return false
	for ext in [".gltf", ".glb", ".scn"]:
		var p := RuntimeAssets.converted_path(stem + ext)
		if RuntimeAssets.file_exists(p):
			return true
	return false


## 解析已转换模型（优先 .gltf 外链贴图，回退旧 .glb）。
## 先按 ContentPackRules 选 Edition stem，再拼地图 variation 数字后缀。
func converted_glb_path(type_id: String, variation: int = 0) -> String:
	var base := resolve_model_stem(type_id)
	if base.is_empty():
		return ""
	var stems: PackedStringArray = []
	if variation > 0:
		stems.append("%s%d" % [base, variation])
	stems.append(base)
	stems.append("%s0" % base)
	for stem in stems:
		for ext in [".gltf", ".glb"]:
			var p := RuntimeAssets.converted_path(stem + ext)
			if RuntimeAssets.file_exists(p):
				return p
	return _scan_converted_model_file(base, variation)


## 目录扫描：SLK 路径大小写 / AltarofKings vs AltarOfKings 与磁盘不一致时兜底。
func _scan_converted_model_file(base: String, variation: int = 0) -> String:
	var dir_logical := base.get_base_dir()
	var stem_want := base.get_file().to_lower()
	var disk_dir := _resolve_converted_dir(dir_logical)
	if disk_dir.is_empty():
		return ""
	var da := DirAccess.open(disk_dir)
	if da == null:
		return ""
	var want_var := str(variation) if variation > 0 else ""
	var found_plain := ""
	da.list_dir_begin()
	var fname := da.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = da.get_next()
			continue
		var lower := fname.to_lower()
		if not (lower.ends_with(".gltf") or lower.ends_with(".glb")):
			fname = da.get_next()
			continue
		var file_stem := lower.get_basename()
		if file_stem == stem_want or file_stem == stem_want + "0":
			da.list_dir_end()
			return RuntimeAssets.converted_path("%s/%s" % [dir_logical, fname])
		if want_var.is_empty() and file_stem.begins_with(stem_want):
			found_plain = fname
		elif not want_var.is_empty() and file_stem == stem_want + want_var:
			da.list_dir_end()
			return RuntimeAssets.converted_path("%s/%s" % [dir_logical, fname])
		fname = da.get_next()
	da.list_dir_end()
	if not found_plain.is_empty():
		return RuntimeAssets.converted_path("%s/%s" % [dir_logical, found_plain])
	return ""


func _resolve_converted_dir(dir_logical: String) -> String:
	var direct := RuntimeAssets.project_abs(RuntimeAssets.converted_path(dir_logical))
	if not direct.is_empty() and DirAccess.dir_exists_absolute(direct):
		return direct
	# 在 Buildings/* / Units/* 下按末级目录名大小写无关匹配
	var leaf := dir_logical.get_file().to_lower()
	if leaf.is_empty():
		return ""
	for root in ["Buildings", "Units", "buildings", "units"]:
		var root_abs := RuntimeAssets.project_abs(RuntimeAssets.converted_path(root))
		if root_abs.is_empty() or not DirAccess.dir_exists_absolute(root_abs):
			continue
		var root_da := DirAccess.open(root_abs)
		if root_da == null:
			continue
		root_da.list_dir_begin()
		var race := root_da.get_next()
		while race != "":
			if race.begins_with("."):
				race = root_da.get_next()
				continue
			var race_path := "%s/%s" % [root, race]
			var race_abs := RuntimeAssets.project_abs(RuntimeAssets.converted_path(race_path))
			if DirAccess.dir_exists_absolute(race_abs):
				var race_da := DirAccess.open(race_abs)
				if race_da != null:
					race_da.list_dir_begin()
					var folder := race_da.get_next()
					while folder != "":
						if folder.begins_with("."):
							folder = race_da.get_next()
							continue
						if folder.to_lower() == leaf:
							race_da.list_dir_end()
							root_da.list_dir_end()
							return RuntimeAssets.project_abs(
								RuntimeAssets.converted_path("%s/%s" % [race_path, folder])
							)
						folder = race_da.get_next()
					race_da.list_dir_end()
			race = root_da.get_next()
		root_da.list_dir_end()
	return ""


## 肖像模型路径（*_Portrait / *_portrait）；无则空串。
## 与 body 共用 resolve_model_stem（TFT 下 Priest → Priest_V1_portrait）。
func portrait_glb_path(type_id: String) -> String:
	var base := resolve_model_stem(type_id)
	if base.is_empty():
		return ""
	var dir := base.get_base_dir()
	var stem := base.get_file()
	var stems: PackedStringArray = [
		"%s/%s_Portrait" % [dir, stem],
		"%s/%s_portrait" % [dir, stem],
	]
	# 常见大小写变体（Peasant vs peasant）
	if stem != stem.to_lower():
		stems.append("%s/%s_Portrait" % [dir, stem.to_lower()])
		stems.append("%s/%s_portrait" % [dir, stem.to_lower()])
	for s in stems:
		for ext in [".gltf", ".glb"]:
			var p := RuntimeAssets.converted_path(s + ext)
			if RuntimeAssets.file_exists(p):
				return p
	# 目录扫描兜底（大小写不一致时）
	var disk_dir := _resolve_converted_dir(dir)
	if disk_dir.is_empty():
		return ""
	var da := DirAccess.open(disk_dir)
	if da == null:
		return ""
	da.list_dir_begin()
	var fname := da.get_next()
	var want := stem.to_lower()
	while fname != "":
		var lower := fname.to_lower()
		if lower.ends_with("_portrait.gltf") or lower.ends_with("_portrait.glb"):
			var name_stem := lower.get_basename().trim_suffix("_portrait")
			# 精确匹配 stem（含 _V1）；勿用 begins_with，避免 Priest 误吃 Priest_V1_portrait
			if name_stem == want:
				var rel := "%s/%s" % [dir, fname]
				var found := RuntimeAssets.converted_path(rel)
				if RuntimeAssets.file_exists(found):
					da.list_dir_end()
					return found
		fname = da.get_next()
	da.list_dir_end()
	return ""


func _entry_matches(e: Dictionary, tileset_letter: String, category_code: String) -> bool:
	if not category_code.is_empty() and category_code != "*":
		if str(e.get("category", "")).to_upper() != category_code:
			return false
	if not tileset_letter.is_empty() and tileset_letter != "*":
		if not _tilesets_allow(str(e.get("tilesets", "")), tileset_letter):
			return false
	return true


## tilesets 字段如 "A,G" / "*" / "L"。
static func _tilesets_allow(tilesets_field: String, letter: String) -> bool:
	var raw := tilesets_field.strip_edges()
	if raw.is_empty() or raw == "*":
		return true
	var want := letter.to_upper()
	for part in raw.split(","):
		var p := part.strip_edges().to_upper()
		if p == "*" or p == want:
			return true
	return false


## 合并 UnitData：race / moveHeight / pathTex 等。
func _merge_unit_data() -> void:
	var store := _def_store()
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 UnitData")
		return
	store.ensure_table(UnitDataDef.TABLE_NAME)
	for id in store.get_ids(UnitDataDef.TABLE_NAME):
		if not _units.has(id):
			continue
		var d := store.get_row(UnitDataDef.TABLE_NAME, id) as UnitDataDef
		if d == null:
			continue
		var e: Dictionary = _units[id]
		var race := d.race.strip_edges().to_lower()
		e["race"] = race if not race.is_empty() else "other"
		e["move_height"] = d.move_height
		var path_tex := d.path_tex.strip_edges()
		e["path_tex"] = path_tex if not path_tex.is_empty() else "_"
		if str(e.get("name", "")).is_empty():
			var comment := d.comment.strip_edges()
			if not comment.is_empty() and comment != "_":
				e["name"] = comment
		_units[id] = e
	_merge_unit_balance()


func _merge_unit_balance() -> void:
	var store := _def_store()
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 UnitBalance")
		return
	store.ensure_table(UnitBalanceDef.TABLE_NAME)
	for id in store.get_ids(UnitBalanceDef.TABLE_NAME):
		if not _units.has(id):
			continue
		var d := store.get_row(UnitBalanceDef.TABLE_NAME, id) as UnitBalanceDef
		if d == null:
			continue
		var e: Dictionary = _units[id]
		e["is_building"] = d.isbldg
		e["level"] = d.level
		var ts := d.tilesets.strip_edges()
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


## 从 *UnitStrings.txt 读 Name=；从 *UnitFunc.txt 读 Art= / Buttonpos=。
func _load_unit_display_names() -> void:
	const STRING_FILES := [
		"Units/HumanUnitStrings.txt",
		"Units/OrcUnitStrings.txt",
		"Units/UndeadUnitStrings.txt",
		"Units/NightElfUnitStrings.txt",
		"Units/NeutralUnitStrings.txt",
		"Units/CampaignUnitStrings.txt",
	]
	const FUNC_FILES := [
		"Units/HumanUnitFunc.txt",
		"Units/OrcUnitFunc.txt",
		"Units/UndeadUnitFunc.txt",
		"Units/NightElfUnitFunc.txt",
		"Units/NeutralUnitFunc.txt",
		"Units/CampaignUnitFunc.txt",
	]
	const ROOTS := ["", "Melee_V0/", "Melee_V1/", "Custom_V0/", "Custom_V1/"]
	var names: Dictionary = {}
	var arts: Dictionary = {}
	var buttonpos: Dictionary = {}
	for rel in STRING_FILES:
		for root in ROOTS:
			_parse_unit_ini_file(root + rel, names, "Name")
	for rel2 in FUNC_FILES:
		for root2 in ROOTS:
			_parse_unit_func_file(root2 + rel2, arts, buttonpos)
	for id in _units.keys():
		var e: Dictionary = _units[id]
		if names.has(id):
			e["name"] = str(names[id])
			e["name_key"] = id
		if arts.has(id):
			e["art"] = str(arts[id])
		if buttonpos.has(id):
			e["button_pos"] = buttonpos[id]
		_units[id] = e


func _parse_unit_ini_file(logical: String, out_names: Dictionary, field: String) -> void:
	var abs_path := RuntimeAssets.resolve(logical)
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		return
	var text := RuntimeAssets.read_utf8_text(abs_path)
	if text.is_empty():
		return
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	var section := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		if section.is_empty():
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		if key != field:
			continue
		var val := line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
		if not val.is_empty():
			out_names[section] = val


func _parse_unit_func_file(logical: String, out_art: Dictionary, out_pos: Dictionary) -> void:
	var abs_path := RuntimeAssets.resolve(logical)
	if abs_path.is_empty() or not FileAccess.file_exists(abs_path):
		return
	var text := RuntimeAssets.read_utf8_text(abs_path)
	if text.is_empty():
		return
	if text.begins_with("\ufeff"):
		text = text.substr(1)
	var section := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		if section.is_empty():
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		if key == "Art" and not val.is_empty():
			out_art[section] = val.replace("\\", "/")
		elif key == "Buttonpos":
			var parts := val.split(",")
			var bx := int(parts[0]) if parts.size() > 0 else 0
			var by := int(parts[1]) if parts.size() > 1 else 0
			out_pos[section] = Vector2i(bx, by)


## 单位面板分区：units / heroes / buildings / special（对齐 WE）。
static func unit_palette_section(e: Dictionary) -> String:
	if bool(e.get("special", false)):
		return "special"
	var uc := str(e.get("unit_class", "")).to_lower()
	if uc.find("hero") >= 0:
		return "heroes"
	if bool(e.get("is_building", false)) or uc.find("building") >= 0:
		return "buildings"
	return "units"


## 命令按钮图标（Art → converted png）。
func unit_art_texture(type_id: String) -> Texture2D:
	var info: Dictionary = lookup(type_id)
	var art := str(info.get("art", "")).replace("\\", "/")
	if art.is_empty():
		return null
	var lower := art.to_lower()
	if lower.ends_with(".tga") or lower.ends_with(".blp"):
		art = art.substr(0, art.length() - 4) + ".png"
	elif not lower.ends_with(".png"):
		art = art + ".png"
	return RuntimeAssets.load_converted_texture(art)


## 按种族 + 对战/战役筛选，再按面板分区归类。
## tileset_letter：中立时按 UnitBalance.tilesets 过滤（空/"*"=不限）。
## level：中立时按 UnitBalance.level 过滤（<0 = 任何等级）。
## 返回 { "units": [], "heroes": [], "buildings": [], "special": [] }
func list_units_palette_sections(
	race: String,
	set_id: String = "melee",
	tileset_letter: String = "*",
	level: int = -1,
) -> Dictionary:
	var out := {
		"units": [],
		"heroes": [],
		"buildings": [],
		"special": [],
	}
	var want_races := _expand_palette_race(race)
	var want_set := set_id.strip_edges().to_lower()
	if want_set.is_empty():
		want_set = "melee"
	var ts := tileset_letter.strip_edges().to_upper()
	var filter_ts := not ts.is_empty() and ts != "*"
	var filter_lv := level >= 0
	var is_neutral_bucket := str(race).strip_edges().to_lower() == "neutral"
	for id in _units.keys():
		var e: Dictionary = _units[id]
		if not bool(e.get("in_editor", true)):
			continue
		if bool(e.get("hidden_in_editor", false)):
			continue
		var is_sloc: bool = bool(e.get("is_start_location", false)) or str(e.get("id", "")) == "sloc"
		if not want_races.is_empty() and not is_sloc:
			var ur := str(e.get("race", "")).to_lower()
			if not want_races.has(ur):
				continue
		var is_campaign: bool = bool(e.get("campaign", false))
		if want_set == "melee" or want_set == "standard":
			if is_campaign:
				continue
		elif want_set == "campaign":
			if not is_campaign:
				continue
		# 中立桶：地图集 + 等级（对齐 WE LocaleMenu / LevelMenu）；开始点始终可见
		if is_neutral_bucket and not is_sloc:
			if filter_ts and not _tilesets_allow(str(e.get("tilesets", "*")), ts):
				continue
			if filter_lv and int(e.get("level", -1)) != level:
				continue
		var sec := unit_palette_section(e)
		(out[sec] as Array).append(e)
	for k in out.keys():
		var arr: Array = out[k]
		arr.sort_custom(_cmp_unit_palette_entries)
		out[k] = arr
	# 开始点置顶「建筑」分类（对齐 WE）
	_move_start_location_first(out["buildings"] as Array)
	return out


func _move_start_location_first(buildings: Array) -> void:
	for i in range(buildings.size()):
		var e: Dictionary = buildings[i]
		if str(e.get("id", "")) == "sloc" or bool(e.get("is_start_location", false)):
			buildings.remove_at(i)
			buildings.insert(0, e)
			return


## WE 面板序：unitClass 尾号（HUnit01 < HUnit02）；同号再 sortUI / button_pos / id。
## Buttonpos 是建造/训练按钮位，多单位撞车，不能当主序。
func _cmp_unit_palette_entries(a: Dictionary, b: Dictionary) -> bool:
	var ca := _unit_class_sort_key(str(a.get("unit_class", "")))
	var cb := _unit_class_sort_key(str(b.get("unit_class", "")))
	if ca[0] != cb[0]:
		return str(ca[0]).nocasecmp_to(str(cb[0])) < 0
	if int(ca[1]) != int(cb[1]):
		return int(ca[1]) < int(cb[1])
	var sa := str(a.get("sort_ui", ""))
	var sb := str(b.get("sort_ui", ""))
	if sa != sb:
		return sa.nocasecmp_to(sb) < 0
	var pa: Vector2i = a.get("button_pos", Vector2i.ZERO) as Vector2i
	var pb: Vector2i = b.get("button_pos", Vector2i.ZERO) as Vector2i
	if pa.y != pb.y:
		return pa.y < pb.y
	if pa.x != pb.x:
		return pa.x < pb.x
	return str(a.get("id", "")).nocasecmp_to(str(b.get("id", ""))) < 0


## "HUnit12" → ["HUnit", 12]；无尾号 → [全文, 0]
static func _unit_class_sort_key(unit_class: String) -> Array:
	var uc := unit_class.strip_edges()
	if uc.is_empty():
		return ["", 0]
	var i := uc.length() - 1
	while i >= 0 and uc[i] >= "0" and uc[i] <= "9":
		i -= 1
	if i >= uc.length() - 1:
		return [uc, 0]
	var prefix := uc.substr(0, i + 1)
	var num_s := uc.substr(i + 1)
	return [prefix, int(num_s) if num_s.is_valid_int() else 0]


func _load_unit_ui() -> void:
	var store := _def_store()
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 UnitUI")
		return
	store.ensure_table(UnitUiDef.TABLE_NAME)
	for id in store.get_ids(UnitUiDef.TABLE_NAME):
		var d := store.get_row(UnitUiDef.TABLE_NAME, id) as UnitUiDef
		if d == null or d.unit_uiid.is_empty():
			continue
		# name 先用 SLK name 列（常为键/占位）；正式显示名由 *UnitStrings 覆盖
		var name := d.name_key.strip_edges()
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
	var store := _def_store()
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 DestructableData")
		return
	store.ensure_table(DestructableDataDef.TABLE_NAME)
	for id in store.get_ids(DestructableDataDef.TABLE_NAME):
		var d := store.get_row(DestructableDataDef.TABLE_NAME, id) as DestructableDataDef
		if d == null or d.destructable_id.is_empty():
			continue
		var tilesets := d.tilesets.strip_edges()
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
	var store := _def_store()
	if store == null:
		push_warning("Wc3IdCatalog: Wc3DefStore 不可用，跳过 Doodads")
		return
	store.ensure_table(DoodadDataDef.TABLE_NAME)
	for id in store.get_ids(DoodadDataDef.TABLE_NAME):
		var d := store.get_row(DoodadDataDef.TABLE_NAME, id) as DoodadDataDef
		if d == null or d.dood_id.is_empty():
			continue
		var tilesets := d.tilesets.strip_edges()
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


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


## 从 pathTex 文件名解析寻路格尺寸，如 `PathTextures\4x4Default.tga` → (4,4)。
## 无法解析（none / 异形图）返回 Vector2i.ZERO。
static func parse_path_tex_cells(path_tex: String) -> Vector2i:
	var s := path_tex.replace("\\", "/").get_file()
	if s.is_empty() or s.to_lower() == "none" or s == "_":
		return Vector2i.ZERO
	var re := RegEx.new()
	if re.compile("(\\d+)x(\\d+)") != OK:
		return Vector2i.ZERO
	var m := re.search(s)
	if m == null:
		return Vector2i.ZERO
	var w: int = int(m.get_string(1))
	var h: int = int(m.get_string(2))
	if w <= 0 or h <= 0:
		return Vector2i.ZERO
	return Vector2i(w, h)


## 选中环直径（WC3 单位）。
## 优先级：doodad selSize → pathTex 脚印 → UnitBalance.collision×2 → UnitUI.scale(Selection Scale)×基线 → 1 格。
## UnitUI 无 selSize；单位尺寸主要看 collision / Selection Scale。HiveWE 选框另用模型 bounds_radius。
const UNIT_SELECTION_SCALE_BASE := 72.0


static func selection_diameter_wc3(info: Dictionary) -> float:
	var sel: float = float(info.get("sel_size", 0.0))
	if sel > 1.0:
		return sel
	var cells: Vector2i = parse_path_tex_cells(str(info.get("path_tex", "")))
	if cells != Vector2i.ZERO:
		return float(maxi(cells.x, cells.y)) * Wc3Coords.PATHING_CELL
	var collision: float = float(info.get("collision", 0.0))
	var from_col: float = collision * 2.0 if collision > 0.0 else 0.0
	# UnitUI.scale = Art - Selection Scale；1.0 为默认，不当作 ×72（否则农民圈≈2 格）
	var sel_scale: float = float(info.get("def_scale", 0.0))
	var from_scale: float = sel_scale * UNIT_SELECTION_SCALE_BASE if sel_scale > 1.0 else 0.0
	var diam: float = maxf(from_col, from_scale)
	if diam > 1.0:
		return diam
	return Wc3Coords.PATHING_CELL

## 放置默认朝向：fixedRot≥0 用固定角；-1（自由旋转）用 WE 默认 270°。
static func default_facing_deg(info: Dictionary) -> float:
	var fr: float = float(info.get("fixed_rot", -1.0))
	if fr >= 0.0:
		return fposmod(fr, 360.0)
	return 270.0


## 预览相机距离（WE「距离」框，WC3 单位）。
## 经验对齐：常见 visRadius=50 → 400；大物件跟 selSize；瀑布 visRadius=100 → 800。
static func preview_distance_wc3(info: Dictionary) -> float:
	var vis: float = float(info.get("vis_radius", 50.0))
	var from_vis: float = vis * 8.0 if vis > 0.0 else 400.0
	var sel: float = float(info.get("sel_size", 0.0))
	var from_sel: float = sel if sel > 1.0 else 0.0
	var foot: float = selection_diameter_wc3(info)
	return maxf(maxf(from_vis, from_sel), foot * 2.0)
