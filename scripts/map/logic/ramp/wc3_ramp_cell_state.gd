extends RefCounted
## Corner order: BL, BR, TL, TR. Classify before selecting a rendering owner.
enum Kind { FLAT, CLIFF, RAMP_CANDIDATE, MULTILEVEL_RAMP }
static func classify(levels: Array, flags: Array) -> int:
	var low: int = levels.min()
	var high: int = levels.max()
	if low == high:
		return Kind.FLAT
	var ramp := false
	for flag in flags:
		ramp = ramp or (int(flag) & Wc3Coords.FLAG_RAMP) != 0
	if not ramp:
		return Kind.CLIFF
	return Kind.MULTILEVEL_RAMP if high - low > 1 else Kind.RAMP_CANDIDATE

## Canonical D4 equivalence removes absolute elevation, rotation and reflection.
static func canonical_key(levels: Array, flags: Array) -> String:
	var low: int = levels.min()
	var best := ""
	for order in [[0,1,2,3], [2,0,3,1], [3,2,1,0], [1,3,0,2], [1,0,3,2], [3,1,2,0], [2,3,0,1], [0,2,1,3]]:
		var key := ""
		for i in order:
			key += "%d:%d;" % [int(levels[i]) - low, 1 if (int(flags[i]) & 4) != 0 else 0]
		if best.is_empty() or key < best:
			best = key
	return best


# Rendering policy is separate from shape classification. A local candidate alone
# is not proof of a supported original model; the collector supplies that evidence.
enum Route { NON_RAMP, SUPPORTED, INVALID, FALLBACK }
static func resolve(levels: Array, flags: Array, entrance: bool, model_coverage: bool) -> Dictionary:
	var kind := classify(levels, flags)
	var marked := 0
	for flag in flags:
		if (int(flag) & Wc3Coords.FLAG_RAMP) != 0:
			marked += 1
	if model_coverage:
		return {"route": Route.SUPPORTED, "owner": "original_model", "reason": "resolved_model"}
	if marked == 0:
		return {"route": Route.NON_RAMP, "owner": "base", "reason": "no_ramp_flags"}
	if kind == Kind.FLAT:
		return {"route": Route.INVALID, "owner": "base", "reason": "flat_ramp_flags"}
	if entrance and kind == Kind.RAMP_CANDIDATE:
		return {"route": Route.SUPPORTED, "owner": "ground", "reason": "single_level_entrance"}
	if marked == 4:
		return {"route": Route.FALLBACK, "owner": "ground", "reason": "multilevel" if kind == Kind.MULTILEVEL_RAMP else "saddle"}
	return {"route": Route.INVALID, "owner": "base", "reason": "incomplete_ramp_flags"}
