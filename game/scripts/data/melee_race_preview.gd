class_name MeleeRacePreview
extends RefCounted

## 对战种族预览 API：主城 / 初始工人 typeId（竖切用，非完整 Melee 规则）。


enum Race {
	HUMAN = 0,
	ORC = 1,
	UNDEAD = 2,
	NIGHT_ELF = 3,
}

const RACE_IDS := ["human", "orc", "undead", "nightelf"]


static func race_from_string(s: String) -> int:
	var key := s.strip_edges().to_lower()
	match key:
		"human", "h", "人族":
			return Race.HUMAN
		"orc", "o", "兽族":
			return Race.ORC
		"undead", "u", "ud", "不死":
			return Race.UNDEAD
		"nightelf", "night_elf", "ne", "e", "暗夜", "精灵":
			return Race.NIGHT_ELF
		_:
			return Race.HUMAN


static func race_id(race: int) -> String:
	var i := clampi(race, 0, RACE_IDS.size() - 1)
	return RACE_IDS[i]


static func display_name(race: int) -> String:
	match clampi(race, 0, 3):
		Race.HUMAN:
			return "人族"
		Race.ORC:
			return "兽族"
		Race.UNDEAD:
			return "不死族"
		Race.NIGHT_ELF:
			return "暗夜精灵"
		_:
			return "人族"


## 一级主城 typeId。
static func town_hall_id(race: int) -> String:
	match clampi(race, 0, 3):
		Race.HUMAN:
			return "htow"
		Race.ORC:
			return "ogre"
		Race.UNDEAD:
			return "unpl"
		Race.NIGHT_ELF:
			return "etol"
		_:
			return "htow"


## 初始工人 typeId。
static func worker_id(race: int) -> String:
	match clampi(race, 0, 3):
		Race.HUMAN:
			return "hpea"
		Race.ORC:
			return "opeo"
		Race.UNDEAD:
			return "uaco"
		Race.NIGHT_ELF:
			return "ewsp"
		_:
			return "hpea"


## 默认初始工人数量（经典 Melee 人族 5；各族先统一，后续可分）。
static func default_worker_count(race: int) -> int:
	match clampi(race, 0, 3):
		Race.HUMAN, Race.ORC:
			return 5
		Race.UNDEAD, Race.NIGHT_ELF:
			return 5
		_:
			return 5


static func preview_dict(race: int) -> Dictionary:
	return {
		"race": race_id(race),
		"display_name": display_name(race),
		"town_hall": town_hall_id(race),
		"worker": worker_id(race),
		"worker_count": default_worker_count(race),
	}
