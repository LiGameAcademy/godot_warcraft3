@tool
extends Node3D
## 模型视觉封装根脚本：AnimationPlayer 切换 Sequence 时同步 PE2 emitting。
## 挂在 assets/visuals/**/*.tscn 根上；无游戏逻辑。
## @tool：编辑器里播 Stand_Work / Birth 时也能看到粒子（否则一直 emitting=false）。
##
## visuals 故意不 ExtResource pe2.tscn（贴图在 .gdignore 会刷屏）；
## 编辑器/运行时都从旁路 pe2.json 动态挂 Pe2Root（与 MapModelCache 配方一致）。

const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")


func _ready() -> void:
	_ensure_pe2_attached()
	_hook_animation_player()


## 无 Pe2Root 时从同 stem 的 pe2.json 挂上（编辑器打开 visuals 才能见门光）。
func _ensure_pe2_attached() -> void:
	if find_child(_Pe2.PE2_ROOT_NAME, true, false) != null:
		return
	var glb := _resolve_model_glb_path()
	if glb.is_empty():
		return
	if not _Pe2.has_emitters(glb):
		return
	_Pe2.attach_to(self, glb)


## 根 scene_file_path：.scn / visuals.tscn → asset-converted 同 stem .gltf。
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
	elif stem.ends_with(".gltf"):
		return stem
	elif stem.ends_with(".glb"):
		return stem
	var gltf := stem + ".gltf"
	if RuntimeAssets.file_exists(gltf) or ResourceLoader.exists(gltf):
		return gltf
	var glb := stem + ".glb"
	if RuntimeAssets.file_exists(glb) or ResourceLoader.exists(glb):
		return glb
	return gltf


func _hook_animation_player() -> void:
	var ap := _find_animation_player(self)
	if ap == null:
		return
	if not ap.animation_started.is_connected(_on_animation_started):
		ap.animation_started.connect(_on_animation_started)
	# 编辑器下拉切换动画时也会改 current_animation（不一定 fire started）
	if ap.has_signal("current_animation_changed"):
		if not ap.current_animation_changed.is_connected(_on_current_animation_changed):
			ap.current_animation_changed.connect(_on_current_animation_changed)
	_sync_from_ap(ap)


func _on_animation_started(anim_name: StringName) -> void:
	_Pe2.apply_sequence(self, str(anim_name))


func _on_current_animation_changed(anim_name: String) -> void:
	_Pe2.apply_sequence(self, anim_name)


func _sync_from_ap(ap: AnimationPlayer) -> void:
	var cur := str(ap.current_animation)
	# 未播时按 Stand 关闸，避免 visuals 内嵌 Pe2 在空闲态误喷 Death/着火粒子
	if cur.is_empty():
		_Pe2.apply_sequence(self, "Stand")
		return
	_Pe2.apply_sequence(self, cur)


func _find_animation_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n as AnimationPlayer
	for c in n.get_children():
		var found := _find_animation_player(c)
		if found:
			return found
	return null
