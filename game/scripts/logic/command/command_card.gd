class_name CommandCard
extends RefCounted

## 行动面板条目构建（HUD 命令格）。
## 图标 / 槽位 / 热键 / Tip 来自 CommandButtonCatalog（WC3 Func+Strings）；
## action_id 与运行时态（执行中、买不起）仍由本类组装。

const ACTION_MOVE := "move"
const ACTION_STOP := "stop"
const ACTION_HARVEST_GOLD := "harvest_gold"
const ACTION_RETURN_GOODS := "return_goods"
const ACTION_BUILD_PREFIX := "build:" ## F2-4：建造按钮 action_id 前缀
const ACTION_TRAIN_PREFIX := "train:" ## 训练单位：train:hpea
const ACTION_CALL_TO_ARMS := "call_to_arms"
const ACTION_SET_RALLY := "set_rally"

## 采集 / 交回：官方 Ahar Buttonpos=3,1；无 Catalog 时回退槽
const SLOT_HARVEST_FALLBACK := 7

## 建造按钮槽位（F2 竖切：主卡摊平 3 建筑，非完整 AHbu 子菜单）
const SLOT_BUILD_FIRST := 3
const SLOT_BUILD_COUNT := 3

const CMD_MOVE := "CmdMove"
const CMD_STOP := "CmdStop"
const CMD_RALLY := "CmdRally"
const ABIL_HARVEST := "Ahar"
const ABIL_CALL_TO_ARMS := "Amic"
const TOWN_HALL_ID := "htow"


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


## 人族主城卡：Trains + Amic + CmdRally（位姿/文案/图标读 Catalog）
static func town_hall() -> Array[Dictionary]:
	var cat := _cat()
	var card := _empty_card()
	var trains := cat.get_trains(TOWN_HALL_ID)
	if trains.is_empty():
		trains = PackedStringArray(["hpea"])
	for tid in trains:
		_place(
			card,
			cat.unit_hud_entry(
				tid,
				ACTION_TRAIN_PREFIX + tid,
				{"enabled": true, "executing": false}
			)
		)
	_place(
		card,
		cat.ability_hud_entry(
			ABIL_CALL_TO_ARMS,
			ACTION_CALL_TO_ARMS,
			{"enabled": true, "executing": false}
		)
	)
	_place(
		card,
		cat.command_hud_entry(
			CMD_RALLY,
			ACTION_SET_RALLY,
			{"enabled": true, "executing": false}
		)
	)
	return card


## WC3 基础单位卡：CmdMove / CmdStop
static func basic_locomotion(move_executing: bool = false) -> Array[Dictionary]:
	var cat := _cat()
	var card := _empty_card()
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
	return card


## 农民卡：移动/停止 + Ahar 采集↔交回（Unart / Unhotkey）
static func peasant(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false
) -> Array[Dictionary]:
	var cat := _cat()
	var card := basic_locomotion(move_executing)
	var har := cat.get_ability(ABIL_HARVEST)
	if har.is_empty():
		# Catalog 未同步时极简回退
		var fallback_slot := SLOT_HARVEST_FALLBACK
		if carrying:
			card[fallback_slot] = {
				"id": ACTION_RETURN_GOODS,
				"text": "",
				"tooltip": "送回资源",
				"hotkey": KEY_E,
				"hotkey_label": "E",
				"icon": "ReplaceableTextures/CommandButtons/BTNReturnGoods.png",
				"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNReturnGoods.png",
				"executing": return_executing,
				"enabled": true,
				"slot": fallback_slot,
			}
		else:
			card[fallback_slot] = {
				"id": ACTION_HARVEST_GOLD,
				"text": "",
				"tooltip": "采集",
				"hotkey": KEY_G,
				"hotkey_label": "G",
				"icon": "ReplaceableTextures/CommandButtons/BTNGatherGold.png",
				"icon_disabled": "ReplaceableTextures/CommandButtonsDisabled/DISBTNGatherGold.png",
				"executing": harvest_executing,
				"enabled": true,
				"slot": fallback_slot,
			}
		return card
	if carrying:
		_place(
			card,
			cat.ability_hud_entry(
				ABIL_HARVEST,
				ACTION_RETURN_GOODS,
				{"use_un": true, "executing": return_executing, "enabled": true}
			)
		)
	else:
		_place(
			card,
			cat.ability_hud_entry(
				ABIL_HARVEST,
				ACTION_HARVEST_GOLD,
				{"use_un": false, "executing": harvest_executing, "enabled": true}
			)
		)
	return card


## 农民卡 + F2 建造三按钮（图标/热键/Tip 读单位 UI；槽位仍用 F2 摊平 3–5）
static func peasant_with_build(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false,
	building_ids: PackedStringArray = PackedStringArray(),
	can_afford: PackedInt32Array = PackedInt32Array(),
	building_executing: PackedInt32Array = PackedInt32Array()
) -> Array[Dictionary]:
	var card := peasant(move_executing, carrying, harvest_executing, return_executing)
	var cat := _cat()
	for i in range(SLOT_BUILD_COUNT):
		var slot := SLOT_BUILD_FIRST + i
		if i < building_ids.size():
			var bid := str(building_ids[i])
			var ok := i < can_afford.size() and int(can_afford[i]) != 0
			var exec := i < building_executing.size() and int(building_executing[i]) != 0
			var cost := _building_cost_line(bid)
			var entry := cat.unit_hud_entry(
				bid,
				ACTION_BUILD_PREFIX + bid,
				{
					"slot_override": slot,
					"enabled": ok,
					"executing": exec,
					"cost_line": cost,
				}
			)
			if entry.is_empty():
				entry = _build_button_fallback(bid, ok, exec, slot)
			card[slot] = entry
		else:
			card[slot] = {}
	return card


static func _building_cost_line(building_id: String) -> String:
	var g := BuildingCatalog.get_gold_cost(building_id)
	var l := BuildingCatalog.get_lumber_cost(building_id)
	var cost := "造价 %d 金" % g
	if l > 0:
		cost += " · %d 木" % l
	return cost + "。"


static func _build_button_fallback(
	building_id: String, can_afford: bool, executing: bool, slot: int
) -> Dictionary:
	var name := building_id
	var hotkey := "?"
	var icon := "ReplaceableTextures/CommandButtons/BTNBuild.png"
	match building_id:
		"hhou":
			name = "农场"
			hotkey = "F"
			icon = "ReplaceableTextures/CommandButtons/BTNFarm.png"
		"halt":
			name = "祭坛"
			hotkey = "A"
			icon = "ReplaceableTextures/CommandButtons/BTNAltarOfKings.png"
		"hbar":
			name = "兵营"
			hotkey = "B"
			icon = "ReplaceableTextures/CommandButtons/BTNHumanBarracks.png"
	var tip := "建造 %s (|cffffcc00%s|r)\n%s" % [name, hotkey, _building_cost_line(building_id)]
	if not can_afford:
		tip += "\n|cffff6060资源不足|r"
	elif executing:
		tip += "\n|cff00ff00当前：执行中|r"
	return {
		"id": ACTION_BUILD_PREFIX + building_id,
		"text": "执行中" if executing else "",
		"tooltip": tip,
		"hotkey": hotkey.unicode_at(0),
		"hotkey_label": hotkey,
		"icon": icon,
		"icon_disabled": icon,
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
	match building_id:
		"hhou":
			return "农场"
		"halt":
			return "祭坛"
		"hbar":
			return "兵营"
		_:
			return building_id


## 去掉 WC3 色码，供 Godot tooltip 纯文本显示。
static func plain_tooltip(raw: String) -> String:
	var re := RegEx.new()
	if re.compile("\\|c[0-9a-fA-F]{8}") != OK:
		return raw.replace("|r", "")
	var s := re.sub(raw, "", true)
	return s.replace("|r", "")
