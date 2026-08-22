@tool
class_name Wc3ModelScene
extends Node3D

## bake:scn 根脚本：模型场景对外门面（挂点 / 转发动画 / 事件 / PE2 补挂）。
##
## 职责契约与目录迁出计划：docs/design/presentation/WC3_MODEL_SCENE.md
##
## ## 分层（勿越权）
## - **本类** = 场景门面：挂点、肖像机、找到 Wc3AnimPlayer、旧 scn 补 PE2。
## - **Wc3AnimPlayer** = `extends AnimationPlayer`：播放、过渡约定、Animation meta。
## - **UnitVisual / BuildingVisual** = 策略层：玩法/阶段 → 逻辑 Sequence 名。
## - **AnimPlayback / AnimSequenceResolver** = 共享解析实现。
##
## 外界不要 `get_node` 翻子树；走本 API 或直接拿 `wc3_anim_player()`。

const META_SOCKET := "wc3_mdx_attachment"
const _AnimPlayerScript := preload("res://scripts/presentation/wc3_model/wc3_anim_player.gd")

var _ap: AnimationPlayer = null
var _overhead: Node3D = null
var _origin: Node3D = null


func _enter_tree() -> void:
	_apply_stand_bind_rest()


func _ready() -> void:
	_apply_stand_bind_rest()
	_ensure_anim_player()
	_ensure_pe2_attached()
	# PE2 补挂后再剪悬空 :emitting 轨（否则 AP._ready 时粒子尚未就位会误删）
	var ap := wc3_anim_player()
	if ap != null and ap.has_method("prune_unresolved_tracks"):
		ap.call("prune_unresolved_tracks")


## 在 host 自身或子树中找 bake 根（host 常为单位/建筑实体，脚本在 .scn 根上）。
static func find_on(host: Node) -> Wc3ModelScene:
	if host == null:
		return null
	if host is Wc3ModelScene:
		return host as Wc3ModelScene
	for c in host.get_children():
		if c is Wc3ModelScene:
			return c as Wc3ModelScene
	for n in host.find_children("*", "Node3D", true, false):
		if n is Wc3ModelScene:
			return n as Wc3ModelScene
	return null


func _apply_stand_bind_rest() -> void:
	var glb := _resolve_model_glb_path()
	if glb.is_empty():
		return
	MapModelCache.apply_bone_rest_sidecar(self, glb)


## 本模型的 AnimationPlayer（会 ensure Wc3AnimPlayer 脚本）；无则 null。
func animation_player() -> AnimationPlayer:
	return wc3_anim_player()


## 带播放 API 的 AP；旧 .scn 会在此补挂脚本。
func wc3_anim_player() -> AnimationPlayer:
	if _ap != null and is_instance_valid(_ap):
		return _ap
	_ap = _AnimPlayerScript.ensure_on(self) as AnimationPlayer
	return _ap


func _ensure_anim_player() -> void:
	wc3_anim_player()


## 由宿主注入已解析的 AnimationPlayer（会 ensure 为 Wc3AnimPlayer）。
func bind_animation_player(ap: AnimationPlayer) -> void:
	if ap == null:
		_ap = null
		AnimPlayback.bind_animation_player(self, null)
		return
	if ap.get_script() != _AnimPlayerScript:
		ap.set_script(_AnimPlayerScript)
	_ap = ap
	if _ap.has_method("ensure_hooks"):
		_ap.call("ensure_hooks")
	AnimPlayback.bind_animation_player(self, ap)


## 解析逻辑名 → 库内动画路径（转发 AP）。
func resolve_logical(logical_name: String) -> String:
	var ap := wc3_anim_player()
	if ap != null and ap.has_method("resolve_logical"):
		return ap.call("resolve_logical", logical_name) as String
	return AnimPlayback.resolve(self, logical_name, ap)


## 按逻辑 Sequence 名播放（转发 Wc3AnimPlayer）。
func play_logical(
	logical: String,
	blend: float = 0.0,
	cache: Variant = null,
	activity_hint: int = 0,
	fallbacks: Array = []
) -> Dictionary:
	var ap := wc3_anim_player()
	if ap != null and ap.has_method("play_logical"):
		return ap.call("play_logical", logical, blend, cache, activity_hint, fallbacks) as Dictionary
	return AnimPlayback.play_logical(
		self, logical, blend, cache, activity_hint, fallbacks, ap
	)


## Stance×Activity → 逻辑名再播放。
func play_activity(
	activity: int,
	stance: int = 0,
	blend: float = 0.0,
	cache: Variant = null,
	fallbacks: Array = []
) -> Dictionary:
	var ap := wc3_anim_player()
	if ap != null and ap.has_method("play_activity"):
		return ap.call("play_activity", activity, stance, blend, cache, fallbacks) as Dictionary
	var logical := AnimSequenceResolver.sequence_name(activity, stance)
	return play_logical(logical, blend, cache, activity, fallbacks)


## 头顶插座：buff / 飘字 / 血条锚点。没有 OverHead Ref 则 null（调用方再 AABB）。
func overhead_anchor() -> Node3D:
	if _overhead != null and is_instance_valid(_overhead):
		return _overhead
	_overhead = _find_named_socket(["overheadref", "overhead"])
	return _overhead


## 脚底/原点插座（特效 origin、部分落点）。
func origin_anchor() -> Node3D:
	if _origin != null and is_instance_valid(_origin):
		return _origin
	_origin = _find_named_socket(["originref", "origin"])
	return _origin


## MDX 挂点：overhead / origin / sprite first / hand left …
func find_socket(logical: String) -> Node3D:
	var want := _socket_key(logical)
	if want.is_empty():
		return null
	if want == "overhead" or want == "overheadref":
		return overhead_anchor()
	if want == "origin" or want == "originref":
		return origin_anchor()
	return _find_named_socket([want, want + "ref"])


## MDX 动画事件节点（打击帧等）；无则 null。
func anim_events() -> Node:
	return find_child(MdxAnimEvents.NODE_NAME, true, false)


## MDX 肖像机位（Camera01 等），挂在场景根；没有则 null。
func portrait_camera() -> Camera3D:
	for prefer in ["Camera01", "PortraitCamera", "Camera"]:
		var n := find_child(prefer, true, false)
		if n is Camera3D:
			return n as Camera3D
	for c in find_children("*", "Camera3D", true, false):
		if c is Camera3D and bool((c as Camera3D).get_meta("wc3_mdx_camera", false)):
			return c as Camera3D
	return null


func _find_named_socket(keys: PackedStringArray) -> Node3D:
	var want: Dictionary = {}
	for k in keys:
		var kk := _socket_key(str(k))
		if not kk.is_empty():
			want[kk] = true
	if want.is_empty():
		return null
	for n in find_children("*", "Node3D", true, false):
		if not (n is Node3D):
			continue
		var node := n as Node3D
		var key := _socket_key(str(node.name))
		if key.begins_with("attach"):
			key = key.substr("attach".length())
		if want.has(key):
			return node
		for w in want.keys():
			if key == str(w) or key == str(w) + "ref":
				return node
	return null


func _socket_key(s: String) -> String:
	return s.strip_edges().replace(" ", "").replace("-", "").replace("_", "").to_lower()


## 旧 / 残缺 Pe2Root：交给 attach_to（缺发射器会重建），避免 :emitting 轨悬空。
func _ensure_pe2_attached() -> void:
	var glb := _resolve_model_glb_path()
	if glb.is_empty() or not Wc3Pe2Particles.has_emitters(glb):
		return
	Wc3Pe2Particles.attach_to(self, glb)


func _resolve_model_glb_path() -> String:
	var p := str(scene_file_path).replace("\\", "/")
	if p.is_empty():
		return ""
	if p.contains("/visuals/"):
		p = p.replace("/visuals/", "/asset-converted/")
	var stem := p
	if stem.ends_with(".tscn"):
		stem = stem.substr(0, stem.length() - 5)
	elif stem.ends_with(".scn"):
		stem = stem.substr(0, stem.length() - 4)
	elif stem.ends_with(".gltf") or stem.ends_with(".glb"):
		return stem
	var gltf := stem + ".gltf"
	if RuntimeAssets.file_exists(gltf) or ResourceLoader.exists(gltf):
		return gltf
	var glb := stem + ".glb"
	if RuntimeAssets.file_exists(glb) or ResourceLoader.exists(glb):
		return glb
	return gltf
