extends RefCounted

## Pure palette filtering and ordering; dictionaries are supplied by the catalog.

## 可放置物列表（装饰物 + 可破坏物），按显示名排序。
## 每项为 lookup() 同形 Dictionary。
static func list_placeables(_doodads: Dictionary, _destructables: Dictionary, include_doodads: bool = true, include_destructables: bool = true) -> Array:
	return list_placeables_filtered(_doodads, _destructables, "", "", include_doodads, include_destructables)


## 按地形集字母 + 分类码筛选。
## tileset_letter 空/"*" = 不限；条目 tilesets 含 "*" 或含该字母才通过。
## category_code 空/"*" = 不限；否则精确匹配 entry.category。
static func list_placeables_filtered(
	_doodads: Dictionary,
	_destructables: Dictionary,
	tileset_letter: String = "",
	category_code: String = "",
	include_doodads: bool = true,
	include_destructables: bool = true,
) -> Array:
	var out: Array = []
	var ts: String = tileset_letter.strip_edges().to_upper()
	var cat: String = category_code.strip_edges().to_upper()
	if include_doodads:
		for id: String in _doodads.keys():
			var e: Dictionary = _doodads[id]
			if _entry_matches(e, ts, cat):
				out.append(e)
	if include_destructables:
		for id: String in _destructables.keys():
			var e2: Dictionary = _destructables[id]
			if _entry_matches(e2, ts, cat):
				out.append(e2)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)
	return out


## WE 单位面板种族下拉（固定桶；勿直接展开 UnitData.race，否则 critters/commoner 会重复成两个「中立无敌意」）。
## 对齐经典 WE：人族 / 兽族 / 不死 / 暗夜 / 中立 / 中立-娜迦。
const UNIT_PALETTE_RACE_BUCKETS: Array[Dictionary] = [
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
static func list_units_filtered(_units: Dictionary, race: String = "", group: String = "standard") -> Array:
	var out: Array = []
	var want_races: Dictionary = _expand_palette_race(race)
	var want_group: String = group.strip_edges().to_lower()
	if want_group.is_empty():
		want_group = "*"
	for id: String in _units.keys():
		var e: Dictionary = _units[id]
		if not bool(e.get("in_editor", true)):
			continue
		if bool(e.get("hidden_in_editor", false)):
			continue
		if not want_races.is_empty():
			var ur: String = str(e.get("race", "")).to_lower()
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
static func list_unit_races(_units: Dictionary) -> PackedStringArray:
	var present: Dictionary = {}
	for id: String in _units.keys():
		var e: Dictionary = _units[id]
		if not bool(e.get("in_editor", true)) or bool(e.get("hidden_in_editor", false)):
			continue
		var r: String = str(e.get("race", "other")).to_lower()
		if r.is_empty():
			r = "other"
		present[r] = true
	var out: PackedStringArray = PackedStringArray()
	for bucket: Dictionary in UNIT_PALETTE_RACE_BUCKETS:
		var has_any: bool = false
		for raw: String in bucket.get("races", []):
			if present.has(str(raw)):
				has_any = true
				break
		if has_any:
			out.append(str(bucket.get("id", "")))
	return out


## 面板种族桶 → 显示名 WESTRING key。
static func unit_palette_race_name_key(palette_race_id: String) -> String:
	var pid: String = palette_race_id.strip_edges().to_lower()
	for bucket: Dictionary in UNIT_PALETTE_RACE_BUCKETS:
		if str(bucket.get("id", "")) == pid:
			return str(bucket.get("name_key", ""))
	return "WESTRING_RACE_OTHER"


## 面板种族桶 → UnitData.race 集合；空/"*" → 空 Dictionary（表示不限）。
static func _expand_palette_race(race: String) -> Dictionary:
	var want: String = race.strip_edges().to_lower()
	var out: Dictionary = {}
	if want.is_empty() or want == "*":
		return out
	for bucket: Dictionary in UNIT_PALETTE_RACE_BUCKETS:
		if str(bucket.get("id", "")) == want:
			for raw: String in bucket.get("races", []):
				out[str(raw)] = true
			return out
	# 兼容直接传 UnitData.race
	out[want] = true
	return out


static func _entry_matches(e: Dictionary, tileset_letter: String, category_code: String) -> bool:
	if not category_code.is_empty() and category_code != "*":
		if str(e.get("category", "")).to_upper() != category_code:
			return false
	if not tileset_letter.is_empty() and tileset_letter != "*":
		if not _tilesets_allow(str(e.get("tilesets", "")), tileset_letter):
			return false
	return true


## tilesets 字段如 "A,G" / "*" / "L"。
static func _tilesets_allow(tilesets_field: String, letter: String) -> bool:
	var raw: String = tilesets_field.strip_edges()
	if raw.is_empty() or raw == "*":
		return true
	var want: String = letter.to_upper()
	for part: String in raw.split(","):
		var p: String = part.strip_edges().to_upper()
		if p == "*" or p == want:
			return true
	return false


## 单位面板分区：units / heroes / buildings / special（对齐 WE）。
static func unit_palette_section(e: Dictionary) -> String:
	if bool(e.get("special", false)):
		return "special"
	var uc: String = str(e.get("unit_class", "")).to_lower()
	if uc.find("hero") >= 0:
		return "heroes"
	if bool(e.get("is_building", false)) or uc.find("building") >= 0:
		return "buildings"
	return "units"


## 按种族 + 对战/战役筛选，再按面板分区归类。
## tileset_letter：中立时按 UnitBalance.tilesets 过滤（空/"*"=不限）。
## level：中立时按 UnitBalance.level 过滤（<0 = 任何等级）。
## 返回 { "units": [], "heroes": [], "buildings": [], "special": [] }
static func list_units_palette_sections(
	_units: Dictionary,
	race: String,
	set_id: String = "melee",
	tileset_letter: String = "*",
	level: int = -1,
) -> Dictionary:
	var out: Dictionary = {
		"units": [],
		"heroes": [],
		"buildings": [],
		"special": [],
	}
	var want_races: Dictionary = _expand_palette_race(race)
	var want_set: String = set_id.strip_edges().to_lower()
	if want_set.is_empty():
		want_set = "melee"
	var ts: String = tileset_letter.strip_edges().to_upper()
	var filter_ts: bool = not ts.is_empty() and ts != "*"
	var filter_lv: bool = level >= 0
	var is_neutral_bucket: bool = str(race).strip_edges().to_lower() == "neutral"
	for id: String in _units.keys():
		var e: Dictionary = _units[id]
		if not bool(e.get("in_editor", true)):
			continue
		if bool(e.get("hidden_in_editor", false)):
			continue
		var is_sloc: bool = bool(e.get("is_start_location", false)) or str(e.get("id", "")) == "sloc"
		if not want_races.is_empty() and not is_sloc:
			var ur: String = str(e.get("race", "")).to_lower()
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
		var sec: String = unit_palette_section(e)
		(out[sec] as Array).append(e)
	for k: String in out.keys():
		var arr: Array = out[k]
		arr.sort_custom(_cmp_unit_palette_entries)
		out[k] = arr
	# 开始点置顶「建筑」分类（对齐 WE）
	_move_start_location_first(out["buildings"] as Array)
	return out


static func _move_start_location_first(buildings: Array) -> void:
	for i: int in range(buildings.size()):
		var e: Dictionary = buildings[i]
		if str(e.get("id", "")) == "sloc" or bool(e.get("is_start_location", false)):
			buildings.remove_at(i)
			buildings.insert(0, e)
			return


## WE 面板序：unitClass 尾号（HUnit01 < HUnit02）；同号再 sortUI / button_pos / id。
## Buttonpos 是建造/训练按钮位，多单位撞车，不能当主序。
static func _cmp_unit_palette_entries(a: Dictionary, b: Dictionary) -> bool:
	var ca: Array = _unit_class_sort_key(str(a.get("unit_class", "")))
	var cb: Array = _unit_class_sort_key(str(b.get("unit_class", "")))
	if ca[0] != cb[0]:
		return str(ca[0]).nocasecmp_to(str(cb[0])) < 0
	if int(ca[1]) != int(cb[1]):
		return int(ca[1]) < int(cb[1])
	var sa: String = str(a.get("sort_ui", ""))
	var sb: String = str(b.get("sort_ui", ""))
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
	var uc: String = unit_class.strip_edges()
	if uc.is_empty():
		return ["", 0]
	var i: int = uc.length() - 1
	while i >= 0 and uc[i] >= "0" and uc[i] <= "9":
		i -= 1
	if i >= uc.length() - 1:
		return [uc, 0]
	var prefix: String = uc.substr(0, i + 1)
	var num_s: String = uc.substr(i + 1)
	return [prefix, int(num_s) if num_s.is_valid_int() else 0]


