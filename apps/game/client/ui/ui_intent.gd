class_name UiIntent
extends RefCounted

## 客户端 UI → 玩法桥的意图 id（StringName）。
## 约定见 docs/design/game/UI_FRAMEWORK.md §6。

const COMMAND := &"command"
const COMMAND_RCLICK := &"command_rclick"
const TRAIN_CANCEL := &"train_cancel"
const ITEM_USE := &"item_use"
const ITEM_DROP := &"item_drop"
const ITEM_SWAP := &"item_swap"
const MULTI_SELECT := &"multi_select"
const MINIMAP_CLICK := &"minimap_click"
