class_name AnimSoftLoop
extends RefCounted

## Soft-loop for sequences whose first/last pose do not match (e.g. Stand Gold).
## Plays forward then backward instead of LOOP_LINEAR hard wrap.
## Owner passes should_continue: Callable() -> bool; false stops the loop.

const _TAG := "AnimSoftLoop"

var _ap: AnimationPlayer = null
var _anim: String = ""
var _back: bool = false
var _should_continue: Callable = Callable()


func begin(ap: AnimationPlayer, anim_name: String, should_continue: Callable) -> void:
	clear()
	if ap == null or anim_name.is_empty():
		AppLog.warn(AppLog.Layer.PRESENT, _TAG, "begin 忽略：ap 或 anim 为空")
		return
	_ap = ap
	_anim = anim_name
	_back = false
	_should_continue = should_continue
	if ap.speed_scale < 0.0:
		ap.speed_scale = 1.0
	if not ap.animation_finished.is_connected(_on_finished):
		ap.animation_finished.connect(_on_finished)
	AppLog.debug(AppLog.Layer.PRESENT, _TAG, "begin anim=%s" % anim_name)


func clear() -> void:
	if _anim.is_empty() and _ap == null:
		return
	var was := _anim
	if _ap != null and is_instance_valid(_ap):
		if _ap.animation_finished.is_connected(_on_finished):
			_ap.animation_finished.disconnect(_on_finished)
		if _ap.speed_scale < 0.0:
			_ap.speed_scale = 1.0
	_ap = null
	_anim = ""
	_back = false
	_should_continue = Callable()
	if not was.is_empty():
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "clear was=%s" % was)


func is_active() -> bool:
	return not _anim.is_empty() and _ap != null and is_instance_valid(_ap)


func _on_finished(anim_name: StringName) -> void:
	if _anim.is_empty():
		return
	if AnimPlayback.anim_leaf(str(anim_name)).to_lower() != AnimPlayback.anim_leaf(_anim).to_lower():
		return
	if not _should_continue.is_valid() or not bool(_should_continue.call()):
		AppLog.debug(AppLog.Layer.PRESENT, _TAG, "stop anim=%s (should_continue=false)" % _anim)
		clear()
		return
	var ap := _ap
	if ap == null or not is_instance_valid(ap) or not ap.has_animation(_anim):
		AppLog.warn(AppLog.Layer.PRESENT, _TAG, "stop anim=%s：AnimationPlayer 失效" % _anim)
		clear()
		return
	_back = not _back
	AppLog.debug(
		AppLog.Layer.PRESENT,
		_TAG,
		"flip anim=%s dir=%s" % [_anim, ("back" if _back else "fwd")]
	)
	if _back:
		ap.play_backwards(_anim)
	else:
		ap.play(_anim)
