class_name CombatAttackPresentation
extends RefCounted
## 收招由动画完成通知结束；此通知不结算伤害，也不改变攻击冷却。
var _unit: Unit = null
var _player: AnimationPlayer = null
var _clip: StringName = &""

func begin(body: Node3D) -> void:
	cancel()
	_unit = Unit.of(body)
	if _unit == null or _unit.is_dying():
		return
	_unit.set_combat_attack(true)
	_player = AnimPlayback.find_animation_player(_unit.model_node())
	if _player == null:
		return
	_clip = StringName(_player.current_animation)
	if not _clip.is_empty():
		_player.animation_finished.connect(_finished)

func cancel() -> void:
	_disconnect()
	if is_instance_valid(_unit):
		_unit.set_combat_attack(false)
	_unit = null
	_player = null
	_clip = &""

func _finished(clip: StringName) -> void:
	if clip != _clip:
		return
	# 施法、移动、死亡可以打断攻击；旧通知不能盖掉新表现。
	var still_attacking: bool = is_instance_valid(_player) and _player.assigned_animation == _clip
	_disconnect()
	if still_attacking and is_instance_valid(_unit) and not _unit.is_dying():
		_unit.set_combat_attack(false)
	_unit = null
	_player = null
	_clip = &""

func _disconnect() -> void:
	if is_instance_valid(_player) and _player.animation_finished.is_connected(_finished):
		_player.animation_finished.disconnect(_finished)
