class_name AbilityCastController
extends Node

## 技能施法（Logic）：即时 Cast / 引导 Channel（暴风雪等）。

const NODE_NAME := "AbilityCastController"

enum Mode { NONE, CAST_DELAY, CHANNEL }

signal cast_resolved(result: Dictionary, abil_id: String)


var _mode: int = Mode.NONE
var _active: bool = false
var _left: float = 0.0
var _abil_id: String = ""
var _goal := Vector2.ZERO
var _target: Node3D = null
var _ctx: Dictionary = {}
var _zone: BlizzardZone = null


static func of(unit: Node3D) -> AbilityCastController:
	if unit == null:
		return null
	return unit.get_node_or_null(NODE_NAME) as AbilityCastController


static func ensure_on(unit: Node3D) -> AbilityCastController:
	if unit == null:
		return null
	var existing := of(unit)
	if existing != null:
		return existing
	var c := AbilityCastController.new()
	c.name = NODE_NAME
	unit.add_child(c)
	return c


func is_channeling() -> bool:
	return _active and _mode == Mode.CHANNEL


## 开始施法；引导技 cast_resolved 在引导结束/打断后发出。
func begin_cast(abil_id: String, goal_wc3: Vector2, ctx: Dictionary) -> Dictionary:
	var out := {"ok": false, "reason": ""}
	if _active:
		out["reason"] = "已在施法"
		return out
	var caster := get_parent() as Node3D
	if caster == null or not is_instance_valid(caster):
		out["reason"] = "无施法者"
		return out
	var id := abil_id.strip_edges()
	if id.is_empty():
		out["reason"] = "无效技能"
		return out
	var lv := AbilityCatalog.level_for(caster, id)
	_target = ctx.get("target") as Node3D if ctx.get("target") is Node3D else null
	var kind := AbilityCatalog.target_kind(id)
	var check: Dictionary
	match kind:
		AbilityCatalog.TARGET_SELF:
			check = AbilityCastRules.can_cast_self(caster, id, lv)
		AbilityCatalog.TARGET_UNIT, AbilityCatalog.TARGET_ALLY:
			check = AbilityCastRules.can_cast_unit(caster, id, _target, lv)
		_:
			check = AbilityCastRules.can_cast_point(caster, id, goal_wc3, lv)
	if not bool(check.get("ok", false)):
		return check
	_abil_id = id
	if kind == AbilityCatalog.TARGET_SELF:
		_goal = Wc3Coords.godot_to_wc3_xy(caster.global_position)
	elif kind == AbilityCatalog.TARGET_UNIT and _target != null:
		_goal = Wc3Coords.godot_to_wc3_xy(_target.global_position)
	elif kind == AbilityCatalog.TARGET_ALLY and _target != null:
		_goal = Wc3Coords.godot_to_wc3_xy(_target.global_position)
	else:
		_goal = goal_wc3
	_ctx = ctx.duplicate(true)
	_stop_caster_move(caster)
	if AbilityCastCatalog.is_channel_ability(id):
		return _begin_channel(caster, id, goal_wc3, lv)
	return _begin_cast_delay(caster, id, lv)


func _begin_cast_delay(caster: Node3D, abil_id: String, lv: int) -> Dictionary:
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	var cast_sec := maxf(ab.cast_time_at(lv), 0.0)
	_mode = Mode.CAST_DELAY
	_active = true
	_left = cast_sec
	AbilityCastPresenter.begin(caster, abil_id, cast_sec > 0.05, _goal)
	if cast_sec <= 0.0:
		_resolve_instant()
	else:
		set_process(true)
	return {"ok": true}


func _begin_channel(caster: Node3D, abil_id: String, goal_wc3: Vector2, _lv: int) -> Dictionary:
	_mode = Mode.CHANNEL
	_active = true
	_zone = null
	AbilityCastPresenter.begin(caster, abil_id, true, goal_wc3)
	var start := BlizzardAbility.begin_channel(caster, abil_id, goal_wc3, _ctx)
	if not bool(start.get("ok", false)):
		_reset_channel_state(caster)
		return start
	_zone = start.get("zone") as BlizzardZone
	if _zone != null:
		_zone.finished.connect(_on_zone_finished, CONNECT_ONE_SHOT)
	set_process(true)
	return {"ok": true}


func cancel_cast() -> void:
	if not _active:
		return
	if _mode == Mode.CHANNEL:
		_interrupt_channel("引导取消")
		return
	_active = false
	_left = 0.0
	_mode = Mode.NONE
	_target = null
	set_process(false)
	var caster := get_parent() as Node3D
	if caster != null and is_instance_valid(caster):
		AbilityCastPresenter.end(caster)


func _process(delta: float) -> void:
	if not _active:
		set_process(false)
		return
	if _mode == Mode.CHANNEL:
		_tick_channel()
		return
	_left -= delta
	if _left > 0.0:
		return
	set_process(false)
	_resolve_instant()


func _tick_channel() -> void:
	var caster := get_parent() as Node3D
	if _channel_broken(caster):
		_interrupt_channel("引导打断")
		return
	if _zone == null or not is_instance_valid(_zone):
		_finish_channel(false)


func _channel_broken(caster: Node3D) -> bool:
	if caster == null or not is_instance_valid(caster):
		return true
	var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null and nav.is_moving():
		return true
	var check: Callable = _ctx.get("channel_interrupt_check", Callable())
	if check.is_valid() and bool(check.call(caster)):
		return true
	return false


func _on_zone_finished(success: bool) -> void:
	_zone = null
	_finish_channel(success)


func _interrupt_channel(reason: String) -> void:
	if _zone != null and is_instance_valid(_zone):
		_zone.cancel()
	_zone = null
	_finish_channel(false, reason)


func _finish_channel(success: bool, reason: String = "") -> void:
	if not _active:
		return
	var caster := get_parent() as Node3D
	var abil_id := _abil_id
	var goal := _goal
	var ctx := _ctx
	_reset_channel_state(caster)
	var result := {"ok": false, "reason": reason if not reason.is_empty() else "引导打断"}
	if success and caster != null and is_instance_valid(caster):
		var lv := AbilityCatalog.level_for(caster, abil_id)
		var check := AbilityCastRules.can_cast_point(caster, abil_id, goal, lv)
		if bool(check.get("ok", false)):
			AbilityCastRules.commit_cost(caster, abil_id, lv)
			result = {"ok": true, "reason": "", "unit": null}
		else:
			result = check
	cast_resolved.emit(result, abil_id)


func _reset_channel_state(caster: Node3D) -> void:
	_active = false
	_mode = Mode.NONE
	_left = 0.0
	set_process(false)
	if caster != null and is_instance_valid(caster):
		AbilityCastPresenter.end(caster)


func _resolve_instant() -> void:
	var caster := get_parent() as Node3D
	var abil_id := _abil_id
	var goal := _goal
	var target := _target
	var ctx := _ctx
	_active = false
	_mode = Mode.NONE
	_left = 0.0
	_target = null
	if caster != null and is_instance_valid(caster):
		AbilityCastPresenter.end(caster)
	var result := {"ok": false, "reason": "施法中断"}
	if caster != null and is_instance_valid(caster):
		var lv := AbilityCatalog.level_for(caster, abil_id)
		var kind := AbilityCatalog.target_kind(abil_id)
		var check: Dictionary
		match kind:
			AbilityCatalog.TARGET_SELF:
				check = AbilityCastRules.can_cast_self(caster, abil_id, lv)
			AbilityCatalog.TARGET_UNIT, AbilityCatalog.TARGET_ALLY:
				check = AbilityCastRules.can_cast_unit(caster, abil_id, target, lv)
			_:
				check = AbilityCastRules.can_cast_point(caster, abil_id, goal, lv)
		if bool(check.get("ok", false)):
			result = AbilityExecutor.try_cast(caster, abil_id, goal, target, ctx)
		else:
			result = check
	cast_resolved.emit(result, abil_id)


static func _stop_caster_move(caster: Node3D) -> void:
	var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
