class_name AbilityCastCatalog
extends RefCounted

## 技能施法表现映射（Game · data）：Sequence / channel 时长。
## 特效路径已迁至 AbilityFxCatalog；本类保留 order→Sequence 与引导参数。

const _SPELL_SEQ_BY_ORDER := {
	"blizzard": "Spell Channel",
	"waterelemental": "Spell Throw",
	"massteleport": "Spell Throw",
	"thunderbolt": "Spell Throw",
	"thunderclap": "Spell Slam",
	"avatar": "Spell Throw",
	"heal": "SpellAttack",
	"innerfire": "SpellAttack",
	"slow": "Spell Throw",
}


static func is_channel_ability(abil_id: String) -> bool:
	return AbilityBehaviorCatalog.is_channel(abil_id)


## 读条时长（秒）。优先 AbilityData.CastN；AHmt 的 Cast=0 但 DataB≈真实吟唱（原作约 3s）。
static func cast_time_sec(abil_id: String, level: int) -> float:
	var id := abil_id.strip_edges()
	var ab := AbilityCatalog.data(id)
	if ab == null:
		return 0.0
	var from_cast := maxf(ab.cast_time_at(level), 0.0)
	if from_cast > 0.01:
		return from_cast
	if id == "AHmt":
		return maxf(ab.data_b_at(level), 0.0)
	return 0.0


static func channel_duration_sec(abil_id: String, level: int) -> float:
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return 0.0
	var waves := maxi(int(round(ab.data_a_at(level))), 1)
	var interval := maxf(ab.data_d_at(level), 0.05)
	return float(waves) * interval


static func hit_effect_art(abil_id: String) -> String:
	return AbilityFxCatalog.hit_effect_art(abil_id)


static func spell_sequence_for(abil_id: String) -> String:
	var order := AbilityCatalog.order_for(abil_id)
	return str(_SPELL_SEQ_BY_ORDER.get(order, "Spell Throw"))


static func ground_effect_art(abil_id: String) -> String:
	return AbilityFxCatalog.ground_effect_art(abil_id)


static func missile_art(abil_id: String) -> String:
	return AbilityFxCatalog.missile_art(abil_id)


static func caster_art(abil_id: String) -> String:
	return AbilityFxCatalog.caster_art(abil_id)
