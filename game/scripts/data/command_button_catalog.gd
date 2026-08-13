class_name CommandButtonCatalog
extends RefCounted

## 命令卡资源映射：Command / Ability / Unit 的 Func+Strings → 图标路径、槽位、热键、Tip。
## 数据权威：assets/slk-exported/Units/{Command*,*Ability*,*Unit*}（经 passthrough，禁止读 .cache）。
##
## 槽位：slot = Buttonpos.y * 4 + Buttonpos.x（WC3 4×3）。

const FOLDER := "res://assets/slk-exported/Units"
const CMD_BTNS := "ReplaceableTextures/CommandButtons"
const CMD_BTNS_DIS := "ReplaceableTextures/CommandButtonsDisabled"

static var _shared: CommandButtonCatalog = null

## section_id → 合并后的行（Func + Strings）
var _commands: Dictionary = {}
var _abilities: Dictionary = {}
var _units: Dictionary = {}
var _loaded: bool = false


static func get_shared() -> CommandButtonCatalog:
	if _shared == null:
		_shared = CommandButtonCatalog.new()
	return _shared


func _init() -> void:
	ensure_loaded()


func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_load_pair("CommandFunc.txt", "CommandStrings.txt", _commands)
	for race in [
		"Common", "Human", "Orc", "Undead", "NightElf", "Neutral", "Item", "Campaign"
	]:
		_load_pair("%sAbilityFunc.txt" % race, "%sAbilityStrings.txt" % race, _abilities)
	for race in ["Human", "Orc", "Undead", "NightElf", "Neutral", "Campaign"]:
		_load_pair("%sUnitFunc.txt" % race, "%sUnitStrings.txt" % race, _units)


func get_command(cmd_id: String) -> Dictionary:
	return (_commands.get(cmd_id, {}) as Dictionary).duplicate(true)


func get_ability(abil_id: String) -> Dictionary:
	return (_abilities.get(abil_id, {}) as Dictionary).duplicate(true)


func get_unit_ui(unit_id: String) -> Dictionary:
	return (_units.get(unit_id, {}) as Dictionary).duplicate(true)


func get_trains(building_id: String) -> PackedStringArray:
	var row := get_unit_ui(building_id)
	return _split_csv(str(row.get("trains", "")))


func get_builds(unit_id: String) -> PackedStringArray:
	var row := get_unit_ui(unit_id)
	return _split_csv(str(row.get("builds", "")))


static func slot_of(pos: Vector2i) -> int:
	return clampi(pos.y, 0, 2) * 4 + clampi(pos.x, 0, 3)


static func parse_buttonpos(raw: String) -> Vector2i:
	var parts := raw.split(",")
	var x := int(parts[0].strip_edges()) if parts.size() > 0 else 0
	var y := int(parts[1].strip_edges()) if parts.size() > 1 else 0
	return Vector2i(x, y)


## Art 短名 / 完整 BLP 路径 → asset-converted 逻辑 PNG 路径。
func icon_path(art: String) -> String:
	var a := art.strip_edges().replace("\\", "/")
	if a.is_empty():
		return ""
	var lower := a.to_lower()
	if lower.ends_with(".blp") or lower.ends_with(".tga"):
		a = a.substr(0, a.length() - 4) + ".png"
	elif not lower.ends_with(".png") and a.contains("/"):
		a = a + ".png"
	if a.contains("/"):
		return a
	# CommandFunc 短名：CommandMove → BTNMove.png
	var short := a
	if short.begins_with("Command"):
		short = short.substr("Command".length())
	var candidates: PackedStringArray = PackedStringArray([
		"%s/BTN%s.png" % [CMD_BTNS, short],
		"%s/BTN%s.png" % [CMD_BTNS, a],
	])
	# 若干短名与 BTN 文件名不完全同形
	match a:
		"CommandBasicStructHuman", "CommandBasicStruct":
			candidates = PackedStringArray([
				"%s/BTNHumanBuild.png" % CMD_BTNS,
				"%s/BTNBasicStruct.png" % CMD_BTNS,
			])
		"CommandRally":
			candidates = PackedStringArray([
				"%s/BTNRallyPoint.png" % CMD_BTNS,
				"%s/BTNRally.png" % CMD_BTNS,
			])
		"CommandHoldPosition":
			candidates = PackedStringArray([
				"%s/BTNHoldPosition.png" % CMD_BTNS,
			])
	for c in candidates:
		if _converted_file_exists(c):
			return c
	return candidates[0]


func disabled_icon_path(art: String) -> String:
	var p := icon_path(art)
	if p.is_empty():
		return ""
	var base := p.get_file()
	if base.begins_with("BTN"):
		return "%s/DIS%s" % [CMD_BTNS_DIS, base]
	if base.begins_with("DIS"):
		return "%s/%s" % [CMD_BTNS_DIS, base]
	return "%s/DIS%s" % [CMD_BTNS_DIS, base]


func hotkey_code(letter: String) -> int:
	var s := letter.strip_edges()
	if s.is_empty():
		return 0
	var ch := s.to_upper().unicode_at(0)
	if ch >= 65 and ch <= 90:
		return KEY_A + (ch - 65)
	return ch


## 把 Catalog 行变成 HUD Dictionary（可覆盖 slot）。
## opts: executing / enabled / use_un / slot_override / cost_line / action_id
func make_hud_entry(row: Dictionary, action_id: String, opts: Dictionary = {}) -> Dictionary:
	if row.is_empty() or action_id.is_empty():
		return {}
	var use_un := bool(opts.get("use_un", false))
	var art := str(row.get("unart" if use_un else "art", ""))
	if art.is_empty():
		art = str(row.get("art", ""))
	var tip := str(row.get("untip" if use_un else "tip", ""))
	if tip.is_empty():
		tip = str(row.get("tip", ""))
	var ubertip := str(row.get("unubertip" if use_un else "ubertip", ""))
	if ubertip.is_empty():
		ubertip = str(row.get("ubertip", ""))
	var hotkey_s := str(row.get("unhotkey" if use_un else "hotkey", ""))
	if hotkey_s.is_empty():
		hotkey_s = str(row.get("hotkey", ""))
	var pos_raw := str(row.get("unbuttonpos" if use_un else "buttonpos", ""))
	if pos_raw.is_empty():
		pos_raw = str(row.get("buttonpos", "0,0"))
	var pos := parse_buttonpos(pos_raw)
	var slot := int(opts.get("slot_override", slot_of(pos)))
	var tooltip := tip
	if not ubertip.is_empty():
		tooltip = tip + "\n" + ubertip if not tip.is_empty() else ubertip
	var cost_line := str(opts.get("cost_line", ""))
	if not cost_line.is_empty():
		tooltip += "\n" + cost_line
	var executing := bool(opts.get("executing", false))
	if executing:
		tooltip += "\n|cff00ff00当前：执行中|r"
	var enabled := bool(opts.get("enabled", true))
	if not enabled:
		tooltip += "\n|cffff6060资源不足|r"
	var icon := icon_path(art)
	return {
		"id": action_id,
		"text": "执行中" if executing else "",
		"tooltip": tooltip,
		"hotkey": hotkey_code(hotkey_s),
		"hotkey_label": hotkey_s.to_upper(),
		"icon": icon,
		"icon_disabled": disabled_icon_path(art),
		"executing": executing,
		"enabled": enabled,
		"slot": slot,
		"button_pos": pos,
		"name": str(row.get("name", "")),
	}


func command_hud_entry(cmd_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_command(cmd_id), action_id, opts)


func ability_hud_entry(abil_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_ability(abil_id), action_id, opts)


func unit_hud_entry(unit_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_unit_ui(unit_id), action_id, opts)


func _converted_file_exists(logical: String) -> bool:
	var res := RuntimeAssets.converted_path(logical)
	return RuntimeAssets.file_exists(res)


func _load_pair(func_name: String, strings_name: String, into: Dictionary) -> void:
	_merge_ini_file(FOLDER.path_join(func_name), into)
	_merge_ini_file(FOLDER.path_join(strings_name), into)


func _merge_ini_file(res_path: String, into: Dictionary) -> void:
	if not FileAccess.file_exists(res_path):
		return
	var text := RuntimeAssets.read_utf8_text(res_path)
	if text.is_empty():
		return
	# 去 BOM
	if text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	var section := ""
	for raw in text.split("\n"):
		var line := String(raw).strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			if not into.has(section):
				into[section] = {}
			continue
		if section.is_empty():
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var key := line.substr(0, eq).strip_edges()
		var val := line.substr(eq + 1).strip_edges()
		val = _strip_quotes(val)
		var row: Dictionary = into[section]
		row[_normalize_key(key)] = val


func _normalize_key(key: String) -> String:
	var k := key.strip_edges()
	# WC3 偶发 UnButtonpos
	match k.to_lower():
		"art":
			return "art"
		"unart":
			return "unart"
		"buttonpos":
			return "buttonpos"
		"unbuttonpos":
			return "unbuttonpos"
		"tip":
			return "tip"
		"untip":
			return "untip"
		"ubertip":
			return "ubertip"
		"unubertip":
			return "unubertip"
		"hotkey":
			return "hotkey"
		"unhotkey":
			return "unhotkey"
		"name":
			return "name"
		"order":
			return "order"
		"trains":
			return "trains"
		"builds":
			return "builds"
		_:
			return k.to_lower()


func _strip_quotes(val: String) -> String:
	var v := val.strip_edges()
	if v.length() >= 2 and v.begins_with("\"") and v.ends_with("\""):
		return v.substr(1, v.length() - 2)
	return v


func _split_csv(raw: String) -> PackedStringArray:
	var out := PackedStringArray()
	if raw.is_empty():
		return out
	var seen: Dictionary = {}
	for piece in raw.split(","):
		var s := String(piece).strip_edges()
		if s.is_empty() or seen.has(s):
			continue
		seen[s] = true
		out.append(s)
	return out
