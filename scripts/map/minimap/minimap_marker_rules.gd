extends RefCounted
## Shared semantic classification; visibility and team colors remain adapter policy.
const NONE := -1
const GOLD := 0
const NEUTRAL_BUILDING := 1
const START := 2
const CREEP := 3
static func classify(id: String, owner: int, info: Dictionary) -> int:
	if id == "ngol":
		return GOLD
	if id == "sloc":
		return START
	var building := bool(info.get("is_building", false))
	if building and bool(info.get("nbmm_icon", owner >= 12 or owner < 0)):
		return NEUTRAL_BUILDING
	if owner == 12 and not building:
		return CREEP
	return NONE
