class_name CommandButtonCatalog
extends RefCounted

## 命令卡资源映射：Command / Ability / Unit / Upgrade 的 Func+Strings → 图标路径、槽位、热键、Tip。
## 数据权威：assets/slk-exported/Units/{Command*,*Ability*,*Unit*,*Upgrade*}（经 passthrough，禁止读 .cache）。
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
var _upgrades: Dictionary = {}
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
	for race in ["Human", "Orc", "Undead", "NightElf", "Neutral", "Campaign"]:
		_load_pair("%sUpgradeFunc.txt" % race, "%sUpgradeStrings.txt" % race, _upgrades)


func get_command(cmd_id: String) -> Dictionary:
	return (_commands.get(cmd_id, {}) as Dictionary).duplicate(true)


func get_ability(abil_id: String) -> Dictionary:
	return (_abilities.get(abil_id, {}) as Dictionary).duplicate(true)


func get_unit_ui(unit_id: String) -> Dictionary:
	return (_units.get(unit_id, {}) as Dictionary).duplicate(true)


func get_trains(building_id: String) -> PackedStringArray:
	var row := get_unit_ui(building_id)
	return _split_csv(str(row.get("trains", "")))


func get_researches(building_id: String) -> PackedStringArray:
	var row := get_unit_ui(building_id)
	return _split_csv(str(row.get("researches", "")))


func get_upgrade_ui(upgrade_id: String) -> Dictionary:
	return (_upgrades.get(upgrade_id, {}) as Dictionary).duplicate(true)


func get_builds(unit_id: String) -> PackedStringArray:
	var row := get_unit_ui(unit_id)
	return _split_csv(str(row.get("builds", "")))


## UnitAbilities.abilList（DefStore）；无表/无行 → 空。
func get_abil_list(unit_id: String) -> PackedStringArray:
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return PackedStringArray()
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	store.ensure_table(UnitAbilitiesDef.TABLE_NAME)
	var def: UnitAbilitiesDef = store.get_row(UnitAbilitiesDef.TABLE_NAME, uid) as UnitAbilitiesDef
	if def == null:
		return PackedStringArray()
	return _split_csv(def.abil_list)


## 英雄可学技能（UnitAbilities.heroAbilList）。
func get_hero_abil_list(unit_id: String) -> PackedStringArray:
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return PackedStringArray()
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	store.ensure_table(UnitAbilitiesDef.TABLE_NAME)
	var def: UnitAbilitiesDef = store.get_row(UnitAbilitiesDef.TABLE_NAME, uid) as UnitAbilitiesDef
	if def == null:
		return PackedStringArray()
	return def.hero_ability_ids()


## 普通 + 英雄技能（UnitAbilities.slk）。
func get_all_abil_list(unit_id: String) -> PackedStringArray:
	var uid := unit_id.strip_edges()
	if uid.is_empty():
		return PackedStringArray()
	var store := _def_store()
	if store == null:
		return PackedStringArray()
	store.ensure_table(UnitAbilitiesDef.TABLE_NAME)
	var def: UnitAbilitiesDef = store.get_row(UnitAbilitiesDef.TABLE_NAME, uid) as UnitAbilitiesDef
	if def == null:
		return PackedStringArray()
	return def.all_ability_ids()


func get_ability_order(abil_id: String) -> String:
	var row := get_ability(abil_id)
	return str(row.get("order", "")).strip_edges().to_lower()


func get_ability_requires(abil_id: String) -> PackedStringArray:
	var row := get_ability(abil_id)
	return _split_csv(str(row.get("requires", "")))


## Requiresamount 与 Requires 对齐；缺省每项为 1。
func get_ability_require_levels(abil_id: String) -> Dictionary:
	var reqs := get_ability_requires(abil_id)
	var amounts := _split_csv(str(get_ability(abil_id).get("requiresamount", "")))
	var out: Dictionary = {}
	for i in range(reqs.size()):
		var rid := str(reqs[i])
		var lv := 1
		if i < amounts.size():
			lv = maxi(int(amounts[i]), 1)
		out[rid] = lv
	return out


## Builds ∩ allowlist。
## allow 空 → 原 Builds 顺序；allow 非空 → **按 allowlist 顺序**（F2 锁死表稳定槽位）。
func filter_builds(unit_id: String, allowlist: PackedStringArray = PackedStringArray()) -> PackedStringArray:
	var builds := get_builds(unit_id)
	if allowlist.is_empty():
		return builds
	var have: Dictionary = {}
	for b in builds:
		have[str(b)] = true
	var out := PackedStringArray()
	for a in allowlist:
		var id := str(a)
		if have.has(id):
			out.append(id)
	return out


func _def_store() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Wc3DefStore")


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
	# PassiveButtons/PASBTN*：原作无 DIS 灰图；禁用时仍用原图，由 modulate/逻辑表达
	if base.begins_with("PASBTN") or p.contains("/PassiveButtons/"):
		return p
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
	var learn_menu := bool(opts.get("learn_menu", false))
	var art := str(row.get("unart" if use_un else "art", ""))
	if learn_menu:
		var research_art := str(row.get("researchart", "")).strip_edges()
		if not research_art.is_empty():
			art = research_art
	if art.is_empty():
		art = str(row.get("art", ""))
	var tip := str(row.get("untip" if use_un else "tip", ""))
	if tip.is_empty():
		tip = str(row.get("tip", ""))
	if learn_menu:
		var rt := str(row.get("researchtip", "")).strip_edges()
		if not rt.is_empty():
			tip = rt
	var ubertip := str(row.get("unubertip" if use_un else "ubertip", ""))
	if ubertip.is_empty():
		ubertip = str(row.get("ubertip", ""))
	if learn_menu:
		var rub := str(row.get("researchubertip", "")).strip_edges()
		if not rub.is_empty():
			ubertip = rub
	var hotkey_s := str(row.get("unhotkey" if use_un else "hotkey", ""))
	if hotkey_s.is_empty():
		hotkey_s = str(row.get("hotkey", ""))
	var pos_raw := ""
	if learn_menu:
		pos_raw = str(row.get("researchbuttonpos", "")).strip_edges()
	if pos_raw.is_empty():
		pos_raw = str(row.get("unbuttonpos" if use_un else "buttonpos", ""))
	if pos_raw.is_empty():
		pos_raw = str(row.get("buttonpos", "0,0"))
	var pos := parse_buttonpos(pos_raw)
	var slot := int(opts.get("slot_override", slot_of(pos)))
	var abil_level := int(opts.get("ability_level", 0))
	var pick_level := not bool(opts.get("tooltip_all_levels", false))
	# Tip / Ubertip 必须分别做多等级截取再拼接。
	# 若先合并再 format：Ubertip 的 `","` 会把整段误判为 CSV，Tip 被吞掉（辉煌光环等被动表现为「无描述」）。
	var tip_f := tip
	var uber_f := ubertip
	if abil_level > 0 or not pick_level:
		var lv := maxi(abil_level, 1)
		tip_f = Wc3TooltipText.format(tip, lv, pick_level) if not tip.is_empty() else ""
		uber_f = Wc3TooltipText.format(ubertip, lv, pick_level) if not ubertip.is_empty() else ""
	var tooltip := tip_f
	if not uber_f.is_empty():
		tooltip = tip_f + "\n" + uber_f if not tip_f.is_empty() else uber_f
	var cost_line := str(opts.get("cost_line", ""))
	if not cost_line.is_empty():
		tooltip += "\n" + cost_line
	var auto_cast := bool(opts.get("auto_cast", false))
	var autocast_capable := bool(opts.get("autocast_capable", false))
	if auto_cast:
		tooltip += "\n|cff00ff00自动施法：开|r\n右键切换"
	elif autocast_capable and use_un:
		tooltip += "\n自动施法：关\n右键切换"
	var executing := bool(opts.get("executing", false))
	var passive := bool(opts.get("passive", false))
	# 被动光环常带 executing=true（视觉常亮），tooltip 不要写「执行中」
	if executing and not passive:
		tooltip += "\n|cff00ff00当前：执行中|r"
	var enabled := bool(opts.get("enabled", true))
	if not enabled and not passive:
		var reason := str(opts.get("disabled_reason", "")).strip_edges()
		if reason.is_empty():
			reason = "资源不足"
		# 醒目前置一行（原作红字提示），正文 Tip/Ubertip 仍完整保留。
		var warn := "|cffff6060%s|r" % reason
		if tooltip.strip_edges().is_empty():
			tooltip = warn
		else:
			tooltip = warn + "\n" + tooltip
	elif passive:
		var reason_p := str(opts.get("disabled_reason", "")).strip_edges()
		if reason_p.is_empty():
			reason_p = "被动技能"
		tooltip += "\n|cffc0c0c0%s|r" % reason_p
	# 可自动施法：图标用干净底图（BTNHeal），角标/粒子由 AutocastButtonOverlay 叠层
	if autocast_capable:
		art = AbilityFxCatalog.strip_autocast_art_suffix(art)
	var icon := icon_path(art)
	# 原作：已学技能右下角等级角标；未显式 badge 时回落 ability_level
	var badge_level := int(opts.get("badge_level", 0))
	if badge_level <= 0:
		badge_level = abil_level
	var out := {
		"id": action_id,
		"text": "执行中" if executing and not passive else "",
		"tooltip": tooltip,
		"hotkey": hotkey_code(hotkey_s),
		"hotkey_label": hotkey_s.to_upper(),
		"icon": icon,
		"icon_disabled": disabled_icon_path(art),
		"executing": executing,
		"enabled": enabled,
		"passive": passive,
		"slot": slot,
		"button_pos": pos,
		"name": str(row.get("name", "")),
		"auto_cast": auto_cast,
		"autocast_capable": autocast_capable,
	}
	if badge_level > 0:
		out["badge_level"] = badge_level
	var cd_ratio := clampf(float(opts.get("cooldown_ratio", 0.0)), 0.0, 1.0)
	if cd_ratio > 0.0:
		out["cooldown_ratio"] = cd_ratio
	if bool(opts.get("keep_icon_on_cd", false)):
		out["keep_icon_on_cd"] = true
	return out


func command_hud_entry(cmd_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_command(cmd_id), action_id, opts)


func ability_hud_entry(abil_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_ability(abil_id), action_id, opts)


func unit_hud_entry(unit_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_unit_ui(unit_id), action_id, opts)


func upgrade_hud_entry(upgrade_id: String, action_id: String, opts: Dictionary = {}) -> Dictionary:
	return make_hud_entry(get_upgrade_ui(upgrade_id), action_id, opts)


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
		"researchbuttonpos":
			return "researchbuttonpos"
		"researchtip":
			return "researchtip"
		"researchubertip":
			return "researchubertip"
		"researchart":
			return "researchart"
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
		"researches":
			return "researches"
		"builds":
			return "builds"
		_:
			return k.to_lower()


func _strip_quotes(val: String) -> String:
	var v := val.strip_edges()
	# 多等级 `"L1","L2","L3"` 整段保留，交给 Wc3TooltipText.pick_level_string
	if v.contains('","'):
		return v
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
