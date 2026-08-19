@tool
class_name Wc3ModelScene
extends Node3D
## bake:scn 根脚本：模型场景对外 API（挂点 / 动画 / 事件）。
## 表现层；无单位血量、无战斗。外界不要 get_node 翻子树。
## @tool：编辑器播 Sequence 时也能走同一套查询。

const META_SOCKET := "wc3_mdx_attachment"


var _ap: AnimationPlayer = null
var _overhead: Node3D = null
var _origin: Node3D = null


func _enter_tree() -> void:
	_apply_stand_bind_rest()


func _ready() -> void:
	_apply_stand_bind_rest()
	_hook_animation_player()
	_ensure_pe2_attached()


func _apply_stand_bind_rest() -> void:
	var glb := _resolve_model_glb_path()
	if glb.is_empty():
		return
	MapModelCache.apply_bone_rest_sidecar(self, glb)


func animation_player() -> AnimationPlayer:
	if _ap != null and is_instance_valid(_ap):
		return _ap
	_ap = AnimPlayback.find_animation_player(self)
	return _ap


## 头顶插座：buff / 飘字 / 血条锚点。没有 OverHead Ref 则 null（调用方再 AABB）。
func overhead_anchor() -> Node3D:
	if _overhead != null and is_instance_valid(_overhead):
		return _overhead
	_overhead = _find_named_socket(["overheadref", "overhead"])
	return _overhead


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


func _hook_animation_player() -> void:
	var ap := animation_player()
	if ap == null:
		return
	if not ap.animation_started.is_connected(_on_animation_started):
		ap.animation_started.connect(_on_animation_started)
	if ap.has_signal("current_animation_changed"):
		if not ap.current_animation_changed.is_connected(_on_current_animation_changed):
			ap.current_animation_changed.connect(_on_current_animation_changed)


func _on_animation_started(anim_name: StringName) -> void:
	Wc3Pe2Particles.apply_sequence(self, str(anim_name))


func _on_current_animation_changed(anim_name: String) -> void:
	Wc3Pe2Particles.apply_sequence(self, anim_name)


## 旧 .scn 无 Pe2Root 时从 pe2.json 补挂。
func _ensure_pe2_attached() -> void:
	if find_child(Wc3Pe2Particles.PE2_ROOT_NAME, true, false) != null:
		return
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
