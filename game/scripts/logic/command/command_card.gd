class_name CommandCard
extends RefCounted

## 行动面板条目构建（HUD 命令格）。id 稳定，供 Director 按动作而非槽位下发。

const ACTION_MOVE := "move"
const ACTION_STOP := "stop"
const ACTION_HARVEST_GOLD := "harvest_gold"
const ACTION_RETURN_GOODS := "return_goods"

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
