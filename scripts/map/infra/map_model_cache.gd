class_name MapModelCache
extends RefCounted

## 运行时 GLB 场景 / Mesh 缓存，供单位与装饰层共用。

var _scene_cache: Dictionary = {}
## path → bool（是否含 AnimationPlayer 动画）
var _anim_flags: Dictionary = {}
## path → Array[{ "mesh": Mesh, "material": Material }]
var _parts_cache: Dictionary = {}


func instance_glb(path: String) -> Node3D:
	var proto := _ensure_scene(path)
	if proto == null:
		return null
	# PackedScene.instantiate 比 duplicate 更稳（AnimationPlayer / 库引用）
	var packed := PackedScene.new()
	if packed.pack(proto) == OK:
		var inst := packed.instantiate()
		if inst is Node3D:
			return inst as Node3D
		if inst != null:
			inst.free()
	return proto.duplicate() as Node3D


## GLB 是否含「会动」的循环骨骼动画（空 Stand / 仅 GeosetAnim 不算）
func glb_has_animation(path: String) -> bool:
	if path.is_empty():
		return false
	_ensure_scene(path)
	return bool(_anim_flags.get(path, false))


## 优先播 Stand（及 Stand -1 等变体），否则第一条；循环。
## random_phase：多实例错开相位，避免蝙蝠/鸟群齐刷刷扑翅。
func autoplay_stand(root: Node, random_phase: bool = true) -> bool:
	if root == null:
		return false
	var ap := _find_animation_player(root)
	if ap == null:
		return false
	var chosen := _pick_stand_name(ap)
	if chosen.is_empty():
		var names := ap.get_animation_list()
		if names.is_empty():
			return false
		chosen = str(names[0])
	if not play_animation(root, chosen, true):
		return false
	if random_phase:
		var len: float = ap.current_animation_length
		if len > 0.05:
			ap.seek(randf() * len, true)
	return true


## 模型上全部动画名（含 Death / Birth 等；不限骨骼 Stand）。
func list_animations(root: Node) -> PackedStringArray:
	var ap := _find_animation_player(root)
	if ap == null:
		return PackedStringArray()
	return ap.get_animation_list()


## 播放指定动画；loop=true 时强制线性循环（预览用）。
func play_animation(root: Node, anim_name: String, loop: bool = true) -> bool:
	if root == null or anim_name.is_empty():
		return false
	var ap := _find_animation_player(root)
	if ap == null or not ap.has_animation(anim_name):
		return false
	ap.active = true
	var anim := ap.get_animation(anim_name)
	if anim != null and loop:
		anim.loop_mode = Animation.LOOP_LINEAR
	ap.play(anim_name)
	return true


## GLB / 实例是否含可见网格（空壳 PE2-only GLB → false）。
func glb_has_mesh(path: String) -> bool:
	if path.is_empty():
		return false
	var parts := mesh_parts_from_glb(path)
	return not parts.is_empty()


func node_has_mesh(root: Node) -> bool:
	return MapPlaceholders.node_has_mesh(root)


## 兼容旧调用：取第一个可见网格
func mesh_from_glb(path: String) -> Mesh:
	var parts := mesh_parts_from_glb(path)
	if parts.is_empty():
		return null
	return parts[0]["mesh"] as Mesh


## 所有 Geoset 网格（含材质），供 MultiMesh 分片实例化
func mesh_parts_from_glb(path: String) -> Array:
	if path.is_empty():
		return []
	if _parts_cache.has(path):
		return _parts_cache[path]
	# 带动画模型不应抽静态网格；调用方应先 glb_has_animation
	var root := instance_glb(path)
	if root == null:
		return []
	var parts: Array = []
	_collect_mesh_parts(root, parts)
	root.free()
	_parts_cache[path] = parts
	return parts


func _ensure_scene(path: String) -> Node3D:
	if path.is_empty():
		return null
	if _scene_cache.has(path):
		return _scene_cache[path] as Node3D
	var loaded := RuntimeAssets.load_gltf_scene(path)
	if loaded == null:
		return null
	var has_anim := _scene_has_skeletal_stand(loaded)
	_anim_flags[path] = has_anim
	# 静物：GeosetAnim 在 rest 可能 scale=0，强制可见
	# 动画物：交给 Stand 轨驱动显隐，勿强行 reveal
	if not has_anim:
		_reveal_hidden_geosets(loaded)
	_scene_cache[path] = loaded
	return loaded


## 真正会动的 Stand：pos/rot 轨足够多（空 Stand、树的微动轨排除）
const _MIN_SKELETAL_TRACKS := 6


func _scene_has_skeletal_stand(n: Node) -> bool:
	var ap := _find_animation_player(n)
	if ap == null:
		return false
	var stand := _pick_stand_name(ap)
	if stand.is_empty():
		return false
	return _is_skeletal_motion(ap.get_animation(stand))


func _pick_stand_name(ap: AnimationPlayer) -> String:
	var names := ap.get_animation_list()
	if names.is_empty():
		return ""
	# 精确 Stand / stand
	for n in names:
		var s := str(n)
		if s == "Stand" or s == "stand":
			return s
	for n in names:
		var s2 := str(n)
		if s2.begins_with("Stand ") or s2.begins_with("stand "):
			return s2
	return ""


func _is_skeletal_motion(anim: Animation) -> bool:
	if anim == null or anim.length < 0.05:
		return false
	var move_tracks := 0
	for ti in range(anim.get_track_count()):
		var tt := anim.track_get_type(ti)
		if tt == Animation.TYPE_POSITION_3D or tt == Animation.TYPE_ROTATION_3D:
			move_tracks += 1
			if move_tracks >= _MIN_SKELETAL_TRACKS:
				return true
	return false


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null


func _reveal_hidden_geosets(n: Node) -> void:
	if n is Node3D:
		var n3 := n as Node3D
		if n3.scale.length_squared() < 1e-8:
			n3.scale = Vector3.ONE
	for c in n.get_children():
		_reveal_hidden_geosets(c)


func _collect_mesh_parts(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			out.append({
				"mesh": mi.mesh,
				"material": mi.get_active_material(0),
			})
	for c in n.get_children():
		_collect_mesh_parts(c, out)
