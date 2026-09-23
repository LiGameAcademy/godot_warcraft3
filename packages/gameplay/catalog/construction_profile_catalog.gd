class_name ConstructionProfileCatalog
extends RefCounted

## F2-A 契约：race → ConstructionProfile 映射。
## 来源：UnitData.race（人类/兽/灵/亡/娜迦）。
## 来源：docs/design/game/BUILD_SYSTEM.md §4.4
##
## F2 范围：人族（HUMA/ORC/NIGHT/UNDEAD/NAGA 5 个 race 都注册，但 F2 只用 human）。

const PROFILES := {
	"human": "human",
	"orc": "orc",
	"nightelf": "nightelf",
	"undead": "undead",
	"naga": "human",  # 娜迦 F2 不实现，fallback human
}

## 缓存已构造的 profile
var _cache: Dictionary = {}


## 按 race_id 拿 profile
func for_race(race_id: String) -> ConstructionProfile:
	if race_id.is_empty():
		return ConstructionProfile.human()
	var key: String = PROFILES.get(race_id.to_lower(), "human")
	if _cache.has(key):
		return _cache[key]
	var p: ConstructionProfile
	match key:
		"human":
			p = ConstructionProfile.human()
		"orc":
			p = ConstructionProfile.orc()
		"nightelf":
			p = ConstructionProfile.nightelf()
		"undead":
			p = ConstructionProfile.undead()
		_:
			p = ConstructionProfile.human()
	_cache[key] = p
	return p


## 清缓存（test 用）
func clear() -> void:
	_cache.clear()
