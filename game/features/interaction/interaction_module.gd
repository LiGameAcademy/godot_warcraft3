class_name InteractionModule
extends Node

## 对局交互协调：互斥瞄准状态机 + 光标同步 + 选择取消瞄准。
## 命令卡内容生成仍在总管；本模块只编排「瞄准 ↔ 光标 ↔ 选中」。

enum Aim {
	NONE,
	MOVE,
	ATTACK,
	PATROL,
	HARVEST,
	RALLY,
	ABILITY,
	BUILD,
}

signal aiming_changed(aim: int, payload: Dictionary)

var _aim: int = Aim.NONE
var _payload: Dictionary = {}
## 防止 cancel_aim ↔ cancel_ability/build 回调互相重入。
var _mutating: bool = false

var _cursor: Wc3GameCursor
var _unit_selector: Node
var _set_status: Callable
var _cancel_ability: Callable
var _cancel_build: Callable
var _ability_target_kind: Callable
var _is_ability_targeting: Callable
var _is_build_targeting: Callable


func configure(deps: Dictionary) -> void:
	_cursor = deps.get("cursor") as Wc3GameCursor
	_unit_selector = deps.get("unit_selector") as Node
	_set_status = deps.get("set_status", Callable()) as Callable
	_cancel_ability = deps.get("cancel_ability", Callable()) as Callable
	_cancel_build = deps.get("cancel_build", Callable()) as Callable
	_ability_target_kind = deps.get("ability_target_kind", Callable()) as Callable
	_is_ability_targeting = deps.get("is_ability_targeting", Callable()) as Callable
	_is_build_targeting = deps.get("is_build_targeting", Callable()) as Callable


func shutdown() -> void:
	_aim = Aim.NONE
	_payload.clear()
	_mutating = false
	_cursor = null
	_unit_selector = null
	_set_status = Callable()
	_cancel_ability = Callable()
	_cancel_build = Callable()
	_ability_target_kind = Callable()
	_is_ability_targeting = Callable()
	_is_build_targeting = Callable()


func _exit_tree() -> void:
	shutdown()


func current_aim() -> int:
	return _aim


func is_aiming() -> bool:
	return _aim != Aim.NONE


func is_move() -> bool:
	return _aim == Aim.MOVE


func is_attack() -> bool:
	return _aim == Aim.ATTACK


func is_patrol() -> bool:
	return _aim == Aim.PATROL


func is_harvest() -> bool:
	return _aim == Aim.HARVEST


func is_rally() -> bool:
	return _aim == Aim.RALLY


func is_ability() -> bool:
	return _aim == Aim.ABILITY


func is_build() -> bool:
	return _aim == Aim.BUILD


## 唯一进入瞄准入口：先取消其它态（含 ability/build），再进入。
func begin_aim(aim: int, payload: Dictionary = {}) -> void:
	if aim == Aim.NONE:
		cancel_aim()
		return
	if _mutating:
		return
	_mutating = true
	# Director 主动进入 MOVE/ATTACK/… 时清掉 ability/build
	_exit_current(false)
	_aim = aim
	_payload = payload.duplicate(true)
	_apply_cursor_for_aim()
	_sync_selector()
	_mutating = false
	aiming_changed.emit(_aim, _payload)


## Abilities/Build 模块已自行进入瞄准后，只同步状态机与光标（不 cancel 自己）。
func adopt_external_aim(aim: int, payload: Dictionary = {}) -> void:
	if aim != Aim.ABILITY and aim != Aim.BUILD:
		begin_aim(aim, payload)
		return
	if _mutating:
		return
	_mutating = true
	# 清掉互斥的其它瞄准（不含自己）
	if _aim != Aim.NONE and _aim != aim:
		if _aim == Aim.ABILITY and _cancel_ability.is_valid():
			_cancel_ability.call()
		elif _aim == Aim.BUILD and _cancel_build.is_valid():
			_cancel_build.call()
	# 外部另一类瞄准也可能仍在（状态机尚未同步）
	if aim == Aim.ABILITY and _is_build_targeting.is_valid() and bool(_is_build_targeting.call()):
		if _cancel_build.is_valid():
			_cancel_build.call()
	elif aim == Aim.BUILD and _is_ability_targeting.is_valid() and bool(_is_ability_targeting.call()):
		if _cancel_ability.is_valid():
			_cancel_ability.call()
	_aim = aim
	_payload = payload.duplicate(true)
	_apply_cursor_for_aim()
	_sync_selector()
	_mutating = false
	aiming_changed.emit(_aim, _payload)


func cancel_aim(_reason: String = "") -> void:
	if _mutating:
		return
	if _aim == Aim.NONE and not _external_aim_active():
		_sync_selector()
		return
	_mutating = true
	_exit_current(true)
	_aim = Aim.NONE
	_payload.clear()
	_apply_idle_cursor()
	_sync_selector()
	_mutating = false
	aiming_changed.emit(_aim, {})


## 外部模块已自行结束瞄准（如建造 commit 后 placement 已 inactive）：只清状态机，不回调 cancel_*。
func acknowledge_external_end() -> void:
	if _mutating:
		return
	_mutating = true
	_aim = Aim.NONE
	_payload.clear()
	_apply_idle_cursor()
	_sync_selector()
	_mutating = false
	aiming_changed.emit(_aim, {})


## 选中变化：取消所有瞄准。
func on_selection_changed(_primary: Node3D, _selected: Array) -> void:
	cancel_aim("selection")


## 下发移动/巡逻后闪箭头：先退出瞄准，再 flash（不被 IDLE 掐死）。
func flash_move_confirm() -> void:
	if _mutating:
		return
	_mutating = true
	_exit_current(true)
	_aim = Aim.NONE
	_payload.clear()
	_sync_selector()
	_mutating = false
	if _cursor != null:
		_cursor.flash_move()
	aiming_changed.emit(_aim, {})


func set_cursor_race(race_id: String) -> void:
	if _cursor != null:
		_cursor.set_race(race_id)


func sync_from_external() -> void:
	## 当 Abilities/Build 模块自行进入瞄准时，同步本状态机。
	if _is_ability_targeting.is_valid() and bool(_is_ability_targeting.call()):
		if _aim != Aim.ABILITY:
			_aim = Aim.ABILITY
			_apply_cursor_for_aim()
			_sync_selector()
		return
	if _is_build_targeting.is_valid() and bool(_is_build_targeting.call()):
		if _aim != Aim.BUILD:
			_aim = Aim.BUILD
			_apply_cursor_for_aim()
			_sync_selector()
		return


func _exit_current(cancel_modules: bool) -> void:
	var prev := _aim
	if cancel_modules:
		if prev == Aim.ABILITY or (_is_ability_targeting.is_valid() and bool(_is_ability_targeting.call())):
			if _cancel_ability.is_valid():
				_cancel_ability.call()
		if prev == Aim.BUILD or (_is_build_targeting.is_valid() and bool(_is_build_targeting.call())):
			if _cancel_build.is_valid():
				_cancel_build.call()
	elif prev == Aim.ABILITY:
		# 进入其它瞄准时也必须取消技能
		if _cancel_ability.is_valid():
			_cancel_ability.call()
	elif prev == Aim.BUILD:
		if _cancel_build.is_valid():
			_cancel_build.call()
	# 进入新瞄准时，若外部仍在 ability/build，一并清
	if not cancel_modules:
		if prev != Aim.ABILITY and _is_ability_targeting.is_valid() and bool(_is_ability_targeting.call()):
			if _cancel_ability.is_valid():
				_cancel_ability.call()
		if prev != Aim.BUILD and _is_build_targeting.is_valid() and bool(_is_build_targeting.call()):
			if _cancel_build.is_valid():
				_cancel_build.call()


func _external_aim_active() -> bool:
	if _is_ability_targeting.is_valid() and bool(_is_ability_targeting.call()):
		return true
	if _is_build_targeting.is_valid() and bool(_is_build_targeting.call()):
		return true
	return false


func _apply_cursor_for_aim() -> void:
	if _cursor == null:
		return
	match _aim:
		Aim.MOVE, Aim.PATROL, Aim.HARVEST:
			_cursor.apply_aim_cursor(Wc3GameCursor.Mode.MOVE)
		Aim.ATTACK:
			_cursor.apply_aim_cursor(Wc3GameCursor.Mode.TARGET)
		Aim.ABILITY:
			var kind := 0
			if _ability_target_kind.is_valid():
				kind = int(_ability_target_kind.call())
			elif _payload.has("target_kind"):
				kind = int(_payload.get("target_kind", 0))
			if kind == AbilityCatalog.TARGET_ALLY:
				_cursor.apply_aim_cursor(Wc3GameCursor.Mode.ALLY)
			else:
				_cursor.apply_aim_cursor(Wc3GameCursor.Mode.TARGET)
		Aim.RALLY:
			_cursor.apply_aim_cursor(Wc3GameCursor.Mode.SELECT)
		Aim.BUILD:
			_cursor.apply_aim_cursor(Wc3GameCursor.Mode.SELECT)
		_:
			_cursor.end_aim_cursor()


func _apply_idle_cursor() -> void:
	if _cursor != null:
		_cursor.end_aim_cursor()


func _sync_selector() -> void:
	if _unit_selector == null:
		return
	var aiming := _aim != Aim.NONE or _external_aim_active()
	_unit_selector.enabled = not aiming
