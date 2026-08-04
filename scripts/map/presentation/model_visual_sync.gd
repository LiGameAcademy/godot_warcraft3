@tool
extends Node3D
## 模型视觉封装根脚本：AnimationPlayer 切换 Sequence 时同步 PE2 emitting。
## 挂在 assets/visuals/**/*.tscn 根上；无游戏逻辑。
## @tool：编辑器里播 Stand_Work / Birth 时也能看到粒子（否则一直 emitting=false）。

const _Pe2 := preload("res://scripts/map/presentation/effects/wc3_pe2_particles.gd")


func _ready() -> void:
	_hook_animation_player()


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
