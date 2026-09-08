class_name AnimSequenceResolver
extends RefCounted

## Stance × Activity → WC3 Sequence 逻辑名（空格版，播放前再由 AnimPlayback 解析 `_`/变体）。
##
## ## 分层
## - 纯命名表，无 Node、无播放；编辑器与游戏共用。
## - 姿态 = 平行动画族（负金/顶盾/主城升级档）；活动 = 当前在做什么。
## - 策略层（UnitVisual / BuildingVisual）组名；门面（Wc3ModelScene）负责播。
## - 技能施法 Sequence（Spell Throw / Spell Channel 等）由 Unit.play_spell_cast + AbilityCastCatalog 驱动。

## 姿态。
enum Stance {
	DEFAULT = 0,								## 默认。
	GOLD = 1,									## 金矿。
	LUMBER = 2,									## 木材。
	DEFEND = 3,									## 防御。
	UPGRADE_FIRST = 4,							## 升级第一。
	UPGRADE_SECOND = 5,							## 升级第二。
	ALTERNATE = 6,								## 变身（天神下凡 → Alternate*）。
}

## 活动。
enum Activity {
	IDLE = 0,									## 闲置。
	MOVE = 1,									## 移动。
	ATTACK = 2,									## 攻击。
	WORK = 3,									## 工作。
	BIRTH = 4,									## 出生。
	DEATH = 5,									## 死亡。
}

## 人族主城 typeId → 档位姿态（共用 TownHall.mdx）。
const TOWN_HALL_STANCE := {
	"htow": Stance.DEFAULT,						## 人族主城，默认姿态。
	"hkee": Stance.UPGRADE_FIRST,				## 人族主城，升级第一姿态。
	"hcas": Stance.UPGRADE_SECOND,				## 人族主城，升级第二姿态。
}

## 姿态后缀。
static func stance_suffix(stance: int) -> String:
	match stance:
		Stance.GOLD:
			return " Gold"							## 金矿姿态后缀。
		Stance.LUMBER:
			return " Lumber"						## 木材姿态后缀。
		Stance.DEFEND:
			return " Defend"						## 防御姿态后缀。
		Stance.UPGRADE_FIRST:
			return " Upgrade First"					## 升级第一姿态后缀。
		Stance.UPGRADE_SECOND:
			return " Upgrade Second"				## 升级第二姿态后缀。
		_:
			return ""								## 默认姿态后缀。


## 普攻动画回退（牧师/女巫等无 Attack，只有 SpellAttack）。
static func attack_animation_fallbacks() -> Array:
	return ["Attack", "SpellAttack", "Spell Attack", "Spell Throw", "Spell"]


## 英雄升天 / 消散死亡回退。
static func hero_dissipate_fallbacks() -> Array:
	return ["Dissipate", "Death", "Dissipate Alternate"]

## 活动基础。
static func activity_base(activity: int) -> String:
	match activity:
		Activity.MOVE:
			return "Walk"							## 移动活动基础。
		Activity.ATTACK:
			return "Attack"							## 攻击活动基础。
		Activity.WORK:
			return "Stand Work"						## 工作活动基础。
		Activity.BIRTH:
			return "Birth"							## 出生活动基础。
		Activity.DEATH:
			return "Death"							## 死亡活动基础。
		_:
			return "Stand"							## 闲置活动基础。


## 逻辑名（空格版）。Alternate 为前缀：`Alternate Stand` / `Alternate Walk`。
static func sequence_name(activity: int, stance: int = 0) -> String:
	var base := activity_base(activity)
	if stance == Stance.ALTERNATE:
		return "Alternate " + base
	return base + stance_suffix(stance)

## 逻辑名（下划线版），如 Stand_Gold / Stand_Work_Lumber / Birth_Upgrade_First。
static func sequence_name_underscored(activity: int, stance: int = 0) -> String:
	return sequence_name(activity, stance).replace(" ", "_")

## 建筑类型 ID → 姿态。
static func stance_for_building_type(type_id: String) -> int:
	return int(TOWN_HALL_STANCE.get(type_id, Stance.DEFAULT))

## 人族主城类型 ID → 姿态后缀。
static func town_hall_tier_suffix(type_id: String) -> String:
	return stance_suffix(stance_for_building_type(type_id))

## 源 MDX 标 looping 但首尾姿势不闭合 → 需 ping-pong，不能 LOOP_LINEAR。
static func needs_ping_pong(anim_or_logical: String) -> bool:
	var c := AnimPlayback.compact_seq_name(anim_or_logical)
	return c == "standgold" or c == "standlumber"

## PE2 侧常用更短的序列标签（负资源站立/走路仍用空手标签关闸）。
static func pe2_hint(logical: String, activity: int) -> String:
	var leaf := logical.replace("_", " ").strip_edges()
	if leaf.begins_with("Attack"):
		return "Attack"
	if activity == Activity.MOVE or activity == Activity.IDLE:
		var lower := leaf.to_lower()
		if lower.ends_with(" gold") or lower.ends_with(" lumber"):
			return activity_base(activity)
	return leaf if not leaf.is_empty() else activity_base(activity)

## 动画路径 → 叶子名。
static func _anim_leaf(anim_path: String) -> String:
	var i := anim_path.rfind("/")
	return anim_path.substr(i + 1) if i >= 0 else anim_path
