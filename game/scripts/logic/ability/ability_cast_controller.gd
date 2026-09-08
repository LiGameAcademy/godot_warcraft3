class_name AbilityCastController
extends Node

## 技能施法（Logic）：即时 Cast / 超距接近 / 读条 CastDelay / 引导 Channel。

const NODE_NAME := "AbilityCastController"
## 接近落点时相对施法距离的余量（略小于 Rng，避免边界抖动）。
const APPROACH_RANGE_FRAC := 0.94

enum Mode { NONE, APPROACH, CAST_DELAY, CHANNEL }

signal cast_resolved(result: Dictionary, abil_id: String)
signal cast_feedback(text: String)


var _mode: int = Mode.NONE
var _active: bool = false
var _left: float = 0.0
var _cast_total: float = 0.0
var _abil_id: String = ""
var _goal := Vector2.ZERO
var _target: Node3D = null
var _ctx: Dictionary = {}
var _zone: BlizzardZone = null
var _channel_left: float = 0.0
var _approach_range: float = 0.0
var _approach_repath_cd: float = 0.0


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


func is_cast_delaying() -> bool:
	return _active and _mode == Mode.CAST_DELAY


func is_approaching() -> bool:
	return _active and _mode == Mode.APPROACH


func channeling_abil_id() -> String:
	if not _active or _mode == Mode.NONE:
		return ""
	return _abil_id.strip_edges()


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
		# 点地超距：先走接近，到位后再吟唱/引导。
		if (
			str(check.get("reason", "")) == "距离过远"
			and kind == AbilityCatalog.TARGET_POINT
		):
			_abil_id = id
			_goal = goal_wc3
			_ctx = ctx.duplicate(true)
			return _begin_approach(caster, id, goal_wc3, lv)
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
	_stop_caster_for_cast(caster)
	if AbilityCastCatalog.is_channel_ability(id):
		return _begin_channel(caster, id, goal_wc3, lv)
	return _begin_cast_delay(caster, id, lv)


func _begin_approach(
	caster: Node3D, abil_id: String, goal_wc3: Vector2, lv: int
) -> Dictionary:
	var ab := AbilityCatalog.data(abil_id)
	if ab == null:
		return {"ok": false, "reason": "无技能数据"}
	# 接近阶段只清队列，不停导航（马上要走路）。
	var clear_orders: Callable = _ctx.get("clear_caster_orders", Callable()) as Callable
	if clear_orders.is_valid():
		clear_orders.call(caster)
	_mode = Mode.APPROACH
	_active = true
	_approach_range = maxf(ab.cast_range_at(lv) * APPROACH_RANGE_FRAC, 32.0)
	_approach_repath_cd = 0.0
	if not _path_to_cast_range(caster, goal_wc3):
		_active = false
		_mode = Mode.NONE
		return {"ok": false, "reason": "无法接近施法点"}
	set_process(true)
	return {"ok": true, "approaching": true}


func _path_to_cast_range(caster: Node3D, goal_wc3: Vector2) -> bool:
	var from := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	var delta := goal_wc3 - from
	var dist := delta.length()
	var approach_pt := goal_wc3
	if dist > _approach_range + 1.0:
		approach_pt = goal_wc3 - delta.normalized() * _approach_range
	var pq: PathQuery = _ctx.get("path_query") as PathQuery
	if pq != null and pq.is_ready():
		var snap: Dictionary = pq.snap_to_walkable(approach_pt.x, approach_pt.y, 12)
		if bool(snap.get("ok", false)):
			approach_pt = snap["wc3"] as Vector2
	var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav == null:
		return false
	return nav.go_to_wc3(approach_pt)


func _begin_cast_delay(caster: Node3D, abil_id: String, lv: int) -> Dictionary:
	if AbilityCatalog.data(abil_id) == null:
		return {"ok": false, "reason": "无技能数据"}
	var cast_sec := AbilityCastCatalog.cast_time_sec(abil_id, lv)
	_mode = Mode.CAST_DELAY
	_active = true
	_cast_total = cast_sec
	_left = cast_sec
	AbilityCastPresenter.begin(caster, abil_id, cast_sec > 0.05, _goal)
	if cast_sec > 0.05 and abil_id.strip_edges() == MassTeleportAbility.ABIL_MASS_TELEPORT:
		MassTeleportPresenter.begin_cast(caster, _goal, cast_sec, _ctx)
	if cast_sec <= 0.0:
		_resolve_instant()
	else:
		set_process(true)
	return {"ok": true}


func _begin_channel(caster: Node3D, abil_id: String, goal_wc3: Vector2, lv: int) -> Dictionary:
	_mode = Mode.CHANNEL
	_active = true
	_zone = null
	_channel_left = AbilityCastCatalog.channel_duration_sec(abil_id, lv) + 0.75
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
	if _mode == Mode.APPROACH:
		_cancel_approach("接近取消")
		return
	if _mode == Mode.CHANNEL:
		_interrupt_channel("引导取消")
		return
	if _mode == Mode.CAST_DELAY:
		_fail_cast_delay("施法取消")
		return
	_active = false
	_left = 0.0
	_cast_total = 0.0
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
	if _mode == Mode.APPROACH:
		_tick_approach(delta)
		return
	if _mode == Mode.CHANNEL:
		_tick_channel()
		return
	if _mode == Mode.CAST_DELAY:
		_tick_cast_delay(delta)
		return
	set_process(false)


func _tick_cast_delay(delta: float) -> void:
	var caster := get_parent() as Node3D
	if _cast_delay_broken(caster):
		_fail_cast_delay("读条打断")
		return
	_left -= delta
	if _left > 0.0:
		return
	set_process(false)
	_resolve_instant()


func _cast_delay_broken(caster: Node3D) -> bool:
	if caster == null or not is_instance_valid(caster):
		return true
	var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null and nav.is_moving():
		return true
	var check: Callable = _ctx.get("channel_interrupt_check", Callable())
	if check.is_valid() and bool(check.call(caster)):
		return true
	return false


func _fail_cast_delay(reason: String) -> void:
	if not _active or _mode != Mode.CAST_DELAY:
		return
	var caster := get_parent() as Node3D
	var abil_id := _abil_id
	var ctx := _ctx
	_active = false
	_left = 0.0
	_cast_total = 0.0
	_mode = Mode.NONE
	_target = null
	set_process(false)
	if caster != null and is_instance_valid(caster):
		AbilityCastPresenter.end(caster)
		if abil_id.strip_edges() == MassTeleportAbility.ABIL_MASS_TELEPORT:
			MassTeleportPresenter.end_cast(caster, ctx)
	cast_resolved.emit({"ok": false, "reason": reason}, abil_id)


func _tick_approach(delta: float) -> void:
	var caster := get_parent() as Node3D
	if caster == null or not is_instance_valid(caster):
		_cancel_approach("施法者失效")
		return
	if _approach_interrupted(caster):
		_cancel_approach("接近打断")
		return
	var lv := AbilityCatalog.level_for(caster, _abil_id)
	var check := AbilityCastRules.can_cast_point(caster, _abil_id, _goal, lv)
	if bool(check.get("ok", false)):
		var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
		_stop_caster_for_cast(caster)
		_active = false
		_mode = Mode.NONE
		set_process(false)
		var start: Dictionary
		if AbilityCastCatalog.is_channel_ability(_abil_id):
			start = _begin_channel(caster, _abil_id, _goal, lv)
			if bool(start.get("ok", false)):
				var dur := AbilityCastCatalog.channel_duration_sec(_abil_id, lv)
				cast_feedback.emit("引导暴风雪 · %.1fs（移动/停止可打断）" % dur)
		else:
			start = _begin_cast_delay(caster, _abil_id, lv)
			if bool(start.get("ok", false)):
				var csec := AbilityCastCatalog.cast_time_sec(_abil_id, lv)
				if csec > 0.05:
					cast_feedback.emit("施法中 · %.1fs（移动/停止可打断）" % csec)
				else:
					cast_feedback.emit("施法中…")
		if not bool(start.get("ok", false)):
			cast_resolved.emit(start, _abil_id)
		return
	# 仍超距：周期性重寻路（被挤偏时）
	_approach_repath_cd -= delta
	if _approach_repath_cd <= 0.0:
		_path_to_cast_range(caster, _goal)
		_approach_repath_cd = 0.45


func _approach_interrupted(caster: Node3D) -> bool:
	var check: Callable = _ctx.get("channel_interrupt_check", Callable())
	if check.is_valid() and bool(check.call(caster)):
		return true
	return false


func _cancel_approach(reason: String) -> void:
	if not _active or _mode != Mode.APPROACH:
		return
	var caster := get_parent() as Node3D
	var abil_id := _abil_id
	_active = false
	_mode = Mode.NONE
	_approach_range = 0.0
	set_process(false)
	if caster != null and is_instance_valid(caster):
		var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
		if nav != null:
			nav.stop()
	cast_resolved.emit({"ok": false, "reason": reason}, abil_id)


func _tick_channel() -> void:
	var caster := get_parent() as Node3D
	_channel_left -= get_process_delta_time()
	if _channel_broken(caster):
		_interrupt_channel("引导打断")
		return
	# 波次权威在 BlizzardZone；finished 信号收尾。此处只做打断检测 + 超时兜底。
	if _zone != null and is_instance_valid(_zone):
		return
	if _channel_left <= -1.0:
		_finish_channel(false, "引导超时")


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
	_channel_left = 0.0
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
	_cast_total = 0.0
	_target = null
	if caster != null and is_instance_valid(caster):
		AbilityCastPresenter.end(caster)
		if abil_id.strip_edges() == MassTeleportAbility.ABIL_MASS_TELEPORT:
			MassTeleportPresenter.end_cast(caster, ctx)
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


## 停步并清空命令队列，避免残留 MOVE 在引导首帧被当成打断。
func _stop_caster_for_cast(caster: Node3D) -> void:
	var nav := caster.get_node_or_null("UnitNavigator") as UnitNavigator
	if nav != null:
		nav.stop()
	var clear_orders: Callable = _ctx.get("clear_caster_orders", Callable()) as Callable
	if clear_orders.is_valid():
		clear_orders.call(caster)
