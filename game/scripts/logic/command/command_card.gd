class_name CommandCard
extends RefCounted

## 行动面板组装（HUD 命令格）——数据驱动。
## - 图标 / 槽位 / 热键 / Tip ← CommandButtonCatalog（Func+Strings）
## - 技能列表 ← UnitAbilities.abilList
## - 训练 / 建造列表 ← UnitFunc Trains / Builds
## - action_id 与运行时态（执行中、买不起）仍由本类按 Order 映射组装
##
## F2 竖切：建造不走完整 AHbu 子菜单，而把 allowlist ∩ Builds 摊平到槽 3–5。

const ACTION_MOVE := "move"
const ACTION_STOP := "stop"
const ACTION_HARVEST_GOLD := "harvest_gold"
const ACTION_RETURN_GOODS := "return_goods"
const ACTION_BUILD_PREFIX := "build:" ## 建造按钮 action_id 前缀
const ACTION_TRAIN_PREFIX := "train:" ## 训练单位：train:hpea
const ACTION_CALL_TO_ARMS := "call_to_arms"
const ACTION_SET_RALLY := "set_rally"

const CMD_MOVE := "CmdMove"
const CMD_STOP := "CmdStop"
const CMD_RALLY := "CmdRally"

## F2：主卡摊平建造槽（非完整 AHbu 子菜单）
const SLOT_BUILD_FIRST := 3
const SLOT_BUILD_COUNT := 3

## Order → 本竖切已接线的 action（未列出的技能有 Art 也不上卡，避免空按钮）
## use_un：携带资源时切 Unart（仅 harvest）
const _ORDER_SPEC := {
	"harvest": {"action": ACTION_HARVEST_GOLD, "un_action": ACTION_RETURN_GOODS},
	"townbellon": {"action": ACTION_CALL_TO_ARMS},
}


static func _cat() -> CommandButtonCatalog:
	return CommandButtonCatalog.get_shared()


static func _empty_card() -> Array[Dictionary]:
	var card: Array[Dictionary] = []
	card.resize(12)
	for i in range(12):
		card[i] = {}
	return card


static func _place(card: Array[Dictionary], entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var slot := int(entry.get("slot", -1))
	if slot < 0 or slot >= card.size():
		return
	card[slot] = entry


## 通用入口：按单位 typeId + 运行时态组装 12 格。
## state 键：
##   move_executing / carrying / harvest_executing / return_executing
##   include_locomotion（默认：非建筑 true）
##   build_allowlist（PackedStringArray；空=不上建造摊平）
##   can_afford / building_executing（与摊平后 building_ids 等长的 PackedInt32Array）
static func for_unit(unit_id: String, state: Dictionary = {}) -> Array[Dictionary]:
	var uid := unit_id.strip_edges()
	var cat := _cat()
	var card := _empty_card()
	if uid.is_empty():
		return card

	var is_bldg := BuildingCatalog.is_building(uid)
	var include_loco := bool(state.get("include_locomotion", not is_bldg))
	if include_loco:
		_place_locomotion(card, cat, bool(state.get("move_executing", false)))

	for tid in cat.get_trains(uid):
		_place(
			card,
			cat.unit_hud_entry(
				tid,
				ACTION_TRAIN_PREFIX + tid,
				{"enabled": true, "executing": false}
			)
		)

	var carrying := bool(state.get("carrying", false))
	for abil_id in cat.get_abil_list(uid):
		_place_supported_ability(card, cat, str(abil_id), state, carrying)

	var allow: PackedStringArray = state.get("build_allowlist", PackedStringArray()) as PackedStringArray
	if allow == null:
		allow = PackedStringArray()
	var building_ids: PackedStringArray = state.get("building_ids", PackedStringArray()) as PackedStringArray
	if building_ids == null:
		building_ids = PackedStringArray()
	if building_ids.is_empty() and not allow.is_empty():
		building_ids = cat.filter_builds(uid, allow)
	if not building_ids.is_empty():
		_place_builds_flat(card, cat, building_ids, state)

	# 可训练建筑：集结点（CmdRally）
	if not cat.get_trains(uid).is_empty():
		_place(
			card,
			cat.command_hud_entry(
				CMD_RALLY,
				ACTION_SET_RALLY,
				{"enabled": true, "executing": false}
			)
		)

	return card


static func _place_locomotion(card: Array[Dictionary], cat: CommandButtonCatalog, move_executing: bool) -> void:
	_place(
		card,
		cat.command_hud_entry(
			CMD_MOVE,
			ACTION_MOVE,
			{"executing": move_executing, "enabled": true}
		)
	)
	_place(
		card,
		cat.command_hud_entry(
			CMD_STOP,
			ACTION_STOP,
			{"executing": false, "enabled": true}
		)
	)


static func _place_supported_ability(
	card: Array[Dictionary],
	cat: CommandButtonCatalog,
	abil_id: String,
	state: Dictionary,
	carrying: bool
) -> void:
	var order := cat.get_ability_order(abil_id)
	if order.is_empty() or not _ORDER_SPEC.has(order):
		return
	var spec: Dictionary = _ORDER_SPEC[order]
	var use_un := false
	var action_id := str(spec.get("action", ""))
	var opts := {"enabled": true, "executing": false}
	if order == "harvest":
		use_un = carrying
		action_id = str(spec.get("un_action" if use_un else "action", action_id))
		if use_un:
			opts["executing"] = bool(state.get("return_executing", false))
		else:
			opts["executing"] = bool(state.get("harvest_executing", false))
		opts["use_un"] = use_un
	var entry := cat.ability_hud_entry(abil_id, action_id, opts)
	_place(card, entry)


static func _place_builds_flat(
	card: Array[Dictionary],
	cat: CommandButtonCatalog,
	building_ids: PackedStringArray,
	state: Dictionary
) -> void:
	var can_afford: PackedInt32Array = state.get("can_afford", PackedInt32Array()) as PackedInt32Array
	var building_executing: PackedInt32Array = state.get("building_executing", PackedInt32Array()) as PackedInt32Array
	if can_afford == null:
		can_afford = PackedInt32Array()
	if building_executing == null:
		building_executing = PackedInt32Array()
	for i in range(SLOT_BUILD_COUNT):
		var slot := SLOT_BUILD_FIRST + i
		if i >= building_ids.size():
			card[slot] = {}
			continue
		var bid := str(building_ids[i])
		var ok := i < can_afford.size() and int(can_afford[i]) != 0
		var exec := i < building_executing.size() and int(building_executing[i]) != 0
		var entry := cat.unit_hud_entry(
			bid,
			ACTION_BUILD_PREFIX + bid,
			{
				"slot_override": slot,
				"enabled": ok,
				"executing": exec,
				"cost_line": _building_cost_line(bid),
			}
		)
		if entry.is_empty():
			entry = _build_button_fallback(bid, ok, exec, slot)
		card[slot] = entry


## —— 兼容旧调用（Director / 文档）；内部转 for_unit ——

static func town_hall(unit_id: String = "htow") -> Array[Dictionary]:
	return for_unit(unit_id, {"include_locomotion": false})


static func basic_locomotion(move_executing: bool = false) -> Array[Dictionary]:
	var card := _empty_card()
	_place_locomotion(card, _cat(), move_executing)
	return card


static func peasant(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false,
	unit_id: String = "hpea"
) -> Array[Dictionary]:
	return for_unit(
		unit_id,
		{
			"move_executing": move_executing,
			"carrying": carrying,
			"harvest_executing": harvest_executing,
			"return_executing": return_executing,
			"include_locomotion": true,
			"build_allowlist": PackedStringArray(), ## 无建造摊平
		}
	)


static func peasant_with_build(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false,
	building_ids: PackedStringArray = PackedStringArray(),
	can_afford: PackedInt32Array = PackedInt32Array(),
	building_executing: PackedInt32Array = PackedInt32Array(),
	unit_id: String = "hpea"
) -> Array[Dictionary]:
	## building_ids 为空：Builds ∩ F2 锁死表（顺序跟 UnitFunc Builds）
	var ids := building_ids
	if ids.is_empty():
		var allow := PackedStringArray()
		for bid in BuildingCatalog.F2_BUILDING_IDS:
			allow.append(str(bid))
		ids = _cat().filter_builds(unit_id, allow)
	return for_unit(
		unit_id,
		{
			"move_executing": move_executing,
			"carrying": carrying,
			"harvest_executing": harvest_executing,
			"return_executing": return_executing,
			"include_locomotion": true,
			"building_ids": ids,
			"can_afford": can_afford,
			"building_executing": building_executing,
		}
	)


static func _building_cost_line(building_id: String) -> String:
	var g := BuildingCatalog.get_gold_cost(building_id)
	var l := BuildingCatalog.get_lumber_cost(building_id)
	var cost := "造价 %d 金" % g
	if l > 0:
		cost += " · %d 木" % l
	return cost + "。"


## Catalog 缺 UI 行时的极简兜底（不再写死中文名/图标表；显示 id）
static func _build_button_fallback(
	building_id: String, can_afford: bool, executing: bool, slot: int
) -> Dictionary:
	var tip := "建造 %s\n%s" % [building_id, _building_cost_line(building_id)]
	if not can_afford:
		tip += "\n|cffff6060资源不足|r"
	elif executing:
		tip += "\n|cff00ff00当前：执行中|r"
	return {
		"id": ACTION_BUILD_PREFIX + building_id,
		"text": "执行中" if executing else "",
		"tooltip": tip,
		"hotkey": 0,
		"hotkey_label": "",
		"icon": "ReplaceableTextures/CommandButtons/BTNBuild.png",
		"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNBuild.png",
		"executing": executing,
		"enabled": can_afford,
		"slot": slot,
	}


## 显示名（Director 状态栏等）；优先 Catalog Name。
static func _building_display_name(building_id: String) -> String:
	var row := _cat().get_unit_ui(building_id)
	var n := str(row.get("name", "")).strip_edges()
	if not n.is_empty():
		return n
	return building_id


## 去掉 WC3 色码，供 Godot tooltip 纯文本显示。
static func plain_tooltip(raw: String) -> String:
	var re := RegEx.new()
	if re.compile("\\|c[0-9a-fA-F]{8}") != OK:
		return raw.replace("|r", "")
	var s := re.sub(raw, "", true)
	return s.replace("|r", "")
