class_name UnitPortraitView
extends Control

## HUD 3D 肖像框：队色 ColorRect 底 + SubViewport。
## 机位：优先肖像 .scn 内 bake 的 Camera3D；无则懒创建回退相机（sidecar / AABB）。
## 动画：普通单位 Portrait* 随机；主城 htow/hkee/hcas 按科技档位固定播。

const PORTRAIT_SIZE := Vector2i(96, 96)
const _EMPTY_BG := Color(0.12, 0.12, 0.14, 1.0)
## 中立（owner≥12）肖像底：黑灰，不用队色条。
const _NEUTRAL_BG := Color(0.1, 0.1, 0.11, 1.0)
const _NEUTRAL_OWNER_MIN := 12

@onready var _bg: ColorRect = $TeamColorBg
@onready var _world: Node3D = $PortraitViewportHost/PortraitViewport/PortraitWorld
@onready var _vp: SubViewport = $PortraitViewportHost/PortraitViewport

var _fallback_cam: Camera3D = null
var _model_root: Node3D
var _ap: AnimationPlayer = null
var _portrait_anims: PackedStringArray = PackedStringArray()
## 非空时锁死该条（主城档位），播完重播，不随机。
var _locked_portrait_anim: String = ""
var _cache: MapModelCache = null
var _catalog: Wc3IdCatalog = null
var _type_id: String = ""
var _model_path: String = ""
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	custom_minimum_size = Vector2(PORTRAIT_SIZE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _bg != null:
		_bg.color = _EMPTY_BG
	if _vp != null:
		_vp.size = PORTRAIT_SIZE
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func configure(cache: MapModelCache, catalog: Wc3IdCatalog) -> void:
	_cache = cache
	_catalog = catalog


func clear_portrait() -> void:
	_type_id = ""
	_model_path = ""
	_disconnect_anim()
	_clear_model()
	if _bg != null:
		_bg.color = _EMPTY_BG


func show_type(type_id: String, owner_id: int = 0) -> void:
	var tid := type_id.strip_edges()
	if tid.is_empty():
		clear_portrait()
		return
	if tid == _type_id and _model_root != null and is_instance_valid(_model_root):
		_apply_team_bg(tid, owner_id)
		return
	_type_id = tid
	_disconnect_anim()
	_clear_model()
	if _cache == null or _catalog == null or _world == null:
		return
	var path := _catalog.portrait_glb_path(tid)
	if path.is_empty():
		path = _catalog.converted_glb_path(tid)
	if path.is_empty():
		_apply_team_bg(tid, owner_id)
		return
	var inst: Node3D = _cache.instance_glb(path) as Node3D
	if inst == null:
		_apply_team_bg(tid, owner_id)
		return
	_model_path = path
	_model_root = inst
	_world.add_child(inst)
	var color_i := MapUnitLayer.resolve_team_color_index(tid, owner_id)
	_cache.apply_team_color(inst, color_i, tid != "sloc")
	_apply_team_bg(tid, owner_id)
	_fit_camera(inst, path)
	_start_portrait_anims(inst, tid)


func _is_neutral_owner(owner_id: int) -> bool:
	return owner_id >= _NEUTRAL_OWNER_MIN or owner_id < 0


func _apply_team_bg(type_id: String, owner_id: int) -> void:
	if _bg == null:
		return
	if _is_neutral_owner(owner_id):
		_bg.color = _NEUTRAL_BG
		return
	var color_i := MapUnitLayer.resolve_team_color_index(type_id, owner_id)
	if color_i >= 0 and color_i < MapPlaceholders.PLAYER_COLORS.size():
		_bg.color = MapPlaceholders.PLAYER_COLORS[color_i]
	else:
		_bg.color = MapPlaceholders.color_for(type_id, owner_id, true)


func _clear_model() -> void:
	if _model_root != null and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = null
	_portrait_anims = PackedStringArray()
	_locked_portrait_anim = ""
	if _fallback_cam != null and is_instance_valid(_fallback_cam):
		_fallback_cam.current = false


func _disconnect_anim() -> void:
	if _ap != null and is_instance_valid(_ap):
		if _ap.animation_finished.is_connected(_on_portrait_anim_finished):
			_ap.animation_finished.disconnect(_on_portrait_anim_finished)
	_ap = null
	_locked_portrait_anim = ""


func _fit_camera(root: Node3D, model_path: String) -> void:
	if root == null or _world == null:
		return
	# 1) 肖像 .scn 内 bake 的 Camera3D —— 唯一「正式」机位
	var baked := _find_baked_camera(root)
	if baked != null:
		if _fallback_cam != null and is_instance_valid(_fallback_cam):
			_fallback_cam.current = false
		baked.current = true
		return
	# 2) 无 bake 相机：用 HUD 回退相机 + sidecar / AABB
	var cam := _ensure_fallback_camera()
	cam.current = true
	if _apply_mdx_camera_sidecar(cam, model_path):
		return
	var aabb := _visual_aabb(root)
	if aabb.size.length() < 1e-4:
		aabb = AABB(Vector3(-0.4, 0.0, -0.4), Vector3(0.8, 1.2, 0.8))
	var center := aabb.position + aabb.size * 0.5
	center.y = aabb.position.y + aabb.size.y * 0.62
	var radius := maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z)) * 0.5
	radius = maxf(radius, 0.35)
	var dist := radius / maxf(tan(deg_to_rad(cam.fov * 0.5)), 0.05) * 1.15
	cam.global_position = center + Vector3(0.0, radius * 0.08, dist)
	cam.look_at(center, Vector3.UP)


func _ensure_fallback_camera() -> Camera3D:
	if _fallback_cam != null and is_instance_valid(_fallback_cam):
		return _fallback_cam
	_fallback_cam = Camera3D.new()
	_fallback_cam.name = "FallbackPortraitCam"
	_fallback_cam.fov = 30.0
	_fallback_cam.current = false
	_world.add_child(_fallback_cam)
	return _fallback_cam


func _find_baked_camera(root: Node) -> Camera3D:
	if root == null:
		return null
	for prefer in ["Camera01", "PortraitCamera", "Camera"]:
		var n := root.find_child(prefer, true, false)
		if n is Camera3D:
			return n as Camera3D
	var found: Array[Node] = root.find_children("*", "Camera3D", true, false)
	if found.is_empty():
		return null
	return found[0] as Camera3D


func _apply_mdx_camera_sidecar(cam: Camera3D, model_path: String) -> bool:
	var data := _load_cameras_sidecar(model_path)
	if data.is_empty():
		return false
	var cams: Variant = data.get("cameras", [])
	if typeof(cams) != TYPE_ARRAY or (cams as Array).is_empty():
		return false
	var first: Variant = (cams as Array)[0]
	if typeof(first) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = first
	var pos_v: Variant = d.get("position", null)
	var tgt_v: Variant = d.get("target", null)
	if typeof(pos_v) != TYPE_ARRAY or typeof(tgt_v) != TYPE_ARRAY:
		return false
	var pos_a: Array = pos_v
	var tgt_a: Array = tgt_v
	if pos_a.size() < 3 or tgt_a.size() < 3:
		return false
	var pos := Vector3(float(pos_a[0]), float(pos_a[1]), float(pos_a[2]))
	var tgt := Vector3(float(tgt_a[0]), float(tgt_a[1]), float(tgt_a[2]))
	cam.fov = clampf(float(d.get("fov_y_deg", 30.0)), 5.0, 120.0)
	var near_v := float(d.get("near", 0.01))
	var far_v := float(d.get("far", 100.0))
	if near_v > 0.0:
		cam.near = near_v
	if far_v > near_v:
		cam.far = far_v
	cam.position = pos
	if pos.distance_squared_to(tgt) > 1e-8:
		cam.look_at(tgt, Vector3.UP)
	return true


func _load_cameras_sidecar(model_path: String) -> Dictionary:
	if model_path.is_empty():
		return {}
	var logical := model_path
	if logical.begins_with("res://assets/asset-converted/"):
		logical = logical.substr("res://assets/asset-converted/".length())
	elif logical.begins_with("res://"):
		logical = logical.substr("res://".length())
	var stem := logical
	var lower := stem.to_lower()
	for ext in [".gltf", ".glb", ".scn"]:
		if lower.ends_with(ext):
			stem = stem.substr(0, stem.length() - ext.length())
			break
	var cam_logical := stem + ".cameras.json"
	var disk := RuntimeAssets.project_abs(RuntimeAssets.converted_path(cam_logical))
	if disk.is_empty() or not FileAccess.file_exists(disk):
		return {}
	var text := RuntimeAssets.read_utf8_text(disk)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed as Dictionary


func _visual_aabb(root: Node3D) -> AABB:
	var aabb := AABB()
	var first := true
	for c in root.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if vi == null or not vi.visible:
			continue
		var la := vi.get_aabb()
		var xf := vi.global_transform
		for i in range(8):
			var local := la.position + la.size * Vector3(
				float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1)
			)
			var p := root.to_local(xf * local)
			if first:
				aabb = AABB(p, Vector3.ZERO)
				first = false
			else:
				aabb = aabb.expand(p)
	return aabb


func _start_portrait_anims(root: Node3D, type_id: String) -> void:
	_disconnect_anim()
	_portrait_anims = PackedStringArray()
	_locked_portrait_anim = ""
	for n in root.find_children("*", "AnimationPlayer", true, false):
		var player := n as AnimationPlayer
		if player == null:
			continue
		_ap = player
		if not player.animation_finished.is_connected(_on_portrait_anim_finished):
			player.animation_finished.connect(_on_portrait_anim_finished)
		# 主城：按 htow / hkee / hcas 播对应 Portrait（不随机）
		if AnimSequenceResolver.TOWN_HALL_STANCE.has(type_id):
			var locked := _resolve_town_hall_portrait(root, player, type_id)
			if locked.is_empty():
				var stand_logical := (
					"Stand" + AnimSequenceResolver.town_hall_tier_suffix(type_id)
				)
				locked = AnimPlayback.resolve(root, stand_logical, player)
			if not locked.is_empty():
				_locked_portrait_anim = locked
				_ap.play(locked)
			return
		_portrait_anims = _collect_portrait_anims(root, player)
		_play_random_portrait_anim()
		return


## TownHall.mdx：Portrait_-1 / Portrait_Upgrade_First / Portrait_Upgrade_Second。
func _resolve_town_hall_portrait(
	root: Node3D, player: AnimationPlayer, type_id: String
) -> String:
	var suffix := AnimSequenceResolver.town_hall_tier_suffix(type_id)
	var logical := "Portrait" + suffix
	var resolved := AnimPlayback.resolve(root, logical, player)
	if not resolved.is_empty():
		return resolved
	# 一本：源名常为 Portrait_-1，精确「Portrait」对不上
	if suffix.is_empty():
		for alt in ["Portrait - 1", "Portrait_-1", "Portrait -1", "Portrait"]:
			resolved = AnimPlayback.resolve(root, alt, player)
			if not resolved.is_empty():
				return resolved
	return ""


func _collect_portrait_anims(root: Node3D, player: AnimationPlayer) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var seen: Dictionary = {}
	# 逻辑名候选（含空格 / 下划线变体由 resolve 处理）
	var candidates: Array[String] = [
		"Portrait",
		"Portrait - 1",
		"Portrait - 2",
		"Portrait - 3",
		"Portrait - 4",
		"Portrait Talk",
		"Portrait Talk -1",
		"Portrait Talk 2",
	]
	for logical in candidates:
		var resolved := AnimPlayback.resolve(root, logical, player)
		if resolved.is_empty() or seen.has(resolved):
			continue
		seen[resolved] = true
		out.append(resolved)
	# 再扫列表：名字叶子以 portrait 开头的都收进池
	for anim_name in player.get_animation_list():
		var leaf := AnimPlayback.anim_leaf(str(anim_name)).to_lower().replace(" ", "_")
		if not leaf.begins_with("portrait"):
			continue
		var key := str(anim_name)
		if seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	return out


func _play_random_portrait_anim() -> void:
	if _ap == null or not is_instance_valid(_ap):
		return
	if _portrait_anims.is_empty():
		# 无 Portrait 序列时退 Stand
		var stand := AnimPlayback.resolve(_model_root, "Stand", _ap) if _model_root else ""
		if not stand.is_empty():
			_ap.play(stand)
		elif _ap.get_animation_list().size() > 0:
			_ap.play(_ap.get_animation_list()[0])
		return
	var idx := _rng.randi_range(0, _portrait_anims.size() - 1)
	var pick := _portrait_anims[idx]
	# 连续多段时尽量不马上重复同一条
	if _portrait_anims.size() > 1 and _ap.is_playing():
		var cur := AnimPlayback.anim_leaf(str(_ap.current_animation)).to_lower()
		var tries := 0
		while tries < 4 and AnimPlayback.anim_leaf(pick).to_lower() == cur:
			idx = _rng.randi_range(0, _portrait_anims.size() - 1)
			pick = _portrait_anims[idx]
			tries += 1
	_ap.play(pick)


func _on_portrait_anim_finished(_anim_name: StringName) -> void:
	if _model_root == null or not is_instance_valid(_model_root):
		return
	if not _locked_portrait_anim.is_empty() and _ap != null and is_instance_valid(_ap):
		_ap.play(_locked_portrait_anim)
		return
	_play_random_portrait_anim()
