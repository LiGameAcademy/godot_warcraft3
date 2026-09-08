class_name AbilityTargetingService
extends RefCounted

## 技能瞄准态机（Orchestration）：begin / issue / cancel。

var _active: bool = false
var _pending_abil_id: String = ""

var _get_primary: Callable = Callable()
var _pick_at: Callable = Callable()
var _ground_at_screen: Callable = Callable()
var _ensure_runtime: Callable = Callable()
var _build_ctx: Callable = Callable()
var _on_cast_resolved: Callable = Callable()
var _clear_rival_targeting: Callable = Callable()
var _on_targeting_changed: Callable = Callable()
var _hud: AbilityHudFeedback = null
var _refresh_command_card: Callable = Callable()
var _on_blizzard_preview: Callable = Callable()


func configure(deps: Dictionary) -> void:
	_get_primary = deps.get("get_primary", Callable()) as Callable
	_pick_at = deps.get("pick_at", Callable()) as Callable
	_ground_at_screen = deps.get("ground_at_screen", Callable()) as Callable
	_ensure_runtime = deps.get("ensure_runtime", Callable()) as Callable
	_build_ctx = deps.get("build_ctx", Callable()) as Callable
	_on_cast_resolved = deps.get("on_cast_resolved", Callable()) as Callable
	_clear_rival_targeting = deps.get("clear_rival_targeting", Callable()) as Callable
	_on_targeting_changed = deps.get("on_targeting_changed", Callable()) as Callable
	_hud = deps.get("hud") as AbilityHudFeedback
	_refresh_command_card = deps.get("refresh_command_card", Callable()) as Callable
	_on_blizzard_preview = deps.get("on_blizzard_preview", Callable()) as Callable


func is_targeting() -> bool:
	return _active


func pending_abil_id() -> String:
	return _pending_abil_id


func cancel() -> void:
	_set_targeting(false)


func begin_targeting(abil_id: String, source: int) -> void:
	var id := abil_id.strip_edges()
	if id.is_empty() or not AbilityCatalog.is_supported(id):
		_status("技能未实现：%s" % id)
		return
	var primary := _primary()
	if primary == null:
		_status("施法：无选中单位")
		return
	if _ensure_runtime.is_valid():
		_ensure_runtime.call(primary)
	var lv := AbilityCatalog.level_for(primary, id)
	if lv <= 0:
		_status("技能等级不足")
		return
	if not AbilityCooldowns.is_ready(primary, id):
		_status("冷却中")
		return
	var ab := AbilityCatalog.data(id)
	if ab != null and UnitMana.has_mana(primary):
		if not UnitMana.can_spend(primary, ab.cost_at(lv)):
			_status("魔法不足")
			return
	if _clear_rival_targeting.is_valid():
		_clear_rival_targeting.call()
	_set_targeting(true, id)
	var aim_hint := "左键点地"
	var tk := AbilityCatalog.target_kind(id)
	if tk == AbilityCatalog.TARGET_UNIT:
		aim_hint = "左键点敌军"
	elif tk == AbilityCatalog.TARGET_ALLY:
		aim_hint = "左键点友军"
	if _hud != null:
		_hud.on_targeting_begin(id, source, aim_hint)
	if id == "AHbz" and _on_blizzard_preview.is_valid():
		_on_blizzard_preview.call()


func issue_self(abil_id: String, _source: int) -> bool:
	var id := abil_id.strip_edges()
	if id.is_empty() or not AbilityCatalog.is_supported(id):
		_status("技能未实现：%s" % id)
		return false
	var caster := _primary()
	if caster == null:
		_status("施法：无选中单位")
		return false
	if _ensure_runtime.is_valid():
		_ensure_runtime.call(caster)
	var lv := AbilityCatalog.level_for(caster, id)
	var check := AbilityCastRules.can_cast_self(caster, id, lv)
	if not bool(check.get("ok", false)):
		_status(str(check.get("reason", "无法施法")))
		return false
	var goal := Wc3Coords.godot_to_wc3_xy(caster.global_position)
	return _begin_cast(caster, id, goal, {})


func issue_at_unit_screen(screen_pos: Vector2, _source: int) -> bool:
	var abil_id := _pending_abil_id.strip_edges()
	if abil_id.is_empty():
		return false
	var caster := _primary()
	if caster == null:
		return false
	if _ensure_runtime.is_valid():
		_ensure_runtime.call(caster)
	var target: Node3D = null
	if _pick_at.is_valid():
		target = _pick_at.call(screen_pos) as Node3D
	if target == null or not is_instance_valid(target):
		_status("施法：未点到目标")
		return false
	var tk := AbilityCatalog.target_kind(abil_id)
	if tk == AbilityCatalog.TARGET_ALLY or tk == AbilityCatalog.TARGET_UNIT:
		if not CombatQuery.is_valid_ability_unit_target(caster, target, abil_id):
			var msg := "施法：无效友军目标" if tk == AbilityCatalog.TARGET_ALLY else "施法：无效敌军目标"
			_status(msg)
			return false
	else:
		_status("施法：无效技能目标类型")
		return false
	var goal := Wc3Coords.godot_to_wc3_xy(target.global_position)
	return _begin_cast(caster, abil_id, goal, {"target": target})


func issue_at_screen(screen_pos: Vector2, _source: int) -> bool:
	var abil_id := _pending_abil_id.strip_edges()
	if abil_id.is_empty():
		return false
	var caster := _primary()
	if caster == null:
		return false
	var hit := Vector3.INF
	if _ground_at_screen.is_valid():
		hit = _ground_at_screen.call(screen_pos) as Vector3
	if hit == Vector3.INF:
		_status("施法：未点到地面")
		return true
	var inv := 1.0 / Wc3Coords.WORLD_SCALE
	var goal := Vector2(hit.x * inv, -hit.z * inv)
	return _begin_cast(caster, abil_id, goal, {})


func _begin_cast(caster: Node3D, abil_id: String, goal: Vector2, extra_ctx: Dictionary) -> bool:
	var acc := AbilityCastController.ensure_on(caster)
	if _on_cast_resolved.is_valid() and not acc.cast_resolved.is_connected(_on_cast_resolved):
		acc.cast_resolved.connect(_on_cast_resolved)
	if not acc.cast_feedback.is_connected(_on_cast_feedback):
		acc.cast_feedback.connect(_on_cast_feedback)
	var ctx: Dictionary = {}
	if _build_ctx.is_valid():
		ctx = _build_ctx.call() as Dictionary
	for k in extra_ctx.keys():
		ctx[k] = extra_ctx[k]
	var start := acc.begin_cast(abil_id, goal, ctx)
	if _hud != null:
		_hud.on_cast_start(abil_id, caster, start)
	if _refresh_command_card.is_valid():
		_refresh_command_card.call()
	return bool(start.get("ok", false))


func _on_cast_feedback(text: String) -> void:
	if _hud != null:
		_hud.set_status(text)


func _primary() -> Node3D:
	if not _get_primary.is_valid():
		return null
	return _get_primary.call() as Node3D


func _set_targeting(active: bool, abil_id: String = "") -> void:
	_active = active
	_pending_abil_id = abil_id.strip_edges() if active else ""
	if _on_targeting_changed.is_valid():
		_on_targeting_changed.call(active, _pending_abil_id)


func _status(text: String) -> void:
	if _hud != null:
		_hud.set_status(text)
