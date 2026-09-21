class_name MatchBootstrapModule
extends Node

## 对局开局：会话创建、本地/对手基地刷兵、镜头落点。
## MeleeBootstrap / MeleeRacePreview 仍为静态规则；本模块协调对局装配。
## 不持有 GameDirector 类型。

var _map_root: MapLoader
var _map_dir: String = ""
var _game_hud: Node
var _rts_camera: Node
var _rng: RandomNumberGenerator
var _apply_cursor_race: Callable
var _refresh_pathing: Callable
var _map_display_name: Callable
var _on_pathing_map: Callable


func configure(deps: Dictionary) -> void:
	_map_root = deps.get("map_root") as MapLoader
	_map_dir = str(deps.get("map_dir", ""))
	_game_hud = deps.get("game_hud") as Node
	_rts_camera = deps.get("rts_camera") as Node
	_rng = deps.get("rng") as RandomNumberGenerator
	_apply_cursor_race = deps.get("apply_cursor_race", Callable()) as Callable
	_refresh_pathing = deps.get("refresh_pathing", Callable()) as Callable
	_map_display_name = deps.get("map_display_name", Callable()) as Callable
	_on_pathing_map = deps.get("on_pathing_map", Callable()) as Callable


func shutdown() -> void:
	_map_root = null
	_map_dir = ""
	_game_hud = null
	_rts_camera = null
	_rng = null
	_apply_cursor_race = Callable()
	_refresh_pathing = Callable()
	_map_display_name = Callable()
	_on_pathing_map = Callable()


func _exit_tree() -> void:
	shutdown()


## 开局入口。options: preview_race / local_player / random_start_location /
## spawn_melee_base / spawn_opponent_base。
## 返回 { session, hall_world, local_sloc, ok }。
func bootstrap_melee(options: Dictionary) -> Dictionary:
	var preview_race := str(options.get("preview_race", "human"))
	var local_player := int(options.get("local_player", 0))
	var random_start := bool(options.get("random_start_location", true))
	var spawn_base := bool(options.get("spawn_melee_base", true))
	var spawn_opponent := bool(options.get("spawn_opponent_base", false))

	var race := MeleeRacePreview.race_from_string(preview_race)
	var preview := MeleeRacePreview.preview_dict(race)
	var worker_n: int = int(preview.get("worker_count", 5))
	var session := GameSession.from_melee_bootstrap(
		_map_dir,
		local_player,
		str(preview.get("race", "human")),
		worker_n,
		PlayerStock.MELEE_TOWN_HALL_FOOD
	)
	TechPresence.bind_session(session)
	if _apply_cursor_race.is_valid():
		_apply_cursor_race.call(str(preview.get("race", "human")))
	if _game_hud != null and _game_hud.has_method("bind_stock"):
		_game_hud.call("bind_stock", session.local_stock())

	var out := {
		"session": session,
		"hall_world": Vector3.ZERO,
		"local_sloc": {},
		"ok": true,
	}

	var slocs := MeleeBootstrap.collect_slocs(_map_dir)
	if slocs.is_empty():
		_set_status("%s · 无 sloc，跳过开局刷兵" % str(preview.get("display_name", "")))
		_finish_pathing()
		return out

	var sloc: Dictionary
	if random_start:
		sloc = MeleeBootstrap.pick_random_sloc(slocs, _rng)
	else:
		sloc = _find_sloc_for_owner(slocs, local_player)
		if sloc.is_empty():
			sloc = MeleeBootstrap.pick_random_sloc(slocs, _rng)
	out["local_sloc"] = sloc

	var hall_world := Vector3.ZERO
	if spawn_base:
		if _map_root == null:
			out["ok"] = false
			_set_status("%s · 开局刷兵失败" % str(preview.get("display_name", "")))
			_finish_pathing()
			return out
		var hf := _map_root.get_heightfield_dict()
		var result := MeleeBootstrap.spawn_at_sloc(_map_root, sloc, race, local_player, hf)
		if result.get("ok", false):
			hall_world = result.get("hall_world", Vector3.ZERO) as Vector3
			_set_status(
				"%s · %s @ sloc owner=%s · 刷 %d · 金%d 木%d"
				% [
					_display_name(),
					str(preview.get("display_name", "")),
					str(sloc.get("owner", "?")),
					int(result.get("spawned", 0)),
					session.local_stock().gold,
					session.local_stock().lumber,
				]
			)
		else:
			out["ok"] = false
			_set_status("%s · 开局刷兵失败" % str(preview.get("display_name", "")))
	else:
		var pos: Dictionary = sloc.get("position", {})
		hall_world = Wc3Coords.wc3_xy_to_godot(
			float(pos.get("x", 0.0)),
			float(pos.get("y", 0.0)),
			float(pos.get("z", 0.0))
		)

	out["hall_world"] = hall_world
	if _rts_camera != null and hall_world != Vector3.ZERO:
		if _rts_camera.has_method("snap_to"):
			_rts_camera.call("snap_to", hall_world)
		if _rts_camera.has_method("focus_on_position"):
			_rts_camera.call("focus_on_position", hall_world, 0.35)

	if spawn_base and spawn_opponent:
		spawn_opponent_base(session, slocs, sloc, local_player)

	_finish_pathing()
	return out


func spawn_opponent_base(
	session: GameSession, slocs: Array[Dictionary], local_sloc: Dictionary, local_player: int
) -> bool:
	if session == null or _map_root == null:
		return false
	var available := MeleeBootstrap.available_slocs(slocs, [local_sloc])
	if available.is_empty():
		push_warning("双玩家开局：没有独立的对手出生点")
		return false
	var owner_id := 1 if local_player == 0 else 0
	if session.stocks.has(owner_id):
		return false
	var sloc := MeleeBootstrap.pick_random_sloc(available, _rng)
	var race := MeleeRacePreview.race_from_string("human")
	var result := MeleeBootstrap.spawn_at_sloc(
		_map_root, sloc, race, owner_id, _map_root.get_heightfield_dict()
	)
	if not bool(result.get("ok", false)):
		return false
	var workers := maxi(int(result.get("spawned", 1)) - 1, 0)
	var cap := BuildingCatalog.get_food_made(str(result.get("town_hall", "htow")))
	session.set_stock(owner_id, PlayerStock.melee_start(workers, cap))
	return true


func _find_sloc_for_owner(slocs: Array[Dictionary], owner_id: int) -> Dictionary:
	for s in slocs:
		if int(s.get("owner", -1)) == owner_id:
			return s
	return {}


func _finish_pathing() -> void:
	# 开局刷兵后立刻同步动态 pathing（与叠层一致），避免瞄准时漏检脚印
	if _on_pathing_map.is_valid() and _map_root != null:
		_on_pathing_map.call(_map_root.get_pathing_map())
	if _refresh_pathing.is_valid():
		_refresh_pathing.call()


func _display_name() -> String:
	if _map_display_name.is_valid():
		return str(_map_display_name.call())
	return _map_dir.get_file()


func _set_status(text: String) -> void:
	if _game_hud != null and _game_hud.has_method("set_status"):
		_game_hud.call("set_status", text)
