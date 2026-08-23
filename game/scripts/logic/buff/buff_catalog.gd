class_name BuffCatalog
extends RefCounted

## Buff 静态定义（Logic · data）：id、可驱散、与 Ability 映射。

const ID_STUN := "stun"
const ID_SLOW := "slow"
const ID_INNER_FIRE := "inner_fire"
const ID_BONUS_ARMOR := "bonus_armor"

const DISPELLABLE := {
	ID_SLOW: true,
	ID_INNER_FIRE: true,
	ID_BONUS_ARMOR: false,
	ID_STUN: false,
}

## 技能 → buff id（Phase C 竖切；光环 tick 类不在此表）
const BUFF_BY_ABIL := {
	"Aslo": ID_SLOW,
	"Ainf": ID_INNER_FIRE,
}


static func is_dispellable(buff_id: String) -> bool:
	return bool(DISPELLABLE.get(buff_id.strip_edges(), false))


static func buff_id_for_ability(abil_id: String) -> String:
	return str(BUFF_BY_ABIL.get(abil_id.strip_edges(), ""))
