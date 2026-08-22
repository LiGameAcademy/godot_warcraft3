@tool
class_name Wc3AnimPlayer
extends AnimationPlayer

## 挂在模型 `.scn` 的 AnimationPlayer 上（`extends AnimationPlayer`）。
## 职责：逻辑 Sequence 播放 / 过渡约定 / 读 Animation 元数据 / **同族 rarity 抽签**。
##
## ## 分层
## - **本类**：AP 自身能力（怎么播、轨 meta、族变体加权）。
## - Wc3ModelScene：场景门面（挂点、找本 AP、PE2 宿主节点）。
## - Unit / BuildingVisual：何时播哪类活动（只给逻辑名）。
## - AnimPlayback：名规范化与低层 play（与本文件同目录；无状态工具）。
##
## bake:scn 写入；旧场景由 ensure_on 运行时补挂。
## 动画列表 / 族成员缓存在本实例上；库变更或 [method invalidate_anim_cache] 时失效。

const _TAG := "Wc3AnimPlayer"

const META_LOOPING := "wc3_seq_looping"
const META_RARITY := "wc3_rarity"
const META_MOVE_SPEED := "wc3_move_speed"
const META_MDX_NAME := "wc3_mdx_name"

const _SCRIPT_PATH := "res://scripts/presentation/wc3_model/wc3_anim_player.gd"

## 可走 rarity 族抽取的逻辑根名（小写）。
const _FAMILY_ROOTS := ["attack", "walk", "death", "stand"]

## 库内动画路径缓存（含 Library/ 前缀）。
var _anim_list: PackedStringArray = PackedStringArray()
var _anim_list_ready: bool = false
## 族根 → 成员路径列表。
var _family_cache: Dictionary = {}


func _ready() -> void:
	ensure_hooks()
	_ensure_anim_list_cache()


## 在 host 子树找到 AP；若仍是裸 AnimationPlayer 则 set_script 为本类。
## 返回类型用 AnimationPlayer，避免与门面脚本循环依赖卡住 class_name 注册。
static func ensure_on(host: Node) -> AnimationPlayer:
	if host == null:
		return null
	var ap := AnimPlayback.find_animation_player(host)
	if ap == null:
		return null
	var script := load(_SCRIPT_PATH) as Script
	if ap.get_script() != script:
		ap.set_script(script)
	if ap.has_method("ensure_hooks"):
		ap.call("ensure_hooks")
	# 勿在此 prune：PE2 常由 Wc3ModelScene._ready 稍后补挂，过早剪会丢 Death 等轨
	return ap


## 解析逻辑名 → 库内动画路径（含 Library/ 前缀）。同族经 [method pick_family]。
func resolve_logical(logical_name: String) -> String:
	return AnimPlayback.resolve(_sequence_host(), logical_name, self)


## 按逻辑 Sequence 播放。返回 `{ ok, resolved, played_as, ping_pong }`。
func play_logical(
	logical: String,
	blend: float = 0.0,
	cache: Variant = null,
	activity_hint: int = 0,
	fallbacks: Array = []
) -> Dictionary:
	var out := AnimPlayback.play_logical(
		_sequence_host(), logical, blend, cache, activity_hint, fallbacks, self
	)
	if bool(out.get("ok", false)):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"play_logical ok logical=%s → %s blend=%.2f"
			% [logical, str(out.get("resolved", "")), blend]
		)
	else:
		AppLog.warn(
			AppLog.Layer.PRESENT,
			_TAG,
			"play_logical 失败 logical=%s fallbacks=%s" % [logical, str(fallbacks)]
		)
	return out


## Stance×Activity → 逻辑名再播放。
func play_activity(
	activity: int,
	stance: int = 0,
	blend: float = 0.0,
	cache: Variant = null,
	fallbacks: Array = []
) -> Dictionary:
	var logical := AnimSequenceResolver.sequence_name(activity, stance)
	return play_logical(logical, blend, cache, activity, fallbacks)


## 缓存的动画路径列表（供 AnimPlayback.resolve 复用，避免反复 get_animation_list）。
func animation_names() -> PackedStringArray:
	_ensure_anim_list_cache()
	return _anim_list


## 清空列表与族缓存（bake 改库、热重载、手动补轨后调用）。
func invalidate_anim_cache() -> void:
	var had := _anim_list.size()
	_anim_list = PackedStringArray()
	_anim_list_ready = false
	_family_cache.clear()
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"invalidate_anim_cache cleared_list=%d host=%s" % [had, str(name)]
	)


## Animation 上的 MDX Rarity（缺省 0）。
func seq_rarity(anim_path: String = "") -> float:
	var path := anim_path
	if path.is_empty():
		path = str(current_animation)
	if path.is_empty() or not has_animation(path):
		return 0.0
	var anim := get_animation(path)
	if anim == null:
		return 0.0
	if anim.has_meta(META_RARITY):
		return float(anim.get_meta(META_RARITY))
	return 0.0


## 收集与逻辑根同族的库内路径（如 Attack → Attack / Attack-1 / Attack-2）。
## 排除 Defend / Gold / Lumber / Work 等姿态后缀变体。结果按族根缓存。
func collect_family(logical_name: String) -> PackedStringArray:
	var root := _family_root(logical_name)
	if root.is_empty():
		return PackedStringArray()
	_ensure_anim_list_cache()
	if _family_cache.has(root):
		return _family_cache[root] as PackedStringArray
	var out: PackedStringArray = PackedStringArray()
	for path in _anim_list:
		if _is_family_member(AnimPlayback.anim_leaf(str(path)), root):
			out.append(str(path))
	_family_cache[root] = out
	if AppLog.enabled(AppLog.Level.DEBUG, AppLog.Layer.PRESENT):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"collect_family root=%s n=%d → %s" % [root, out.size(), _family_leaves_preview(out)]
		)
	return out


## 同族按 `weight ∝ 1/(rarity+1)` 加权抽取；单条或空则原样返回。
## `rng` 可注入（自测定种子）；null 时每次 `randomize()`。
func pick_family(logical_name: String, rng: RandomNumberGenerator = null) -> String:
	var members := collect_family(logical_name)
	if members.is_empty():
		if AppLog.enabled(AppLog.Level.DEBUG, AppLog.Layer.PRESENT):
			AppLog.debug(
				AppLog.Layer.PRESENT,
				_TAG,
				"pick_family 空族 logical=%s" % logical_name
			)
		return ""
	if members.size() == 1:
		if AppLog.enabled(AppLog.Level.DEBUG, AppLog.Layer.PRESENT):
			AppLog.debug(
				AppLog.Layer.PRESENT,
				_TAG,
				"pick_family logical=%s sole=%s" % [logical_name, AnimPlayback.anim_leaf(members[0])]
			)
		return members[0]
	var r := rng
	if r == null:
		r = RandomNumberGenerator.new()
		r.randomize()
	var total := 0.0
	var weights: Array[float] = []
	weights.resize(members.size())
	for i in members.size():
		var w := 1.0 / (seq_rarity(members[i]) + 1.0)
		weights[i] = w
		total += w
	if total <= 0.0:
		return members[0]
	var roll := r.randf() * total
	var acc := 0.0
	var picked := members[members.size() - 1]
	for i in members.size():
		acc += weights[i]
		if roll <= acc:
			picked = members[i]
			break
	if AppLog.enabled(AppLog.Level.DEBUG, AppLog.Layer.PRESENT):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"pick_family logical=%s → %s rarity=%.0f roll=%.3f among=%s"
			% [
				logical_name,
				AnimPlayback.anim_leaf(picked),
				seq_rarity(picked),
				roll,
				_family_rarity_preview(members),
			]
		)
	return picked


## 当前（或指定）动画是否带 WC3 looping meta；无 meta 则看 loop_mode。
func is_seq_looping(anim_path: String = "") -> bool:
	var path := anim_path
	if path.is_empty():
		path = str(current_animation)
	if path.is_empty() or not has_animation(path):
		return false
	var anim := get_animation(path)
	if anim == null:
		return false
	if anim.has_meta(META_LOOPING):
		return bool(anim.get_meta(META_LOOPING))
	return anim.loop_mode == Animation.LOOP_LINEAR


## 读 Animation 上的 MDX 名（旁路写入）；无则退回叶名。
func seq_mdx_name(anim_path: String = "") -> String:
	var path := anim_path
	if path.is_empty():
		path = str(current_animation)
	if path.is_empty() or not has_animation(path):
		return ""
	var anim := get_animation(path)
	if anim != null and anim.has_meta(META_MDX_NAME):
		return str(anim.get_meta(META_MDX_NAME))
	return AnimPlayback.anim_leaf(path)


## PE2 / geoset 作用的宿主：优先带挂点门面的祖先，否则 AP 父节点。
func _sequence_host() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("overhead_anchor") and n.has_method("wc3_anim_player"):
			return n
		n = n.get_parent()
	if get_parent() != null:
		return get_parent()
	return self


func ensure_hooks() -> void:
	if not animation_started.is_connected(_on_animation_started):
		animation_started.connect(_on_animation_started)
	if has_signal("current_animation_changed"):
		if not current_animation_changed.is_connected(_on_current_animation_changed):
			current_animation_changed.connect(_on_current_animation_changed)
	if has_signal("animation_libraries_updated"):
		if not animation_libraries_updated.is_connected(_on_animation_libraries_updated):
			animation_libraries_updated.connect(_on_animation_libraries_updated)


## 删掉指向不存在节点的轨（旧 bake 的 Pe2 :emitting 等），避免 AnimationMixer 每帧警告。
func prune_unresolved_tracks() -> int:
	var anim_root: Node = get_node_or_null(root_node)
	if anim_root == null:
		anim_root = get_parent()
	if anim_root == null:
		return 0
	var removed := 0
	for anim_name in get_animation_list():
		var anim := get_animation(anim_name)
		if anim == null:
			continue
		for i in range(anim.get_track_count() - 1, -1, -1):
			var full := anim.track_get_path(i)
			var node_path := _track_node_path(full)
			if str(node_path).is_empty() or str(node_path) == ".":
				continue
			if anim_root.get_node_or_null(node_path) != null:
				continue
			anim.remove_track(i)
			removed += 1
	if removed > 0 and AppLog.enabled(AppLog.Level.DEBUG, AppLog.Layer.PRESENT):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"prune_unresolved_tracks removed=%d host=%s" % [removed, str(name)]
		)
	return removed


func _track_node_path(track_path: NodePath) -> NodePath:
	var s := str(track_path)
	var colon := s.find(":")
	if colon >= 0:
		s = s.substr(0, colon)
	return NodePath(s)


func _on_animation_started(anim_name: StringName) -> void:
	Wc3Pe2Particles.apply_sequence(_sequence_host(), str(anim_name))


func _on_current_animation_changed(anim_name: String) -> void:
	Wc3Pe2Particles.apply_sequence(_sequence_host(), anim_name)


func _on_animation_libraries_updated() -> void:
	AppLog.debug(AppLog.Layer.PRESENT, _TAG, "animation_libraries_updated → invalidate")
	invalidate_anim_cache()


func _ensure_anim_list_cache() -> void:
	if _anim_list_ready:
		return
	_anim_list = get_animation_list()
	_anim_list_ready = true
	_family_cache.clear()
	if AppLog.enabled(AppLog.Level.DEBUG, AppLog.Layer.PRESENT):
		AppLog.debug(
			AppLog.Layer.PRESENT,
			_TAG,
			"anim_list cached n=%d host=%s" % [_anim_list.size(), str(name)]
		)


func _family_root(logical_name: String) -> String:
	var s := logical_name.strip_edges().to_lower().replace("_", " ")
	if s.is_empty():
		return ""
	var token := s.split(" ", false)[0]
	# Attack-1 → attack
	if token.contains("-"):
		token = token.split("-", false)[0]
	if token in _FAMILY_ROOTS:
		return token
	return ""


func _is_family_member(leaf: String, root: String) -> bool:
	var leaf_u := leaf.to_lower().replace(" ", "_")
	if not leaf_u.begins_with(root):
		return false
	if (
		leaf_u.contains("defend")
		or leaf_u.contains("gold")
		or leaf_u.contains("lumber")
		or leaf_u.contains("work")
		or leaf_u.contains("upgrade")
		or leaf_u.contains("ready")
		or leaf_u.contains("channel")
		or leaf_u.contains("hit")
		or leaf_u.contains("victory")
		or leaf_u.contains("portrait")
		or leaf_u.contains("decay")
		or leaf_u.contains("spell")
		or leaf_u.contains("birth")
	):
		return false
	return true


func _family_leaves_preview(members: PackedStringArray, max_n: int = 8) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var n := mini(members.size(), max_n)
	for i in n:
		parts.append(AnimPlayback.anim_leaf(str(members[i])))
	if members.size() > max_n:
		parts.append("…+%d" % (members.size() - max_n))
	return ", ".join(parts)


func _family_rarity_preview(members: PackedStringArray, max_n: int = 6) -> String:
	var parts: PackedStringArray = PackedStringArray()
	var n := mini(members.size(), max_n)
	for i in n:
		var p := str(members[i])
		parts.append("%s(r=%.0f)" % [AnimPlayback.anim_leaf(p), seq_rarity(p)])
	if members.size() > max_n:
		parts.append("…")
	return ", ".join(parts)
