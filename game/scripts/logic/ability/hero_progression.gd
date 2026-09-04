class_name HeroProgression
extends RefCounted

## 英雄等级 / 经验（Logic）：经验阈值对齐 WC3 Melee GameBalance。

const META_HERO_XP := "hero_xp"
const MAX_HERO_LEVEL := 10

## 到达该等级所需的累计经验（index = level）。
const _XP_THRESHOLDS := [
	0, 200, 700, 1625, 2875, 4475, 6425, 8825, 11675, 14975, 999999,
]


static func ensure(unit: Node3D) -> void:
	if unit == null:
		return
	if not unit.has_meta(META_HERO_XP):
		unit.set_meta(META_HERO_XP, 0)
	if not unit.has_meta(AbilityCatalog.META_HERO_LEVEL):
		unit.set_meta(AbilityCatalog.META_HERO_LEVEL, 1)


## 复活/调试：设等级并同步经验到该级门槛。
static func set_level(unit: Node3D, level: int, xp_total: int = -1) -> void:
	if unit == null:
		return
	var lv := clampi(level, 1, MAX_HERO_LEVEL)
	unit.set_meta(AbilityCatalog.META_HERO_LEVEL, lv)
	var xp := xp_total if xp_total >= 0 else xp_threshold(lv)
	unit.set_meta(META_HERO_XP, maxi(xp, 0))


static func xp_of(unit: Node3D) -> int:
	if unit == null:
		return 0
	ensure(unit)
	return maxi(int(unit.get_meta(META_HERO_XP)), 0)


static func xp_threshold(level: int) -> int:
	var lv := clampi(level, 1, MAX_HERO_LEVEL)
	if lv < _XP_THRESHOLDS.size():
		return int(_XP_THRESHOLDS[lv - 1])
	return int(_XP_THRESHOLDS[MAX_HERO_LEVEL - 1])


static func xp_for_next_level(level: int) -> int:
	var lv := clampi(level, 1, MAX_HERO_LEVEL)
	if lv >= MAX_HERO_LEVEL:
		return xp_threshold(MAX_HERO_LEVEL)
	return xp_threshold(lv + 1)


## 当前等级段内进度：{ level, xp_total, xp_in_level, xp_need, at_max }。
static func progress_for(unit: Node3D) -> Dictionary:
	var out := {
		"level": 1,
		"xp_total": 0,
		"xp_in_level": 0,
		"xp_need": 1,
		"at_max": false,
	}
	if unit == null:
		return out
	ensure(unit)
	var lv := AbilityCatalog.hero_level_of(unit)
	var total := xp_of(unit)
	var floor_xp := xp_threshold(lv)
	var at_max := lv >= MAX_HERO_LEVEL
	var ceil_xp := xp_for_next_level(lv) if not at_max else floor_xp
	var need := maxi(ceil_xp - floor_xp, 1)
	out["level"] = lv
	out["xp_total"] = total
	out["xp_in_level"] = clampi(total - floor_xp, 0, need)
	out["xp_need"] = need
	out["at_max"] = at_max
	return out
