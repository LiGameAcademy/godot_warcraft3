class_name PortraitAnimation
extends RefCounted
## Portrait sequence selection and replay, independent of viewport/pooling.
var _ap: AnimationPlayer
var player: AnimationPlayer:
	get:
		return _ap
var _portrait_anims: PackedStringArray = PackedStringArray()
var _locked_portrait_anim: String = ""
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _model_root: Node3D
var _cache: MapModelCache

func configure(cache: MapModelCache) -> void:
	_cache = cache
	_rng.randomize()

func _snap_portrait_geoset() -> void:
	if _cache != null and _model_root != null and _ap != null:
		_cache.snap_geoset_visibility_for(_model_root, str(_ap.current_animation), 0.0, false)

func _start_portrait_anims(root: Node3D, type_id: String) -> void:
	_model_root = root
	_disconnect_anim()
	_portrait_anims = PackedStringArray()
	_locked_portrait_anim = ""
	for n: Node in root.find_children("*", "AnimationPlayer", true, false):
		var player: AnimationPlayer = n as AnimationPlayer
		if player == null:
			continue
		_ap = player
		if not player.animation_finished.is_connected(_on_portrait_anim_finished):
			player.animation_finished.connect(_on_portrait_anim_finished)
		# 主城：按 htow / hkee / hcas 播对应 Portrait（不随机）
		if AnimSequenceResolver.TOWN_HALL_STANCE.has(type_id):
			var locked: String = _resolve_town_hall_portrait(root, player, type_id)
			if locked.is_empty():
				var stand_logical: String = (
					"Stand" + AnimSequenceResolver.town_hall_tier_suffix(type_id)
				)
				locked = AnimPlayback.resolve(root, stand_logical, player)
			if not locked.is_empty():
				_locked_portrait_anim = locked
				_ap.play(locked)
				_snap_portrait_geoset()
			return
		_portrait_anims = _collect_portrait_anims(root, player)
		if _portrait_anims.is_empty() and BuildingCatalog.is_building(type_id):
			# 建筑无 Portrait*：定格 Stand geoset 后亮 mesh，避免只剩队色底。
			var stand_b: String = AnimPlayback.resolve(root, "Stand", player)
			if not stand_b.is_empty():
				player.play(stand_b)
				_snap_portrait_geoset()
			return
		_play_random_portrait_anim()
		return


## TownHall.mdx：Portrait_-1 / Portrait_Upgrade_First / Portrait_Upgrade_Second。
func _resolve_town_hall_portrait(
	root: Node3D, player: AnimationPlayer, type_id: String
) -> String:
	var suffix: String = AnimSequenceResolver.town_hall_tier_suffix(type_id)
	var logical: String = "Portrait" + suffix
	var resolved: String = AnimPlayback.resolve(root, logical, player)
	if not resolved.is_empty():
		return resolved
	# 一本：源名常为 Portrait_-1，精确「Portrait」对不上
	if suffix.is_empty():
		for alt: String in ["Portrait - 1", "Portrait_-1", "Portrait -1", "Portrait-1", "Portrait"]:
			resolved = AnimPlayback.resolve(root, alt, player)
			if not resolved.is_empty():
				return resolved
	return ""


func _collect_portrait_anims(root: Node3D, player: AnimationPlayer) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	# 只扫列表：避免对不存在的 Portrait Talk 等反复 resolve 刷 DBG
	for anim_name: String in player.get_animation_list():
		var leaf: String = AnimPlayback.anim_leaf(str(anim_name)).to_lower().replace(" ", "_")
		if not leaf.begins_with("portrait"):
			continue
		var key: String = str(anim_name)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	if not out.is_empty():
		return out
	# 列表里没有 portrait* 时再试少量逻辑名
	for logical: String in ["Portrait", "Portrait - 1", "Portrait Talk"]:
		var resolved: String = AnimPlayback.resolve(root, logical, player)
		if resolved.is_empty() or seen.has(resolved):
			continue
		seen[resolved] = true
		out.append(resolved)
	return out


func _play_random_portrait_anim() -> void:
	if _ap == null or not is_instance_valid(_ap):
		return
	if _portrait_anims.is_empty():
		# 无 Portrait 序列时退 Stand
		var stand: String = AnimPlayback.resolve(_model_root, "Stand", _ap) if _model_root else ""
		if not stand.is_empty():
			_ap.play(stand)
			_snap_portrait_geoset()
		elif _ap.get_animation_list().size() > 0:
			_ap.play(_ap.get_animation_list()[0])
			_snap_portrait_geoset()
		return
	var idx: int = _rng.randi_range(0, _portrait_anims.size() - 1)
	var pick: String = _portrait_anims[idx]
	# 连续多段时尽量不马上重复同一条
	if _portrait_anims.size() > 1 and _ap.is_playing():
		var cur: String = AnimPlayback.anim_leaf(str(_ap.current_animation)).to_lower()
		var tries: int = 0
		while tries < 4 and AnimPlayback.anim_leaf(pick).to_lower() == cur:
			idx = _rng.randi_range(0, _portrait_anims.size() - 1)
			pick = _portrait_anims[idx]
			tries += 1
	_ap.play(pick)
	_snap_portrait_geoset()


func _on_portrait_anim_finished(_anim_name: StringName) -> void:
	if _model_root == null or not is_instance_valid(_model_root):
		return
	if not _locked_portrait_anim.is_empty() and _ap != null and is_instance_valid(_ap):
		_ap.play(_locked_portrait_anim)
		return
	_play_random_portrait_anim()
func _disconnect_anim() -> void:
	_disconnect_anim_only()
	_locked_portrait_anim = ""


func _disconnect_anim_only() -> void:
	if _ap != null and is_instance_valid(_ap):
		if _ap.animation_finished.is_connected(_on_portrait_anim_finished):
			_ap.animation_finished.disconnect(_on_portrait_anim_finished)
	_ap = null
