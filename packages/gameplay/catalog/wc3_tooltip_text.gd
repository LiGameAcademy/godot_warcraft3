class_name Wc3TooltipText
extends RefCounted

## WC3 技能/单位描述占位符解析（Data · 表现文案）。
## 语法：`<ObjectId,FieldName>`，如 `<AHwe,Dur1>`、`<hwat,realHP>`、`<hwat,mindmg1>`。
## 多等级 Tip/Ubertip 为逗号分隔的引号串，按 ability_level 取段。

const _ABILITY_TABLE := AbilityDataDef.TABLE_NAME
const _BALANCE_TABLE := UnitBalanceDef.TABLE_NAME
const _WEAPONS_TABLE := UnitWeaponsDef.TABLE_NAME

static var _placeholder: RegEx


static func _regex() -> RegEx:
	if _placeholder == null:
		_placeholder = RegEx.new()
		_placeholder.compile("<([^,>]+),([^>]+)>")
	return _placeholder


## pick_level=false 时保留全文（学习面板 Researchubertip 含多级说明）。
static func format(raw: String, ability_level: int = 1, pick_level: bool = true) -> String:
	var text := raw.strip_edges()
	if text.is_empty():
		return ""
	if pick_level and ability_level > 0:
		text = pick_level_string(text, ability_level)
	text = resolve_placeholders(text)
	return text.replace("|n", "\n")


## WC3 多等级字符串：`"L1","L2","L3"` 或未加引号但以 `|r],` 分段的 Tip。
static func pick_level_string(raw: String, level: int) -> String:
	var s := raw.strip_edges()
	if s.is_empty():
		return ""
	if s.contains('","'):
		var parts := _split_quoted_csv(s)
		if parts.is_empty():
			return s
		var idx := clampi(level - 1, 0, parts.size() - 1)
		return parts[idx]
	# AHab 等 Tip：辉煌光环 - [|cffffcc00等级 1|r],辉煌光环 - [|cffffcc00等级 2|r],…
	if s.contains("|r],"):
		var chunks := s.split("|r],")
		if chunks.size() >= 2:
			var restored: PackedStringArray = PackedStringArray()
			for i in chunks.size():
				var c := str(chunks[i])
				if i < chunks.size() - 1:
					c += "|r]"
				restored.append(c)
			var idx2 := clampi(level - 1, 0, restored.size() - 1)
			return restored[idx2]
	return _unquote(s)


static func resolve_placeholders(text: String) -> String:
	if text.is_empty():
		return text
	var re := _regex()
	var out := text
	var m := re.search(out)
	while m != null:
		var rep := _replace_match(m)
		if rep == m.get_string(0):
			m = re.search(out, m.get_end())
			continue
		out = out.substr(0, m.get_start()) + rep + out.substr(m.get_end())
		m = re.search(out, m.get_start())
	return out


static func _replace_match(match: RegExMatch) -> String:
	var object_id := match.get_string(1).strip_edges()
	var field := match.get_string(2).strip_edges()
	var val: Variant = _lookup_value(object_id, field)
	if val == null:
		return match.get_string(0)
	return format_value(val)


static func _lookup_value(object_id: String, field: String) -> Variant:
	var oid := object_id.strip_edges()
	var fld := field.strip_edges()
	if oid.is_empty() or fld.is_empty():
		return null
	var store := _def_store()
	if store == null:
		return null
	store.ensure_table(_ABILITY_TABLE)
	var ab: AbilityDataDef = store.get_row(_ABILITY_TABLE, oid) as AbilityDataDef
	if ab != null:
		var av: Variant = _read_field(ab, fld)
		if av != null:
			return av
	store.ensure_table(_BALANCE_TABLE)
	var bal: UnitBalanceDef = store.get_row(_BALANCE_TABLE, oid) as UnitBalanceDef
	if bal != null:
		var bv: Variant = _read_field(bal, fld)
		if bv != null:
			return bv
	store.ensure_table(_WEAPONS_TABLE)
	var wpn: UnitWeaponsDef = store.get_row(_WEAPONS_TABLE, oid) as UnitWeaponsDef
	if wpn != null:
		var wv: Variant = _read_field(wpn, fld)
		if wv != null:
			return wv
	return null


static func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


static func _read_field(obj: Object, slk_field: String) -> Variant:
	if obj == null:
		return null
	var fld := slk_field.strip_edges()
	if fld.is_empty():
		return null
	var candidates: PackedStringArray = PackedStringArray([
		_slk_to_prop(fld),
		fld.to_lower(),
		fld,
	])
	var seen: Dictionary = {}
	for name in candidates:
		if name.is_empty() or seen.has(name):
			continue
		seen[name] = true
		for info in obj.get_property_list():
			if str(info.name) != name:
				continue
			return obj.get(name)
	return null


## SLK 字段名 → Def 属性名（realHP→real_hp，Dur1→dur1，DataA1→data_a1）。
static func _slk_to_prop(slk: String) -> String:
	var s := slk.strip_edges()
	if s.is_empty():
		return ""
	if s.ends_with("HP") and s.length() > 2:
		return "%s_hp" % s.substr(0, s.length() - 2).to_lower()
	if s.ends_with("Mana") and s.length() > 4:
		return "%s_mana" % s.substr(0, s.length() - 4).to_lower()
	if s.length() >= 6 and s.begins_with("Data") and s[4] >= "A" and s[4] <= "E":
		var letter := s[4].to_lower()
		var digit := s.substr(5)
		if digit.is_valid_int():
			return "data_%s%s" % [letter, digit]
	if s.begins_with("HeroDur") and s.length() == 8 and s[7].is_valid_int():
		return "hero_dur%s" % s[7]
	const PREFIXES := ["Dur", "Cool", "Cost", "Cast", "Area", "Rng"]
	for p in PREFIXES:
		if s.begins_with(p) and s.length() == p.length() + 1 and s[s.length() - 1].is_valid_int():
			return "%s%s" % [p.to_lower(), s[s.length() - 1]]
	var out := ""
	for i in s.length():
		var c := s[i]
		if c >= "A" and c <= "Z":
			if i > 0:
				out += "_"
			out += c.to_lower()
		else:
			out += c
	return out


static func format_value(v: Variant) -> String:
	match typeof(v):
		TYPE_INT:
			return str(v)
		TYPE_FLOAT:
			var f: float = float(v)
			if is_equal_approx(f, floor(f)):
				return str(int(f))
			var rounded: float = snapped(f, 0.01)
			if is_equal_approx(rounded, floor(rounded)):
				return str(int(rounded))
			return str(rounded)
		TYPE_BOOL:
			return "1" if v else "0"
		_:
			return str(v)


static func _unquote(s: String) -> String:
	var v := s.strip_edges()
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		return v.substr(1, v.length() - 2)
	return v


static func _split_quoted_csv(s: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while i < s.length():
		if s[i] != "\"":
			i += 1
			continue
		i += 1
		var buf := ""
		while i < s.length():
			if s[i] == "\"":
				if i + 1 < s.length() and s[i + 1] == "\"":
					buf += "\""
					i += 2
					continue
				i += 1
				break
			buf += s[i]
			i += 1
		out.append(buf)
	return out
