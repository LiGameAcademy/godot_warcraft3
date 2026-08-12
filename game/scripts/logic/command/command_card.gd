class_name CommandCard
extends RefCounted

## 行动面板条目构建（HUD 命令格）。id 稳定，供 Director 按动作而非槽位下发。

const ACTION_MOVE := "move"
const ACTION_STOP := "stop"
const ACTION_HARVEST_GOLD := "harvest_gold"
const ACTION_RETURN_GOODS := "return_goods"
const ACTION_BUILD_PREFIX := "build:" ## F2-4：建造按钮 action_id 前缀

const ICON_MOVE := "ReplaceableTextures/CommandButtons/BTNMove.png"
const ICON_STOP := "ReplaceableTextures/CommandButtons/BTNStop.png"
const ICON_MOVE_DIS := "ReplaceableTextures/CommandButtonsDisabled/DISBTNMove.png"
const ICON_STOP_DIS := "ReplaceableTextures/CommandButtonsDisabled/DISBTNStop.png"
const ICON_GATHER := "ReplaceableTextures/CommandButtons/BTNGatherGold.png"
const ICON_GATHER_DIS := "ReplaceableTextures/CommandButtonsDisabled/DISBTNGatherGold.png"
const ICON_RETURN := "ReplaceableTextures/CommandButtons/BTNReturnGoods.png"
const ICON_RETURN_DIS := "ReplaceableTextures/CommandButtonsDisabled/DISBTNReturnGoods.png"

## 采集 / 交回互斥格（WC3 同槽换图）
const SLOT_HARVEST_RETURN := 2

## 建造按钮槽位（3-5；WC3 经典：农民 12 槽中 3-5 为种建筑）。
const SLOT_BUILD_FIRST := 3
const SLOT_BUILD_COUNT := 3


static func move_tooltip(executing: bool) -> String:
	var body := "移动 (|cffffcc00M|r)\n命令单位移动到指定地点。"
	if executing:
		return body + "\n|cff00ff00当前：执行中|r"
	return body


static func harvest_tooltip(executing: bool) -> String:
	var body := "采集金币 (|cffffcc00G|r)\n命令农民开采金矿。"
	if executing:
		return body + "\n|cff00ff00当前：执行中|r"
	return body


static func return_tooltip(executing: bool) -> String:
	var body := "送回资源 (|cffffcc00R|r)\n将携带的资源送回主城等接收建筑。"
	if executing:
		return body + "\n|cff00ff00当前：执行中|r"
	return body


## WC3 基础单位卡：槽 0=移动(M)，槽 1=停止(S)；其余空。
static func basic_locomotion(move_executing: bool = false) -> Array[Dictionary]:
	var card: Array[Dictionary] = []
	card.resize(12)
	for i in range(12):
		card[i] = {}
	card[0] = {
		"id": ACTION_MOVE,
		"text": "执行中" if move_executing else "",
		"tooltip": move_tooltip(move_executing),
		"hotkey": KEY_M,
		"hotkey_label": "M",
		"icon": ICON_MOVE,
		"icon_disabled": ICON_MOVE_DIS,
		"executing": move_executing,
		"enabled": true,
	}
	card[1] = {
		"id": ACTION_STOP,
		"text": "",
		"tooltip": "停止 (|cffffcc00S|r)\n命令单位停止当前行动。",
		"hotkey": KEY_S,
		"hotkey_label": "S",
		"icon": ICON_STOP,
		"icon_disabled": ICON_STOP_DIS,
		"executing": false,
		"enabled": true,
	}
	return card


## F2-4：拼装"执行中/空闲"执行标志到 tooltip 末尾。
static func _exec_note(executing: bool, hotkey_letter: String) -> String:
	return "\n|cff00ff00当前：执行中|r" if executing else ""


## 农民卡：移动/停止 + 槽 2 采集↔交回（按是否负金互斥显示）+ 槽 3-5 建造按钮。
## building_ids：当前可建造列表（按 BuildingCatalog.F2_BUILDING_IDS 顺序；F2 锁死 3 项）。
## can_afford[i]：gold/lumber 够；false → 灰；executing 反高亮。
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
	for i in range(SLOT_BUILD_COUNT):
		var slot := SLOT_BUILD_FIRST + i
		if i < building_ids.size():
			var bid := str(building_ids[i])
			var ok := i < can_afford.size() and int(can_afford[i]) != 0
			var exec := i < building_executing.size() and int(building_executing[i]) != 0
			card[slot] = _build_button_entry(bid, ok, exec)
		else:
			card[slot] = {}
	return card


## 建造按钮 entry 工厂。action_id = "build:<4-char-id>"。
static func _build_button_entry(building_id: String, can_afford: bool, executing: bool) -> Dictionary:
	var name := _building_display_name(building_id)
	var g := BuildingCatalog.get_gold_cost(building_id)
	var l := BuildingCatalog.get_lumber_cost(building_id)
	var cost := "%d 金" % g
	if l > 0:
		cost += " · %d 木" % l
	var hotkey := _building_hotkey(building_id)
	var sb := "\n|cff00ff00%s|r" % name
	var tooltip := "建造 %s (|cffffcc00%s|r)%s\n造价 %s。" % [name, hotkey, sb, cost]
	if not can_afford:
		tooltip += "\n|cffff6060资源不足|r"
	elif executing:
		tooltip += "\n|cff00ff00当前：执行中|r"
	var icon := _building_icon_path(building_id)
	return {
		"id": ACTION_BUILD_PREFIX + building_id,
		"text": "执行中" if executing else "",
		"tooltip": tooltip,
		"hotkey": hotkey.unicode_at(0),
		"hotkey_label": hotkey,
		"icon": icon,
		"icon_disabled": icon,
		"executing": executing,
		"enabled": can_afford,
	}


## 4 字符 id → 中文显示名（F2 锁死 3 建筑）。
static func _building_display_name(building_id: String) -> String:
	match building_id:
		"hhou": return "农场"
		"halt": return "祭坛"
		"hbar": return "兵营"
		_: return building_id


## 4 字符 id → 玩家热键。
static func _building_hotkey(building_id: String) -> String:
	match building_id:
		"hhou": return "F"
		"halt": return "A"
		"hbar": return "B"
		_: return "?"


## 4 字符 id → BTNBuild 按钮图标（按 WC3 习惯 BTN<Name>Build）。
## BTN 模板约定："ReplaceableTextures/CommandButtons/BTNFarm.png" 等。
static func _building_icon_path(building_id: String) -> String:
	match building_id:
		"hhou": return "ReplaceableTextures/CommandButtons/BTNFarm.png"
		"halt": return "ReplaceableTextures/CommandButtons/BTNAltar.png"
		"hbar": return "ReplaceableTextures/CommandButtons/BTNBarracks.png"
		_: return "ReplaceableTextures/CommandButtons/BTNBuild.png"


## 农民卡：移动/停止 + 槽 2 采集↔交回（按是否负金互斥显示）。
static func peasant(
	move_executing: bool = false,
	carrying: bool = false,
	harvest_executing: bool = false,
	return_executing: bool = false
) -> Array[Dictionary]:
	var card := basic_locomotion(move_executing)
	if carrying:
		card[SLOT_HARVEST_RETURN] = {
			"id": ACTION_RETURN_GOODS,
			"text": "执行中" if return_executing else "",
			"tooltip": return_tooltip(return_executing),
			"hotkey": KEY_R,
			"hotkey_label": "R",
			"icon": ICON_RETURN,
			"icon_disabled": ICON_RETURN_DIS,
			"executing": return_executing,
			"enabled": true,
		}
	else:
		card[SLOT_HARVEST_RETURN] = {
			"id": ACTION_HARVEST_GOLD,
			"text": "执行中" if harvest_executing else "",
			"tooltip": harvest_tooltip(harvest_executing),
			"hotkey": KEY_G,
			"hotkey_label": "G",
			"icon": ICON_GATHER,
			"icon_disabled": ICON_GATHER_DIS,
			"executing": harvest_executing,
			"enabled": true,
		}
	return card


## 去掉 WC3 色码，供 Godot tooltip 纯文本显示。
static func plain_tooltip(raw: String) -> String:
	var re := RegEx.new()
	if re.compile("\\|c[0-9a-fA-F]{8}") != OK:
		return raw.replace("|r", "")
	var s := re.sub(raw, "", true)
	return s.replace("|r", "")
