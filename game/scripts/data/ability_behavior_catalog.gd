class_name AbilityBehaviorCatalog
extends RefCounted

## 技能行为注册表（Game · data）：order / behavior / target / passive 唯一来源。
## Logic 路由读 behavior 键；新增技能优先只改本表。

const TARGET_POINT := 0
const TARGET_UNIT := 1
const TARGET_SELF := 2
const TARGET_ALLY := 3

const BEHAVIOR_SUMMON_POINT := "summon_point"
const BEHAVIOR_SUMMON_INSTANT := "summon_instant"
const BEHAVIOR_CHANNEL_AOE := "channel_aoe_damage"
const BEHAVIOR_MASS_TELEPORT := "mass_teleport"
const BEHAVIOR_STORM_BOLT := "storm_bolt"
const BEHAVIOR_SLOW := "slow_debuff"
const BEHAVIOR_HEAL := "ally_heal"
const BEHAVIOR_INNER_FIRE := "ally_inner_fire"
const BEHAVIOR_THUNDER_CLAP := "self_thunder_clap"
const BEHAVIOR_AVATAR := "self_avatar"
const BEHAVIOR_AURA_REGEN_MANA := "aura_regen_mana"
const BEHAVIOR_PROC_BASH := "proc_bash"

## order → entry。`supported` 为 false 时不进 Executor，但仍可上命令卡（采集等）。
const ORDER_ENTRIES := {
	"harvest": {"behavior": "", "target_kind": TARGET_POINT, "supported": true},
	"defend": {"behavior": "", "target_kind": TARGET_SELF, "supported": true},
	"townbellon": {"behavior": "", "target_kind": TARGET_SELF, "supported": true},
	"militia": {"behavior": "", "target_kind": TARGET_SELF, "supported": true},
	"waterelemental": {
		"behavior": BEHAVIOR_SUMMON_INSTANT,
		"target_kind": TARGET_SELF,
		"supported": true,
	},
	"blizzard": {
		"behavior": BEHAVIOR_CHANNEL_AOE,
		"target_kind": TARGET_POINT,
		"supported": true,
		"channel": true,
	},
	"massteleport": {
		"behavior": BEHAVIOR_MASS_TELEPORT,
		"target_kind": TARGET_POINT,
		"supported": true,
	},
	"thunderbolt": {
		"behavior": BEHAVIOR_STORM_BOLT,
		"target_kind": TARGET_UNIT,
		"supported": true,
	},
	"thunderclap": {
		"behavior": BEHAVIOR_THUNDER_CLAP,
		"target_kind": TARGET_SELF,
		"supported": true,
	},
	"avatar": {
		"behavior": BEHAVIOR_AVATAR,
		"target_kind": TARGET_SELF,
		"supported": true,
	},
	"heal": {
		"behavior": BEHAVIOR_HEAL,
		"target_kind": TARGET_ALLY,
		"supported": true,
		"autocast_eligible": true,
	},
	"innerfire": {
		"behavior": BEHAVIOR_INNER_FIRE,
		"target_kind": TARGET_ALLY,
		"supported": true,
	},
	"slow": {
		"behavior": BEHAVIOR_SLOW,
		"target_kind": TARGET_UNIT,
		"supported": true,
		"autocast_eligible": true,
	},
}

## 被动技能（无 order）；命令格 `passive:` 前缀。
const PASSIVE_ENTRIES := {
	"AHab": {"behavior": BEHAVIOR_AURA_REGEN_MANA, "kind": "aura"},
	"AHbh": {"behavior": BEHAVIOR_PROC_BASH, "kind": "proc"},
}


static func order_for(abil_id: String) -> String:
	return CommandButtonCatalog.get_shared().get_ability_order(abil_id)


static func entry_for_order(order: String) -> Dictionary:
	var ord := order.strip_edges()
	if ord.is_empty() or not ORDER_ENTRIES.has(ord):
		return {}
	return ORDER_ENTRIES[ord] as Dictionary


static func entry_for_abil(abil_id: String) -> Dictionary:
	return entry_for_order(order_for(abil_id))


static func behavior_for(abil_id: String) -> String:
	var e := entry_for_abil(abil_id)
	return str(e.get("behavior", "")).strip_edges()


static func target_kind(abil_id: String) -> int:
	var e := entry_for_abil(abil_id)
	if e.is_empty():
		return TARGET_POINT
	return int(e.get("target_kind", TARGET_POINT))


static func is_supported(abil_id: String) -> bool:
	var e := entry_for_abil(abil_id)
	return not e.is_empty() and bool(e.get("supported", false))


static func is_channel(abil_id: String) -> bool:
	var e := entry_for_abil(abil_id)
	return bool(e.get("channel", false))


static func is_autocast_eligible(abil_id: String) -> bool:
	var e := entry_for_abil(abil_id)
	return bool(e.get("autocast_eligible", false))


static func is_passive_ability(abil_id: String) -> bool:
	var id := abil_id.strip_edges()
	return PASSIVE_ENTRIES.has(id)


static func passive_behavior(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if not PASSIVE_ENTRIES.has(id):
		return ""
	return str((PASSIVE_ENTRIES[id] as Dictionary).get("behavior", "")).strip_edges()


static func passive_kind(abil_id: String) -> String:
	var id := abil_id.strip_edges()
	if not PASSIVE_ENTRIES.has(id):
		return ""
	return str((PASSIVE_ENTRIES[id] as Dictionary).get("kind", "")).strip_edges()
