extends SceneTree
const State := preload("res://addons/rts_map/logic/ramp/wc3_ramp_cell_state.gd")
func _initialize() -> void:
	var cases := 0
	var classes := {}
	var routes := {}
	var route_classes := {}
	for heights in range(256):
		var levels := [heights%4, (heights/4)%4, (heights/16)%4, (heights/64)%4]
		for mask in range(16):
			var flags := [4 if mask&1 else 0, 4 if mask&2 else 0, 4 if mask&4 else 0, 4 if mask&8 else 0]
			var key := State.canonical_key(levels, flags)
			var rotated := [levels[2]+7, levels[0]+7, levels[3]+7, levels[1]+7]
			assert(State.canonical_key(rotated, [flags[2], flags[0], flags[3], flags[1]]) == key)
			assert(State.canonical_key([levels[1],levels[0],levels[3],levels[2]], [flags[1],flags[0],flags[3],flags[2]]) == key)
			var spread: int = levels.max() - levels.min()
			var expected := State.Kind.FLAT if spread == 0 else (State.Kind.CLIFF if mask == 0 else (State.Kind.MULTILEVEL_RAMP if spread > 1 else State.Kind.RAMP_CANDIDATE))
			assert(State.classify(levels,flags) == expected)
			var entrance: bool = mask == 15 and not (levels[0] == levels[3] and levels[1] == levels[2])
			var policy := State.resolve(levels,flags,entrance,false)
			var names := ["non_ramp", "supported", "invalid", "fallback"]
			var route: String = names[policy.route]
			routes[route] = int(routes.get(route,0)) + 1
			if not route_classes.has(route):
				route_classes[route] = {}
			route_classes[route][key] = true
			assert(State.resolve(rotated,[flags[2],flags[0],flags[3],flags[1]],entrance,false).route == policy.route)
			if mask == 0:
				assert(policy.route == State.Route.NON_RAMP)
			elif spread == 0 or mask != 15:
				assert(policy.route == State.Route.INVALID)
			elif spread > 1 or not entrance:
				assert(policy.route == State.Route.FALLBACK)
			else:
				assert(policy.route == State.Route.SUPPORTED)
			assert(State.resolve(levels,flags,entrance,true).owner == "original_model")
			classes[key] = true
			cases += 1
	print("selftest_ramp_cell_state: PASS cases=%d canonical=%d" % [cases, classes.size()])
	var summary := {}
	for route in routes:
		summary[route] = {"raw": routes[route], "canonical": route_classes[route].size()}
	var file := FileAccess.open("res://tmp/ramp-state-routes.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(summary,"  "))
	print("Local-only routing (model coverage tested separately): ", summary)
	quit()
